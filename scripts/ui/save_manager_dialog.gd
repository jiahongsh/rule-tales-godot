extends Window

signal loaded

const DIALOG_SIZE := Vector2i(1120, 760)
const MANUAL_SLOT_COUNT := 6
const AUTOSAVE_GENERATIONS := 3

var _tabs: TabContainer
var _manual_grid: GridContainer
var _autosave_list: VBoxContainer
var _timeline_list: VBoxContainer
var _feedback: Label
var _content_root: Control
var _import_json_button: Button
var _export_json_button: Button
var _refresh_required := true


func _ready() -> void:
	title = "档案管理 · 多存档与时间线"
	borderless = true
	min_size = Vector2i(900, 620)
	exclusive = true
	transient = true
	theme = UIFactory.build_theme()
	close_requested.connect(_close)
	_build_ui()
	GameSession.busy_changed.connect(func(_value: bool, _message: String) -> void: _refresh_transfer_buttons())
	GameSession.rules_changed.connect(func() -> void:
		_refresh_transfer_buttons()
		invalidate_content())
	GameSession.state_changed.connect(func(_changes: Array) -> void: invalidate_content())
	GameSession.history_changed.connect(invalidate_content)
	GameSession.autosave_written.connect(func(_time_text: String, _path: String) -> void: invalidate_content())


func open_dialog() -> void:
	prepare_dialog()
	_tabs.current_tab = 0
	_feedback.text = ""
	popup_centered(DIALOG_SIZE)
	UIFactory.fade_in(_content_root)


func prepare_dialog() -> void:
	if _refresh_required:
		_refresh_all()


func invalidate_content() -> void:
	_refresh_required = true


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = UIFactory.C_BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var outer := MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		outer.add_theme_constant_override("margin_%s" % side, 16)
	add_child(outer)

	_content_root = VBoxContainer.new()
	_content_root.add_theme_constant_override("separation", 10)
	outer.add_child(_content_root)
	_content_root.add_child(_build_header())

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_stylebox_override("panel", UIFactory.style(Color("#100e0c"), Color("#4a3a2b"), 7, 1, 10))
	_content_root.add_child(_tabs)

	var manual_page := _scroll_page("手动槽位 6")
	_manual_grid = GridContainer.new()
	_manual_grid.columns = 2
	_manual_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_manual_grid.add_theme_constant_override("h_separation", 10)
	_manual_grid.add_theme_constant_override("v_separation", 10)
	manual_page.host.add_child(_manual_grid)
	_tabs.add_child(manual_page.scroll)

	var autosave_page := _scroll_page("自动轮换 3")
	_autosave_list = VBoxContainer.new()
	_autosave_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_autosave_list.add_theme_constant_override("separation", 10)
	autosave_page.host.add_child(_autosave_list)
	_tabs.add_child(autosave_page.scroll)

	var timeline_page := _scroll_page("回合时间线")
	_timeline_list = VBoxContainer.new()
	_timeline_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timeline_list.add_theme_constant_override("separation", 8)
	timeline_page.host.add_child(_timeline_list)
	_tabs.add_child(timeline_page.scroll)

	_style_tab_bar()
	_content_root.add_child(_build_footer())


func _build_header() -> Control:
	var panel := UIFactory.panel(Color("#171310"), Color("#6b512d"), 8, 13)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(titles)
	titles.add_child(UIFactory.eyebrow("ARCHIVE MANAGEMENT  /  档案管理"))
	titles.add_child(UIFactory.title("保留调查，也保留后悔的机会", 29))
	titles.add_child(UIFactory.label(
		"六个手动槽位长期保留；自动存档轮换三代。时间线回溯会舍弃所选节点之后的进度。",
		14,
		UIFactory.C_MUTED))
	var status := UIFactory.panel(Color("#12100e"), Color("#403329"), 6, 9)
	status.custom_minimum_size.x = 226
	row.add_child(status)
	var status_box := VBoxContainer.new()
	status.add_child(status_box)
	status_box.add_child(UIFactory.eyebrow("CURRENT ARCHIVE / 当前档案"))
	var current := UIFactory.label(_current_archive_text(), 14, UIFactory.C_TEXT)
	current.name = "CurrentArchive"
	status_box.add_child(current)
	return panel


