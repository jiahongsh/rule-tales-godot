extends Window

signal closed

const PAGE_DEFINITIONS := [
	{"eyebrow": "01 / NARRATIVE CORE", "title": "叙事核心", "hint": "配置离线体验或 OpenAI 兼容接口。"},
	{"eyebrow": "02 / GAMEPLAY", "title": "调查体验", "hint": "控制上下文、生成规模与调查辅助。"},
	{"eyebrow": "03 / AUDIO MIX", "title": "声音混合", "hint": "分别调整界面音效与环境氛围。"},
	{"eyebrow": "04 / ACCESSIBILITY", "title": "显示与无障碍", "hint": "调整阅读比例、动态效果与观察工具。"},
]

const PRESETS := [
	{
		"name": "平衡体验",
		"caption": "推荐",
		"values": {
			"text_scale": 100, "horror_level": 2, "shake_intensity": 65,
			"reduced_motion": false, "high_contrast": false, "sound_enabled": true,
			"master_volume": 38, "effects_mix": 85, "ambience_mix": 65,
		},
	},
	{
		"name": "舒适阅读",
		"caption": "低动态",
		"values": {
			"text_scale": 115, "horror_level": 1, "shake_intensity": 25,
			"reduced_motion": true, "high_contrast": true, "sound_enabled": true,
			"master_volume": 28, "effects_mix": 70, "ambience_mix": 35,
		},
	},
	{
		"name": "沉浸恐怖",
		"caption": "完整演出",
		"values": {
			"text_scale": 100, "horror_level": 2, "shake_intensity": 82,
			"reduced_motion": false, "high_contrast": false, "sound_enabled": true,
			"master_volume": 48, "effects_mix": 92, "ambience_mix": 82,
		},
	},
	{
		"name": "静音专注",
		"caption": "纯阅读",
		"values": {
			"text_scale": 115, "horror_level": 1, "shake_intensity": 20,
			"reduced_motion": true, "high_contrast": false, "sound_enabled": false,
			"master_volume": 28, "effects_mix": 60, "ambience_mix": 0,
		},
	},
]

const PROVIDERS := [
	{"id": "offline", "label": "离线体验", "caption": "无需 API"},
	{"id": "deepseek", "label": "DeepSeek", "caption": "兼容接口"},
	{"id": "custom", "label": "自定义 API", "caption": "OpenAI 格式"},
]

var _built := false
var _closing := false
var _has_opened := false
var _updating := false
var _active_preset := -1
var _provider := "offline"

var _tabs: TabContainer
var _pages: Array[Control] = []
var _page_hosts: Array[MarginContainer] = []
var _nav_buttons: Array[Button] = []
var _preset_buttons: Array[Button] = []
var _provider_buttons: Dictionary = {}

var _endpoint_edit: LineEdit
var _model_edit: LineEdit
var _api_key_edit: LineEdit
var _api_status: Label
var _probe_button: Button
var _probe: AiGateway
var _probe_busy := false
var _probe_serial := 0

var _recent_slider: HSlider
var _relevant_slider: HSlider
var _temperature_slider: HSlider
var _max_tokens_slider: HSlider
var _horror_slider: HSlider
var _horror_value: Label
var _shake_slider: HSlider
var _text_scale_slider: HSlider
var _window_mode_option: OptionButton
var _window_size_option: OptionButton
var _frame_rate_option: OptionButton

var _choice_hints_check: CheckBox
var _confirm_risky_check: CheckBox
var _auto_scroll_check: CheckBox
var _sound_enabled_check: CheckBox
var _reduced_motion_check: CheckBox
var _high_contrast_check: CheckBox
var _debug_observer_check: CheckBox

var _master_slider: HSlider
var _effects_slider: HSlider
var _ambience_slider: HSlider

var _profile_chip: Label
var _feedback_label: Label
var _preview_summary: Label
var _preview_text: RichTextLabel
var _preview_panel: PanelContainer


func _ready() -> void:
	title = "异闻夜谈 · 开始设置"
	borderless = true
	theme = UIFactory.build_theme()
	transient = true
	transient_to_focused = true
	exclusive = true
	min_size = Vector2i(1080, 690)
	close_requested.connect(_close_dialog)
	# Building the form assigns initial Range values and therefore emits their
	# value_changed signals. Keep the form in its staging state until every
	# dependent control (notably the footer feedback and live preview) exists.
	_updating = true
	_build_interface()
	_load_from_settings()


func open_dialog() -> void:
	# The fixed preview/footer must remain visible at the 1440x810 design size;
	# the inner settings page itself provides scrolling for longer forms.
	if _has_opened:
		_load_from_settings()
	_has_opened = true
	_closing = false
	popup_centered_ratio(0.98)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close_dialog()


func _build_interface() -> void:
	if _built:
		return
	_built = true
	var background := ColorRect.new()
	background.color = UIFactory.C_BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var outer := MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("margin_left", 22)
	outer.add_theme_constant_override("margin_right", 22)
	outer.add_theme_constant_override("margin_top", 18)
	outer.add_theme_constant_override("margin_bottom", 18)
	add_child(outer)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	outer.add_child(root)
	root.add_child(_build_header())
	root.add_child(_build_preset_strip())
	root.add_child(_build_configuration_body())
	root.add_child(_build_live_preview())
	root.add_child(_build_footer())


