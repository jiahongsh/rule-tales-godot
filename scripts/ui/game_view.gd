extends Control

const RunSystemsScript := preload("res://scripts/engine/run_systems.gd")

signal lobby_requested
signal settings_requested
signal saves_requested
signal import_requested

var _story_title: Label
var _workspace_split: HSplitContainer
var _connection_chip: Label
var _autosave_chip: Label
var _time_value: Label
var _weather_value: Label
var _deadline_value: Label
var _health_value: Label
var _sanity_value: Label
var _stamina_value: Label
var _health_bar: ProgressBar
var _sanity_bar: ProgressBar
var _stamina_bar: ProgressBar
var _status_text: RichTextLabel
var _transcript_list: VBoxContainer
var _transcript_scroll: ScrollContainer
var _history_toggle: Button
var _choice_list: VBoxContainer
var _action_edit: TextEdit
var _send_button: Button
var _loading: Label
var _cancel_generation_button: Button
var _error: Label
var _notice: Label
var _turn_result: PanelContainer
var _turn_result_label: Label
var _ending_card: PanelContainer
var _ending_title: Label
var _ending_rating: Label
var _ending_summary: RichTextLabel

var _context_title: Label
var _context_subtitle: Label
var _context_pages: Array[Control] = []
var _context_buttons: Array[Button] = []
var _active_context := 0
var _rules_text: RichTextLabel
var _chapter_row: HBoxContainer
var _tamper_button: Button
var _active_chapter := 0
var _inventory_list: VBoxContainer
var _facts_text: RichTextLabel
var _map_text: RichTextLabel
var _character_text: RichTextLabel
var _debug_text: RichTextLabel
var _show_full_history := false
var _modal_open := false
var _notice_serial := 0


func _ready() -> void:
	_build_ui()
	_connect_session()
	refresh_all()


func _build_ui() -> void:
	var background := ColorRect.new(); background.color = UIFactory.C_BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); background.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(background)
	var margin := MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_%s" % side, 10)
	add_child(margin)
	var root := VBoxContainer.new(); root.add_theme_constant_override("separation", 8); margin.add_child(root)
	root.add_child(_build_header())
	root.add_child(_build_status_bar())
	var workspace := HBoxContainer.new(); workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL; workspace.add_theme_constant_override("separation", 8); root.add_child(workspace)
	workspace.add_child(_build_tool_rail())
	_workspace_split = HSplitContainer.new(); _workspace_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _workspace_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_workspace_split.split_offsets = PackedInt32Array([720]); _workspace_split.dragger_visibility = SplitContainer.DRAGGER_VISIBLE; workspace.add_child(_workspace_split)
	_workspace_split.add_child(_build_narrative())
	_workspace_split.add_child(_build_context())
	_workspace_split.resized.connect(_apply_context_split)


func _build_header() -> Control:
	var panel := UIFactory.panel(Color("#171310"), Color("#403329"), 7, 9)
	var row := HBoxContainer.new(); panel.add_child(row)
	var titles := VBoxContainer.new(); titles.add_theme_constant_override("separation", 0); row.add_child(titles)
	titles.add_child(UIFactory.title("异闻夜谈", 27))
	_story_title = UIFactory.label("等待导入规则", 13, Color("#afa08f")); titles.add_child(_story_title)
	row.add_child(_expander())
	_connection_chip = _chip("体验剧本 · 离线"); row.add_child(_connection_chip)
	_autosave_chip = _chip("自动存档 · 待命"); row.add_child(_autosave_chip)
	var archives := UIFactory.button("档案管理", "ghost", 44); archives.pressed.connect(func() -> void: saves_requested.emit()); row.add_child(archives)
	var settings := UIFactory.button("设置", "ghost", 44); settings.pressed.connect(func() -> void: settings_requested.emit()); row.add_child(settings)
	var lobby := UIFactory.button("返回大厅", "normal", 44); lobby.pressed.connect(func() -> void: lobby_requested.emit()); row.add_child(lobby)
	return panel


func _build_status_bar() -> Control:
	var panel := UIFactory.panel(Color("#110f0d"), Color("#514029"), 7, 7)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8); panel.add_child(row)
	var facts := UIFactory.panel(Color("#181410"), Color("#3c3026"), 5, 6); facts.custom_minimum_size.x = 190; row.add_child(facts)
	var grid := GridContainer.new(); grid.columns = 2; facts.add_child(grid)
	grid.add_child(UIFactory.eyebrow("TIME / 时间")); _time_value = UIFactory.label("第1日 20:13", 14, UIFactory.C_TEXT); grid.add_child(_time_value)
	grid.add_child(UIFactory.eyebrow("WEATHER / 天气")); _weather_value = UIFactory.label("阴", 14, UIFactory.C_TEXT); grid.add_child(_weather_value)
	grid.add_child(UIFactory.eyebrow("DEADLINE / 期限")); _deadline_value = UIFactory.label("不限", 14, UIFactory.C_TEXT); grid.add_child(_deadline_value)
	var sanity_card := _metric_card("异常压力", "sanity"); sanity_card.custom_minimum_size.x = 185; row.add_child(sanity_card)
	_status_text = UIFactory.rich_text(54); _status_text.custom_minimum_size.x = 300; _status_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_text.add_theme_stylebox_override("normal", UIFactory.style(Color("#0d0c0b"), Color("#40352a"), 5, 1, 8)); row.add_child(_status_text)
	row.add_child(_metric_card("健康", "health")); row.add_child(_metric_card("体力", "stamina"))
	return panel