func _build_footer() -> Control:
	var panel := UIFactory.panel(Color("#15120f"), Color("#4a392b"), 7, 9)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	panel.add_child(row)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 2)
	row.add_child(copy)
	copy.add_child(UIFactory.eyebrow("PORTABLE ARCHIVE  /  外部 JSON 档案"))
	copy.add_child(UIFactory.label("导入会在确认后替换当前调查；导出只复制当前状态，不改变游戏进度。", 12, UIFactory.C_MUTED))
	_feedback = UIFactory.label("", 13, UIFactory.C_GREEN)
	_feedback.name = "TransferFeedback"
	_feedback.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_feedback.tooltip_text = "档案传输状态"
	copy.add_child(_feedback)
	_import_json_button = UIFactory.button("导入 JSON", "normal", 44)
	_import_json_button.name = "ImportJson"
	_import_json_button.custom_minimum_size.x = 132
	_import_json_button.pressed.connect(_request_import_json)
	row.add_child(_import_json_button)
	_export_json_button = UIFactory.button("导出 JSON", "primary", 44)
	_export_json_button.name = "ExportJson"
	_export_json_button.custom_minimum_size.x = 132
	_export_json_button.pressed.connect(_request_export_json)
	row.add_child(_export_json_button)
	var close_button := UIFactory.button("关闭", "normal", 44)
	close_button.custom_minimum_size.x = 112
	close_button.pressed.connect(_close)
	row.add_child(close_button)
	return panel


func _scroll_page(page_name: String) -> Dictionary:
	var scroll := ScrollContainer.new()
	scroll.name = page_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 5)
	scroll.add_child(margin)
	return {"scroll": scroll, "host": margin}


func _style_tab_bar() -> void:
	var bar := _tabs.get_tab_bar()
	bar.add_theme_font_size_override("font_size", 15)
	bar.add_theme_color_override("font_selected_color", Color("#ffe2a0"))
	bar.add_theme_color_override("font_unselected_color", Color("#a29484"))
	bar.add_theme_color_override("font_hovered_color", Color("#f2d390"))
	bar.add_theme_stylebox_override("tab_selected", UIFactory.style(Color("#2a2119"), UIFactory.C_BORDER_HOT, 6, 1, 12))
	bar.add_theme_stylebox_override("tab_unselected", UIFactory.style(Color("#12100e"), Color("#342b24"), 6, 1, 12))
	bar.add_theme_stylebox_override("tab_hovered", UIFactory.style(Color("#1d1814"), Color("#765936"), 6, 1, 12))


func _refresh_all() -> void:
	_refresh_current_archive()
	_refresh_transfer_buttons()
	_refresh_manual_page()
	_refresh_autosave_page()
	_refresh_timeline_page()
	_refresh_required = false


func _refresh_transfer_buttons() -> void:
	if _import_json_button == null or _export_json_button == null:
		return
	_import_json_button.disabled = GameSession.busy
	_import_json_button.tooltip_text = "叙事生成期间不能替换当前调查。" if GameSession.busy else "从电脑中选择规则怪谈 JSON 存档。"
	_export_json_button.disabled = GameSession.rules.is_empty() or GameSession.busy
	if GameSession.rules.is_empty():
		_export_json_button.tooltip_text = "当前没有可导出的调查。"
	elif GameSession.busy:
		_export_json_button.tooltip_text = "叙事生成期间不能导出调查。"
	else:
		_export_json_button.tooltip_text = "把当前调查的完整状态、历史与时间线复制为 JSON。"


func _refresh_current_archive() -> void:
	var label := _content_root.find_child("CurrentArchive", true, false) as Label
	if label != null:
		label.text = _current_archive_text()


