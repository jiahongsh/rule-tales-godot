class_name RuleTalesSaveService
extends RefCounted

const SAVE_SCHEMA := 1
const SAVE_ROOT := "user://saves"
const AUTOSAVE_CONFIG_PATH := SAVE_ROOT + "/autosave.cfg"
const LEGACY_AUTOSAVE_CURSOR_PATH := SAVE_ROOT + "/autosave.cursor"
const LEGACY_AUTOSAVE_PATH := SAVE_ROOT + "/autosave.json"
const MAX_SAVE_BYTES := 32 * 1024 * 1024


static func manual_path(slot: int) -> String:
	return "%s/manual_%d.json" % [SAVE_ROOT, clampi(slot, 1, 6)]


static func autosave_path(generation: int) -> String:
	return "%s/auto_%d.json" % [SAVE_ROOT, clampi(generation, 1, 3)]


static func thumbnail_path(slot: int) -> String:
	return "%s/manual_%d.png" % [SAVE_ROOT, clampi(slot, 1, 6)]


static func write_thumbnail(slot: int, source: Image) -> Dictionary:
	return write_thumbnail_for_save(manual_path(slot), source)


static func thumbnail_for_save(save_path: String) -> String:
	return save_path.get_basename() + ".png"


static func write_thumbnail_for_save(save_path: String, source: Image) -> Dictionary:
	if source == null or source.is_empty():
		return {"ok": false, "error": "无法取得当前画面。"}
	if save_path.strip_edges().is_empty():
		return {"ok": false, "error": "存档路径为空。"}
	var error := _ensure_root()
	if error != OK: return {"ok": false, "error": "无法创建存档目录：%s" % error_string(error)}
	var image := source.duplicate()
	var target_width := 480
	var target_height := maxi(1, roundi(image.get_height() * target_width / float(maxi(1, image.get_width()))))
	image.resize(target_width, target_height, Image.INTERPOLATE_LANCZOS)
	if target_height > 270:
		image.crop(target_width, 270)
	var path := thumbnail_for_save(save_path)
	# Image.save_png() chooses its encoder from the final extension. Keep the
	# staging file PNG-suffixed, then rename it after a successful encode.
	var temporary := path.get_basename() + ".tmp.png"
	var save_error: Error = image.save_png(temporary)
	if save_error != OK: return {"ok": false, "error": "无法写入存档缩略图：%s" % error_string(save_error)}
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	var replace_error := DirAccess.rename_absolute(temporary, path)
	if replace_error != OK: return {"ok": false, "error": "无法提交存档缩略图：%s" % error_string(replace_error)}
	return {"ok": true, "error": "", "path": path}


static func write_document(path: String, document: Dictionary) -> Dictionary:
	var error := _ensure_root()
	if error != OK: return {"ok": false, "error": "无法创建存档目录：%s" % error_string(error)}
	var serialized := JSON.stringify(document, "  ", true)
	if serialized.to_utf8_buffer().size() > MAX_SAVE_BYTES:
		return {"ok": false, "error": "存档超过 32 MB 安全上限。"}
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return {"ok": false, "error": "无法写入临时存档：%s" % error_string(FileAccess.get_open_error())}
	var write_succeeded := file.store_string(serialized)
	file.flush()
	file.close()
	if not write_succeeded:
		return {"ok": false, "error": "临时存档写入不完整。"}
	var verify := read_document(temporary)
	if not verify.ok:
		return {"ok": false, "error": "临时存档校验失败：%s" % verify.error}
	var backup := path + ".bak"
	if FileAccess.file_exists(backup): DirAccess.remove_absolute(backup)
	if FileAccess.file_exists(path):
		var backup_error := DirAccess.rename_absolute(path, backup)
		if backup_error != OK: return {"ok": false, "error": "无法轮换旧存档：%s" % error_string(backup_error)}
	var replace_error := DirAccess.rename_absolute(temporary, path)
	if replace_error != OK:
		if FileAccess.file_exists(backup): DirAccess.rename_absolute(backup, path)
		return {"ok": false, "error": "无法提交存档：%s" % error_string(replace_error)}
	return {"ok": true, "error": ""}


