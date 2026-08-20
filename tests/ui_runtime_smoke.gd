extends Node

const MainScene := preload("res://scenes/main.tscn")
const SettingsDialog := preload("res://scripts/ui/settings_dialog.gd")
const SaveDialog := preload("res://scripts/ui/save_manager_dialog.gd")
const WorkshopDialog := preload("res://scripts/ui/rule_workshop.gd")
const SeedRunDialog := preload("res://scripts/ui/seed_run_dialog.gd")

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main := MainScene.instantiate()
	get_tree().root.add_child(main)
	while not main._startup_complete:
		await get_tree().process_frame
	_expect(main.lobby.visible, "启动预热完成后应显示大厅")
	await get_tree().create_timer(0.4).timeout
	_expect(main.find_child("StartupLoadingOverlay", true, false) == null, "加载画面应在完成动画后释放")
	_expect(main.get_child_count() >= 2, "主场景应创建音频服务与大厅")
	var lobby: Control = main.lobby
	_expect(is_instance_valid(main._settings_dialog) and not main._settings_dialog.visible, "设置窗口应在大厅显示前隐藏预热")
	_expect(is_instance_valid(main._save_dialog) and not main._save_dialog.visible, "档案管理窗口应在大厅显示前隐藏预热")
	_expect(is_instance_valid(main._workshop_dialog) and not main._workshop_dialog.visible, "规则工坊应在大厅显示前隐藏预热")
	_expect(is_instance_valid(main._seed_run_dialog) and not main._seed_run_dialog.visible, "种子局窗口应在大厅显示前隐藏预热")
	var quit_button := lobby.find_child("QuitGameButton", true, false) as Button
	_expect(quit_button != null and quit_button.text.contains("CTRL+Q"), "大厅应提供标明 Ctrl+Q 的退出游戏按钮")
	if quit_button != null:
		quit_button.pressed.emit()
	var quit_dialog := main.find_child("QuitConfirmationDialog", true, false) as ConfirmationDialog
	_expect(quit_dialog != null and quit_dialog.visible, "退出按钮应先打开确认对话框")
	if quit_dialog != null:
		quit_dialog.canceled.emit()
	await get_tree().process_frame
	var quit_event := InputEventKey.new()
	quit_event.pressed = true
	quit_event.ctrl_pressed = true
	quit_event.keycode = KEY_Q
	main._unhandled_input(quit_event)
	quit_dialog = main.find_child("QuitConfirmationDialog", true, false) as ConfirmationDialog
	_expect(quit_dialog != null and quit_dialog.visible, "Ctrl+Q 应打开同一退出确认流程")
	if quit_dialog != null:
		quit_dialog.canceled.emit()
	await get_tree().process_frame
	lobby.show_selection()
	_expect(lobby.get_node("CaseSelectionPage").visible, "档案选择页应可打开")
	var cancel_event := InputEventAction.new()
	cancel_event.action = "ui_cancel"
	cancel_event.pressed = true
	main._unhandled_input(cancel_event)
	_expect(lobby.get_node("StartMenuPage").visible and not lobby.get_node("CaseSelectionPage").visible, "档案选择页的 ESC 应返回主菜单")

	var settings := SettingsDialog.new()
	main.add_child(settings); settings.open_dialog()
	await get_tree().process_frame
	_expect(settings.visible and settings.get_child_count() > 0, "开始设置窗口应能在运行时构建")
	settings._show_page(3)
	var window_mode_option := settings.find_child("WindowModeOption", true, false) as OptionButton
	var window_size_option := settings.find_child("WindowSizeOption", true, false) as OptionButton
	var frame_rate_option := settings.find_child("FrameRateOption", true, false) as OptionButton
	var embedded_display_notice := settings.find_child("EmbeddedDisplayNotice", true, false) as Control
	_expect(window_mode_option != null and window_mode_option.item_count == 2, "设置页应提供窗口化与无边框全屏")
	_expect(window_size_option != null and window_size_option.item_count == 5, "设置页应提供五档窗口尺寸")
	_expect(frame_rate_option != null and frame_rate_option.item_count == 5, "设置页应提供五档帧率上限")
	_expect(embedded_display_notice != null, "设置页应提供编辑器嵌入模式提示")
	if embedded_display_notice != null:
		_expect(embedded_display_notice.visible == Engine.is_embedded_in_editor(), "仅编辑器嵌入运行时应显示窗口模式限制提示")
	if window_mode_option != null and window_size_option != null:
		window_mode_option.select(1)
		settings._on_option_selected(1)
		_expect(window_size_option.disabled, "无边框全屏下窗口尺寸选项应禁用")
	settings.hide(); settings.free(); await get_tree().process_frame
	main._show_settings()
	var cached_settings: Window = main._settings_dialog
	cached_settings._close_dialog()
	main._show_settings()
	_expect(main._settings_dialog == cached_settings and cached_settings.visible, "设置窗口应缓存复用，不应每次点击重建")
	cached_settings._close_dialog()
	await get_tree().process_frame

	var previous_window_size := Vector2i(AppSettings.window_width, AppSettings.window_height)
	var previous_max_fps := AppSettings.max_fps
	var previous_window_mode := AppSettings.window_mode
	AppSettings.window_mode = "windowed"
	AppSettings.window_width = 960
	AppSettings.window_height = 600
	AppSettings.max_fps = 30
	var window_change_supported := AppSettings.apply_runtime_display()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(not bool(ProjectSettings.get_setting("display/window/size/resizable", true)), "项目应禁止主窗口边框自由拖拽缩放")
	_expect(window_change_supported == not Engine.is_embedded_in_editor(), "窗口设置应用结果应反映编辑器嵌入限制")
	if window_change_supported:
		_expect(get_tree().root.size == Vector2i(960, 600), "应用窗口尺寸后应立即更新物理窗口")
	_expect(Engine.max_fps == 30, "应用帧率上限后应立即更新 Engine.max_fps")
	AppSettings.window_width = previous_window_size.x
	AppSettings.window_height = previous_window_size.y
	AppSettings.max_fps = previous_max_fps
	AppSettings.window_mode = previous_window_mode
	AppSettings.apply_runtime_display()
	await get_tree().process_frame
	await get_tree().process_frame

	var saves := SaveDialog.new()
	main.add_child(saves); saves.open_dialog()
	await get_tree().process_frame
	_expect(saves.visible and saves.get_child_count() > 0, "档案管理窗口应能在运行时构建")
	saves.hide(); saves.free(); await get_tree().process_frame
	main._show_saves()
	var cached_saves: Window = main._save_dialog
	cached_saves._close()
	main._show_saves()
	_expect(main._save_dialog == cached_saves and cached_saves.visible, "档案管理窗口应缓存复用，不应每次点击重建")
	cached_saves._close()
	await get_tree().process_frame

	var workshop := WorkshopDialog.new()
	main.add_child(workshop); workshop.open_dialog()
	await get_tree().process_frame
	_expect(workshop.visible and workshop.get_child_count() > 0, "规则工坊应能在运行时构建")
	workshop.hide(); workshop.free(); await get_tree().process_frame

	var seed_dialog := SeedRunDialog.new()
	main.add_child(seed_dialog); seed_dialog.open_dialog()
	await get_tree().process_frame
	_expect(seed_dialog.visible and seed_dialog.get_child_count() > 0, "规则种子配置应能在运行时构建")
	seed_dialog.hide(); seed_dialog.free(); await get_tree().process_frame

	var started := GameSession.start_offline_demo()
	_expect(started, "离线体验应无需 API 启动")
	main.show_game()
	await get_tree().process_frame
	var cancel_button := main.game_view.find_child("CancelGenerationButton", true, false) as Button
	_expect(GameSession.busy and cancel_button != null and cancel_button.visible, "推演期间应显示中止入口")
	if cancel_button != null:
		cancel_button.pressed.emit()
	_expect(not GameSession.busy and GameSession.history.is_empty(), "中止推演应回滚待提交回合且不写入历史")
	var notice_label := main.game_view.find_child("SessionNotice", true, false) as Label
	_expect(notice_label != null and notice_label.visible and notice_label.text.contains("状态没有改变"), "中止后应显示状态未改变的反馈")
	started = GameSession.start_offline_demo()
	_expect(started, "中止后应能重新开始离线体验")
	await get_tree().create_timer(0.65).timeout
	print("OFFLINE_INITIAL history=", GameSession.history.size(), " choices=", GameSession.choices.size(), " busy=", GameSession.busy, " diag=", GameSession.diagnostics.get("outcome", ""), " detail=", GameSession.diagnostics.get("outcome_detail", ""))
	_expect(GameSession.history.size() == 1 and GameSession.choices.size() == 3, "离线初始场景应生成叙事与三个选项")
	var progressed := GameSession.submit_action("进入档案室，检查最近的门牌与出口")
	_expect(progressed, "离线选项应提交为真实回合")
	await get_tree().create_timer(0.65).timeout
	print("OFFLINE_ACTION turns=", GameSession.completed_turns, " history=", GameSession.history.size(), " choices=", GameSession.choices.size(), " busy=", GameSession.busy, " diag=", GameSession.diagnostics.get("outcome", ""), " detail=", GameSession.diagnostics.get("outcome_detail", ""))
	_expect(GameSession.completed_turns == 2 and GameSession.history.size() == 3, "离线行动后剧情、回合与历史必须推进")
	_expect(GameSession.state.data.map.nodes.size() == 1, "明确探索行动应在客户端地图留下节点")

	main.free()
	await get_tree().process_frame
	await get_tree().process_frame
	if _failures.is_empty():
		print("UI_RUNTIME_SMOKE_OK")
		get_tree().quit(0)
	else:
		for failure in _failures: push_error(failure)
		print("UI_RUNTIME_SMOKE_FAILED:%d" % _failures.size())
		get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition: _failures.append(message)
