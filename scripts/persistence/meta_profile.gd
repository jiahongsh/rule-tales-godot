class_name MetaProfileService
extends RefCounted

const PATH := "user://meta.json"


static func load_profile() -> Dictionary:
	var fresh := {"version": 1, "cognition_points": 0, "codex": [], "talents": [], "anomalies": []}
	if not FileAccess.file_exists(PATH):
		return fresh
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(PATH)) != OK or not parser.data is Dictionary:
		return fresh
	var source: Dictionary = parser.data
	var profile := fresh.duplicate(true)
	profile.cognition_points = maxi(0, int(source.get("cognition_points", 0)))
	if source.get("codex", []) is Array: profile.codex = source.codex.duplicate(true)
	if source.get("talents", []) is Array: profile.talents = source.talents.duplicate()
	if source.get("anomalies", []) is Array: profile.anomalies = source.anomalies.duplicate()
	_evaluate_talents(profile)
	return profile


static func record_run(theme_id: String, ending_type: String, score: int, points: int, anomaly_ids: Array) -> Dictionary:
	var profile := load_profile()
	profile.cognition_points = int(profile.cognition_points) + maxi(0, points)
	var found := false
	for record in profile.codex:
		if str(record.get("theme", "")) == theme_id and str(record.get("ending", "")) == ending_type:
			record.best_score = maxi(int(record.get("best_score", 0)), score)
			record.count = int(record.get("count", 0)) + 1
			found = true
			break
	if not found:
		profile.codex.append({"theme": theme_id, "ending": ending_type, "best_score": score, "count": 1})
	for anomaly_id in anomaly_ids:
		var cleaned := str(anomaly_id).strip_edges()
		if not cleaned.is_empty() and cleaned not in profile.anomalies:
			profile.anomalies.append(cleaned)
	profile.anomalies.sort()
	_evaluate_talents(profile)
	var saved := _write(profile)
	return {"ok": saved.is_empty(), "error": saved, "profile": profile, "points": points}


static func _evaluate_talents(profile: Dictionary) -> void:
	if int(profile.cognition_points) >= 200 and "keen_eye" not in profile.talents:
		profile.talents.append("keen_eye")
	if int(profile.cognition_points) >= 500 and "second_wind" not in profile.talents:
		profile.talents.append("second_wind")


static func _write(profile: Dictionary) -> String:
	var path := ProjectSettings.globalize_path(PATH)
	var parent := path.get_base_dir()
	var directory_error := DirAccess.make_dir_recursive_absolute(parent)
	if directory_error != OK:
		return "无法创建元档案目录：%s" % error_string(directory_error)
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "无法写入元档案：%s" % error_string(FileAccess.get_open_error())
	file.store_string(JSON.stringify(profile, "  ", true))
	file.flush()
	file.close()
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(temporary)) != OK or not parser.data is Dictionary:
		return "元档案写入后校验失败。"
	var backup := path + ".bak"
	if FileAccess.file_exists(backup): DirAccess.remove_absolute(backup)
	if FileAccess.file_exists(path):
		var backup_error := DirAccess.rename_absolute(path, backup)
		if backup_error != OK: return "无法备份旧元档案：%s" % error_string(backup_error)
	var replace_error := DirAccess.rename_absolute(temporary, path)
	if replace_error != OK:
		if FileAccess.file_exists(backup): DirAccess.rename_absolute(backup, path)
		return "无法提交元档案：%s" % error_string(replace_error)
	return ""