static func read_document(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {"ok": false, "error": "存档不存在。", "document": {}}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"ok": false, "error": "无法读取存档：%s" % error_string(FileAccess.get_open_error()), "document": {}}
	if file.get_length() <= 0 or file.get_length() > MAX_SAVE_BYTES:
		return {"ok": false, "error": "存档为空或超过安全上限。", "document": {}}
	var text := file.get_as_text()
	file.close()
	var parser := JSON.new()
	var error := parser.parse(text)
	if error != OK or not parser.data is Dictionary:
		return {"ok": false, "error": "JSON 第 %d 行：%s" % [parser.get_error_line(), parser.get_error_message()], "document": {}}
	return {"ok": true, "error": "", "document": parser.data}


static func write_next_autosave(document: Dictionary) -> Dictionary:
	var config := ConfigFile.new()
	config.load(AUTOSAVE_CONFIG_PATH)
	var generation := _next_autosave_generation(config)
	var sequence := maxi(int(config.get_value("rotation", "sequence", 0)), _max_autosave_sequence()) + 1
	var path := autosave_path(generation)
	var stored_document := document.duplicate(true)
	stored_document["_autosave_sequence"] = sequence
	var result := write_document(path, stored_document)
	if result.ok:
		config.set_value("rotation", "next", generation % 3 + 1)
		config.set_value("rotation", "sequence", sequence)
		config.set_value("slots", "generation_%d" % generation, sequence)
		var config_error := config.save(AUTOSAVE_CONFIG_PATH)
		if config_error != OK:
			result.warning = "进度已写入，但自动存档轮换索引保存失败：%s" % error_string(config_error)
		result.path = path
	return result


static func autosaves_newest_first() -> Array[String]:
	var config := ConfigFile.new()
	config.load(AUTOSAVE_CONFIG_PATH)
	var next_generation := _next_autosave_generation(config)
	var ring_rank := {}
	for distance in range(1, 4):
		var generation := posmod(next_generation - 1 - distance, 3) + 1
		ring_rank[generation] = distance
	var candidates: Array[Dictionary] = []
	for generation in range(1, 4):
		var path := autosave_path(generation)
		if not FileAccess.file_exists(path):
			continue
		var read := read_document(path)
		var sequence := int(read.document.get("_autosave_sequence", 0)) if read.ok else int(config.get_value("slots", "generation_%d" % generation, 0))
		candidates.append({"path": path, "sequence": sequence, "time": FileAccess.get_modified_time(path), "ring_rank": int(ring_rank.get(generation, 4))})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_has_sequence := int(a.sequence) > 0
		var b_has_sequence := int(b.sequence) > 0
		if a_has_sequence != b_has_sequence: return a_has_sequence
		if int(a.sequence) != int(b.sequence): return int(a.sequence) > int(b.sequence)
		if int(a.time) != int(b.time): return int(a.time) > int(b.time)
		return int(a.ring_rank) < int(b.ring_rank))
	var output: Array[String] = []
	for candidate in candidates: output.append(str(candidate.path))
	if FileAccess.file_exists(LEGACY_AUTOSAVE_PATH) and LEGACY_AUTOSAVE_PATH not in output:
		output.append(LEGACY_AUTOSAVE_PATH)
	return output


static func _max_autosave_sequence() -> int:
	var maximum := 0
	for generation in range(1, 4):
		var read := read_document(autosave_path(generation))
		if read.ok:
			maximum = maxi(maximum, int(read.document.get("_autosave_sequence", 0)))
	return maximum


static func _next_autosave_generation(config: ConfigFile) -> int:
	if config.has_section_key("rotation", "next"):
		return clampi(int(config.get_value("rotation", "next", 1)), 1, 3)
	if FileAccess.file_exists(LEGACY_AUTOSAVE_CURSOR_PATH):
		var cursor_text := FileAccess.get_file_as_string(LEGACY_AUTOSAVE_CURSOR_PATH).strip_edges()
		if cursor_text.is_valid_int():
			return clampi(cursor_text.to_int(), 1, 3)
	return 1


static func slot_summary(slot: int) -> Dictionary:
	var path := manual_path(slot)
	var result := read_document(path)
	if not result.ok: return {"slot": slot, "empty": true, "path": path}
	var document: Dictionary = result.document
	var state: Dictionary = document.get("state", {})
	return {"slot": slot, "empty": false, "path": path, "story_title": str(document.get("story_title", "未命名档案")), "turn": int(document.get("completed_turns", 0)), "day": int(state.get("day", 1)), "time": int(FileAccess.get_modified_time(path))}


static func _ensure_root() -> Error:
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_ROOT))