func _build_header() -> Control:
	var panel := UIFactory.panel(Color("#15110f"), Color("#76582c"), 8, 16)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)

	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_child(UIFactory.eyebrow("CONFIGURATION / 调查配置"))
	copy.add_child(UIFactory.title("开始设置", 34))
	copy.add_child(UIFactory.label("先选择体验预设，再按需要细调。关闭窗口不会改动现有配置。", 14, UIFactory.C_MUTED))
	row.add_child(copy)

	var profile := UIFactory.panel(Color("#211a14"), Color("#5d4932"), 6, 12)
	profile.custom_minimum_size = Vector2(218, 0)
	var profile_box := VBoxContainer.new()
	profile.add_child(profile_box)
	_profile_chip = UIFactory.eyebrow("LOCAL PROFILE  01")
	_profile_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	profile_box.add_child(_profile_chip)
	var privacy := UIFactory.label("密钥仅驻留本次进程", 12, UIFactory.C_GREEN)
	privacy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	profile_box.add_child(privacy)
	row.add_child(profile)
	return panel


func _build_preset_strip() -> Control:
	var panel := UIFactory.panel(Color("#1a1511"), Color("#6f5330"), 8, 12)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	panel.add_child(root)

	var heading := HBoxContainer.new()
	heading.add_child(UIFactory.eyebrow("EXPERIENCE PRESET / 体验预设"))
	heading.add_child(_expander())
	heading.add_child(UIFactory.label("文字、动效、恐怖强度与声音的一键组合", 13, UIFactory.C_MUTED))
	root.add_child(heading)

	var group := ButtonGroup.new()
	group.allow_unpress = true
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	root.add_child(buttons)
	for index in range(PRESETS.size()):
		var preset: Dictionary = PRESETS[index]
		var button := UIFactory.button("%s\n%s" % [preset.name, preset.caption], "ghost", 58)
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_apply_preset_to_form.bind(index))
		buttons.add_child(button)
		_preset_buttons.append(button)
	return panel


func _build_configuration_body() -> Control:
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)

	var navigation := UIFactory.panel(Color("#100e0c"), Color("#3d3229"), 7, 8)
	navigation.custom_minimum_size.x = 235
	var nav_box := VBoxContainer.new()
	nav_box.add_theme_constant_override("separation", 6)
	navigation.add_child(nav_box)
	var nav_group := ButtonGroup.new()
	for index in range(PAGE_DEFINITIONS.size()):
		var definition: Dictionary = PAGE_DEFINITIONS[index]
		var nav := UIFactory.button("%02d   %s\n       %s" % [index + 1, definition.title, definition.eyebrow.get_slice(" / ", 1)], "ghost", 62)
		nav.toggle_mode = true
		nav.button_group = nav_group
		nav.alignment = HORIZONTAL_ALIGNMENT_LEFT
		nav.pressed.connect(_show_page.bind(index))
		nav_box.add_child(nav)
		_nav_buttons.append(nav)
	nav_box.add_child(_expander())
	var key_note := UIFactory.label("ESC  关闭而不保存\nF12  局内观察器", 12, Color("#756a60"))
	key_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nav_box.add_child(key_note)
	body.add_child(navigation)

	var page_panel := UIFactory.panel(Color("#15120f"), Color("#4b3a2b"), 7, 10)
	page_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs = TabContainer.new()
	_tabs.tabs_visible = false
	_tabs.use_hidden_tabs_for_min_size = false
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_stylebox_override("panel", UIFactory.style(Color("#15120f"), Color("#15120f"), 0, 0, 0))
	page_panel.add_child(_tabs)
	_pages.assign([
		_build_narrative_page(),
		_build_gameplay_page(),
		_build_audio_page(),
		_build_accessibility_page(),
	])
	for index in range(_pages.size()):
		var host := MarginContainer.new()
		host.name = "%sTab" % _pages[index].name
		host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		host.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_page_hosts.append(host)
		_tabs.add_child(host)
	_attach_page(0)
	body.add_child(page_panel)
	return body


func _attach_page(index: int) -> void:
	if index < 0 or index >= _pages.size():
		return
	var page := _pages[index]
	if page.get_parent() == null:
		_page_hosts[index].add_child(page)


