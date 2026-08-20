extends Control

signal continue_requested
signal offline_requested
signal campus_requested
signal apartment_requested
signal import_requested
signal settings_requested
signal saves_requested
signal workshop_requested
signal help_requested
signal quit_requested

var _menu_page: Control
var _selection_page: Control
var _continue_button: Button
var _ai_banner: PanelContainer
var _ai_message: Label
var _feedback: Label
var _summary: Label


func _ready() -> void:
	_build_background()
	_build_menu()
	_build_selection()
	show_menu()


func _build_background() -> void:
	var background := TextureRect.new()
	background.name = "ArchiveLobbyBackground"
	background.texture = load("res://assets/backgrounds/archive_lobby_v1.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.021, 0.018, 0.66)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var left_shade := ColorRect.new()
	left_shade.color = Color(0.018, 0.015, 0.013, 0.78)
	left_shade.anchor_bottom = 1.0
	left_shade.offset_right = 560
	left_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(left_shade)


func _build_menu() -> void:
	_menu_page = Control.new(); _menu_page.name = "StartMenuPage"
	_menu_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(_menu_page)
	var margin := MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 58); margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_right", 42); margin.add_theme_constant_override("margin_bottom", 30)
	_menu_page.add_child(margin)
	var row := HBoxContainer.new(); margin.add_child(row)
	var plate := UIFactory.panel(Color("#100d0bcf"), Color("#72542c"), 8, 22)
	plate.custom_minimum_size.x = 455; plate.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(plate)
	var menu := VBoxContainer.new(); menu.add_theme_constant_override("separation", 9); plate.add_child(menu)
	menu.add_child(UIFactory.eyebrow("RULE TALES / 异闻档案馆"))
	menu.add_child(UIFactory.title("异闻夜谈", 44))
	menu.add_child(UIFactory.label("在档案先写下你的名字之前，找到能够离开的那一页。", 17, Color("#b7a897")))
	menu.add_child(_spacer(18))
	_continue_button = _menu_button("继续上次记录", true)
	_continue_button.pressed.connect(func() -> void: continue_requested.emit())
	menu.add_child(_continue_button)
	var start := _menu_button("开始新的调查\nNEW INVESTIGATION", true)
	start.pressed.connect(show_selection); menu.add_child(start)
	var archives := _menu_button("档案管理\nARCHIVES")
	archives.pressed.connect(func() -> void: saves_requested.emit()); menu.add_child(archives)
	var workshop := _menu_button("规则工坊\nRULE WORKSHOP")
	workshop.pressed.connect(func() -> void: workshop_requested.emit()); menu.add_child(workshop)
	var settings := _menu_button("设置\nSETTINGS")
	settings.pressed.connect(func() -> void: settings_requested.emit()); menu.add_child(settings)
	var help := _menu_button("玩法与写作指南\nHELP  ·  F1")
	help.pressed.connect(func() -> void: help_requested.emit()); menu.add_child(help)
	var quit := _menu_button("退出游戏\nQUIT GAME  ·  CTRL+Q")
	quit.name = "QuitGameButton"
	quit.add_theme_color_override("font_color", Color("#e9b4a8"))
	quit.add_theme_color_override("font_hover_color", Color("#ffd5cc"))
	quit.pressed.connect(func() -> void: quit_requested.emit()); menu.add_child(quit)
	var stretch := Control.new(); stretch.size_flags_vertical = Control.SIZE_EXPAND_FILL; menu.add_child(stretch)
	_summary = UIFactory.label("", 13, Color("#9d8d7c")); menu.add_child(_summary)
	menu.add_child(UIFactory.label("16+  ·  心理恐怖与血腥文字  ·  联网模式请勿导入隐私信息", 12, Color("#776d63")))
	row.add_child(_expander())
	_feedback = UIFactory.label("", 14, Color("#efc674"))
	_feedback.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_feedback.offset_left = 18; _feedback.offset_right = -18; _feedback.offset_top = -64; _feedback.offset_bottom = -16
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.hide(); _menu_page.add_child(_feedback)
	refresh_summary()


