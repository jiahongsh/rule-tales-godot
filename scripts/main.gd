extends Control

const LobbyScene := preload("res://scenes/screens/lobby_view.tscn")
const GameScene := preload("res://scenes/screens/game_view.tscn")
const SettingsDialogScript := preload("res://scripts/ui/settings_dialog.gd")
const SaveDialogScript := preload("res://scripts/ui/save_manager_dialog.gd")
const WorkshopScript := preload("res://scripts/ui/rule_workshop.gd")
const SeedRunDialogScript := preload("res://scripts/ui/seed_run_dialog.gd")
const StartupLoadingOverlayScript := preload("res://scripts/ui/startup_loading_overlay.gd")

var lobby: Control
var game_view: Control
var sound: RuleTalesSoundManager
var _pending_ai_start := false
var _pending_ai_action := ""
var _quit_dialog: ConfirmationDialog
var _settings_dialog: Window
var _save_dialog: Window
var _workshop_dialog: Window
var _seed_run_dialog: Window
var _loading_overlay: StartupLoadingOverlay
var _startup_complete := false


func _ready() -> void:
	AppSettings.apply_runtime_display()
	theme = UIFactory.build_theme()
	sound = RuleTalesSoundManager.new(); sound.name = "AudioService"; add_child(sound)
	lobby = LobbyScene.instantiate(); add_child(lobby)
	lobby.hide()
	_loading_overlay = StartupLoadingOverlayScript.new()
	add_child(_loading_overlay)
	_connect_lobby()
	GameSession.ai_configuration_required.connect(_on_ai_required)
	GameSession.error_occurred.connect(_on_session_error)
	GameSession.ending_reached.connect(_on_ending)
	lobby.set_continue_available(not GameSession.rules.is_empty())
	sound.set_ambience("drone")
	_startup_sequence()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if lobby != null and lobby.handle_cancel_navigation():
			get_viewport().set_input_as_handled()
			return
		if game_view != null and game_view.visible:
			get_viewport().set_input_as_handled()
			show_lobby()
			return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed and event.keycode == KEY_Q:
			get_viewport().set_input_as_handled()
			_request_quit()
		elif event.ctrl_pressed and event.keycode == KEY_I:
			get_viewport().set_input_as_handled()
			_import_rules()
		elif event.keycode == KEY_F1: _show_help()
		elif event.keycode == KEY_F12:
			AppSettings.debug_observer = not AppSettings.debug_observer
			AppSettings.save_settings()


func _connect_lobby() -> void:
	lobby.continue_requested.connect(show_game)
	lobby.offline_requested.connect(func() -> void:
		if GameSession.start_offline_demo(): sound.cue("commit"); show_game())
	lobby.campus_requested.connect(func() -> void:
		if GameSession.start_bundled_rules("res://content/rules/white_locust_school/rules.txt", "白槐中学"): sound.cue("commit"); show_game())
	lobby.apartment_requested.connect(_show_seed_run)
	lobby.import_requested.connect(_import_rules)
	lobby.settings_requested.connect(_show_settings)
	lobby.saves_requested.connect(_show_saves)
	lobby.workshop_requested.connect(_show_workshop)
	lobby.help_requested.connect(_show_help)
	lobby.quit_requested.connect(_request_quit)


func show_game() -> void:
	if GameSession.rules.is_empty(): return
	if game_view == null:
		game_view = GameScene.instantiate(); add_child(game_view)
		game_view.lobby_requested.connect(show_lobby)
		game_view.settings_requested.connect(_show_settings)
		game_view.saves_requested.connect(_show_saves)
		game_view.import_requested.connect(_import_rules)
	lobby.hide(); game_view.show(); game_view.refresh_all(); UIFactory.fade_in(game_view)
	sound.set_ambience("rain" if str(GameSession.state.data.weather).contains("雨") else "pulse")


func show_lobby() -> void:
	if game_view != null: game_view.hide()
	lobby.show(); lobby.set_continue_available(not GameSession.rules.is_empty()); lobby.show_menu(); UIFactory.fade_in(lobby)
	sound.set_ambience("drone")


func _import_rules() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	dialog.filters = PackedStringArray(["*.txt, *.md ; 规则文档"])
	dialog.file_selected.connect(func(path: String) -> void:
		if GameSession.import_rules_path(path, true): show_game()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog); dialog.popup_centered_ratio(0.72)


func _show_settings() -> void:
	_ensure_settings_dialog()
	_settings_dialog.open_dialog()


func _ensure_settings_dialog() -> void:
	if not is_instance_valid(_settings_dialog):
		_settings_dialog = SettingsDialogScript.new()
		_settings_dialog.visible = false
		add_child(_settings_dialog)
		_settings_dialog.closed.connect(func() -> void:
			if game_view != null: game_view.refresh_all()
			lobby.refresh_summary()
			_resume_after_ai_configuration())


func _resume_after_ai_configuration() -> void:
	if not AppSettings.has_live_ai():
		return
	var should_start := _pending_ai_start
	var pending_action := _pending_ai_action
	_pending_ai_start = false
	_pending_ai_action = ""
	if should_start:
		if GameSession.start_new_story():
			sound.cue("commit")
			show_game()
	elif not pending_action.is_empty() and GameSession.submit_action(pending_action):
		sound.cue("commit")
		show_game()


func _show_saves() -> void:
	_ensure_save_dialog()
	_save_dialog.open_dialog()


