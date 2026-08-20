extends Node

const SaveDialogScript := preload("res://scripts/ui/save_manager_dialog.gd")
const EXPORT_BASE := "user://transfer_smoke/night_archive_backup"
const EXPORT_PATH := EXPORT_BASE + ".json"
const CORRUPT_PATH := "user://transfer_smoke/corrupt.json"
const BLOCKED_PATH := "user://transfer_smoke/blocked.json"

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var root_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://transfer_smoke"))
	_expect(root_error == OK, "测试应能创建隔离的外部档案目录。")
	GameSession.reset_session()
	_expect(GameSession.start_offline_demo(), "档案传输测试需要可导出的离线调查。")
	await _wait_for_session()

	var dialog := SaveDialogScript.new()
	add_child(dialog)
	dialog.open_dialog()
	await get_tree().process_frame
	await get_tree().process_frame
	var import_button := dialog.find_child("ImportJson", true, false) as Button
	var export_button := dialog.find_child("ExportJson", true, false) as Button
	var feedback := dialog.find_child("TransferFeedback", true, false) as Label
	_expect(import_button != null and export_button != null and feedback != null, "档案管理底栏应显示 JSON 导入、导出与反馈区域。")
	if import_button == null or export_button == null or feedback == null:
		await _finish(dialog)
		return
	_expect(not import_button.disabled and not export_button.disabled, "调查空闲且已启封时，JSON 导入与导出都应可用。")

	var open_dialog: FileDialog = dialog.call("_create_json_file_dialog", "测试导入", FileDialog.FILE_MODE_OPEN_FILE)
	_expect(open_dialog.use_native_dialog, "JSON 文件选择器必须请求操作系统原生对话框。")
	_expect(open_dialog.access == FileDialog.ACCESS_FILESYSTEM and open_dialog.file_mode == FileDialog.FILE_MODE_OPEN_FILE, "导入选择器应只选择一个文件并访问主机文件系统。")
	_expect(open_dialog.filters.size() == 1 and str(open_dialog.filters[0]).contains("*.json"), "导入选择器应只展示 JSON 档案。")
	dialog.add_child(open_dialog)
	open_dialog.queue_free()
	await get_tree().process_frame

	dialog.call("_export_json_path", EXPORT_BASE)
	_expect(FileAccess.file_exists(EXPORT_PATH), "省略扩展名时，导出应自动生成 .json 文件。")
	var exported := RuleTalesSaveService.read_document(EXPORT_PATH)
	_expect(bool(exported.get("ok", false)), "导出的外部 JSON 应通过现有存档完整性校验。")
	if bool(exported.get("ok", false)):
		_expect(int(exported.document.get("completed_turns", 0)) == 1, "外部 JSON 应保存当前回合。")
		_expect(str(exported.document.get("archive_id", "")) == "night_archive", "外部 JSON 应保留档案身份。")
		_expect(exported.document.get("timeline", []).size() == 1, "外部 JSON 应包含回合时间线。")
	_expect(feedback.text.contains("当前调查已导出"), "导出完成后应提供明确成功反馈。")

	_expect(GameSession.submit_action("进入档案室，调查值班窗与门牌"), "测试行动应正常提交。")
	await _wait_for_session()
	_expect(GameSession.completed_turns == 2, "导入确认前，当前调查应已经推进到第 2 回合。")
	var loaded_counter := {"value": 0}
	dialog.loaded.connect(func() -> void: loaded_counter.value = int(loaded_counter.value) + 1)
	dialog.call("_prepare_import_json", EXPORT_PATH)
	await get_tree().process_frame
	var confirmation := _find_confirmation(dialog)
	_expect(confirmation != null, "已有调查时导入外部 JSON 必须先要求确认替换。")
	_expect(GameSession.completed_turns == 2, "玩家确认前不得提前替换当前调查。")
	if confirmation == null:
		await _finish(dialog)
		return
	confirmation.confirmed.emit()
	await get_tree().process_frame
	_expect(GameSession.completed_turns == 1, "确认导入后应恢复外部 JSON 中的回合状态。")
	_expect(GameSession.history.size() == 1 and GameSession.timeline.size() == 1, "确认导入后应恢复对应历史与时间线。")
	_expect(int(loaded_counter.value) == 1, "成功导入应发出 loaded 信号以返回游戏界面。")
	_expect(feedback.text.contains("外部档案已导入"), "成功导入后应提供明确反馈。")

	var corrupt := FileAccess.open(CORRUPT_PATH, FileAccess.WRITE)
	if corrupt != null:
		corrupt.store_string("{not valid json")
		corrupt.close()
	var turn_before_corrupt := GameSession.completed_turns
	dialog.call("_prepare_import_json", CORRUPT_PATH)
	_expect(GameSession.completed_turns == turn_before_corrupt, "损坏 JSON 不得改变当前调查。")
	_expect(feedback.text.contains("导入失败"), "损坏 JSON 应显示具体导入失败反馈。")

	GameSession.busy = true
	dialog.call("_refresh_transfer_buttons")
	_expect(import_button.disabled and export_button.disabled, "叙事生成期间，导入与导出按钮都应禁用。")
	dialog.call("_export_json_path", BLOCKED_PATH)
	_expect(not FileAccess.file_exists(BLOCKED_PATH), "忙碌状态下即使直接调用也不得写出 JSON。")
	_expect(feedback.text.contains("叙事生成期间"), "忙碌状态下的导出拒绝应给出原因。")
	GameSession.busy = false

	GameSession.reset_session()
	GameSession.rules = RuleDocumentData.new()
	dialog.call("_refresh_transfer_buttons")
	_expect(not import_button.disabled and export_button.disabled, "没有当前调查时仍可导入，但必须禁用导出。")
	dialog.call("_export_json_path", BLOCKED_PATH)
	_expect(not FileAccess.file_exists(BLOCKED_PATH), "没有调查时不得写出空 JSON。")
	_expect(feedback.text.contains("没有可导出的调查"), "没有调查时的导出拒绝应给出明确原因。")
	await _finish(dialog)


func _wait_for_session() -> void:
	for _attempt in 40:
		if not GameSession.busy:
			return
		await get_tree().create_timer(0.05).timeout


func _find_confirmation(parent: Node) -> ConfirmationDialog:
	for child in parent.get_children():
		if child is ConfirmationDialog and not child is FileDialog:
			return child as ConfirmationDialog
	return null


func _finish(dialog: Window) -> void:
	dialog.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("SAVE_TRANSFER_SMOKE_OK")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SAVE_TRANSFER_SMOKE_FAILED:%d" % _failures.size())
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
