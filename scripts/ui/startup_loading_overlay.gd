class_name StartupLoadingOverlay
extends Control

var _seal: PanelContainer
var _seal_glow: PanelContainer
var _status: Label
var _detail: Label
var _percent: Label
var _progress: ProgressBar
var _stage_labels: Array[Label] = []
var _phase := 0.0


func _ready() -> void:
	name = "StartupLoadingOverlay"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UIFactory.build_theme()
	z_index = 100
	_build_interface()
	set_process(not AppSettings.reduced_motion)


func _process(delta: float) -> void:
	_phase += delta
	var pulse := (sin(_phase * 2.2) + 1.0) * 0.5
	_seal.scale = Vector2.ONE * lerpf(0.985, 1.015, pulse)
	_seal.modulate = Color(1.0, 0.92 + pulse * 0.08, 0.76 + pulse * 0.12, 1.0)
	_seal_glow.modulate.a = lerpf(0.16, 0.42, pulse)


func update_stage(index: int, progress: float, status_text: String, detail_text: String) -> void:
	_progress.value = clampf(progress, 0.0, 1.0) * 100.0
	_percent.text = "%02d%%" % roundi(_progress.value)
	_status.text = status_text
	_detail.text = detail_text
	for label_index in range(_stage_labels.size()):
		var label := _stage_labels[label_index]
		if label_index < index:
			label.text = "◆"
			label.add_theme_color_override("font_color", UIFactory.C_GOLD)
		elif label_index == index:
			label.text = "◇"
			label.add_theme_color_override("font_color", Color("#efd58e"))
		else:
			label.text = "·"
			label.add_theme_color_override("font_color", Color("#55493e"))


func finish() -> void:
	update_stage(_stage_labels.size(), 1.0, "档案馆已就绪", "调查权限校验完成，正在打开夜间入口。")
	if AppSettings.reduced_motion:
		queue_free()
		return
	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "modulate:a", 0.0, 0.32)
	await tween.finished
	queue_free()


func _build_interface() -> void:
	var background := TextureRect.new()
	background.texture = load("res://assets/backgrounds/archive_lobby_v1.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var shade := ColorRect.new()
	shade.color = Color("#070605e8")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var vignette := PanelContainer.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.add_theme_stylebox_override("panel", UIFactory.style(Color("#0907068a"), Color("#261e17"), 0, 1, 0))
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var card := UIFactory.panel(Color("#100d0bf2"), Color("#76582c"), 10, 30)
	card.custom_minimum_size = Vector2(670, 430)
	center.add_child(card)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 13)
	card.add_child(root)

	var eyebrow := UIFactory.eyebrow("RULE TALES  /  ARCHIVE INITIALIZATION")
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(eyebrow)

	var seal_center := CenterContainer.new()
	seal_center.custom_minimum_size.y = 132
	root.add_child(seal_center)
	var seal_stack := Control.new()
	seal_stack.custom_minimum_size = Vector2(112, 112)
	seal_center.add_child(seal_stack)
	_seal_glow = UIFactory.panel(Color("#b78b3030"), Color("#d7b86044"), 56, 0)
	_seal_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_seal_glow.offset_left = -8; _seal_glow.offset_top = -8
	_seal_glow.offset_right = 8; _seal_glow.offset_bottom = 8
	seal_stack.add_child(_seal_glow)
	_seal = UIFactory.panel(Color("#21140f"), Color("#d7b860"), 50, 5)
	_seal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_seal.pivot_offset = Vector2(56, 56)
	seal_stack.add_child(_seal)
	var glyph := UIFactory.title("异", 54)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_seal.add_child(glyph)

	var title_label := UIFactory.title("异闻夜谈", 34)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title_label)
	var subtitle := UIFactory.label("夜间档案馆正在核对调查权限", 14, UIFactory.C_MUTED)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(subtitle)

	var stage_row := HBoxContainer.new()
	stage_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stage_row.add_theme_constant_override("separation", 30)
	root.add_child(stage_row)
	for _index in range(4):
		var marker := UIFactory.label("·", 18, Color("#55493e"))
		marker.custom_minimum_size.x = 26
		marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_stage_labels.append(marker)
		stage_row.add_child(marker)

	var status_row := HBoxContainer.new()
	root.add_child(status_row)
	_status = UIFactory.label("唤醒档案索引", 16, UIFactory.C_GOLD_SOFT)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(_status)
	_percent = UIFactory.label("00%", 16, Color("#efd58e"))
	_percent.custom_minimum_size.x = 70
	_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_row.add_child(_percent)

	_progress = ProgressBar.new()
	_progress.min_value = 0.0
	_progress.max_value = 100.0
	_progress.show_percentage = false
	_progress.custom_minimum_size.y = 8
	_progress.add_theme_stylebox_override("background", UIFactory.style(Color("#080706"), Color("#3b3027"), 4, 1, 0))
	_progress.add_theme_stylebox_override("fill", UIFactory.style(Color("#a98335"), Color("#d7b860"), 4, 1, 0))
	root.add_child(_progress)

	_detail = UIFactory.label("正在建立本地档案目录……", 13, Color("#8e8175"))
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_detail)
	var privacy := UIFactory.label("LOCAL ONLY  ·  加载过程不会连接网络或写入 API KEY", 11, Color("#62584f"))
	privacy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(privacy)