func _build_narrative_page() -> Control:
	var page := _new_page("NarrativeCore", 0)
	var content: VBoxContainer = page.get_meta("content")

	var mode_panel := UIFactory.panel(Color("#100e0c"), Color("#3e3329"), 6, 10)
	var mode_box := VBoxContainer.new()
	mode_box.add_child(UIFactory.label("运行方式", 16, UIFactory.C_GOLD_SOFT))
	var mode_row := HBoxContainer.new()
	var provider_group := ButtonGroup.new()
	for entry in PROVIDERS:
		var button := UIFactory.button("%s\n%s" % [entry.label, entry.caption], "ghost", 56)
		button.toggle_mode = true
		button.button_group = provider_group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_select_provider.bind(str(entry.id)))
		mode_row.add_child(button)
		_provider_buttons[str(entry.id)] = button
	mode_box.add_child(mode_row)
	mode_panel.add_child(mode_box)
	content.add_child(mode_panel)

	_endpoint_edit = UIFactory.line_edit("https://api.deepseek.com")
	_endpoint_edit.text_changed.connect(_on_text_changed)
	_add_form_row(content, "Endpoint", "仅允许 HTTPS；本机调试可使用 localhost。", _endpoint_edit)
	_model_edit = UIFactory.line_edit("例如 deepseek-chat")
	_model_edit.text_changed.connect(_on_text_changed)
	_add_form_row(content, "模型", "填写服务商公开的模型标识，不在客户端猜测名称。", _model_edit)
	_api_key_edit = UIFactory.line_edit("仅保留到本次关闭程序")
	_api_key_edit.secret = true
	_api_key_edit.secret_character = "•"
	_api_key_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_api_key_edit.text_changed.connect(_on_text_changed)
	var key_row := HBoxContainer.new()
	key_row.add_theme_constant_override("separation", 8)
	key_row.add_child(_api_key_edit)
	var reveal_key := UIFactory.button("显示", "ghost", 46)
	reveal_key.custom_minimum_size.x = 92
	reveal_key.toggle_mode = true
	reveal_key.toggled.connect(func(pressed: bool) -> void:
		_api_key_edit.secret = not pressed
		reveal_key.text = "隐藏" if pressed else "显示"
	)
	key_row.add_child(reveal_key)
	_add_form_row(content, "API Key", "不会写入 settings.cfg、存档或调试观察器。", key_row)

	var security := UIFactory.panel(Color("#101613"), Color("#355541"), 6, 10)
	var security_row := HBoxContainer.new()
	security_row.add_child(UIFactory.label("●", 14, UIFactory.C_GREEN))
	security_row.add_child(UIFactory.label("本地密钥策略已启用：应用时只更新内存，持久化配置会明确跳过 API Key。", 13, Color("#9fc2a5")))
	security.add_child(security_row)
	content.add_child(security)
	var probe_row := HBoxContainer.new()
	probe_row.add_theme_constant_override("separation", 10)
	_api_status = UIFactory.label("", 13, UIFactory.C_MUTED)
	_api_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	probe_row.add_child(_api_status)
	_probe_button = UIFactory.button("测试连接", "normal", 42)
	_probe_button.name = "ApiProbeButton"
	_probe_button.custom_minimum_size.x = 126
	_probe_button.pressed.connect(_run_api_probe)
	probe_row.add_child(_probe_button)
	content.add_child(probe_row)
	return page


func _build_gameplay_page() -> Control:
	var page := _new_page("Gameplay", 1)
	var content: VBoxContainer = page.get_meta("content")
	_recent_slider = _add_slider_row(content, "最近上下文", "每回合连续发送的最近消息数量。", 1, 60, 1, " 条").slider
	_relevant_slider = _add_slider_row(content, "相关检索", "从较早历史中检索的高相关记录数量。", 0, 30, 1, " 条").slider
	_temperature_slider = _add_slider_row(content, "叙事温度", "越高越发散；规则裁判仍由客户端完成。", 0.0, 2.0, 0.05, "", 2).slider
	_max_tokens_slider = _add_slider_row(content, "最大输出", "限制单次 AI 回复的输出预算。", 256, 8192, 128, " tokens").slider

	var horror := _add_slider_row(content, "恐怖强度", "0 关闭高危演出，1 克制，2 完整。", 0, 2, 1, "")
	_horror_slider = horror.slider
	_horror_value = horror.value_label
	_horror_slider.value_changed.connect(_refresh_horror_label)

	_choice_hints_check = _add_toggle_row(content, "行动提示", "在选项下显示风险方向提示。")
	_confirm_risky_check = _add_toggle_row(content, "危险行动确认", "对直视、闯入、触碰等高风险行为二次确认。")
	_auto_scroll_check = _add_toggle_row(content, "自动跟随叙事", "新回合完成后滚动到最新剧情卡片。")
	return page


func _build_audio_page() -> Control:
	var page := _new_page("AudioMix", 2)
	var content: VBoxContainer = page.get_meta("content")
	_sound_enabled_check = _add_toggle_row(content, "启用声音", "总开关；关闭后立即停止音效与环境声。")
	_sound_enabled_check.toggled.connect(_update_dependencies)
	_master_slider = _add_slider_row(content, "主音量", "所有非空间音效与氛围的总增益。", 0, 100, 1, "%").slider
	_effects_slider = _add_slider_row(content, "交互音效", "点击、确认、拒绝、物品与异常提示。", 0, 100, 1, "%").slider
	_ambience_slider = _add_slider_row(content, "环境氛围", "雨声、低频脉冲与档案室底噪。", 0, 100, 1, "%").slider

	var note := UIFactory.panel(Color("#11100e"), Color("#3c332a"), 6, 10)
	note.add_child(UIFactory.label("声音设置会在应用后通过 AudioStreamPlayer 的线性音量实时更新；预览区不会主动播放声音。", 13, UIFactory.C_MUTED))
	content.add_child(note)
	return page