func _refresh_manual_page() -> void:
	_clear(_manual_grid)
	for slot in range(1, MANUAL_SLOT_COUNT + 1):
		_manual_grid.add_child(_manual_card(slot))


func _manual_card(slot: int) -> Control:
	var path := RuleTalesSaveService.manual_path(slot)
	var summary := _read_summary(path)
	var card := UIFactory.panel(Color("#1a1512"), Color("#4c3b2d"), 7, 12)
	card.custom_minimum_size = Vector2(430, 242)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	card.add_child(box)

	var heading := HBoxContainer.new()
	box.add_child(heading)
	heading.add_child(UIFactory.eyebrow("MANUAL %02d  /  手动槽位 %d" % [slot, slot]))
	heading.add_child(_expander())
	var state_label := "已损坏" if summary.corrupt else ("已记录" if summary.exists else "空槽位")
	var state_color := UIFactory.C_RED if summary.corrupt else (UIFactory.C_GREEN if summary.valid else UIFactory.C_MUTED)
	heading.add_child(UIFactory.label(state_label, 12, state_color))

	var body := HBoxContainer.new(); body.add_theme_constant_override("separation", 12); body.size_flags_vertical = Control.SIZE_EXPAND_FILL; box.add_child(body)
	var preview := UIFactory.panel(Color("#090807"), Color("#3d3128"), 5, 4); preview.custom_minimum_size = Vector2(180, 102); body.add_child(preview)
	var thumbnail_path := RuleTalesSaveService.thumbnail_path(slot)
	if FileAccess.file_exists(thumbnail_path):
		var image := Image.load_from_file(thumbnail_path)
		if image != null and not image.is_empty():
			var texture := ImageTexture.create_from_image(image)
			var picture := TextureRect.new(); picture.texture = texture; picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED; picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); preview.add_child(picture)
		else:
			var missing := UIFactory.label("NO PREVIEW\n缩略图损坏", 12, UIFactory.C_MUTED); missing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; missing.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; missing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); preview.add_child(missing)
	else:
		var missing := UIFactory.label("NO PREVIEW\n无缩略图", 12, UIFactory.C_MUTED); missing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; missing.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; missing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); preview.add_child(missing)
	var metadata := UIFactory.label(_summary_text(summary), 15, UIFactory.C_TEXT)
	metadata.size_flags_vertical = Control.SIZE_EXPAND_FILL
	metadata.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	metadata.tooltip_text = path
	body.add_child(metadata)

	var actions := HBoxContainer.new()
	box.add_child(actions)
	var save_button := UIFactory.button("覆盖" if summary.exists else "保存", "primary" if not summary.exists else "normal", 42)
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_button.disabled = GameSession.rules.is_empty() or GameSession.busy
	save_button.tooltip_text = "当前没有可保存的调查。" if GameSession.rules.is_empty() else ("叙事生成期间不能写入手动存档。" if GameSession.busy else "将当前调查写入此槽位。")
	save_button.pressed.connect(_request_manual_save.bind(slot, bool(summary.exists)))
	actions.add_child(save_button)
	var load_button := UIFactory.button("读取", "normal", 42)
	load_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_button.disabled = not summary.valid or GameSession.busy
	load_button.tooltip_text = "该槽位不可读取。" if not summary.valid else "读取此槽位并替换当前调查。"
	load_button.pressed.connect(_request_load_path.bind(path, "读取该手动槽位"))
	actions.add_child(load_button)
	return card


func _refresh_autosave_page() -> void:
	_clear(_autosave_list)
	var paths := RuleTalesSaveService.autosaves_newest_first()
	var descriptions := ["最新", "上一代", "更早"]
	for index in range(AUTOSAVE_GENERATIONS):
		var path := paths[index] if index < paths.size() else ""
		var summary := _read_summary(path) if not path.is_empty() else _empty_summary()
		_autosave_list.add_child(_autosave_card(index + 1, str(descriptions[index]), path, summary))