func _metric_card(title: String, role: String) -> Control:
	var panel := UIFactory.panel(Color("#181410"), Color("#3c3026"), 5, 6); panel.custom_minimum_size.x = 112
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 3); panel.add_child(box)
	var head := HBoxContainer.new(); box.add_child(head); head.add_child(UIFactory.label(title, 12, Color("#b6a692"))); head.add_child(_expander())
	var value := UIFactory.label("100", 16, Color("#f0d889")); head.add_child(value)
	var bar := ProgressBar.new(); bar.min_value = 0; bar.max_value = 100; bar.value = 100; bar.show_percentage = false; bar.custom_minimum_size.y = 8
	bar.add_theme_stylebox_override("background", UIFactory.style(Color("#292117"), Color.TRANSPARENT, 3, 0, 0))
	bar.add_theme_stylebox_override("fill", UIFactory.style(Color("#b49350"), Color.TRANSPARENT, 3, 0, 0)); box.add_child(bar)
	match role:
		"health": _health_value = value; _health_bar = bar
		"sanity": _sanity_value = value; _sanity_bar = bar
		"stamina": _stamina_value = value; _stamina_bar = bar
	return panel


func _build_tool_rail() -> Control:
	var rail := UIFactory.panel(Color("#12100e"), Color("#403329"), 7, 5); rail.custom_minimum_size.x = 80
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 5); rail.add_child(box)
	var entries := [["RULE\n规则", 0], ["BAG\n背包", 1], ["EVID\n证据", 2], ["MAP\n地图", 3], ["LOG\n档案", 4], ["TRACE\n调试", 5]]
	for entry in entries:
		var button := UIFactory.button(str(entry[0]), "ghost", 62); button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(_show_context.bind(int(entry[1]))); box.add_child(button); _context_buttons.append(button)
		if int(entry[1]) == 5: button.visible = AppSettings.debug_observer
	box.add_child(_vertical_expander())
	return rail


func _build_narrative() -> Control:
	var panel := UIFactory.panel(Color("#12100e"), Color("#403329"), 7, 12); panel.custom_minimum_size.x = 600
	var root := VBoxContainer.new(); root.add_theme_constant_override("separation", 8); panel.add_child(root)
	var heading := HBoxContainer.new(); root.add_child(heading); heading.add_child(UIFactory.eyebrow("CURRENT SCENE  /  当前场景")); heading.add_child(_expander())
	_loading = UIFactory.label("叙事核心正在推演……", 13, UIFactory.C_GOLD_SOFT); _loading.hide(); heading.add_child(_loading)
	_cancel_generation_button = UIFactory.button("中止推演", "danger", 36)
	_cancel_generation_button.name = "CancelGenerationButton"
	_cancel_generation_button.tooltip_text = "取消当前 AI 请求并恢复本回合提交前的行动选项；权威状态不会改变。"
	_cancel_generation_button.hide()
	_cancel_generation_button.pressed.connect(_cancel_generation)
	heading.add_child(_cancel_generation_button)
	_history_toggle = UIFactory.button("调查记录", "ghost", 40); _history_toggle.toggle_mode = true; _history_toggle.toggled.connect(_toggle_history); heading.add_child(_history_toggle)
	_transcript_scroll = ScrollContainer.new(); _transcript_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; _transcript_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_transcript_list = VBoxContainer.new(); _transcript_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _transcript_list.add_theme_constant_override("separation", 10)
	_transcript_scroll.add_child(_transcript_list); root.add_child(_transcript_scroll)
	_ending_card = _build_ending(); _ending_card.hide(); root.add_child(_ending_card)
	_turn_result = UIFactory.panel(Color("#111612"), Color("#52704e"), 6, 8); _turn_result.hide(); root.add_child(_turn_result)
	var result_row := HBoxContainer.new(); _turn_result.add_child(result_row); result_row.add_child(UIFactory.eyebrow("TURN RESULT / 回合结算"))
	_turn_result_label = UIFactory.label("", 14, Color("#cbd8c7")); _turn_result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; result_row.add_child(_turn_result_label)
	_choice_list = VBoxContainer.new(); _choice_list.add_theme_constant_override("separation", 8); root.add_child(_choice_list)
	var composer := HBoxContainer.new(); root.add_child(composer)
	_action_edit = TextEdit.new(); _action_edit.placeholder_text = "描述你的行动……（Enter 发送，Shift+Enter 换行）"; _action_edit.custom_minimum_size.y = 64; _action_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; _action_edit.add_theme_stylebox_override("normal", UIFactory.style(Color("#0a0908"), Color("#42362c"), 6, 1, 10)); _action_edit.gui_input.connect(_on_action_input); composer.add_child(_action_edit)
	_send_button = UIFactory.button("送出行动", "primary", 64); _send_button.custom_minimum_size.x = 120; _send_button.pressed.connect(_send_action); composer.add_child(_send_button)
	_error = UIFactory.label("", 14, Color("#e08a82")); _error.hide(); root.add_child(_error)
	_notice = UIFactory.label("", 14, Color("#a9c79e"), 0, true)
	_notice.name = "SessionNotice"
	_notice.hide()
	root.add_child(_notice)
	return panel