func _build_accessibility_page() -> Control:
	var page := _new_page("Accessibility", 3)
	var content: VBoxContainer = page.get_meta("content")
	var embedded_notice := UIFactory.panel(Color("#21190f"), Color("#9b7135"), 6, 10)
	embedded_notice.name = "EmbeddedDisplayNotice"
	embedded_notice.visible = not AppSettings.can_apply_window_changes()
	embedded_notice.add_child(UIFactory.label(
		"当前由 Godot 编辑器嵌入运行：官方限制下无法改变宿主窗口尺寸或切换全屏。选择仍会保存；请在编辑器“游戏”面板右上菜单关闭“下次运行嵌入游戏”，再重新运行测试。",
		13,
		UIFactory.C_GOLD_SOFT))
	content.add_child(embedded_notice)

	_window_mode_option = _option_button("WindowModeOption")
	_window_mode_option.add_item("窗口化")
	_window_mode_option.add_item("无边框全屏")
	_window_mode_option.item_selected.connect(_on_option_selected)
	_add_form_row(content, "显示模式", "无边框全屏会覆盖当前显示器，但不会切换显示器的视频模式。", _window_mode_option)

	_window_size_option = _option_button("WindowSizeOption")
	for resolution in AppSettings.WINDOW_SIZES:
		_window_size_option.add_item("%d × %d" % [resolution.x, resolution.y])
	_window_size_option.item_selected.connect(_on_option_selected)
	_add_form_row(content, "窗口尺寸", "应用后调整窗口并在当前屏幕居中；窗口边框不接受自由拖拽缩放。", _window_size_option)

	_frame_rate_option = _option_button("FrameRateOption")
	for frame_limit in AppSettings.FRAME_RATE_LIMITS:
		_frame_rate_option.add_item("不限制" if frame_limit == 0 else "%d FPS" % frame_limit)
	_frame_rate_option.item_selected.connect(_on_option_selected)
	_add_form_row(content, "帧率上限", "限制渲染帧率以降低功耗；VSync 或硬件性能可能使实际帧率更低。", _frame_rate_option)

	_text_scale_slider = _add_slider_row(content, "文字比例", "同步调整正文与规则阅读比例。", 90, 130, 5, "%").slider
	_shake_slider = _add_slider_row(content, "异常动态强度", "仅影响高危文本效果；降低动态时自动停用。", 0, 100, 1, "%").slider
	_reduced_motion_check = _add_toggle_row(content, "降低动态效果", "停用危险文本位移，并让界面过渡直接完成。")
	_reduced_motion_check.toggled.connect(_update_dependencies)
	_high_contrast_check = _add_toggle_row(content, "高对比阅读", "提高预览与正文的明暗分离。")
	_debug_observer_check = _add_toggle_row(content, "调试观察器", "显示本回合规则、历史、Token 预算与原始状态补丁。")

	var accessibility := UIFactory.panel(Color("#101318"), Color("#3a5060"), 6, 10)
	accessibility.add_child(UIFactory.label("建议：容易眩晕时启用“降低动态效果”；该选项优先于恐怖强度与抖动数值。", 13, Color("#9fb8c7")))
	content.add_child(accessibility)
	return page


func _new_page(node_name: String, definition_index: int) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = node_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 12)
	scroll.add_child(margin)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 9)
	margin.add_child(content)
	var definition: Dictionary = PAGE_DEFINITIONS[definition_index]
	content.add_child(UIFactory.eyebrow(str(definition.eyebrow)))
	content.add_child(UIFactory.title(str(definition.title), 27))
	content.add_child(UIFactory.label(str(definition.hint), 14, UIFactory.C_MUTED))
	content.add_child(_vertical_space(4))
	scroll.set_meta("content", content)
	_style_scrollbar(scroll)
	return scroll


func _build_live_preview() -> Control:
	_preview_panel = UIFactory.panel(Color("#15110f"), Color("#72542c"), 7, 10)
	_preview_panel.custom_minimum_size.y = 102
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	_preview_panel.add_child(row)

	var summary_box := VBoxContainer.new()
	summary_box.custom_minimum_size.x = 330
	summary_box.add_child(UIFactory.eyebrow("LIVE PREVIEW / 实时预览"))
	_preview_summary = UIFactory.label("", 13, UIFactory.C_MUTED)
	_preview_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_box.add_child(_preview_summary)
	row.add_child(summary_box)

	_preview_text = UIFactory.rich_text(76)
	_preview_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_text.fit_content = false
	_preview_text.scroll_active = false
	_preview_text.selection_enabled = false
	_preview_text.add_theme_stylebox_override("normal", UIFactory.style(Color("#0c0b0a"), Color("#3c3026"), 5, 1, 10))
	row.add_child(_preview_text)
	return _preview_panel


func _build_footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var restore := UIFactory.button("恢复推荐", "ghost", 48)
	restore.custom_minimum_size.x = 170
	restore.pressed.connect(_restore_recommended)
	row.add_child(restore)
	_feedback_label = UIFactory.label("", 13, UIFactory.C_MUTED)
	_feedback_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feedback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_feedback_label)
	var close := UIFactory.button("关闭", "ghost", 48)
	close.custom_minimum_size.x = 130
	close.pressed.connect(_close_dialog)
	row.add_child(close)
	var apply := UIFactory.button("应用设置并返回", "primary", 48)
	apply.custom_minimum_size.x = 240
	apply.pressed.connect(_apply_and_close)
	row.add_child(apply)
	return row


func _add_form_row(parent: VBoxContainer, title_text: String, hint: String, control: Control) -> void:
	var panel := UIFactory.panel(Color("#100e0c"), Color("#352d26"), 6, 9)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	var copy := VBoxContainer.new()
	copy.custom_minimum_size.x = 285
	copy.add_child(UIFactory.label(title_text, 15, UIFactory.C_TEXT))
	copy.add_child(UIFactory.label(hint, 12, UIFactory.C_MUTED))
	row.add_child(copy)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	parent.add_child(panel)


func _add_slider_row(
	parent: VBoxContainer,
	title_text: String,
	hint: String,
	minimum: float,
	maximum: float,
	step: float,
	suffix: String,
	decimals: int = 0
) -> Dictionary:
	var holder := HBoxContainer.new()
	holder.add_theme_constant_override("separation", 10)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.y = 32
	var value_label := UIFactory.label("", 14, UIFactory.C_GOLD_SOFT)
	value_label.custom_minimum_size.x = 92
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	holder.add_child(slider)
	holder.add_child(value_label)
	slider.value_changed.connect(_on_slider_changed.bind(value_label, suffix, decimals))
	_add_form_row(parent, title_text, hint, holder)
	_on_slider_changed(slider.value, value_label, suffix, decimals)
	return {"slider": slider, "value_label": value_label}