func _autosave_card(position: int, generation_label: String, path: String, summary: Dictionary) -> Control:
	var card := UIFactory.panel(Color("#181410"), Color("#493a2d"), 7, 12)
	card.custom_minimum_size.y = 146
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	var marker := UIFactory.panel(Color("#211a13"), Color("#71572f"), 6, 9)
	marker.custom_minimum_size = Vector2(118, 96)
	row.add_child(marker)
	var marker_box := VBoxContainer.new()
	marker.add_child(marker_box)
	marker_box.add_child(UIFactory.eyebrow("AUTO %02d" % position))
	marker_box.add_child(UIFactory.title(generation_label, 22))
	marker_box.add_child(UIFactory.label("轮换存档", 12, UIFactory.C_MUTED))
	row.add_child(_thumbnail_preview(path, Vector2(180, 102)))

	var metadata := UIFactory.label(_summary_text(summary), 15, UIFactory.C_TEXT)
	metadata.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	metadata.tooltip_text = path
	row.add_child(metadata)
	var load_button := UIFactory.button("从这里继续", "primary" if position == 1 else "normal", 48)
	load_button.custom_minimum_size.x = 150
	load_button.disabled = not summary.valid or GameSession.busy
	load_button.tooltip_text = "这一代自动存档尚未形成。" if not summary.exists else ("该存档损坏，无法读取。" if summary.corrupt else "读取这一代自动存档。")
	load_button.pressed.connect(_request_load_path.bind(path, "读取该自动存档"))
	row.add_child(load_button)
	return card


func _thumbnail_preview(save_path: String, minimum_size: Vector2) -> Control:
	var preview := UIFactory.panel(Color("#090807"), Color("#3d3128"), 5, 4)
	preview.custom_minimum_size = minimum_size
	var thumbnail_path := RuleTalesSaveService.thumbnail_for_save(save_path) if not save_path.is_empty() else ""
	if not thumbnail_path.is_empty() and FileAccess.file_exists(thumbnail_path):
		var loaded_image := Image.load_from_file(thumbnail_path)
		if loaded_image != null and not loaded_image.is_empty():
			var picture := TextureRect.new()
			picture.texture = ImageTexture.create_from_image(loaded_image)
			picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			preview.add_child(picture)
			return preview
	var missing := UIFactory.label("NO PREVIEW\n无缩略图", 12, UIFactory.C_MUTED)
	missing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	missing.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	missing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.add_child(missing)
	return preview


func _refresh_timeline_page() -> void:
	_clear(_timeline_list)
	var intro := UIFactory.panel(Color("#15120f"), Color("#3f3329"), 6, 9)
	var intro_text := UIFactory.label("KEY 节点可以成为新的分支起点；普通 TURN 只供回顾。回溯后，该节点之后的当前进度会被截断。", 14, UIFactory.C_MUTED)
	intro.add_child(intro_text)
	_timeline_list.add_child(intro)
	if GameSession.timeline.is_empty():
		var empty := UIFactory.label("开始并完成回合后，时间线会在这里形成。", 16, UIFactory.C_MUTED)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.custom_minimum_size.y = 150
		_timeline_list.add_child(empty)
		return
	for checkpoint_value in GameSession.timeline:
		if checkpoint_value is Dictionary:
			_timeline_list.add_child(_timeline_card(checkpoint_value))