func _build_ending() -> PanelContainer:
	var panel := UIFactory.panel(Color("#201812"), Color("#b08a3f"), 8, 14)
	var box := VBoxContainer.new(); panel.add_child(box)
	var head := HBoxContainer.new(); box.add_child(head)
	var titles := VBoxContainer.new(); titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL; head.add_child(titles)
	titles.add_child(UIFactory.eyebrow("CASE CLOSED / 档案封存")); _ending_title = UIFactory.title("", 29); titles.add_child(_ending_title)
	_ending_rating = UIFactory.title("D", 44); head.add_child(_ending_rating)
	_ending_summary = UIFactory.rich_text(150); box.add_child(_ending_summary)
	return panel


func _build_context() -> Control:
	var panel := UIFactory.panel(Color("#12100e"), Color("#403329"), 7, 10); panel.custom_minimum_size.x = 390
	var root := VBoxContainer.new(); panel.add_child(root)
	var header := UIFactory.panel(Color("#1a1511"), Color("#44362b"), 6, 8); root.add_child(header)
	var title_box := VBoxContainer.new(); header.add_child(title_box); title_box.add_child(UIFactory.eyebrow("ARCHIVE / 规则档案"))
	_context_title = UIFactory.title("规则", 25); title_box.add_child(_context_title)
	_context_subtitle = UIFactory.label("高危异文会以血色标记；可降低动态效果", 13, Color("#988979")); title_box.add_child(_context_subtitle)
	var nav := HFlowContainer.new(); nav.add_theme_constant_override("h_separation", 6); root.add_child(nav)
	var names := ["规则", "背包", "证据", "地图", "档案", "调试"]
	for index in range(names.size()):
		var button := UIFactory.button(names[index], "ghost", 40); button.custom_minimum_size.x = 58; button.pressed.connect(_show_context.bind(index)); nav.add_child(button)
	var stack := Control.new(); stack.size_flags_vertical = Control.SIZE_EXPAND_FILL; root.add_child(stack)
	_context_pages = [_build_rules_page(), _build_inventory_page(), _build_facts_page(), _build_map_page(), _build_character_page(), _build_debug_page()]
	for page in _context_pages:
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); stack.add_child(page)
	_show_context(0)
	return panel


func _build_rules_page() -> Control:
	var page := VBoxContainer.new(); page.add_theme_constant_override("separation", 8)
	_tamper_button = UIFactory.button("档案异常 · 逐条校勘", "danger", 42); _tamper_button.hide(); _tamper_button.pressed.connect(_show_tamper_dialog); page.add_child(_tamper_button)
	_rules_text = UIFactory.rich_text(); _rules_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new(); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO; scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; scroll.custom_minimum_size.y = 50
	_chapter_row = HBoxContainer.new(); _chapter_row.add_theme_constant_override("separation", 6); scroll.add_child(_chapter_row); page.add_child(_rules_text); page.add_child(scroll)
	return page


func _build_inventory_page() -> Control:
	var scroll := ScrollContainer.new(); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_inventory_list = VBoxContainer.new(); _inventory_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(_inventory_list); return scroll


func _build_facts_page() -> Control:
	_facts_text = UIFactory.rich_text(); return _facts_text


func _build_map_page() -> Control:
	_map_text = UIFactory.rich_text(); return _map_text


func _build_character_page() -> Control:
	_character_text = UIFactory.rich_text(); return _character_text


func _build_debug_page() -> Control:
	_debug_text = UIFactory.rich_text(); _debug_text.threaded = false; return _debug_text