func _add_toggle_row(parent: VBoxContainer, title_text: String, hint: String) -> CheckBox:
	var check := CheckBox.new()
	check.text = "启用"
	check.custom_minimum_size.x = 120
	check.toggled.connect(_on_toggle_changed)
	_add_form_row(parent, title_text, hint, check)
	return check


func _load_from_settings() -> void:
	_updating = true
	_provider = AppSettings.provider if _provider_buttons.has(AppSettings.provider) else "custom"
	_endpoint_edit.text = AppSettings.endpoint
	_model_edit.text = AppSettings.model
	_api_key_edit.text = AppSettings.api_key
	_recent_slider.value = AppSettings.recent_count
	_relevant_slider.value = AppSettings.relevant_count
	_temperature_slider.value = AppSettings.temperature
	_max_tokens_slider.value = AppSettings.max_tokens
	_horror_slider.value = AppSettings.horror_level
	_shake_slider.value = AppSettings.shake_intensity
	_text_scale_slider.value = AppSettings.text_scale
	_choice_hints_check.button_pressed = AppSettings.choice_hints
	_confirm_risky_check.button_pressed = AppSettings.confirm_risky
	_auto_scroll_check.button_pressed = AppSettings.auto_scroll
	_sound_enabled_check.button_pressed = AppSettings.sound_enabled
	_master_slider.value = AppSettings.master_volume
	_effects_slider.value = AppSettings.effects_mix
	_ambience_slider.value = AppSettings.ambience_mix
	_reduced_motion_check.button_pressed = AppSettings.reduced_motion
	_high_contrast_check.button_pressed = AppSettings.high_contrast
	_debug_observer_check.button_pressed = AppSettings.debug_observer
	_window_mode_option.select(AppSettings.WINDOW_MODE_IDS.find(AppSettings.window_mode) if AppSettings.window_mode in AppSettings.WINDOW_MODE_IDS else 0)
	_window_size_option.select(_window_size_index(Vector2i(AppSettings.window_width, AppSettings.window_height)))
	_frame_rate_option.select(_frame_rate_index(AppSettings.max_fps))
	_set_provider_button(_provider)
	_active_preset = _matching_preset()
	_set_preset_button(_active_preset)
	_nav_buttons[0].set_pressed_no_signal(true)
	_tabs.current_tab = 0
	_updating = false
	_refresh_horror_label(_horror_slider.value)
	_update_dependencies()
	_update_preview()


func _apply_preset_to_form(index: int) -> void:
	if index < 0 or index >= PRESETS.size():
		return
	_updating = true
	var values: Dictionary = PRESETS[index].values
	_text_scale_slider.value = values.text_scale
	_horror_slider.value = values.horror_level
	_shake_slider.value = values.shake_intensity
	_reduced_motion_check.button_pressed = values.reduced_motion
	_high_contrast_check.button_pressed = values.high_contrast
	_sound_enabled_check.button_pressed = values.sound_enabled
	_master_slider.value = values.master_volume
	_effects_slider.value = values.effects_mix
	_ambience_slider.value = values.ambience_mix
	_active_preset = index
	_set_preset_button(index)
	_updating = false
	_feedback_label.text = "已载入“%s”，应用前仍可继续调整。" % PRESETS[index].name
	_feedback_label.add_theme_color_override("font_color", UIFactory.C_GOLD_SOFT)
	_update_dependencies()
	_update_preview()


func _restore_recommended() -> void:
	_updating = true
	_provider = "offline"
	_set_provider_button(_provider)
	_endpoint_edit.text = "https://api.deepseek.com"
	_model_edit.text = "deepseek-v4-flash"
	_recent_slider.value = 15
	_relevant_slider.value = 5
	_temperature_slider.value = 0.85
	_max_tokens_slider.value = 1800
	_choice_hints_check.button_pressed = true
	_confirm_risky_check.button_pressed = false
	_auto_scroll_check.button_pressed = true
	_debug_observer_check.button_pressed = false
	_window_mode_option.select(0)
	_window_size_option.select(_window_size_index(Vector2i(1440, 810)))
	_frame_rate_option.select(_frame_rate_index(60))
	_updating = false
	_apply_preset_to_form(0)
	_feedback_label.text = "推荐值已恢复到表单，尚未保存；现有 API Key 未被清除。"
	_update_preview()


func _select_provider(provider_id: String) -> void:
	_provider = provider_id
	_set_provider_button(provider_id)
	if provider_id == "deepseek":
		if _endpoint_edit.text.strip_edges().is_empty():
			_endpoint_edit.text = "https://api.deepseek.com"
		if _model_edit.text.strip_edges().is_empty():
			_model_edit.text = "deepseek-chat"
	_mark_changed()


func _show_page(index: int) -> void:
	if index < 0 or index >= _tabs.get_tab_count():
		return
	_attach_page(index)
	_tabs.current_tab = index
	for button_index in range(_nav_buttons.size()):
		_nav_buttons[button_index].set_pressed_no_signal(button_index == index)
	if not AppSettings.reduced_motion:
		UIFactory.fade_in(_tabs.get_current_tab_control(), 0.14)