func _timeline_card(checkpoint: Dictionary) -> Control:
	var key_moment := bool(checkpoint.get("key_moment", false))
	var card := UIFactory.panel(Color("#1a1512") if key_moment else Color("#151310"), Color("#765936") if key_moment else Color("#3c332b"), 6, 10)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	var marker := UIFactory.label("KEY" if key_moment else "TURN", 13, Color("#f0cf7f") if key_moment else Color("#968a7e"))
	marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	marker.custom_minimum_size = Vector2(66, 52)
	marker.add_theme_stylebox_override("normal", UIFactory.style(Color("#221a13") if key_moment else Color("#11100e"), Color("#8f6b34") if key_moment else Color("#39322c"), 5, 1, 5))
	row.add_child(marker)
	var turn := int(checkpoint.get("turn", 0))
	var label := str(checkpoint.get("label", "未命名节点"))
	var timestamp := str(checkpoint.get("timestamp", ""))
	var text := UIFactory.label("第 %d 回合 · %s\n%s" % [turn, label, timestamp], 15, UIFactory.C_TEXT)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var restart := UIFactory.button("从此重开", "primary" if key_moment else "ghost", 44)
	restart.custom_minimum_size.x = 132
	restart.disabled = not key_moment or GameSession.busy
	restart.tooltip_text = "恢复该回合结束时的完整状态，并截断之后的时间线。" if key_moment else "普通回合只供回顾，不能作为分支起点。"
	restart.pressed.connect(_request_restart.bind(str(checkpoint.get("id", "")), turn))
	row.add_child(restart)
	return card


func _request_manual_save(slot: int, overwrite: bool) -> void:
	if GameSession.rules.is_empty():
		_set_feedback("当前没有可保存的调查。", true)
		return
	if GameSession.busy:
		_set_feedback("叙事生成期间不能写入手动存档。", true)
		return
	if overwrite:
		_confirm(
			"覆盖手动槽位？",
			"该槽位现有记录会被当前调查替换。此操作不会影响其他槽位。",
			Callable(self, "_save_manual").bind(slot),
			"确认覆盖")
	else:
		_save_manual(slot)


func _save_manual(slot: int) -> void:
	var result := GameSession.save_manual(slot)
	if not bool(result.get("ok", false)):
		_set_feedback("保存失败：%s" % str(result.get("error", "未知错误")), true)
		_cue("denied")
		return
	await RenderingServer.frame_post_draw
	var thumbnail := RuleTalesSaveService.write_thumbnail(slot, get_tree().root.get_texture().get_image())
	_set_feedback("当前调查已写入手动槽位 %d。" % slot if bool(thumbnail.ok) else "存档已写入，但缩略图失败：%s" % str(thumbnail.error), not bool(thumbnail.ok))
	_cue("commit")
	_refresh_manual_page()


func _request_load_path(path: String, action_name: String) -> void:
	if path.is_empty() or GameSession.busy:
		return
	var action := Callable(self, "_load_path").bind(path)
	if GameSession.rules.is_empty():
		action.call()
		return
	_confirm(
		"替换当前进度？",
		"%s会结束当前档案。之后的自动存档将继续三代轮换。\n\n如需长期保留，请先写入手动槽位。" % action_name,
		action,
		"读取存档")


func _load_path(path: String) -> void:
	var read := RuleTalesSaveService.read_document(path)
	if not bool(read.get("ok", false)):
		_set_feedback("读取失败：%s" % str(read.get("error", "未知错误")), true)
		_cue("denied")
		return
	var result := GameSession.load_document(read.get("document", {}))
	if not bool(result.get("ok", false)):
		_set_feedback("读取失败：%s" % str(result.get("error", "未知错误")), true)
		_cue("denied")
		return
	_cue("reveal")
	loaded.emit()


func _request_import_json() -> void:
	if GameSession.busy:
		_set_feedback("叙事生成期间不能导入外部档案。", true)
		_cue("denied")
		return
	var dialog := _create_json_file_dialog("导入外部 JSON 档案", FileDialog.FILE_MODE_OPEN_FILE)
	dialog.file_selected.connect(func(path: String) -> void:
		dialog.queue_free()
		_prepare_import_json(path))
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.72)