func _ensure_save_dialog() -> void:
	if not is_instance_valid(_save_dialog):
		_save_dialog = SaveDialogScript.new()
		_save_dialog.visible = false
		add_child(_save_dialog)
		_save_dialog.loaded.connect(func() -> void:
			_save_dialog.hide()
			show_game())


func _startup_sequence() -> void:
	# Scene-tree UI creation must stay on the main thread. Yielding between the
	# hidden windows lets the loading overlay present truthful stage progress.
	_loading_overlay.update_stage(0, 0.06, "唤醒档案索引", "正在建立本地档案目录……")
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
	else:
		await RenderingServer.frame_post_draw
	_loading_overlay.update_stage(0, 0.18, "校准调查设置", "正在准备显示、声音与叙事配置。")
	await get_tree().process_frame
	_ensure_settings_dialog()
	_loading_overlay.update_stage(1, 0.42, "核对存档目录", "正在读取手动槽位、自动轮换与时间线摘要。")
	await get_tree().process_frame
	_ensure_save_dialog()
	_save_dialog.prepare_dialog()
	_loading_overlay.update_stage(2, 0.68, "装订规则工坊", "正在准备规则编辑、审计与预检工具。")
	await get_tree().process_frame
	_ensure_workshop_dialog()
	_loading_overlay.update_stage(3, 0.88, "校验规则种子", "正在初始化限时调查生成器。")
	await get_tree().process_frame
	_ensure_seed_run_dialog()
	_loading_overlay.update_stage(4, 1.0, "档案馆已就绪", "调查权限校验完成，正在打开夜间入口。")
	await get_tree().process_frame
	_startup_complete = true
	lobby.show()
	UIFactory.fade_in(lobby, 0.24)
	_loading_overlay.finish()


func _show_workshop() -> void:
	_ensure_workshop_dialog()
	_workshop_dialog.open_dialog()


func _ensure_workshop_dialog() -> void:
	if is_instance_valid(_workshop_dialog):
		return
	_workshop_dialog = WorkshopScript.new()
	_workshop_dialog.visible = false
	add_child(_workshop_dialog)
	_workshop_dialog.start_requested.connect(func(text: String, title: String) -> void:
		if GameSession.import_rules_text(text, title, "workshop://draft", false, "workshop"):
			_workshop_dialog.hide()
			if GameSession.start_new_story(): show_game())


func _show_seed_run() -> void:
	_ensure_seed_run_dialog()
	_seed_run_dialog.open_dialog()


func _ensure_seed_run_dialog() -> void:
	if is_instance_valid(_seed_run_dialog):
		return
	_seed_run_dialog = SeedRunDialogScript.new()
	_seed_run_dialog.visible = false
	add_child(_seed_run_dialog)
	_seed_run_dialog.start_requested.connect(func(seed: int, days_limit: int) -> void:
		if GameSession.start_seed_run(seed, days_limit):
			sound.cue("commit"); show_game())


func _show_help() -> void:
	var popup := AcceptDialog.new()
	popup.title = "调查员手册"
	popup.dialog_text = "规则文档使用独占一行的 <章节标题> 分章。\n\n局内可点击三个行动选项，也可在输入框自由描述行动。背包物品只能通过对话使用；地图只记录亲自探索过的地点。\n\n离线《夜间档案室》无需 API。其他档案请先在设置中连接 DeepSeek 或 OpenAI 兼容接口。联网时，仅本回合检索到的规则片段、当前状态、事实与必要历史会发送给所选服务商；请勿导入真实身份或隐私资料。\n\nCtrl+I 导入规则 · Ctrl+Q 退出游戏 · F12 切换调试观察器。"
	add_child(popup); popup.popup_centered(Vector2i(720, 430))
	popup.confirmed.connect(popup.queue_free)


func _request_quit() -> void:
	if is_instance_valid(_quit_dialog):
		_quit_dialog.popup_centered(Vector2i(560, 260))
		return
	_quit_dialog = ConfirmationDialog.new()
	_quit_dialog.name = "QuitConfirmationDialog"
	_quit_dialog.title = "退出《异闻夜谈》"
	_quit_dialog.dialog_text = "确定要退出游戏吗？\n\n已完成的调查进度会按现有存档规则保留。"
	_quit_dialog.ok_button_text = "退出游戏"
	_quit_dialog.cancel_button_text = "继续调查"
	_quit_dialog.exclusive = true
	add_child(_quit_dialog)
	_quit_dialog.confirmed.connect(func() -> void: get_tree().quit(0))
	_quit_dialog.canceled.connect(_dismiss_quit_dialog)
	_quit_dialog.popup_centered(Vector2i(560, 260))
	if sound != null:
		sound.cue("danger")


func _dismiss_quit_dialog() -> void:
	if not is_instance_valid(_quit_dialog):
		return
	_quit_dialog.queue_free()
	_quit_dialog = null


func _on_ai_required(action: String) -> void:
	if action == "开始故事" and GameSession.completed_turns == 0 and GameSession.history.is_empty():
		_pending_ai_start = true
		_pending_ai_action = ""
	else:
		_pending_ai_start = false
		_pending_ai_action = action
	show_lobby(); lobby.show_ai_guide(action)


func _on_session_error(message: String, detail: String) -> void:
	sound.cue("denied")
	if lobby.visible: lobby.show_feedback("%s\n%s" % [message, detail])


func _on_ending() -> void:
	sound.cue("ending_escape" if str(GameSession.state.data.ending.type) in ["escape", "survival", "special"] else "ending_lost")