func _connect_session() -> void:
	GameSession.rules_changed.connect(_refresh_rules)
	GameSession.state_changed.connect(_on_state_changed)
	GameSession.history_changed.connect(_refresh_transcript)
	GameSession.facts_changed.connect(_refresh_facts)
	GameSession.choices_changed.connect(_refresh_choices)
	GameSession.busy_changed.connect(_on_busy)
	GameSession.error_occurred.connect(_show_error)
	GameSession.notice.connect(_show_notice)
	GameSession.autosave_written.connect(_on_autosave)
	GameSession.diagnostics_changed.connect(_refresh_debug)
	GameSession.tamper_changed.connect(_on_tamper_changed)
	GameSession.anomaly_pending.connect(_on_anomaly_pending)
	GameSession.routes_pending.connect(_on_routes_pending)
	GameSession.meta_awarded.connect(_on_meta_awarded)
	AppSettings.settings_changed.connect(refresh_all)


func refresh_all() -> void:
	_story_title.text = GameSession.story_title
	_connection_chip.text = "AI 已连接 · %s" % AppSettings.model if AppSettings.has_live_ai() and not GameSession.offline_demo else "体验剧本 · 离线"
	_context_buttons[5].visible = AppSettings.debug_observer
	_refresh_state(); _refresh_rules(); _refresh_transcript(); _refresh_choices(GameSession.choices); _refresh_facts(); _refresh_debug(); _refresh_ending()
	_on_busy(GameSession.busy, "叙事核心正在推演……" if GameSession.busy else "")
	if not GameSession.pending_anomaly.is_empty():
		call_deferred("_on_anomaly_pending", GameSession.pending_anomaly)
	elif not GameSession.pending_routes.is_empty():
		call_deferred("_show_routes_if_ready")


func _refresh_state() -> void:
	var data: Dictionary = GameSession.state.data
	_time_value.text = "第%d日 %s" % [int(data.day), GameSession.state.clock_text()]
	_weather_value.text = str(data.weather)
	_deadline_value.text = "%d 天" % RunSystemsScript.days_left(GameSession.state) if bool(data.run_mode) else "不限"
	_set_metric(_health_value, _health_bar, int(data.stats.health)); _set_metric(_sanity_value, _sanity_bar, int(data.stats.sanity)); _set_metric(_stamina_value, _stamina_bar, int(data.stats.stamina))
	_status_text.text = SafeBBCode.prepare(str(data.status_bbcode), not AppSettings.reduced_motion)
	_character_text.text = SafeBBCode.prepare("[color=#d8bd78][font_size=22]人物状态[/font_size][/color]\n\n%s\n\n[color=#988979]时间[/color]　第%d日 %s\n[color=#988979]天气[/color]　%s\n[color=#988979]背包[/color]　%d 件\n[color=#988979]足迹[/color]　%d 处" % [data.status_bbcode, int(data.day), GameSession.state.clock_text(), data.weather, GameSession.state.inventory_total(), data.map.nodes.size()], not AppSettings.reduced_motion)
	_map_text.text = GameSession.state.render_map_bbcode()
	_refresh_inventory(); _refresh_ending()


func _refresh_rules() -> void:
	_clear(_chapter_row)
	var shown_rules := GameSession.display_rules()
	for index in range(shown_rules.chapters.size()):
		var chapter: Dictionary = shown_rules.chapters[index]
		var button := UIFactory.button(str(chapter.title), "primary" if index == _active_chapter else "ghost", 38)
		button.pressed.connect(_select_chapter.bind(index)); _chapter_row.add_child(button)
	_tamper_button.visible = GameSession.tamper_status in ["active", "identified"]
	_tamper_button.disabled = GameSession.tamper_status == "identified"
	_tamper_button.text = "档案已校正" if GameSession.tamper_status == "identified" else "档案异常 · 逐条校勘"
	if shown_rules.chapters.is_empty():
		_rules_text.text = "[color=#817467]尚未导入规则档案。[/color]"
	else:
		_active_chapter = clampi(_active_chapter, 0, shown_rules.chapters.size() - 1)
		_render_chapter()


func _select_chapter(index: int) -> void:
	_active_chapter = index; _refresh_rules(); _cue("page")


func _render_chapter() -> void:
	var shown_rules := GameSession.display_rules()
	var chapter: Dictionary = shown_rules.chapters[_active_chapter]
	var decorated := _decorate_anomalies(str(chapter.content))
	_rules_text.text = SafeBBCode.prepare("[color=#efd58e][font_size=25]%s[/font_size][/color]\n\n%s" % [chapter.title, decorated], not AppSettings.reduced_motion)


func _decorate_anomalies(text: String) -> String:
	if text.contains("[blood]"): return text
	var lines := text.split("\n", true); var highlighted := 0
	for index in range(lines.size()):
		var line := str(lines[index])
		if highlighted < 2 and _contains_any(line, ["不要", "严禁", "立刻", "永远", "完整的人脸", "替你", "不存在"]):
			lines[index] = "[blood][dread strength=1.0]%s[/dread][/blood]" % line; highlighted += 1
	return "\n".join(lines)