func _request_export_json() -> void:
	if GameSession.rules.is_empty():
		_set_feedback("当前没有可导出的调查。", true)
		_cue("denied")
		return
	if GameSession.busy:
		_set_feedback("叙事生成期间不能导出调查。", true)
		_cue("denied")
		return
	var dialog := _create_json_file_dialog("导出当前调查 JSON", FileDialog.FILE_MODE_SAVE_FILE)
	dialog.current_file = "%s.json" % _safe_file_name(GameSession.story_title)
	dialog.file_selected.connect(func(path: String) -> void:
		dialog.queue_free()
		_export_json_path(path))
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.72)


func _create_json_file_dialog(dialog_title: String, mode: int) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.title = dialog_title
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = mode
	dialog.use_native_dialog = true
	dialog.filters = PackedStringArray(["*.json;规则怪谈存档;application/json"])
	return dialog


func _prepare_import_json(path: String) -> void:
	if GameSession.busy:
		_set_feedback("叙事生成期间不能导入外部档案。", true)
		_cue("denied")
		return
	var read := RuleTalesSaveService.read_document(path)
	if not bool(read.get("ok", false)):
		_set_feedback("导入失败：%s" % str(read.get("error", "未知错误")), true)
		_cue("denied")
		return
	var document: Dictionary = read.get("document", {})
	var action := Callable(self, "_apply_import_document").bind(document, path)
	if GameSession.rules.is_empty():
		action.call()
		return
	_confirm(
		"导入并替换当前调查？",
		"外部 JSON 将替换当前档案、状态、历史记录与时间线。\n\n如需保留当前进度，请先写入手动槽位或导出 JSON。",
		action,
		"确认导入")


func _apply_import_document(document: Dictionary, source_path: String) -> void:
	if GameSession.busy:
		_set_feedback("调查状态已经改变，暂时不能完成导入。", true)
		_cue("denied")
		return
	var result := GameSession.load_document(document)
	if not bool(result.get("ok", false)):
		_set_feedback("导入失败：%s" % str(result.get("error", "未知错误")), true)
		_cue("denied")
		return
	_set_feedback("外部档案已导入：%s" % source_path)
	_cue("reveal")
	_refresh_all()
	loaded.emit()


func _export_json_path(path: String) -> void:
	if GameSession.rules.is_empty():
		_set_feedback("当前没有可导出的调查。", true)
		_cue("denied")
		return
	if GameSession.busy:
		_set_feedback("叙事生成期间不能导出调查。", true)
		_cue("denied")
		return
	var actual_path := path.strip_edges()
	if actual_path.is_empty():
		_set_feedback("导出失败：没有选择目标文件。", true)
		_cue("denied")
		return
	if actual_path.get_extension().to_lower() != "json":
		actual_path += ".json"
	var result := RuleTalesSaveService.write_document(actual_path, GameSession.to_dict())
	if not bool(result.get("ok", false)):
		_set_feedback("导出失败：%s" % str(result.get("error", "未知错误")), true)
		_cue("denied")
		return
	_set_feedback("当前调查已导出：%s" % actual_path)
	_cue("commit")


func _request_restart(checkpoint_id: String, turn: int) -> void:
	if checkpoint_id.is_empty() or GameSession.busy:
		return
	_confirm(
		"从关键节点重新开始？",
		"将恢复第 %d 回合结束时的状态，并舍弃此后的当前进度。建议先写入手动槽位。" % turn,
		Callable(self, "_restart_from_checkpoint").bind(checkpoint_id),
		"确认回溯")


func _restart_from_checkpoint(checkpoint_id: String) -> void:
	var result := GameSession.restart_from_checkpoint(checkpoint_id)
	if not bool(result.get("ok", false)):
		_set_feedback("无法回溯：%s" % str(result.get("error", "未知错误")), true)
		_cue("denied")
		return
	_cue("reveal")
	loaded.emit()


func _confirm(dialog_title: String, message: String, action: Callable, confirm_text: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = dialog_title
	dialog.dialog_text = message
	dialog.ok_button_text = confirm_text
	dialog.cancel_button_text = "取消"
	dialog.exclusive = true
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		action.call()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(640, 310))