func _apply_and_close() -> void:
	var error_message := _validate_form()
	if not error_message.is_empty():
		_feedback_label.text = error_message
		_feedback_label.add_theme_color_override("font_color", Color("#dc747b"))
		_profile_chip.text = "CHECK REQUIRED / 需要检查"
		return

	AppSettings.provider = _provider
	AppSettings.endpoint = _endpoint_edit.text.strip_edges()
	AppSettings.model = _model_edit.text.strip_edges()
	AppSettings.api_key = _api_key_edit.text.strip_edges()
	AppSettings.recent_count = roundi(_recent_slider.value)
	AppSettings.relevant_count = roundi(_relevant_slider.value)
	AppSettings.temperature = _temperature_slider.value
	AppSettings.max_tokens = roundi(_max_tokens_slider.value)
	AppSettings.horror_level = roundi(_horror_slider.value)
	AppSettings.shake_intensity = roundi(_shake_slider.value)
	AppSettings.text_scale = roundi(_text_scale_slider.value)
	AppSettings.choice_hints = _choice_hints_check.button_pressed
	AppSettings.confirm_risky = _confirm_risky_check.button_pressed
	AppSettings.auto_scroll = _auto_scroll_check.button_pressed
	AppSettings.sound_enabled = _sound_enabled_check.button_pressed
	AppSettings.master_volume = roundi(_master_slider.value)
	AppSettings.effects_mix = roundi(_effects_slider.value)
	AppSettings.ambience_mix = roundi(_ambience_slider.value)
	AppSettings.reduced_motion = _reduced_motion_check.button_pressed
	AppSettings.high_contrast = _high_contrast_check.button_pressed
	AppSettings.debug_observer = _debug_observer_check.button_pressed
	AppSettings.window_mode = AppSettings.WINDOW_MODE_IDS[clampi(_window_mode_option.selected, 0, AppSettings.WINDOW_MODE_IDS.size() - 1)]
	var selected_size: Vector2i = AppSettings.WINDOW_SIZES[clampi(_window_size_option.selected, 0, AppSettings.WINDOW_SIZES.size() - 1)]
	AppSettings.window_width = selected_size.x
	AppSettings.window_height = selected_size.y
	AppSettings.max_fps = AppSettings.FRAME_RATE_LIMITS[clampi(_frame_rate_option.selected, 0, AppSettings.FRAME_RATE_LIMITS.size() - 1)]

	var save_error: Error = AppSettings.save_settings()
	if save_error != OK:
		_feedback_label.text = "设置无法写入 user://settings.cfg（错误码 %d）。" % save_error
		_feedback_label.add_theme_color_override("font_color", Color("#dc747b"))
		_profile_chip.text = "SAVE FAILED / 保存失败"
		return
	if not AppSettings.can_apply_window_changes():
		AppSettings.apply_runtime_display()
		_feedback_label.text = "设置已保存，帧率已应用；编辑器嵌入模式不支持窗口尺寸或全屏。关闭“下次运行嵌入游戏”后重新运行即可看到所选尺寸。"
		_feedback_label.add_theme_color_override("font_color", UIFactory.C_GOLD_SOFT)
		_profile_chip.text = "SAVED / 待独立运行"
		return
	_profile_chip.text = "SAVED / 已同步"
	_close_dialog()
	AppSettings.apply_runtime_display.call_deferred()


func _validate_form() -> String:
	if _provider == "offline":
		return ""
	var endpoint := _endpoint_edit.text.strip_edges()
	if not _allowed_endpoint(endpoint):
		return "Endpoint 必须使用 HTTPS；只有 localhost / 127.0.0.1 可使用 HTTP。"
	if _model_edit.text.strip_edges().is_empty():
		_model_edit.grab_focus()
		return "请填写服务商提供的模型标识。"
	if _api_key_edit.text.strip_edges().is_empty():
		_api_key_edit.grab_focus()
		return "联网叙事需要 API Key；它只会保留在本次进程内。"
	return ""


func _allowed_endpoint(value: String) -> bool:
	var lowered := value.strip_edges().to_lower()
	if lowered.begins_with("https://"):
		return true
	return lowered == "http://127.0.0.1" \
		or lowered.begins_with("http://127.0.0.1:") \
		or lowered.begins_with("http://127.0.0.1/") \
		or lowered == "http://localhost" \
		or lowered.begins_with("http://localhost:") \
		or lowered.begins_with("http://localhost/")


func _on_slider_changed(value: float, value_label: Label, suffix: String, decimals: int) -> void:
	value_label.text = ("%.2f%s" % [value, suffix]) if decimals > 0 else ("%d%s" % [roundi(value), suffix])
	if not _updating:
		_mark_changed()


func _refresh_horror_label(_value: float) -> void:
	if _horror_value == null:
		return
	_horror_value.text = ["关闭", "克制", "完整"][clampi(roundi(_horror_slider.value), 0, 2)]
	if not _updating:
		_update_dependencies()
		_update_preview()


func _on_text_changed(_value: String) -> void:
	if not _updating:
		_mark_changed()


func _on_toggle_changed(_pressed: bool) -> void:
	if not _updating:
		_mark_changed()


func _on_option_selected(_index: int) -> void:
	if not _updating:
		_mark_changed()


func _mark_changed() -> void:
	if _updating:
		return
	_active_preset = _matching_preset()
	_set_preset_button(_active_preset)
	_feedback_label.text = "当前表单有尚未应用的更改。"
	_feedback_label.add_theme_color_override("font_color", UIFactory.C_MUTED)
	_profile_chip.text = "UNSAVED / 尚未应用"
	_update_dependencies()
	_update_preview()