func _refresh_transcript() -> void:
	_clear(_transcript_list)
	if GameSession.history.is_empty():
		var empty := UIFactory.label("等待叙事核心启封档案……", 16, Color("#817467")); empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; _transcript_list.add_child(empty); return
	var start := 0 if _show_full_history else maxi(0, GameSession.history.size() - 2)
	for index in range(start, GameSession.history.size()):
		var entry: Dictionary = GameSession.history[index]
		_transcript_list.add_child(_history_card(entry, index))
	if AppSettings.auto_scroll:
		await get_tree().process_frame
		_transcript_scroll.scroll_vertical = int(_transcript_scroll.get_v_scroll_bar().max_value)


func _history_card(entry: Dictionary, index: int) -> Control:
	var user := str(entry.role) == "user"
	var card := UIFactory.panel(Color("#14191c") if user else Color("#201a16"), Color("#526673") if user else Color("#5a4630"), 5, 13)
	if user: card.custom_minimum_size.x = 0
	var box := VBoxContainer.new(); card.add_child(box)
	box.add_child(UIFactory.eyebrow("你的行动 / PLAYER" if user else "叙事核心 · 第 %d 回 / NARRATOR" % (index + 1)))
	var text := UIFactory.rich_text(42); text.fit_content = true; text.scroll_active = false
	text.text = SafeBBCode.prepare(str(entry.content), not AppSettings.reduced_motion); box.add_child(text)
	return card


func _refresh_choices(new_choices: Array = GameSession.choices) -> void:
	_clear(_choice_list)
	for index in range(new_choices.size()):
		var choice := str(new_choices[index])
		var text := "%02d  ·  %s" % [index + 1, choice]
		if AppSettings.choice_hints: text += "\n      %s" % _choice_hint(choice)
		var button := UIFactory.button(text, "normal", 58); button.alignment = HORIZONTAL_ALIGNMENT_LEFT; button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(_choose.bind(choice)); _choice_list.add_child(button)
	_send_button.disabled = GameSession.busy or GameSession.state.is_terminal()
	_action_edit.editable = not GameSession.busy and not GameSession.state.is_terminal()


func _choose(choice: String) -> void:
	if AppSettings.confirm_risky and _contains_any(choice, ["追逐", "直视", "触碰", "强行", "闯入", "破坏", "撕掉", "无视", "违反"]):
		var confirm := ConfirmationDialog.new(); confirm.title = "确认危险行动"; confirm.dialog_text = "该行动包含明显危险征兆：\n\n%s\n\n仍要继续吗？" % choice; add_child(confirm)
		confirm.confirmed.connect(func() -> void: confirm.queue_free(); _submit(choice)); confirm.canceled.connect(confirm.queue_free); confirm.popup_centered(Vector2i(600, 320)); _cue("danger"); return
	_submit(choice)


func _send_action() -> void:
	_submit(_action_edit.text)


func _submit(action: String) -> void:
	if GameSession.submit_action(action): _action_edit.clear(); _error.hide(); _cue("commit")


func _on_action_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER] and not event.shift_pressed:
		get_viewport().set_input_as_handled(); _send_action()


func _on_state_changed(changes: Array) -> void:
	_refresh_state()
	if not changes.is_empty(): _turn_result_label.text = "  ◆  ".join(changes); _turn_result.show(); UIFactory.fade_in(_turn_result); _cue("damage" if _contains_any(_turn_result_label.text, ["健康", "理智"]) else "reveal")


func _on_busy(value: bool, message: String) -> void:
	_loading.text = message; _loading.visible = value
	_cancel_generation_button.visible = value
	_send_button.disabled = value or GameSession.state.is_terminal()
	_action_edit.editable = not value and not GameSession.state.is_terminal()


func _cancel_generation() -> void:
	if not GameSession.busy:
		return
	GameSession.cancel_generation()
	_cue("denied")


func _show_notice(message: String) -> void:
	_notice_serial += 1
	var serial := _notice_serial
	_notice.text = message
	_notice.show()
	await get_tree().create_timer(4.0).timeout
	if is_inside_tree() and serial == _notice_serial:
		_notice.hide()


func _show_error(message: String, detail: String) -> void:
	_error.text = "%s  %s" % [message, detail]; _error.show()


func _on_autosave(time_text: String, path: String) -> void:
	_autosave_chip.text = "自动存档 · %s" % time_text
	if path.is_empty() or not is_inside_tree():
		return
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var thumbnail := RuleTalesSaveService.write_thumbnail_for_save(path, get_tree().root.get_texture().get_image())
	if not bool(thumbnail.get("ok", false)):
		_autosave_chip.tooltip_text = "进度已保存，但缩略图写入失败：%s" % str(thumbnail.get("error", "未知错误"))
	else:
		_autosave_chip.tooltip_text = "进度与当前画面已写入三代轮换存档。"


