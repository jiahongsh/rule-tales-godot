extends Window

signal start_requested(seed: int, days_limit: int)

const UINT32_MAX := 4294967295
const MIN_DAYS := 3
const MAX_DAYS := 14
const DEFAULT_DAYS := 7

var _built := false
var _updating := false
var _closing := false
var _valid_seed := -1
var _last_forge: Dictionary = {}

var _seed_edit: LineEdit
var _seed_feedback: Label
var _days_slider: HSlider
var _days_value: Label
var _deadline_note: Label
var _preflight_status: Label
var _chapter_value: Label
var _rule_value: Label
var _chain_value: Label
var _tamper_value: Label
var _preflight_details: Label
var _preflight_chapters: Label
var _seed_meta: Label
var _start_button: Button


func _ready() -> void:
	title = "异闻夜谈 · 规则种子限时调查局"
	borderless = true
	theme = UIFactory.build_theme()
	transient = true
	transient_to_focused = true
	exclusive = true
	min_size = Vector2i(1120, 720)
	close_requested.connect(_cancel_dialog)
	_updating = true
	_build_interface()
	_days_slider.value = DEFAULT_DAYS
	_seed_edit.text = str(randi())
	_updating = false
	_on_days_changed(_days_slider.value)
	_refresh_preflight()


func open_dialog() -> void:
	_closing = false
	_updating = true
	_seed_edit.text = str(randi())
	_updating = false
	_refresh_preflight()
	popup_centered_ratio(0.9)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_cancel_dialog()


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

	var body_scroll := ScrollContainer.new()
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_scroll.custom_minimum_size.y = 260
	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	body.add_child(_build_theme_card())
	body.add_child(_build_configuration_card())
	body_scroll.add_child(body)
	_style_scrollbar(body_scroll)
	root.add_child(body_scroll)

	root.add_child(_build_preflight_panel())
	root.add_child(_build_footer())


func _build_header() -> Control:
	var panel := UIFactory.panel(Color("#15110f"), Color("#76582c"), 8, 15)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)

	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_child(UIFactory.eyebrow("RULE SEED / LIMITED INVESTIGATION"))
	copy.add_child(UIFactory.title("启封一份从未存在过的规则档案", 31))
	copy.add_child(UIFactory.label("种子决定规则、隐藏真伪、出口链与篡改埋点；AI 只负责演绎生成后的世界。", 14, UIFactory.C_MUTED))
	row.add_child(copy)

	var chip := UIFactory.panel(Color("#101713"), Color("#3e684a"), 6, 10)
	chip.custom_minimum_size.x = 235
	var chip_box := VBoxContainer.new()
	chip_box.add_child(UIFactory.eyebrow("LOCAL FORGE  /  本地生成"))
	var chip_hint := UIFactory.label("确定性 · 可复现 · 可解性校验", 12, UIFactory.C_GREEN)
	chip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip_box.add_child(chip_hint)
	chip.add_child(chip_box)
	row.add_child(chip)
	return panel