func _matching_preset() -> int:
	if _text_scale_slider == null:
		return -1
	for index in range(PRESETS.size()):
		var values: Dictionary = PRESETS[index].values
		if roundi(_text_scale_slider.value) == int(values.text_scale) \
			and roundi(_horror_slider.value) == int(values.horror_level) \
			and roundi(_shake_slider.value) == int(values.shake_intensity) \
			and _reduced_motion_check.button_pressed == bool(values.reduced_motion) \
			and _high_contrast_check.button_pressed == bool(values.high_contrast) \
			and _sound_enabled_check.button_pressed == bool(values.sound_enabled) \
			and roundi(_master_slider.value) == int(values.master_volume) \
			and roundi(_effects_slider.value) == int(values.effects_mix) \
			and roundi(_ambience_slider.value) == int(values.ambience_mix):
			return index
	return -1


func _set_provider_button(provider_id: String) -> void:
	for id in _provider_buttons:
		(_provider_buttons[id] as Button).set_pressed_no_signal(str(id) == provider_id)


func _set_preset_button(index: int) -> void:
	for button_index in range(_preset_buttons.size()):
		_preset_buttons[button_index].set_pressed_no_signal(button_index == index)


func _update_dependencies(_unused: bool = false) -> void:
	var live_provider := _provider != "offline"
	_endpoint_edit.editable = live_provider
	_model_edit.editable = live_provider
	_api_key_edit.editable = live_provider
	_endpoint_edit.modulate = Color.WHITE if live_provider else Color(1, 1, 1, 0.46)
	_model_edit.modulate = Color.WHITE if live_provider else Color(1, 1, 1, 0.46)
	_api_key_edit.modulate = Color.WHITE if live_provider else Color(1, 1, 1, 0.46)
	if _probe_button != null:
		_probe_button.disabled = not live_provider or _probe_busy
		_probe_button.text = "连接中……" if _probe_busy else "测试连接"
	var audio_disabled := not _sound_enabled_check.button_pressed
	_master_slider.editable = not audio_disabled
	_effects_slider.editable = not audio_disabled
	_ambience_slider.editable = not audio_disabled
	_window_size_option.disabled = _window_mode_option.selected == 1
	_shake_slider.editable = not _reduced_motion_check.button_pressed and roundi(_horror_slider.value) > 0
	_update_preview()


func _update_preview() -> void:
	if _preview_text == null:
		return
	var preset_name := "自定义调整" if _active_preset < 0 else str(PRESETS[_active_preset].name)
	var provider_name := _provider_label(_provider)
	var motion_name := "降低" if _reduced_motion_check.button_pressed else "完整"
	var sound_name := "关闭" if not _sound_enabled_check.button_pressed else "%d%%" % roundi(_master_slider.value)
	var resolution: Vector2i = AppSettings.WINDOW_SIZES[clampi(_window_size_option.selected, 0, AppSettings.WINDOW_SIZES.size() - 1)]
	var frame_limit: int = AppSettings.FRAME_RATE_LIMITS[clampi(_frame_rate_option.selected, 0, AppSettings.FRAME_RATE_LIMITS.size() - 1)]
	var frame_name := "不限制" if frame_limit == 0 else "%d FPS" % frame_limit
	var display_name := "无边框全屏" if _window_mode_option.selected == 1 else "%d×%d 窗口" % [resolution.x, resolution.y]
	_preview_summary.text = "%s\n%s  ·  %s  ·  %s\n文字 %d%%  ·  动效%s  ·  声音%s" % [preset_name, provider_name, display_name, frame_name, roundi(_text_scale_slider.value), motion_name, sound_name]

	var allow_motion := not _reduced_motion_check.button_pressed and roundi(_horror_slider.value) > 0
	var strength := clampf(_shake_slider.value / 100.0, 0.0, 1.0)
	var sample := "[color=#b79b68][font_size=14]ARCHIVE SAMPLE · 完整动效[/font_size][/color]\n走廊尽头的广播叫出了你的名字。[blood][dread strength=%.2f]不要回应镜子里的点名。[/dread][/blood]\n[color=#d8bd78]02[/color]  检查门缝下的影子" % strength
	_preview_text.text = SafeBBCode.prepare(sample, allow_motion)
	var preview_font_size := clampi(roundi(16.0 * _text_scale_slider.value / 100.0), 14, 22)
	_preview_text.add_theme_font_size_override("normal_font_size", preview_font_size)
	_preview_text.add_theme_font_size_override("bold_font_size", preview_font_size)
	var preview_bg := Color("#020202") if _high_contrast_check.button_pressed else Color("#0c0b0a")
	var preview_border := Color("#b38b42") if _high_contrast_check.button_pressed else Color("#3c3026")
	_preview_text.add_theme_stylebox_override("normal", UIFactory.style(preview_bg, preview_border, 5, 1, 10))

	if _probe_busy:
		_api_status.text = "正在验证接口、模型与 JSON 响应……"
		_api_status.add_theme_color_override("font_color", Color("#d0aa68"))
	elif _provider == "offline":
		_api_status.text = "离线模式：无需密钥，只运行内置《夜间档案室》完整体验流程。"
		_api_status.add_theme_color_override("font_color", UIFactory.C_GREEN)
	elif not _allowed_endpoint(_endpoint_edit.text):
		_api_status.text = "Endpoint 尚未通过本地安全检查。"
		_api_status.add_theme_color_override("font_color", Color("#dc747b"))
	elif _model_edit.text.strip_edges().is_empty() or _api_key_edit.text.strip_edges().is_empty():
		_api_status.text = "联网配置未完成：模型与 API Key 都是必填项。"
		_api_status.add_theme_color_override("font_color", Color("#d0aa68"))
	else:
		_api_status.text = "配置完整：应用后将连接 %s；密钥不会落盘。" % _provider_label(_provider)
		_api_status.add_theme_color_override("font_color", UIFactory.C_GREEN)