func _on_tamper_changed() -> void:
	_refresh_rules()
	if GameSession.tamper_status == "active":
		_show_context(0)
		_cue("danger")


func _show_tamper_dialog() -> void:
	if GameSession.tamper_status != "active" or _modal_open:
		return
	_modal_open = true
	var window := Window.new()
	window.title = "档案校勘 · 指认被改写的规则"
	window.size = Vector2i(900, 680)
	window.min_size = Vector2i(720, 520)
	window.transient = true; window.exclusive = true
	add_child(window)
	var background := ColorRect.new(); background.color = UIFactory.C_BG; background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); window.add_child(background)
	var margin := MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_%s" % side, 22)
	window.add_child(margin)
	var root := VBoxContainer.new(); root.theme = UIFactory.build_theme(); root.add_theme_constant_override("separation", 10); margin.add_child(root)
	root.add_child(UIFactory.eyebrow("ARCHIVE CORRECTION / 档案校勘")); root.add_child(UIFactory.title("哪一条文字不再属于原始档案？", 27))
	root.add_child(UIFactory.label("逐条核对并点击你认为被替换的规则。错误指认会消耗 2 点理智。", 14, UIFactory.C_MUTED))
	var scroll := ScrollContainer.new(); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; root.add_child(scroll)
	var list := VBoxContainer.new(); list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; list.add_theme_constant_override("separation", 8); scroll.add_child(list)
	var shown := GameSession.display_rules()
	for chapter in shown.chapters:
		list.add_child(UIFactory.title(str(chapter.title), 20))
		for raw_line in str(chapter.content).split("\n", false):
			var line := str(raw_line).strip_edges()
			if line.is_empty(): continue
			var button := UIFactory.button(SafeBBCode.plain_text(line), "normal", 54); button.alignment = HORIZONTAL_ALIGNMENT_LEFT; button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.pressed.connect(func() -> void:
				var result := GameSession.identify_tamper(line)
				if result == 1:
					_modal_open = false; window.queue_free(); _refresh_rules(); _cue("recover")
				elif result == 0:
					button.text = "错误指认 · 理智 -2\n" + SafeBBCode.plain_text(line); button.disabled = true; _cue("damage"))
			list.add_child(button)
	var close := UIFactory.button("暂不指认", "ghost", 46); close.pressed.connect(func() -> void: _modal_open = false; window.queue_free()); root.add_child(close)
	window.close_requested.connect(func() -> void: _modal_open = false; window.queue_free())
	window.popup_centered()


func _on_anomaly_pending(encounter: Dictionary) -> void:
	if encounter.is_empty() or _modal_open:
		return
	_modal_open = true
	var dialog := ConfirmationDialog.new()
	dialog.title = "夜间校验 · %s" % str(encounter.title)
	dialog.ok_button_text = "判定为异常 · 原路返回"
	dialog.cancel_button_text = "判定为正常 · 继续前进"
	dialog.dialog_text = "%s\n\n观察地点：%s\n\n这段观察是否违反了档案中的世界规律？判断由客户端权威结算。" % [SafeBBCode.plain_text(str(encounter.observation_bbcode)), str(encounter.location)]
	dialog.min_size = Vector2i(720, 390)
	add_child(dialog)
	dialog.confirmed.connect(func() -> void: _finish_anomaly(dialog, true))
	dialog.get_cancel_button().pressed.connect(func() -> void: _finish_anomaly(dialog, false))
	dialog.close_requested.connect(func() -> void: _modal_open = false; dialog.queue_free())
	dialog.popup_centered(Vector2i(760, 430)); _cue("danger")


func _finish_anomaly(dialog: Window, reported: bool) -> void:
	var result := GameSession.resolve_pending_anomaly(reported)
	dialog.queue_free(); _modal_open = false
	if not bool(result.ok):
		_show_error("异常判断未提交。", str(result.error)); _show_routes_if_ready(); return
	var summary := AcceptDialog.new(); summary.title = "夜间判断结果"; summary.dialog_text = SafeBBCode.plain_text(str(result.result_bbcode)); summary.ok_button_text = "继续选择巡查区域"; add_child(summary)
	_modal_open = true
	summary.confirmed.connect(func() -> void: _modal_open = false; summary.queue_free(); _show_routes_if_ready())
	summary.close_requested.connect(func() -> void: _modal_open = false; summary.queue_free(); _show_routes_if_ready())
	summary.popup_centered(Vector2i(650, 340)); _cue("recover" if bool(result.correct) else "damage")


func _on_routes_pending(_route_set: Dictionary) -> void:
	_show_routes_if_ready()