func _build_theme_card() -> Control:
	var card := UIFactory.panel(Color("#17120f"), Color("#8a6834"), 9, 0)
	card.custom_minimum_size.x = 375
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	card.add_child(root)

	var hero := Control.new()
	hero.custom_minimum_size.y = 245
	root.add_child(hero)

	var image := TextureRect.new()
	image.texture = load("res://assets/backgrounds/archive_lobby_v1.png")
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero.add_child(image)

	var shade := ColorRect.new()
	shade.color = Color(0.035, 0.026, 0.021, 0.62)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero.add_child(shade)

	var hero_margin := MarginContainer.new()
	hero_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hero_margin.add_theme_constant_override("margin_left", 20)
	hero_margin.add_theme_constant_override("margin_right", 20)
	hero_margin.add_theme_constant_override("margin_top", 18)
	hero_margin.add_theme_constant_override("margin_bottom", 18)
	hero.add_child(hero_margin)
	var hero_copy := VBoxContainer.new()
	hero_copy.add_child(UIFactory.eyebrow("THEME 01  /  APARTMENT"))
	hero_copy.add_child(_vertical_expander())
	var icon := UIFactory.label("⌂", 48, Color("#d3ad61"))
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_copy.add_child(icon)
	var title_label := UIFactory.title("雾栖公寓", 32)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_copy.add_child(title_label)
	var subtitle := UIFactory.label("一栋拒绝承认四楼存在的旧公寓", 14, Color("#c3b29f"))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_copy.add_child(subtitle)
	hero_copy.add_child(_vertical_expander())
	hero_margin.add_child(hero_copy)

	var information_margin := MarginContainer.new()
	information_margin.add_theme_constant_override("margin_left", 16)
	information_margin.add_theme_constant_override("margin_right", 16)
	information_margin.add_theme_constant_override("margin_top", 14)
	information_margin.add_theme_constant_override("margin_bottom", 14)
	root.add_child(information_margin)
	var information := VBoxContainer.new()
	information.add_theme_constant_override("separation", 9)
	information.add_child(UIFactory.eyebrow("ARCHIVE PROFILE / 档案画像"))
	information.add_child(UIFactory.label("入住登记、夜间走廊、物业告示与不存在的楼层会被重新组合。每个种子都生成一份不同但可完成的档案。", 14, UIFactory.C_TEXT))
	information.add_child(_theme_fact("章节池", "6 个手写章节"))
	information.add_child(_theme_fact("规则碎片", "程序抽取 12–18 条"))
	information.add_child(_theme_fact("调查节奏", "限时 20–40 分钟"))
	information.add_child(_theme_fact("主题状态", "已安装 · 版本 1"))
	information_margin.add_child(information)
	return card


func _build_configuration_card() -> Control:
	var card := UIFactory.panel(Color("#15120f"), Color("#4b3a2b"), 8, 14)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	card.add_child(root)
	root.add_child(UIFactory.eyebrow("RUN CONFIGURATION / 调查参数"))
	root.add_child(UIFactory.title("决定这一局留下怎样的记录", 25))

	_seed_edit = UIFactory.line_edit("0 – 4294967295")
	_seed_edit.max_length = 10
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_edit.text_changed.connect(_on_seed_changed)
	_seed_edit.text_submitted.connect(_on_seed_submitted)
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	seed_row.add_child(_seed_edit)
	var random_button := UIFactory.button("↻  随机", "ghost", 46)
	random_button.custom_minimum_size.x = 120
	random_button.pressed.connect(_randomize_seed)
	seed_row.add_child(random_button)
	root.add_child(_configuration_row("UINT32 SEED", "同一个主题与种子总会生成逐字一致的规则档案。", seed_row))
	_seed_feedback = UIFactory.label("", 12, UIFactory.C_MUTED)
	root.add_child(_seed_feedback)

	_days_slider = HSlider.new()
	_days_slider.min_value = MIN_DAYS
	_days_slider.max_value = MAX_DAYS
	_days_slider.step = 1
	_days_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_days_slider.custom_minimum_size.y = 34
	_days_slider.value_changed.connect(_on_days_changed)
	var days_row := HBoxContainer.new()
	days_row.add_theme_constant_override("separation", 8)
	var decrease := UIFactory.button("−", "ghost", 42)
	decrease.custom_minimum_size.x = 48
	decrease.pressed.connect(_nudge_days.bind(-1))
	days_row.add_child(decrease)
	days_row.add_child(_days_slider)
	var increase := UIFactory.button("+", "ghost", 42)
	increase.custom_minimum_size.x = 48
	increase.pressed.connect(_nudge_days.bind(1))
	days_row.add_child(increase)
	_days_value = UIFactory.label("7 天", 16, UIFactory.C_GOLD_SOFT)
	_days_value.custom_minimum_size.x = 72
	_days_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_days_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	days_row.add_child(_days_value)
	root.add_child(_configuration_row("DEADLINE / 期限", "期限范围为 3–14 天；耗尽时仍未逃离，将进入失踪结局。", days_row))
	_deadline_note = UIFactory.label("", 12, UIFactory.C_MUTED)
	root.add_child(_deadline_note)

	var architecture_heading := HBoxContainer.new()
	architecture_heading.add_child(UIFactory.eyebrow("HIDDEN STRUCTURE / 隐藏结构"))
	architecture_heading.add_child(_horizontal_expander())
	architecture_heading.add_child(UIFactory.label("由客户端裁判，不交给 AI 猜测", 12, UIFactory.C_GREEN))
	root.add_child(architecture_heading)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.add_child(_architecture_tile("12–18", "规则数量", "从人工碎片池确定性抽取"))
	grid.add_child(_architecture_tile("≥ 1", "出口链", "能力依赖闭合后才允许启封"))
	grid.add_child(_architecture_tile("封存", "真假图谱", "正文不会泄露真假判定"))
	grid.add_child(_architecture_tile("1–2", "篡改埋点", "局内改写后可校勘指认"))
	root.add_child(grid)
	return card