func _build_selection() -> void:
	_selection_page = Control.new(); _selection_page.name = "CaseSelectionPage"
	_selection_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(_selection_page)
	var margin := MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]: margin.add_theme_constant_override("margin_%s" % side, 46)
	margin.add_theme_constant_override("margin_top", 30); margin.add_theme_constant_override("margin_bottom", 26)
	_selection_page.add_child(margin)
	var root := VBoxContainer.new(); root.add_theme_constant_override("separation", 14); margin.add_child(root)
	var top := HBoxContainer.new(); root.add_child(top)
	var back := UIFactory.button("返回主菜单  ·  ESC", "ghost", 46); back.custom_minimum_size.x = 240
	back.pressed.connect(show_menu); top.add_child(back); top.add_child(_expander())
	var plate := UIFactory.panel(Color("#0c0a09e8"), Color("#72542c"), 9, 28)
	plate.size_flags_vertical = Control.SIZE_EXPAND_FILL; root.add_child(plate)
	var content := VBoxContainer.new(); content.add_theme_constant_override("separation", 12); plate.add_child(content)
	var eyebrow := UIFactory.eyebrow("NEW INVESTIGATION / 新的调查"); eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; content.add_child(eyebrow)
	var heading := UIFactory.title("选择一份规则档案", 38); heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; content.add_child(heading)
	var hint := UIFactory.label("先选择调查方式；进入档案后，叙事核心才会生成场景与行动。", 15, Color("#988979")); hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; content.add_child(hint)
	var cases := GridContainer.new(); cases.columns = 4; cases.size_flags_vertical = Control.SIZE_EXPAND_FILL; cases.add_theme_constant_override("h_separation", 16); content.add_child(cases)
	var seed := _case_button(
		"CASE 01", "种", "规则种子", "需要 AI · 限时调查局",
		"生成未知规则、地图与异常；在期限耗尽前找到出口。", true
	)
	seed.pressed.connect(func() -> void: apartment_requested.emit()); cases.add_child(seed)
	var offline := _case_button(
		"CASE 02", "档", "离线体验", "无需 API · 约 10–15 分钟",
		"固定规则、完整六幕调查流程与可达成结局。"
	)
	offline.pressed.connect(func() -> void: offline_requested.emit()); cases.add_child(offline)
	var school := _case_button(
		"CASE 03", "校", "白槐中学", "需要 AI · 长篇多区域",
		"暴雨封校后的校园探索，章节完整，适合连续跑团。"
	)
	school.pressed.connect(func() -> void: campus_requested.emit()); cases.add_child(school)
	var private_case := _case_button(
		"CASE 04", "私", "私人档案", "需要 AI · TXT / Markdown",
		"导入自己的规则怪谈；使用尖括号划分章节。"
	)
	private_case.pressed.connect(func() -> void: import_requested.emit()); cases.add_child(private_case)
	_ai_banner = UIFactory.panel(Color("#251d12"), Color("#b08a3f"), 7, 14); _ai_banner.hide(); root.add_child(_ai_banner)
	var ai_row := HBoxContainer.new(); _ai_banner.add_child(ai_row)
	var copy := VBoxContainer.new(); copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL; ai_row.add_child(copy)
	copy.add_child(UIFactory.title("需要连接 AI 才能开始", 21))
	_ai_message = UIFactory.label("", 14, Color("#c9b997")); copy.add_child(_ai_message)
	var offline_fallback := UIFactory.button("改玩离线体验", "ghost", 46)
	offline_fallback.pressed.connect(func() -> void: offline_requested.emit()); ai_row.add_child(offline_fallback)
	var configure := UIFactory.button("立即配置 AI  →", "primary", 46)
	configure.pressed.connect(func() -> void: settings_requested.emit()); ai_row.add_child(configure)
	var footer := UIFactory.label("离线模式仅运行《夜间档案室》；其他档案需要在“设置”中连接 AI。", 14, Color("#988979")); footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; root.add_child(footer)