func _read_summary(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return _empty_summary()
	var read := RuleTalesSaveService.read_document(path)
	if not bool(read.get("ok", false)):
		return {"exists": true, "valid": false, "corrupt": true, "error": str(read.get("error", "无法读取存档。"))}
	var document: Dictionary = read.get("document", {})
	var state: Dictionary = document.get("state", {}) if document.get("state", {}) is Dictionary else {}
	var ending: Dictionary = state.get("ending", {}) if state.get("ending", {}) is Dictionary else {}
	var minute := clampi(int(state.get("minute_of_day", 0)), 0, 1439)
	return {
		"exists": true,
		"valid": true,
		"corrupt": false,
		"story_title": str(document.get("story_title", "未命名档案")),
		"turn": maxi(0, int(document.get("completed_turns", 0))),
		"day": maxi(1, int(state.get("day", 1))),
		"clock": "%02d:%02d" % [floori(minute / 60.0), minute % 60],
		"ending": str(ending.get("type", "none")),
		"modified": _format_unix_time(FileAccess.get_modified_time(path))
	}


func _empty_summary() -> Dictionary:
	return {"exists": false, "valid": false, "corrupt": false}


func _summary_text(summary: Dictionary) -> String:
	if bool(summary.get("corrupt", false)):
		return "存档损坏或无法解析\n%s" % str(summary.get("error", "未知错误"))
	if not bool(summary.get("exists", false)):
		return "空槽位\n可以保存当前调查"
	var lines: Array[String] = [
		str(summary.get("story_title", "未命名档案")),
		"第 %d 回合 · 第%d日 %s" % [int(summary.get("turn", 0)), int(summary.get("day", 1)), str(summary.get("clock", "00:00"))]
	]
	var ending := str(summary.get("ending", "none"))
	if not ending.is_empty() and ending != "none":
		lines.append("已封存 · %s" % _ending_label(ending))
	lines.append(str(summary.get("modified", "时间未知")))
	return "\n".join(lines)


func _format_unix_time(timestamp: int) -> String:
	if timestamp <= 0:
		return "时间未知"
	var value := Time.get_datetime_dict_from_unix_time(timestamp)
	return "%04d-%02d-%02d %02d:%02d" % [
		int(value.get("year", 1970)), int(value.get("month", 1)), int(value.get("day", 1)),
		int(value.get("hour", 0)), int(value.get("minute", 0))]


func _ending_label(kind: String) -> String:
	return {
		"survival": "存活",
		"escape": "逃脱",
		"missing": "失踪",
		"contamination": "污染",
		"special": "特殊"
	}.get(kind, kind)


func _safe_file_name(value: String) -> String:
	var result := value.strip_edges()
	for invalid in ["<", ">", ":", "\"", "/", "\\", "|", "?", "*"]:
		result = result.replace(invalid, "_")
	while result.ends_with(".") or result.ends_with(" "):
		result = result.left(result.length() - 1)
	return "rule_tales_archive" if result.is_empty() else result.left(80)


func _current_archive_text() -> String:
	if GameSession.rules.is_empty():
		return "尚未启封调查\n可读取已有档案"
	return "%s\n第 %d 回合 · 第%d日 %s" % [
		GameSession.story_title,
		GameSession.completed_turns,
		int(GameSession.state.data.get("day", 1)),
		GameSession.state.clock_text()]


func _set_feedback(message: String, is_error: bool = false) -> void:
	_feedback.text = message
	_feedback.tooltip_text = message
	_feedback.add_theme_color_override("font_color", Color("#e08a82") if is_error else UIFactory.C_GREEN)


func _cue(name: String) -> void:
	var audio := get_node_or_null("/root/Main/AudioService") as RuleTalesSoundManager
	if audio != null:
		audio.cue(name)


func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _expander() -> Control:
	var control := Control.new()
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return control


func _close() -> void:
	hide()