func _build_preflight_panel() -> Control:
	var panel := UIFactory.panel(Color("#111310"), Color("#526044"), 8, 12)
	panel.custom_minimum_size.y = 160
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	panel.add_child(root)

	var heading := HBoxContainer.new()
	heading.add_child(UIFactory.eyebrow("FORGE PREFLIGHT / 生成预检"))
	heading.add_child(_horizontal_expander())
	_preflight_status = UIFactory.label("正在检查…", 13, UIFactory.C_MUTED)
	heading.add_child(_preflight_status)
	root.add_child(heading)

	var metrics := HBoxContainer.new()
	metrics.add_theme_constant_override("separation", 8)
	var chapter_metric: Dictionary = _metric_tile("章节")
	_chapter_value = chapter_metric["value"] as Label
	metrics.add_child(chapter_metric["panel"] as Control)
	var rule_metric: Dictionary = _metric_tile("规则")
	_rule_value = rule_metric["value"] as Label
	metrics.add_child(rule_metric["panel"] as Control)
	var chain_metric: Dictionary = _metric_tile("出口链")
	_chain_value = chain_metric["value"] as Label
	metrics.add_child(chain_metric["panel"] as Control)
	var tamper_metric: Dictionary = _metric_tile("篡改位")
	_tamper_value = tamper_metric["value"] as Label
	metrics.add_child(tamper_metric["panel"] as Control)
	root.add_child(metrics)

	_preflight_details = UIFactory.label("", 13, UIFactory.C_TEXT)
	root.add_child(_preflight_details)
	_preflight_chapters = UIFactory.label("", 12, UIFactory.C_MUTED)
	root.add_child(_preflight_chapters)
	_seed_meta = UIFactory.label("", 12, Color("#827668"))
	root.add_child(_seed_meta)
	return panel


func _build_footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var privacy := UIFactory.label("生成过程只读取本地主题包；预检不会调用 AI 或改动当前存档。", 12, UIFactory.C_MUTED)
	privacy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	privacy.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(privacy)
	var cancel := UIFactory.button("取消", "ghost", 48)
	cancel.custom_minimum_size.x = 140
	cancel.pressed.connect(_cancel_dialog)
	row.add_child(cancel)
	_start_button = UIFactory.button("生成并开始", "primary", 48)
	_start_button.custom_minimum_size.x = 235
	_start_button.disabled = true
	_start_button.pressed.connect(_request_start)
	row.add_child(_start_button)
	return row


func _theme_fact(key: String, value: String) -> Control:
	var row := HBoxContainer.new()
	var key_label := UIFactory.label(key, 12, UIFactory.C_MUTED)
	key_label.custom_minimum_size.x = 90
	row.add_child(key_label)
	row.add_child(UIFactory.label(value, 13, UIFactory.C_TEXT))
	return row