func _run_api_probe() -> void:
	if _probe_busy:
		return
	if _provider == "offline":
		_api_status.text = "离线体验不需要测试连接。"
		_api_status.add_theme_color_override("font_color", UIFactory.C_GREEN)
		return
	var validation_error := _validate_form()
	if not validation_error.is_empty():
		_api_status.text = validation_error
		_api_status.add_theme_color_override("font_color", Color("#dc747b"))
		return
	if _probe == null:
		_probe = AiGateway.new()
		_probe.name = "ConnectionProbe"
		add_child(_probe)
		_probe.completed.connect(_on_probe_completed)
		_probe.failed.connect(_on_probe_failed)
	_probe_serial += 1
	_probe_busy = true
	_update_dependencies()
	_update_preview()
	var messages: Array[Dictionary] = [
		{"role": "system", "content": "只回复一个紧凑 JSON 对象：{\"ok\":true}"},
		{"role": "user", "content": "connection test"},
	]
	var send_error := _probe.send_chat(
		_probe_serial,
		_form_chat_url(),
		_api_key_edit.text.strip_edges(),
		_model_edit.text.strip_edges(),
		messages,
		0.0,
		128)
	if send_error != OK:
		_finish_probe(false, "无法创建测试请求：%s" % error_string(send_error))


func _on_probe_completed(request_id: int, content: String, _raw_response: Dictionary) -> void:
	if request_id != _probe_serial or not _probe_busy:
		return
	var parser := JSON.new()
	var parse_error := parser.parse(content)
	if parse_error != OK or not parser.data is Dictionary:
		_finish_probe(false, "接口已响应，但模型没有返回约定 JSON：第 %d 行 %s" % [parser.get_error_line(), parser.get_error_message()])
		return
	_finish_probe(true, "连接成功：接口、模型与 JSON 输出均可用。")


func _on_probe_failed(request_id: int, message: String, detail: String) -> void:
	if request_id != _probe_serial or not _probe_busy:
		return
	_finish_probe(false, "%s %s" % [message, detail])


func _finish_probe(succeeded: bool, message: String) -> void:
	_probe_busy = false
	if _probe_button != null:
		_probe_button.disabled = _provider == "offline"
		_probe_button.text = "再次测试" if succeeded else "重新测试"
	_api_status.text = message
	_api_status.add_theme_color_override("font_color", UIFactory.C_GREEN if succeeded else Color("#dc747b"))


func _form_chat_url() -> String:
	var base := _endpoint_edit.text.strip_edges().trim_suffix("/")
	if base.ends_with("/chat/completions"):
		return base
	if base.ends_with("/v1"):
		return base + "/chat/completions"
	return base + "/v1/chat/completions"


func _provider_label(provider_id: String) -> String:
	for entry in PROVIDERS:
		if str(entry.id) == provider_id:
			return str(entry.label)
	return "自定义 API"


func _style_scrollbar(scroll: ScrollContainer) -> void:
	var bar := scroll.get_v_scroll_bar()
	bar.add_theme_stylebox_override("scroll", UIFactory.style(Color("#0e0c0b"), Color("#2e2721"), 4, 0, 2))
	bar.add_theme_stylebox_override("grabber", UIFactory.style(Color("#544331"), Color("#544331"), 4, 0, 2))
	bar.add_theme_stylebox_override("grabber_highlight", UIFactory.style(Color("#886a37"), Color("#886a37"), 4, 0, 2))
	bar.add_theme_stylebox_override("grabber_pressed", UIFactory.style(UIFactory.C_GOLD_SOFT, UIFactory.C_GOLD_SOFT, 4, 0, 2))


func _option_button(node_name: String) -> OptionButton:
	var result := OptionButton.new()
	result.name = node_name
	result.custom_minimum_size.y = 46
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.add_theme_stylebox_override("normal", UIFactory.style(Color("#0c0b0a"), UIFactory.C_BORDER, 6, 1, 10))
	result.add_theme_stylebox_override("hover", UIFactory.style(UIFactory.C_PANEL_2, Color("#765936"), 6, 1, 10))
	result.add_theme_stylebox_override("pressed", UIFactory.style(UIFactory.C_PANEL_3, UIFactory.C_GOLD, 6, 1, 10))
	result.add_theme_stylebox_override("focus", UIFactory.style(Color("#0c0b0a"), UIFactory.C_GOLD_SOFT, 6, 2, 9))
	return result


func _window_size_index(value: Vector2i) -> int:
	var index := AppSettings.WINDOW_SIZES.find(value)
	return index if index >= 0 else AppSettings.WINDOW_SIZES.find(Vector2i(1440, 810))


func _frame_rate_index(value: int) -> int:
	var index := AppSettings.FRAME_RATE_LIMITS.find(value)
	return index if index >= 0 else AppSettings.FRAME_RATE_LIMITS.find(60)


func _close_dialog() -> void:
	if _closing:
		return
	_closing = true
	if _probe != null:
		_probe.cancel_active()
	closed.emit()
	hide()


func _expander() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer


func _vertical_space(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	return spacer