func _show_routes_if_ready() -> void:
	if _modal_open or GameSession.pending_routes.is_empty():
		return
	_modal_open = true
	var window := Window.new(); window.title = "次日巡查区域"; window.size = Vector2i(780, 560); window.transient = true; window.exclusive = true; add_child(window)
	var background := ColorRect.new(); background.color = UIFactory.C_BG; background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); window.add_child(background)
	var margin := MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_%s" % side, 24)
	window.add_child(margin)
	var root := VBoxContainer.new(); root.theme = UIFactory.build_theme(); root.add_theme_constant_override("separation", 12); margin.add_child(root)
	root.add_child(UIFactory.eyebrow("ROUTE DOSSIER / 路线档案")); root.add_child(UIFactory.title("选择下一段调查区域", 29)); root.add_child(UIFactory.label("危险提示来自环境征兆；选择会写入客户端权威状态。", 14, UIFactory.C_MUTED))
	for option in GameSession.pending_routes.get("options", []):
		var danger := str(option.risk) == "dangerous"
		var text := "%s　·　%s\n%s" % [str(option.label), str(option.risk_label), SafeBBCode.plain_text(str(option.hint_bbcode))]
		var button := UIFactory.button(text, "danger" if danger else "normal", 74); button.alignment = HORIZONTAL_ALIGNMENT_LEFT; button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(func() -> void:
			var result := GameSession.choose_route(str(option.id))
			if bool(result.ok): _modal_open = false; window.queue_free(); _cue("map")
			else: _show_error("路线选择失败。", str(result.error)))
		root.add_child(button)
	window.close_requested.connect(func() -> void: _modal_open = false; window.queue_free())
	window.popup_centered()


func _on_meta_awarded(points: int, profile: Dictionary) -> void:
	_turn_result_label.text = "本次调查获得 %d 认知点　·　累计 %d" % [points, int(profile.get("cognition_points", 0))]
	_turn_result.show()


func _refresh_inventory() -> void:
	_clear(_inventory_list)
	if GameSession.state.data.inventory.is_empty(): _inventory_list.add_child(UIFactory.label("背包还是空的。\n所有物品交互都在聊天框中进行。", 15, Color("#8d8176"))); return
	for item in GameSession.state.data.inventory:
		var card := UIFactory.panel(Color("#1b1612"), Color("#4a3a2b"), 5, 10); _inventory_list.add_child(card)
		var box := VBoxContainer.new(); card.add_child(box)
		var head := HBoxContainer.new(); box.add_child(head); head.add_child(UIFactory.title(str(item.name), 20)); head.add_child(_expander()); head.add_child(UIFactory.title("×%d" % int(item.quantity), 20))
		var description := UIFactory.rich_text(42); description.fit_content = true; description.scroll_active = false; description.text = SafeBBCode.prepare(str(item.description_bbcode), not AppSettings.reduced_motion); box.add_child(description)


func _refresh_facts() -> void:
	var sections := {"clue": [], "character": [], "location": [], "triggered_rule": [], "open_event": []}
	for fact in GameSession.facts.records: sections[str(fact.kind)].append(fact)
	var output: Array[String] = []
	var labels := {"clue": "线索", "character": "人物", "location": "地点", "triggered_rule": "已触发规则", "open_event": "未解决事件"}
	for kind in ["clue", "character", "location", "triggered_rule", "open_event"]:
		if sections[kind].is_empty(): continue
		output.append("[color=#d8bd78][font_size=20]%s[/font_size][/color]" % labels[kind])
		for fact in sections[kind]: output.append("[indent][b]%s[/b]　[color=#807469]%s[/color]\n%s[/indent]" % [fact.title, "已结案" if str(fact.status) == "resolved" else "活动", fact.detail_bbcode])
	_facts_text.text = SafeBBCode.prepare("\n\n".join(output) if not output.is_empty() else "[color=#817467]尚未记录长期事实。[/color]", not AppSettings.reduced_motion)


func _refresh_debug() -> void:
	if not AppSettings.debug_observer:
		_debug_text.text = "[color=#817467]调试观察器默认隐藏。按 F12 开启。[/color]"; return
	var data := GameSession.diagnostics
	_debug_text.text = SafeBBCode.prepare("[color=#d8bd78][font_size=20]本回合上下文[/font_size][/color]\n\n[b]模式[/b]　%s\n[b]阶段[/b]　%s\n[b]结果[/b]　%s\n[b]估算输入 Token[/b]　%s\n[b]最大输出[/b]　%s\n\n[color=#d8bd78][b]发送规则[/b][/color]\n[code]%s[/code]\n\n[color=#d8bd78][b]历史检索[/b][/color]\n[code]%s[/code]\n\n[color=#d8bd78][b]原始状态补丁[/b][/color]\n[code]%s[/code]" % [data.get("mode", "—"), data.get("phase", "—"), data.get("outcome", "—"), data.get("estimated_input_tokens", 0), data.get("max_output_tokens", 0), JSON.stringify(data.get("rule_selection", {}).get("trace", {}), "  "), JSON.stringify(data.get("history_trace", {}), "  "), JSON.stringify(data.get("raw_patch", {}), "  ")], false)