func _configuration_row(title_text: String, hint: String, control: Control) -> Control:
	var panel := UIFactory.panel(Color("#100e0c"), Color("#352d26"), 6, 9)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	panel.add_child(root)
	var heading := HBoxContainer.new()
	heading.add_child(UIFactory.label(title_text, 14, UIFactory.C_GOLD_SOFT))
	heading.add_child(_horizontal_expander())
	heading.add_child(UIFactory.label(hint, 12, UIFactory.C_MUTED))
	root.add_child(heading)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(control)
	return panel


func _architecture_tile(value_text: String, title_text: String, hint: String) -> Control:
	var panel := UIFactory.panel(Color("#100e0c"), Color("#392f27"), 6, 9)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var value := UIFactory.label(value_text, 21, UIFactory.C_GOLD_SOFT)
	value.custom_minimum_size.x = 62
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_child(UIFactory.label(title_text, 13, UIFactory.C_TEXT))
	copy.add_child(UIFactory.label(hint, 11, UIFactory.C_MUTED))
	row.add_child(copy)
	return panel


func _metric_tile(caption: String) -> Dictionary:
	var panel := UIFactory.panel(Color("#0d100d"), Color("#33402f"), 6, 7)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var caption_label := UIFactory.label(caption, 12, UIFactory.C_MUTED)
	caption_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(caption_label)
	var value := UIFactory.label("—", 17, UIFactory.C_GOLD_SOFT)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return {"panel": panel, "value": value}


func _on_seed_changed(_text: String) -> void:
	if not _updating:
		_refresh_preflight()


func _on_seed_submitted(_text: String) -> void:
	_refresh_preflight()
	if not _start_button.disabled:
		_start_button.grab_focus()


func _randomize_seed() -> void:
	_seed_edit.text = str(randi())
	_refresh_preflight()
	_seed_edit.caret_column = _seed_edit.text.length()
	_seed_edit.grab_focus()
	_seed_edit.select_all()


func _nudge_days(delta: int) -> void:
	_days_slider.value = clampi(roundi(_days_slider.value) + delta, MIN_DAYS, MAX_DAYS)


func _on_days_changed(value: float) -> void:
	if _days_value == null:
		return
	var days := clampi(roundi(value), MIN_DAYS, MAX_DAYS)
	_days_value.text = "%d 天" % days
	var pace := "高压短局" if days <= 5 else ("标准调查" if days <= 9 else "长线调查")
	_deadline_note.text = "%s · 期限耗尽仍未逃离时，档案会将调查员列为失踪。" % pace
	if _start_button != null:
		_start_button.text = "生成并开始  ·  %d 天" % days