func show_menu() -> void:
	_menu_page.show(); _selection_page.hide(); _ai_banner.hide(); UIFactory.fade_in(_menu_page)


func handle_cancel_navigation() -> bool:
	if not visible or _selection_page == null or not _selection_page.visible:
		return false
	show_menu()
	return true


func show_selection() -> void:
	_menu_page.hide(); _selection_page.show(); _ai_banner.hide(); UIFactory.fade_in(_selection_page)


func show_ai_guide(action: String) -> void:
	show_selection()
	_ai_message.text = "“%s”需要实时叙事。请配置 API，或先游玩内置《夜间档案室》。" % action
	_ai_banner.show(); UIFactory.fade_in(_ai_banner)


func show_feedback(text: String) -> void:
	_feedback.text = text; _feedback.show(); UIFactory.fade_in(_feedback)


func set_continue_available(available: bool) -> void:
	_continue_button.disabled = not available
	_continue_button.text = "继续当前调查" if available else "继续上次记录 · 暂无存档"


func refresh_summary() -> void:
	if _summary == null: return
	var mode := "离线体验" if AppSettings.provider == "offline" else ("DeepSeek" if AppSettings.provider == "deepseek" else "自定义 API")
	_summary.text = "%s  ·  文字 %d%%  ·  %s动效  ·  音效%s" % [mode, AppSettings.text_scale, "降低" if AppSettings.reduced_motion else "完整", "开启" if AppSettings.sound_enabled else "关闭"]


func _menu_button(text: String, primary: bool = false) -> Button:
	var result := UIFactory.button(text, "primary" if primary else "normal", 54)
	result.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return result


func _case_button(
	case_id: String,
	icon_text: String,
	title_text: String,
	meta_text: String,
	description: String,
	featured: bool = false
) -> Button:
	var result := UIFactory.button("", "primary" if featured else "normal", 320)
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.size_flags_vertical = Control.SIZE_EXPAND_FILL
	result.tooltip_text = "%s · %s\n%s" % [title_text, meta_text, description]

	# The original Qt selection screen reads as four physical archive cards, not
	# four oversized text buttons. Keep the whole card clickable while letting
	# Containers own the internal layout at every supported resolution.
	var inset := MarginContainer.new()
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inset.add_theme_constant_override("margin_left", 18)
	inset.add_theme_constant_override("margin_right", 18)
	inset.add_theme_constant_override("margin_top", 22)
	inset.add_theme_constant_override("margin_bottom", 22)
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.add_child(inset)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.add_child(stack)
	var upper_space := Control.new()
	upper_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	upper_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(upper_space)

	var icon_plate := PanelContainer.new()
	icon_plate.custom_minimum_size = Vector2(76, 76)
	icon_plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_style := StyleBoxFlat.new()
	icon_style.bg_color = Color("#17120e66") if featured else Color("#0b0908b8")
	icon_style.border_color = Color("#f1cf73") if featured else Color("#967a47")
	icon_style.set_border_width_all(2)
	icon_style.set_corner_radius_all(38)
	icon_plate.add_theme_stylebox_override("panel", icon_style)
	stack.add_child(icon_plate)
	var icon := UIFactory.label(icon_text, 29, Color("#fff0bd") if featured else Color("#c6a760"))
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_plate.add_child(icon)

	var case_label := UIFactory.eyebrow(case_id)
	case_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	case_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(case_label)
	var title_label := UIFactory.title(title_text, 23)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(title_label)
	var meta_label := UIFactory.label(meta_text, 16, Color("#fff0bd") if featured else Color("#d5c6b5"))
	meta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(meta_label)
	var description_label := UIFactory.label(description, 15, Color("#ead7ba") if featured else Color("#b7a897"))
	description_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(description_label)

	var lower_space := Control.new()
	lower_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lower_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(lower_space)
	return result


func _expander() -> Control:
	var result := Control.new(); result.size_flags_horizontal = Control.SIZE_EXPAND_FILL; return result


func _spacer(height: int) -> Control:
	var result := Control.new(); result.custom_minimum_size.y = height; return result
