class_name UIFactory
extends RefCounted

const C_BG := Color("#0d0b0a")
const C_PANEL := Color("#171310")
const C_PANEL_2 := Color("#1e1814")
const C_PANEL_3 := Color("#251d17")
const C_BORDER := Color("#4a3a2b")
const C_BORDER_HOT := Color("#9b7737")
const C_GOLD := Color("#d7b860")
const C_GOLD_SOFT := Color("#c2a56c")
const C_TEXT := Color("#e9dfd2")
const C_MUTED := Color("#988979")
const C_BLUE := Color("#8fa9b9")
const C_GREEN := Color("#8eb490")
const C_RED := Color("#8e2934")

static var _shared_theme: Theme
static var _shared_sans_font: SystemFont
static var _shared_serif_font: SystemFont
static var _shared_styles: Dictionary = {}


static func build_theme() -> Theme:
	if _shared_theme != null:
		return _shared_theme
	var theme := Theme.new()
	theme.default_font = _sans_font()
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", C_TEXT)
	theme.set_color("font_color", "Button", C_TEXT)
	theme.set_color("font_hover_color", "Button", Color("#fff2d4"))
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", Color("#665d54"))
	theme.set_color("font_color", "LineEdit", C_TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", C_MUTED)
	theme.set_color("font_color", "TextEdit", C_TEXT)
	theme.set_color("font_placeholder_color", "TextEdit", C_MUTED)
	theme.set_color("font_color", "RichTextLabel", C_TEXT)
	theme.set_color("default_color", "RichTextLabel", C_TEXT)
	theme.set_color("font_color", "CheckBox", C_TEXT)
	theme.set_color("font_color", "OptionButton", C_TEXT)
	theme.set_constant("separation", "VBoxContainer", 8)
	theme.set_constant("separation", "HBoxContainer", 8)
	theme.set_constant("h_separation", "GridContainer", 10)
	theme.set_constant("v_separation", "GridContainer", 10)
	_shared_theme = theme
	return _shared_theme


static func _sans_font() -> SystemFont:
	if _shared_sans_font == null:
		_shared_sans_font = SystemFont.new()
		_shared_sans_font.font_names = PackedStringArray(["Noto Sans SC", "Microsoft YaHei UI", "Microsoft YaHei", "SimSun"])
	return _shared_sans_font


static func _serif_font() -> SystemFont:
	if _shared_serif_font == null:
		_shared_serif_font = SystemFont.new()
		_shared_serif_font.font_names = PackedStringArray(["Noto Serif SC", "SimSun", "STSong"])
	return _shared_serif_font


static func panel(bg: Color = C_PANEL, border: Color = C_BORDER, radius: int = 7, margin: int = 10) -> PanelContainer:
	var result := PanelContainer.new()
	result.add_theme_stylebox_override("panel", style(bg, border, radius, 1, margin))
	return result


static func style(bg: Color, border: Color = C_BORDER, radius: int = 6, width: int = 1, margin: int = 8) -> StyleBoxFlat:
	var key := "%s:%s:%d:%d:%d" % [bg.to_html(), border.to_html(), radius, width, margin]
	if _shared_styles.has(key):
		return _shared_styles[key] as StyleBoxFlat
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	box.corner_radius_top_left = radius; box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius; box.corner_radius_bottom_right = radius
	box.content_margin_left = margin; box.content_margin_right = margin
	box.content_margin_top = margin; box.content_margin_bottom = margin
	_shared_styles[key] = box
	return box


static func label(text: String, font_size: int = 16, color: Color = C_TEXT, upper_spacing: int = 0, wrap: bool = false) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	if upper_spacing > 0: result.add_theme_constant_override("line_spacing", upper_spacing)
	return result


static func eyebrow(text: String) -> Label:
	var result := label(text, 13, C_GOLD_SOFT)
	result.add_theme_constant_override("outline_size", 1)
	result.add_theme_color_override("font_outline_color", Color("#15110e"))
	return result


static func title(text: String, size: int = 30) -> Label:
	var result := label(text, size, Color("#efd58e"))
	result.add_theme_font_override("font", _serif_font())
	return result


static func button(text: String, kind: String = "normal", min_height: int = 46) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size.y = min_height
	result.focus_mode = Control.FOCUS_ALL
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var bg := C_PANEL_2; var border := C_BORDER; var hover := C_PANEL_3; var hover_border := Color("#765936")
	if kind == "primary":
		bg = Color("#806326"); border = Color("#d1af52"); hover = Color("#98782e"); hover_border = Color("#f0cc68")
	elif kind == "danger":
		bg = Color("#1b1011"); border = Color("#6e2730"); hover = Color("#2b1216"); hover_border = Color("#a6404d")
	elif kind == "ghost":
		bg = Color("#110f0d"); border = Color("#3a3028"); hover = C_PANEL_2
	result.add_theme_stylebox_override("normal", style(bg, border, 6, 1, 10))
	result.add_theme_stylebox_override("hover", style(hover, hover_border, 6, 1, 10))
	result.add_theme_stylebox_override("pressed", style(hover.lightened(0.08), C_GOLD, 6, 2, 9))
	result.add_theme_stylebox_override("focus", style(Color(0, 0, 0, 0), C_GOLD, 6, 2, 8))
	result.add_theme_stylebox_override("disabled", style(Color("#13110f"), Color("#2d2924"), 6, 1, 10))
	result.mouse_entered.connect(func() -> void:
		if not AppSettings.reduced_motion:
			var tween := result.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property(result, "modulate", Color("#fff4df"), 0.09))
	result.mouse_exited.connect(func() -> void:
		var tween := result.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(result, "modulate", Color.WHITE, 0.13))
	result.pressed.connect(func() -> void:
		if Engine.get_main_loop() is SceneTree:
			var audio := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Main/AudioService")
			if audio != null and audio.has_method("cue"): audio.cue("click"))
	return result


static func rich_text(min_height: int = 0) -> RichTextLabel:
	var result := RichTextLabel.new()
	result.bbcode_enabled = true
	result.fit_content = false
	result.scroll_active = true
	result.scroll_following = false
	result.selection_enabled = true
	result.context_menu_enabled = true
	result.threaded = true
	result.custom_minimum_size.y = min_height
	result.add_theme_font_size_override("normal_font_size", 17)
	result.add_theme_font_size_override("bold_font_size", 17)
	result.add_theme_color_override("default_color", C_TEXT)
	result.add_theme_color_override("font_selected_color", Color("#fff1c4"))
	result.add_theme_color_override("selection_color", Color("#6f552d"))
	result.install_effect(BloodTextEffect.new())
	result.install_effect(DreadTextEffect.new())
	return result


static func line_edit(placeholder: String = "") -> LineEdit:
	var result := LineEdit.new()
	result.placeholder_text = placeholder
	result.custom_minimum_size.y = 46
	result.add_theme_stylebox_override("normal", style(Color("#0c0b0a"), C_BORDER, 6, 1, 10))
	result.add_theme_stylebox_override("focus", style(Color("#0c0b0a"), C_GOLD_SOFT, 6, 1, 10))
	return result


static func section(parent: Container, eyebrow_text: String, title_text: String, subtitle: String = "") -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_child(eyebrow(eyebrow_text))
	box.add_child(title(title_text, 25))
	if not subtitle.is_empty(): box.add_child(label(subtitle, 14, C_MUTED))
	parent.add_child(box)
	return box


static func fade_in(control: CanvasItem, duration: float = 0.22) -> void:
	if AppSettings.reduced_motion:
		control.modulate = Color.WHITE
		return
	control.modulate = Color(1, 1, 1, 0)
	var tween := control.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "modulate", Color.WHITE, duration)