func _refresh_preflight() -> void:
	if _preflight_status == null:
		return
	var parsed := _parse_seed(_seed_edit.text)
	if not bool(parsed["ok"]):
		_show_preflight_error(str(parsed["error"]))
		return

	var seed := int(parsed["seed"])
	var forged: Dictionary = RuleForgeService.forge(seed)
	if not bool(forged.get("ok", false)):
		_show_preflight_error("生成器拒绝了这个组合：%s" % str(forged.get("error", "未知错误")))
		return

	_last_forge = forged
	_valid_seed = seed
	_start_button.disabled = false
	_seed_feedback.text = "UINT32 有效 · 预检已使用该种子完成一次真实生成"
	_seed_feedback.add_theme_color_override("font_color", UIFactory.C_GREEN)
	_preflight_status.text = "●  可解性通过  /  READY"
	_preflight_status.add_theme_color_override("font_color", UIFactory.C_GREEN)

	var rules: Array = forged.get("rules", []) if forged.get("rules", []) is Array else []
	var meta: Dictionary = forged.get("meta", {}) if forged.get("meta", {}) is Dictionary else {}
	var fragments: Array = meta.get("fragments", []) if meta.get("fragments", []) is Array else []
	var tamper_plans: Array = meta.get("tamperPlans", []) if meta.get("tamperPlans", []) is Array else []
	var chapters: Array[String] = []
	var chain_steps := 0
	for value in fragments:
		if not value is Dictionary:
			continue
		var fragment: Dictionary = value
		var chapter := str(fragment.get("chapter", ""))
		if not chapter.is_empty() and chapter not in chapters:
			chapters.append(chapter)
		if not str(fragment.get("chainId", "")).is_empty():
			chain_steps += 1

	_chapter_value.text = str(chapters.size())
	_rule_value.text = str(rules.size())
	_chain_value.text = "%d 步" % chain_steps
	_tamper_value.text = str(tamper_plans.size())
	_preflight_details.text = "《%s》已生成：出口能力依赖闭合，隐藏真伪写入客户端私有元数据；正文不会提前泄露答案。" % str(forged.get("display_name", "雾栖公寓"))
	_preflight_chapters.text = "本局章节  ·  %s" % "  /  ".join(chapters)
	_seed_meta.text = "SEED %d  ·  主题与碎片库版本不变时，可复现同一份档案。篡改位只显示数量，不显示目标。" % seed


func _show_preflight_error(message: String) -> void:
	_last_forge = {}
	_valid_seed = -1
	_start_button.disabled = true
	_seed_feedback.text = message
	_seed_feedback.add_theme_color_override("font_color", Color("#d9767d"))
	_preflight_status.text = "●  需要检查  /  BLOCKED"
	_preflight_status.add_theme_color_override("font_color", Color("#d9767d"))
	_chapter_value.text = "—"
	_rule_value.text = "—"
	_chain_value.text = "—"
	_tamper_value.text = "—"
	_preflight_details.text = "输入有效的 uint32 种子后，客户端会在这里运行一次真实生成与可解性校验。"
	_preflight_chapters.text = "不会调用 AI，也不会替换当前调查。"
	_seed_meta.text = "允许范围：0 – 4294967295"


func _parse_seed(input: String) -> Dictionary:
	var text := input.strip_edges()
	if text.is_empty():
		return {"ok": false, "error": "请输入种子，或点击“随机”。"}
	if not text.is_valid_int() or text.begins_with("-"):
		return {"ok": false, "error": "种子只能是 0–4294967295 的十进制整数。"}
	var value := text.to_int()
	if value < 0 or value > UINT32_MAX:
		return {"ok": false, "error": "种子超出 uint32 范围（最大 4294967295）。"}
	return {"ok": true, "seed": value, "error": ""}


func _request_start() -> void:
	_refresh_preflight()
	if _start_button.disabled or _valid_seed < 0 or _last_forge.is_empty():
		return
	var days := clampi(roundi(_days_slider.value), MIN_DAYS, MAX_DAYS)
	start_requested.emit(_valid_seed, days)
	_cancel_dialog()


func _cancel_dialog() -> void:
	if _closing:
		return
	_closing = true
	hide()


func _style_scrollbar(scroll: ScrollContainer) -> void:
	var bar := scroll.get_v_scroll_bar()
	bar.add_theme_stylebox_override("scroll", UIFactory.style(Color("#0e0c0b"), Color("#2e2721"), 4, 0, 2))
	bar.add_theme_stylebox_override("grabber", UIFactory.style(Color("#544331"), Color("#544331"), 4, 0, 2))
	bar.add_theme_stylebox_override("grabber_highlight", UIFactory.style(Color("#886a37"), Color("#886a37"), 4, 0, 2))
	bar.add_theme_stylebox_override("grabber_pressed", UIFactory.style(UIFactory.C_GOLD_SOFT, UIFactory.C_GOLD_SOFT, 4, 0, 2))


func _horizontal_expander() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer


func _vertical_expander() -> Control:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return spacer