func _refresh_ending() -> void:
	var ending: Dictionary = GameSession.state.data.ending
	_ending_card.visible = GameSession.state.is_terminal()
	if not _ending_card.visible: return
	_ending_title.text = str(ending.title); _ending_rating.text = GameSession.investigation_rating()
	_ending_summary.text = SafeBBCode.prepare("%s\n\n[color=#988979]调查评分[/color]　%d / 100\n[color=#988979]发现规则[/color]　%d\n[color=#988979]完成回合[/color]　%d\n\n[color=#d8bd78][b]关键选择回顾[/b][/color]\n%s" % [ending.summary_bbcode, GameSession.investigation_score(), GameSession.discovered_rule_ids.size(), GameSession.completed_turns, _key_choice_text()], not AppSettings.reduced_motion)


func _key_choice_text() -> String:
	var lines: Array[String] = []
	for choice in GameSession.key_choices: lines.append("· 第%d回　%s\n  %s" % [int(choice.turn), choice.action, choice.consequence])
	return "\n".join(lines) if not lines.is_empty() else "暂无关键选择记录"


func _show_context(index: int) -> void:
	_active_context = clampi(index, 0, _context_pages.size() - 1) if not _context_pages.is_empty() else 0
	for page_index in range(_context_pages.size()): _context_pages[page_index].visible = page_index == _active_context
	var names := ["规则", "背包", "结构化证据", "探索地图", "人物档案", "调试观察"]
	var subtitles := ["严格按章节展示玩家规则", "物品只能通过行动文字使用", "线索、人物、地点与未解决事件", "客户端根据图结构确定性绘制", "当前状态与调查概览", "本回合规则、历史、预算与原始补丁"]
	if _context_title != null: _context_title.text = names[_active_context]; _context_subtitle.text = subtitles[_active_context]
	_apply_context_split()
	if not _context_pages.is_empty(): UIFactory.fade_in(_context_pages[_active_context], 0.14)


func _apply_context_split() -> void:
	if _workspace_split == null or _workspace_split.size.x <= 0:
		return
	var narrative_ratio := 0.50 if _active_context == 0 else 0.68
	_workspace_split.split_offsets = PackedInt32Array([int(_workspace_split.size.x * narrative_ratio)])


func _toggle_history(enabled: bool) -> void:
	_show_full_history = enabled; _history_toggle.text = "返回当前场景" if enabled else "调查记录"; _refresh_transcript()


func _choice_hint(choice: String) -> String:
	var kind := "行动"; var time := "约 3–10 分钟"
	if _contains_any(choice, ["观察", "检查", "翻看", "确认", "倾听", "调查", "搜索", "查看", "核对"]): kind = "调查"; time = "约 3–8 分钟"
	elif _contains_any(choice, ["前往", "进入", "离开", "返回", "上楼", "下楼", "穿过", "绕到", "赶往"]): kind = "移动"; time = "约 8–15 分钟"
	elif _contains_any(choice, ["询问", "交谈", "回答", "呼喊", "敲门"]): kind = "交涉"; time = "约 5–10 分钟"
	elif _contains_any(choice, ["喝", "吃", "使用", "拿出", "丢弃", "点燃"]): kind = "物品"; time = "约 1–3 分钟"
	return "%s  ·  %s%s" % [kind, time, "  ·  危险征兆" if _contains_any(choice, ["直视", "触碰", "强行", "闯入", "无视", "违反"]) else ""]


func _set_metric(label: Label, bar: ProgressBar, value: int) -> void:
	label.text = str(value)
	if AppSettings.reduced_motion: bar.value = value
	else: create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).tween_property(bar, "value", value, 0.24)


func _cue(name: String) -> void:
	var audio := get_node_or_null("/root/Main/AudioService") as RuleTalesSoundManager
	if audio != null: audio.cue(name)


func _chip(text: String) -> Label:
	var result := UIFactory.label(text, 13, Color("#d8c9b7")); result.add_theme_stylebox_override("normal", UIFactory.style(Color("#171310"), Color("#503d2b"), 8, 1, 9)); return result


func _clear(parent: Node) -> void:
	for child in parent.get_children(): child.queue_free()


func _expander() -> Control:
	var result := Control.new(); result.size_flags_horizontal = Control.SIZE_EXPAND_FILL; return result


func _vertical_expander() -> Control:
	var result := Control.new(); result.size_flags_vertical = Control.SIZE_EXPAND_FILL; return result


func _contains_any(text: String, needles: Array) -> bool:
	for needle in needles:
		if text.contains(str(needle)): return true
	return false
