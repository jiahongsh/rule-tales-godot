extends Window

## 程序化规则档案制作工具。
##
## 文档格式保持为：每个章节以独占一行的 <章节名> 开始，正文支持经
## SafeBBCode 过滤后的有限 BBCode。此窗口只负责制作与校验；真正开始游戏
## 由外层监听 start_requested 后接管。

signal start_requested(text: String, title: String)

const DRAFT_PATH := "user://rule_workshop_draft.cfg"
const MAX_CHAPTERS := 64
const REFRESH_DELAY := 0.22

const TEMPLATE_ORDINARY := "%d. 当【触发条件】出现时，立即【应对动作】；否则【可验证后果】。"
const TEMPLATE_CONDITIONAL := "%d. 如果你观察到【异常征兆】，请在【时限】内【应对动作】；不要【错误动作】。"
const TEMPLATE_EXIT := "%d. 只有在【可验证条件】全部满足后，才可以从【出口】离开。"

const GUIDE_TEMPLATES := [
	{
		"title": "区域约束",
		"summary": "适合走廊、宿舍、医院等空间。写清进入条件、环境征兆与禁止动作。",
		"content": "1. 进入【区域】前，确认【可观察征兆】与记录一致。\n2. 如果【环境异常】出现，请在【时限】内前往【安全位置】。\n3. 不要在【危险条件】成立时执行【禁止动作】；否则【后果】。",
	},
	{
		"title": "异常实体",
		"summary": "描述它如何被辨认、何时危险，以及玩家能够验证的规避方法。",
		"content": "1. 真正的【实体】具有【可验证特征】，伪装者则会【异常表现】。\n2. 当它开始【危险征兆】时，不要【错误动作】，应立即【规避动作】。\n3. [blood][dread strength=1.0]如果它说出你的全名，闭眼并数到七。[/dread][/blood]",
	},
	{
		"title": "离开与代价",
		"summary": "为长局提供清楚目标。出口可达，但必须要求玩家承担选择后果。",
		"content": "1. 只有取得【关键凭证】并确认【时间条件】后，出口才是真实的。\n2. 离开前必须放弃【重要物品或状态】，这是无法撤销的代价。\n3. 如果出口外出现【错误征兆】，不要跨过门槛，返回【安全节点】重新核对。",
	},
]

var _chapters: Array[Dictionary] = []
var _current_index := -1
var _suppress_editor_signals := false
var _dirty := false
var _draft_enabled := true
var _latest_report: Dictionary = {}
var _mode_buttons: Array[Button] = []
var _search_chapter := -1
var _search_offset := 0

var _tabs: TabContainer
var _chapter_list: ItemList
var _chapter_stats: Label
var _chapter_title: LineEdit
var _content_editor: TextEdit
var _editor_stats: Label
var _preview: RichTextLabel
var _validation_view: RichTextLabel
var _quality_label: Label
var _quality_bar: ProgressBar
var _status_label: Label
var _draft_label: Label
var _restore_draft_button: Button
var _draft_toggle: CheckButton
var _search_edit: LineEdit
var _search_feedback: Label
var _audit_list: ItemList
var _audit_summary: RichTextLabel
var _preflight_gates: RichTextLabel
var _preflight_context: RichTextLabel
var _refresh_timer: Timer


func _init() -> void:
	title = "规则工坊 · 规则档案制作工具"
	borderless = true
	size = Vector2i(1380, 860)
	min_size = Vector2i(1080, 680)
	transient = true
	exclusive = true
	close_requested.connect(_request_close)
	_build_interface()
	_seed_default_document()
	_refresh_draft_state()
	_refresh_all(true)


func open_dialog() -> void:
	if _chapters.is_empty():
		_seed_default_document()
		_refresh_all(true)
	_set_mode(_tabs.current_tab)
	popup_centered_clamped(Vector2i(1380, 860), 0.94)
	UIFactory.fade_in(_tabs, 0.18)


func _build_interface() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = UIFactory.C_BG
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.theme = UIFactory.build_theme()
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	margin.add_child(page)
	page.add_child(_build_header())
	page.add_child(_build_mode_bar())

	_tabs = TabContainer.new()
	_tabs.tabs_visible = false
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_child(_build_author_page())
	_tabs.add_child(_build_audit_page())
	_tabs.add_child(_build_preflight_page())
	_tabs.add_child(_build_guide_page())
	page.add_child(_tabs)

	page.add_child(_build_footer())

	_refresh_timer = Timer.new()
	_refresh_timer.one_shot = true
	_refresh_timer.wait_time = REFRESH_DELAY
	_refresh_timer.timeout.connect(func() -> void: _refresh_all(false))
	add_child(_refresh_timer)


func _build_header() -> Control:
	var panel := UIFactory.panel(UIFactory.C_PANEL, UIFactory.C_BORDER_HOT, 8, 16)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)

	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(UIFactory.eyebrow("RULE WORKSHOP  /  规则制作"))
	heading.add_child(UIFactory.title("把怪谈写成可推理、可游玩的规则档案", 28))
	heading.add_child(UIFactory.label("这里制作的是世界约束，不是固定剧情。每条规则尽量写清触发、征兆、动作与后果。", 14, UIFactory.C_MUTED))
	row.add_child(heading)

	var status_box := VBoxContainer.new()
	status_box.custom_minimum_size.x = 260
	status_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_status_label = UIFactory.label("等待校验", 14, UIFactory.C_GOLD_SOFT)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_draft_label = UIFactory.label("自动草稿准备中", 13, UIFactory.C_MUTED)
	_draft_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_box.add_child(_status_label)
	status_box.add_child(_draft_label)
	row.add_child(status_box)
	return panel


func _build_mode_bar() -> Control:
	var panel := UIFactory.panel(Color("#100e0c"), UIFactory.C_BORDER, 7, 8)
	var row := HBoxContainer.new()
	panel.add_child(row)
	var modes := ["01  编写", "02  全局审查", "03  游玩预检", "04  写作指南"]
	for index in modes.size():
		var button := UIFactory.button(modes[index], "ghost", 42)
		button.custom_minimum_size.x = 132
		button.pressed.connect(_set_mode.bind(index))
		_mode_buttons.append(button)
		row.add_child(button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_search_edit = UIFactory.line_edit("搜索全部章节和规则…")
	_search_edit.custom_minimum_size.x = 220
	_search_edit.text_changed.connect(func(_value: String) -> void:
		_reset_search_state())
	_search_edit.text_submitted.connect(func(_value: String) -> void: _search_next())
	row.add_child(_search_edit)
	var search_button := UIFactory.button("查找下一个", "normal", 42)
	search_button.pressed.connect(_search_next)
	row.add_child(search_button)
	_search_feedback = UIFactory.label("", 13, UIFactory.C_MUTED)
	_search_feedback.custom_minimum_size.x = 76
	row.add_child(_search_feedback)
	return panel


func _build_author_page() -> Control:
	var split := HSplitContainer.new()
	split.name = "Author"
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var chapter_panel := UIFactory.panel(UIFactory.C_PANEL, UIFactory.C_BORDER, 7, 12)
	chapter_panel.custom_minimum_size.x = 220
	var chapter_box := VBoxContainer.new()
	chapter_panel.add_child(chapter_box)
	chapter_box.add_child(UIFactory.eyebrow("CHAPTERS  /  章节结构"))
	chapter_box.add_child(UIFactory.label("用尖括号章节组织规则", 18, UIFactory.C_GOLD))
	_chapter_list = ItemList.new()
	_chapter_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chapter_list.allow_reselect = true
	_chapter_list.item_selected.connect(_select_chapter)
	chapter_box.add_child(_chapter_list)
	_chapter_stats = UIFactory.label("", 13, UIFactory.C_MUTED)
	chapter_box.add_child(_chapter_stats)

	var chapter_actions := GridContainer.new()
	chapter_actions.columns = 2
	chapter_box.add_child(chapter_actions)
	_add_action_button(chapter_actions, "+ 新增", _add_chapter)
	_add_action_button(chapter_actions, "复制", _duplicate_chapter)
	_add_action_button(chapter_actions, "上移", _move_chapter.bind(-1))
	_add_action_button(chapter_actions, "下移", _move_chapter.bind(1))
	var delete_button := UIFactory.button("删除当前章节", "danger", 38)
	delete_button.pressed.connect(_confirm_delete_chapter)
	chapter_box.add_child(delete_button)
	split.add_child(chapter_panel)
	var work_split := HSplitContainer.new()
	work_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(work_split)

	var editor_panel := UIFactory.panel(UIFactory.C_PANEL_2, UIFactory.C_BORDER_HOT, 7, 12)
	editor_panel.custom_minimum_size.x = 420
	editor_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var editor_box := VBoxContainer.new()
	editor_panel.add_child(editor_box)
	editor_box.add_child(UIFactory.eyebrow("RULE EDITOR  /  规则正文"))
	_chapter_title = UIFactory.line_edit("章节标题，例如：宿舍夜间守则")
	_chapter_title.text_changed.connect(func(_value: String) -> void: _on_editor_changed(true))
	editor_box.add_child(_chapter_title)

	var tools := HBoxContainer.new()
	editor_box.add_child(tools)
	_add_action_button(tools, "普通规则", _insert_template.bind("ordinary"))
	_add_action_button(tools, "条件规则", _insert_template.bind("conditional"))
	_add_action_button(tools, "出口规则", _insert_template.bind("exit"))
	var danger_button := UIFactory.button("标记高危", "danger", 38)
	danger_button.tooltip_text = "将选中文字包裹为 [blood][dread] 慢速异常效果；没有选区时插入高危异象占位词。"
	danger_button.pressed.connect(_mark_danger)
	tools.add_child(danger_button)

	_content_editor = TextEdit.new()
	_content_editor.placeholder_text = "一行一条规则。先写玩家可以观察到的征兆，再写能够执行的动作与可验证后果。"
	_content_editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_content_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_editor.custom_minimum_size.y = 260
	_content_editor.add_theme_stylebox_override("normal", UIFactory.style(Color("#0c0b0a"), UIFactory.C_BORDER, 6, 1, 12))
	_content_editor.add_theme_stylebox_override("focus", UIFactory.style(Color("#0c0b0a"), UIFactory.C_GOLD_SOFT, 6, 1, 12))
	_content_editor.text_changed.connect(func() -> void: _on_editor_changed(false))
	editor_box.add_child(_content_editor)
	_editor_stats = UIFactory.label("", 13, UIFactory.C_MUTED)
	editor_box.add_child(_editor_stats)
	work_split.add_child(editor_panel)

	var inspector_panel := UIFactory.panel(UIFactory.C_PANEL, UIFactory.C_BORDER, 7, 12)
	inspector_panel.custom_minimum_size.x = 310
	var inspector := VBoxContainer.new()
	inspector_panel.add_child(inspector)
	inspector.add_child(UIFactory.eyebrow("LIVE INSPECTOR  /  实时检查"))
	var quality_row := HBoxContainer.new()
	_quality_label = UIFactory.label("质量 --", 17, UIFactory.C_GOLD)
	_quality_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quality_row.add_child(_quality_label)
	_quality_bar = ProgressBar.new()
	_quality_bar.custom_minimum_size = Vector2(150, 22)
	_quality_bar.show_percentage = false
	_quality_bar.max_value = 100
	quality_row.add_child(_quality_bar)
	inspector.add_child(quality_row)

	var preview_split := VSplitContainer.new()
	preview_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var preview_box := VBoxContainer.new()
	preview_box.add_child(UIFactory.label("BBCode 实时预览", 14, UIFactory.C_GOLD_SOFT))
	_preview = UIFactory.rich_text(170)
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_box.add_child(_preview)
	preview_split.add_child(preview_box)
	var report_box := VBoxContainer.new()
	report_box.add_child(UIFactory.label("结构校验", 14, UIFactory.C_GOLD_SOFT))
	_validation_view = UIFactory.rich_text(150)
	_validation_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	report_box.add_child(_validation_view)
	preview_split.add_child(report_box)
	inspector.add_child(preview_split)
	work_split.add_child(inspector_panel)
	return split


func _build_audit_page() -> Control:
	var split := HSplitContainer.new()
	split.name = "Audit"
	var inventory_panel := UIFactory.panel(UIFactory.C_PANEL, UIFactory.C_BORDER, 7, 12)
	inventory_panel.custom_minimum_size.x = 430
	var inventory_box := VBoxContainer.new()
	inventory_panel.add_child(inventory_box)
	inventory_box.add_child(UIFactory.eyebrow("RULE INVENTORY  /  规则清单"))
	inventory_box.add_child(UIFactory.label("双击条目可返回原章节定位", 14, UIFactory.C_MUTED))
	_audit_list = ItemList.new()
	_audit_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_audit_list.item_activated.connect(_locate_audit_item)
	inventory_box.add_child(_audit_list)
	split.add_child(inventory_panel)

	var report_panel := UIFactory.panel(UIFactory.C_PANEL_2, UIFactory.C_BORDER_HOT, 7, 16)
	report_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var report_box := VBoxContainer.new()
	report_panel.add_child(report_box)
	report_box.add_child(UIFactory.eyebrow("GLOBAL REVIEW  /  全局审查"))
	report_box.add_child(UIFactory.title("从整份档案寻找重复、冲突与缺口", 24))
	_audit_summary = UIFactory.rich_text()
	_audit_summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	report_box.add_child(_audit_summary)
	split.add_child(report_panel)
	return split


func _build_preflight_page() -> Control:
	var split := HSplitContainer.new()
	split.name = "Preflight"
	var gates_panel := UIFactory.panel(UIFactory.C_PANEL, UIFactory.C_BORDER_HOT, 7, 16)
	gates_panel.custom_minimum_size.x = 500
	var gates_box := VBoxContainer.new()
	gates_panel.add_child(gates_box)
	gates_box.add_child(UIFactory.eyebrow("PLAYABILITY GATES  /  游玩闸门"))
	gates_box.add_child(UIFactory.title("不是所有规则集都能支撑一场调查", 24))
	gates_box.add_child(UIFactory.label("预检只判断档案是否具备可观察、可抉择、可承担后果的基本结构。", 14, UIFactory.C_MUTED))
	_preflight_gates = UIFactory.rich_text()
	_preflight_gates.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gates_box.add_child(_preflight_gates)
	split.add_child(gates_panel)

	var context_panel := UIFactory.panel(UIFactory.C_PANEL_2, UIFactory.C_BORDER, 7, 16)
	context_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var context_box := VBoxContainer.new()
	context_panel.add_child(context_box)
	context_box.add_child(UIFactory.eyebrow("CONTEXT PREVIEW  /  上下文预览"))
	context_box.add_child(UIFactory.label("这是校验后交给叙事核心的规范化规则文本。", 14, UIFactory.C_MUTED))
	_preflight_context = UIFactory.rich_text()
	_preflight_context.size_flags_vertical = Control.SIZE_EXPAND_FILL
	context_box.add_child(_preflight_context)
	split.add_child(context_panel)
	return split


func _build_guide_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Guide"
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 14)
	scroll.add_child(page)
	page.add_child(UIFactory.eyebrow("AUTHORING GUIDE  /  写作指南"))
	page.add_child(UIFactory.title("不要从空白页开始：选择一种规则组件，再按世界观修改", 25))
	page.add_child(UIFactory.label("模板不会替你决定剧情，它只确保玩家能看见线索、做出选择，并理解代价。", 14, UIFactory.C_MUTED))

	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 12)
	page.add_child(cards)
	for index in GUIDE_TEMPLATES.size():
		var template: Dictionary = GUIDE_TEMPLATES[index]
		var card := UIFactory.panel(UIFactory.C_PANEL_2, UIFactory.C_BORDER, 7, 14)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size.y = 220
		var box := VBoxContainer.new()
		card.add_child(box)
		box.add_child(UIFactory.eyebrow("MODULE  %02d" % (index + 1)))
		box.add_child(UIFactory.title(str(template.get("title", "规则模块")), 22))
		var summary := UIFactory.label(str(template.get("summary", "")), 14, UIFactory.C_MUTED)
		summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(summary)
		var insert_button := UIFactory.button("加入%s模板" % str(template.get("title", "规则")), "normal", 42)
		insert_button.pressed.connect(_insert_guide_template.bind(index))
		box.add_child(insert_button)
		cards.add_child(card)

	var principles := UIFactory.panel(UIFactory.C_PANEL, UIFactory.C_BORDER, 7, 18)
	var principle_text := UIFactory.rich_text(260)
	principle_text.text = "[font_size=22][color=#d7b860]一条成熟规则的四层结构[/color][/font_size]\n\n[b]触发[/b]：什么时候生效　　[b]征兆[/b]：玩家凭什么察觉\n[b]动作[/b]：玩家能做什么　　[b]后果[/b]：遵守或违反后发生什么\n\n[color=#8eb490]推荐：[/color] ‘当广播连续念出同一名字三次时，离开正在使用的楼梯；否则下一层会重复。’\n\n[color=#8e2934]常见失败：[/color]\n• 只写‘不要回头’，却不给任何可观察征兆。\n• 用随机死亡代替后果，玩家无法从失败中学习。\n• 所有规则都是真的，缺少能够被验证的例外或伪装。\n• 出口只在结局突然出现，前面的调查无法积累进度。\n\n[color=#c2a56c]安全 BBCode：[/color] [b]粗体[/b]、[i]斜体[/i]、[color=#d7b860]颜色[/color]、[blood]血迹[/blood] 与 [dread strength=1.0]慢速高危异常[/dread]。高危效果应少量使用，避免稀释恐惧；旧 [shake] 标签仍可导入。"
	principles.add_child(principle_text)
	page.add_child(principles)
	return scroll


func _build_footer() -> Control:
	var panel := UIFactory.panel(Color("#100e0c"), UIFactory.C_BORDER, 7, 8)
	var row := HBoxContainer.new()
	panel.add_child(row)
	_draft_toggle = CheckButton.new()
	_draft_toggle.text = "自动草稿"
	_draft_toggle.button_pressed = true
	_draft_toggle.toggled.connect(_toggle_draft)
	row.add_child(_draft_toggle)
	_restore_draft_button = UIFactory.button("恢复草稿", "ghost", 42)
	_restore_draft_button.visible = false
	_restore_draft_button.pressed.connect(_restore_draft)
	row.add_child(_restore_draft_button)
	var clear_draft := UIFactory.button("清空草稿", "ghost", 42)
	clear_draft.pressed.connect(_confirm_clear_draft)
	row.add_child(clear_draft)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var import_button := UIFactory.button("导入 TXT / MD", "normal", 42)
	import_button.pressed.connect(_request_import)
	row.add_child(import_button)
	var export_button := UIFactory.button("校验并导出", "normal", 42)
	export_button.pressed.connect(_request_export)
	row.add_child(export_button)
	var start_button := UIFactory.button("校验并开始游戏", "primary", 42)
	start_button.pressed.connect(_validate_and_start)
	row.add_child(start_button)
	var close_button := UIFactory.button("关闭", "ghost", 42)
	close_button.pressed.connect(_request_close)
	row.add_child(close_button)
	return panel


func _add_action_button(parent: Container, text_value: String, callback: Callable) -> Button:
	var button := UIFactory.button(text_value, "normal", 38)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _seed_default_document() -> void:
	_chapters = [
		{
			"title": "基础规则",
			"content": "1. 进入档案室前，确认门牌上的值班日期是今天。\n2. 如果广播在闭馆后叫出你的名字，不要回应；记录它重复的次数。\n3. 走廊尽头的镜子不属于本馆。当镜面出现水雾时，沿原路返回。",
		},
		{
			"title": "离开条件",
			"content": "1. 找到三枚带编号的借阅章，并确认编号没有重复。\n2. 只有大厅时钟与值班表同时指向 06:00，北门才是真实出口。\n3. 如果门外仍能听见广播，不要跨过门槛；返回服务台重新核对记录。",
		},
	]
	_current_index = 0
	_dirty = false


func _refresh_all(force_editor_sync: bool) -> void:
	if force_editor_sync:
		_refresh_chapter_list()
		_select_chapter(clampi(_current_index, 0, maxi(0, _chapters.size() - 1)))
	_latest_report = _validate_document()
	_refresh_quality_and_preview()
	_refresh_audit()
	_refresh_preflight()
	_refresh_header_status()
	if _draft_enabled and _dirty:
		_save_draft()


func _schedule_refresh() -> void:
	_refresh_timer.start(REFRESH_DELAY)


func _refresh_chapter_list() -> void:
	if _chapter_list == null:
		return
	_chapter_list.clear()
	for index in _chapters.size():
		var chapter: Dictionary = _chapters[index]
		var title_text := str(chapter.get("title", "")).strip_edges()
		if title_text.is_empty():
			title_text = "未命名章节"
		var count := _count_rule_lines(str(chapter.get("content", "")))
		_chapter_list.add_item("%02d  %s\n      %d 条规则" % [index + 1, title_text, count])
	if _current_index >= 0 and _current_index < _chapters.size():
		_chapter_list.select(_current_index)
	_chapter_stats.text = "%d / %d 章节  ·  %d 条规则" % [_chapters.size(), MAX_CHAPTERS, _total_rule_count()]


func _select_chapter(index: int) -> void:
	if index < 0 or index >= _chapters.size():
		_current_index = -1
		_suppress_editor_signals = true
		_chapter_title.text = ""
		_content_editor.text = ""
		_chapter_title.editable = false
		_content_editor.editable = false
		_suppress_editor_signals = false
		return
	_current_index = index
	var chapter: Dictionary = _chapters[index]
	_suppress_editor_signals = true
	_chapter_title.editable = true
	_content_editor.editable = true
	_chapter_title.text = str(chapter.get("title", ""))
	_content_editor.text = str(chapter.get("content", ""))
	_suppress_editor_signals = false
	_chapter_list.select(index)
	_refresh_editor_stats()
	_refresh_quality_and_preview()


func _on_editor_changed(_title_changed: bool) -> void:
	if _suppress_editor_signals or _current_index < 0 or _current_index >= _chapters.size():
		return
	_chapters[_current_index]["title"] = _chapter_title.text
	_chapters[_current_index]["content"] = _content_editor.text
	_dirty = true
	var display_title := _chapter_title.text.strip_edges()
	if display_title.is_empty():
		display_title = "未命名章节"
	_chapter_list.set_item_text(_current_index, "%02d  %s\n      %d 条规则" % [_current_index + 1, display_title, _count_rule_lines(_content_editor.text)])
	_chapter_stats.text = "%d / %d 章节  ·  %d 条规则" % [_chapters.size(), MAX_CHAPTERS, _total_rule_count()]
	_refresh_editor_stats()
	_reset_search_state()
	_schedule_refresh()


func _refresh_editor_stats() -> void:
	if _current_index < 0:
		_editor_stats.text = "没有可编辑章节"
		return
	var content := _content_editor.text
	var lowered_content := content.to_lower()
	var motion_count := lowered_content.count("[shake]") + lowered_content.count("[dread")
	var danger_count := maxi(lowered_content.count("[blood]"), motion_count)
	_editor_stats.text = "%d 字符  ·  %d 条非空规则  ·  %d 个高危标记" % [content.length(), _count_rule_lines(content), danger_count]


func _add_chapter() -> void:
	if _chapters.size() >= MAX_CHAPTERS:
		_show_message("无法新增", "单份规则档案最多包含 %d 个章节。" % MAX_CHAPTERS)
		return
	_chapters.append({"title": _unique_title("新章节"), "content": ""})
	_current_index = _chapters.size() - 1
	_mark_structure_changed()
	_chapter_title.grab_focus()
	_chapter_title.select_all()


func _duplicate_chapter() -> void:
	if _current_index < 0 or _current_index >= _chapters.size():
		return
	if _chapters.size() >= MAX_CHAPTERS:
		_show_message("无法复制", "章节数量已经达到上限。")
		return
	var source: Dictionary = _chapters[_current_index]
	var copy := {
		"title": _unique_title("%s 副本" % str(source.get("title", "未命名章节"))),
		"content": str(source.get("content", "")),
	}
	_chapters.insert(_current_index + 1, copy)
	_current_index += 1
	_mark_structure_changed()


func _confirm_delete_chapter() -> void:
	if _current_index < 0 or _current_index >= _chapters.size():
		return
	var chapter: Dictionary = _chapters[_current_index]
	_confirm(
		"删除章节",
		"确定删除 <%s>？此操作会从当前档案中移除该章节。" % str(chapter.get("title", "未命名章节")),
		_delete_current_chapter
	)


func _delete_current_chapter() -> void:
	if _current_index < 0 or _current_index >= _chapters.size():
		return
	_chapters.remove_at(_current_index)
	_current_index = mini(_current_index, _chapters.size() - 1)
	_mark_structure_changed()


func _move_chapter(direction: int) -> void:
	var target := _current_index + direction
	if _current_index < 0 or target < 0 or target >= _chapters.size():
		return
	var temporary: Dictionary = _chapters[_current_index]
	_chapters[_current_index] = _chapters[target]
	_chapters[target] = temporary
	_current_index = target
	_mark_structure_changed()


func _mark_structure_changed() -> void:
	_dirty = true
	_reset_search_state()
	_refresh_chapter_list()
	_select_chapter(_current_index)
	_refresh_all(false)


func _insert_template(kind: String) -> void:
	if _current_index < 0:
		_add_chapter()
	var next_number := _count_rule_lines(_content_editor.text) + 1
	var insertion := TEMPLATE_ORDINARY % next_number
	if kind == "conditional":
		insertion = TEMPLATE_CONDITIONAL % next_number
	elif kind == "exit":
		insertion = TEMPLATE_EXIT % next_number
	_append_to_editor(insertion)


func _mark_danger() -> void:
	if _current_index < 0:
		return
	var selected := _content_editor.get_selected_text()
	if selected.is_empty():
		selected = "高危异象"
	else:
		_content_editor.delete_selection()
	_content_editor.insert_text_at_caret("[blood][dread strength=1.0]%s[/dread][/blood]" % selected)
	_content_editor.grab_focus()


func _append_to_editor(text_value: String) -> void:
	var prefix := ""
	if not _content_editor.text.is_empty() and not _content_editor.text.ends_with("\n"):
		prefix = "\n"
	_content_editor.set_caret_line(maxi(0, _content_editor.get_line_count() - 1))
	_content_editor.set_caret_column(_content_editor.get_line(_content_editor.get_caret_line()).length())
	_content_editor.insert_text_at_caret(prefix + text_value)
	_content_editor.grab_focus()


func _insert_guide_template(index: int) -> void:
	if index < 0 or index >= GUIDE_TEMPLATES.size():
		return
	if _chapters.size() >= MAX_CHAPTERS:
		_show_message("无法加入模板", "章节数量已经达到上限。")
		return
	var template: Dictionary = GUIDE_TEMPLATES[index]
	_chapters.append({
		"title": _unique_title(str(template.get("title", "规则模块"))),
		"content": str(template.get("content", "")),
	})
	_current_index = _chapters.size() - 1
	_mark_structure_changed()
	_set_mode(0)


func _set_mode(index: int) -> void:
	if index < 0 or index >= _tabs.get_tab_count():
		return
	_tabs.current_tab = index
	for button_index in _mode_buttons.size():
		var selected := button_index == index
		_mode_buttons[button_index].modulate = Color("#fff0c5") if selected else Color.WHITE
		_mode_buttons[button_index].add_theme_color_override("font_color", UIFactory.C_GOLD if selected else UIFactory.C_TEXT)
	if index == 1:
		_refresh_audit()
	elif index == 2:
		_refresh_preflight()
	UIFactory.fade_in(_tabs.get_current_tab_control(), 0.12)


func _validate_document() -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var issue_by_chapter: Dictionary = {}
	var seen_titles: Dictionary = {}
	var seen_rules: Dictionary = {}
	var polarity_rules: Dictionary = {}
	var total_rules := 0
	var danger_total := 0

	if _chapters.is_empty():
		errors.append("档案没有任何章节。")
	if _chapters.size() > MAX_CHAPTERS:
		errors.append("章节数量超过 %d 个上限。" % MAX_CHAPTERS)

	for chapter_index in _chapters.size():
		var chapter: Dictionary = _chapters[chapter_index]
		var title_text := str(chapter.get("title", "")).strip_edges()
		var content := str(chapter.get("content", ""))
		var chapter_issues: Array[String] = []
		if title_text.is_empty():
			chapter_issues.append("章节标题为空")
			errors.append("第 %d 章缺少标题。" % (chapter_index + 1))
		elif title_text.contains("<") or title_text.contains(">") or title_text.contains("\n"):
			chapter_issues.append("标题含非法的尖括号或换行")
			errors.append("<%s> 的标题不能包含尖括号或换行。" % _report_safe(title_text))
		var normalized_title := title_text.to_lower()
		if not normalized_title.is_empty() and seen_titles.has(normalized_title):
			chapter_issues.append("标题与其他章节重复")
			errors.append("章节标题 <%s> 重复。" % _report_safe(title_text))
		else:
			seen_titles[normalized_title] = chapter_index
		if content.strip_edges().is_empty():
			chapter_issues.append("正文为空")
			errors.append("<%s> 没有规则正文。" % _report_safe(title_text))

		var lower := content.to_lower()
		var tag_errors := _validate_bbcode_tags(content)
		for tag_error in tag_errors:
			chapter_issues.append(str(tag_error))
			errors.append("<%s> 的 BBCode 无效：%s" % [_report_safe(title_text), _report_safe(str(tag_error))])
		var marker_regex := RegEx.new()
		marker_regex.compile("(?m)^\\s*<[^<>\\r\\n]+>\\s*$")
		if marker_regex.search(content) != null:
			chapter_issues.append("正文中出现独占一行的章节标记")
			errors.append("<%s> 正文内含有新的 <章节> 标记，请拆分为独立章节。" % _report_safe(title_text))

		var chapter_rule_count := 0
		for raw_line in content.split("\n", true):
			var plain_line := SafeBBCode.plain_text(str(raw_line)).strip_edges()
			if plain_line.is_empty():
				continue
			chapter_rule_count += 1
			total_rules += 1
			var normalized_rule := _normalize_rule(plain_line)
			if normalized_rule.length() >= 4:
				if seen_rules.has(normalized_rule):
					warnings.append("规则疑似重复：<%s> 与 <%s> 中出现相同内容。" % [_report_safe(str(seen_rules[normalized_rule])), _report_safe(title_text)])
				else:
					seen_rules[normalized_rule] = title_text
			var negative := plain_line.contains("不要") or plain_line.contains("禁止") or plain_line.contains("不得")
			var polarity_key := _polarity_key(plain_line)
			if polarity_key.length() >= 6:
				if polarity_rules.has(polarity_key) and bool(polarity_rules[polarity_key].get("negative", false)) != negative:
					warnings.append("可能存在正反冲突：<%s> 与 <%s> 对相近动作给出不同要求。" % [_report_safe(str(polarity_rules[polarity_key].get("title", "其他章节"))), _report_safe(title_text)])
				else:
					polarity_rules[polarity_key] = {"negative": negative, "title": title_text}
		if chapter_rule_count < 2 and not content.strip_edges().is_empty():
			warnings.append("<%s> 只有 %d 条规则，章节可能过薄。" % [_report_safe(title_text), chapter_rule_count])
		var chapter_motion := lower.count("[shake]") + lower.count("[dread")
		var chapter_danger := maxi(lower.count("[blood]"), chapter_motion)
		danger_total += chapter_danger
		if chapter_danger > 4:
			warnings.append("<%s> 使用了 %d 个高危效果，频繁动效会削弱恐惧。" % [_report_safe(title_text), chapter_danger])
		if not chapter_issues.is_empty():
			issue_by_chapter[chapter_index] = chapter_issues

	var raw := _joined_text()
	var byte_count := raw.to_utf8_buffer().size()
	if byte_count > RuleDocumentData.MAXIMUM_RULE_BYTES:
		errors.append("档案大小超过 512 KB，无法安全导入游戏。")
	if not _contains_pattern(raw, "出口|离开|逃离|通关|解除"):
		warnings.append("没有发现明确的离开或解除条件。")
	if total_rules < 5:
		warnings.append("整份档案只有 %d 条规则，建议至少写 5 条。" % total_rules)

	var score := clampi(100 - errors.size() * 24 - warnings.size() * 6, 0, 100)
	return {
		"errors": errors,
		"warnings": warnings,
		"issues": issue_by_chapter,
		"rule_count": total_rules,
		"danger_count": danger_total,
		"bytes": byte_count,
		"score": score,
	}


func _refresh_quality_and_preview() -> void:
	if _latest_report.is_empty():
		_latest_report = _validate_document()
	var errors: Array = _latest_report.get("errors", [])
	var warnings: Array = _latest_report.get("warnings", [])
	var score := int(_latest_report.get("score", 0))
	var grade := "C"
	if score >= 90:
		grade = "A"
	elif score >= 75:
		grade = "B"
	if not errors.is_empty():
		grade = "未就绪"
	_quality_label.text = "质量 %s  ·  %d" % [grade, score]
	_quality_label.add_theme_color_override("font_color", UIFactory.C_GREEN if errors.is_empty() else UIFactory.C_RED)
	_quality_bar.value = score

	if _current_index >= 0 and _current_index < _chapters.size():
		var chapter: Dictionary = _chapters[_current_index]
		var preview_title := _report_safe(str(chapter.get("title", "未命名章节")))
		var preview_body := str(chapter.get("content", ""))
		_preview.text = "[color=#c2a56c][font_size=14]PREVIEW  /  <%s>[/font_size][/color]\n\n%s" % [preview_title, SafeBBCode.prepare(preview_body, _motion_allowed())]
	else:
		_preview.text = "[color=#988979]新增章节后，这里会显示经过安全过滤的 BBCode 效果。[/color]"

	var report_lines: Array[String] = []
	if errors.is_empty() and warnings.is_empty():
		report_lines.append("[color=#8eb490]✓ 结构检查通过，可以导出或开始游戏。[/color]")
	else:
		for error_value in errors:
			report_lines.append("[color=#c85a63]● 阻断：%s[/color]" % _report_safe(str(error_value)))
		for warning_value in warnings:
			report_lines.append("[color=#d7b860]◆ 建议：%s[/color]" % _report_safe(str(warning_value)))
	_validation_view.text = "\n".join(report_lines)
	_refresh_editor_stats()


func _refresh_audit() -> void:
	if _audit_list == null:
		return
	_audit_list.clear()
	for chapter_index in _chapters.size():
		var chapter: Dictionary = _chapters[chapter_index]
		var line_index := 0
		for raw_line in str(chapter.get("content", "")).split("\n", true):
			var plain_line := SafeBBCode.plain_text(str(raw_line)).strip_edges()
			if not plain_line.is_empty():
				var item_index := _audit_list.add_item("%02d.%02d  %s  /  %s" % [chapter_index + 1, line_index + 1, str(chapter.get("title", "未命名")), plain_line])
				_audit_list.set_item_metadata(item_index, {"chapter": chapter_index, "line": line_index})
			line_index += 1

	var errors: Array = _latest_report.get("errors", [])
	var warnings: Array = _latest_report.get("warnings", [])
	var summary: Array[String] = []
	summary.append("[font_size=22][color=#d7b860]%d 个章节 · %d 条规则 · %.1f KB[/color][/font_size]" % [_chapters.size(), int(_latest_report.get("rule_count", 0)), float(_latest_report.get("bytes", 0)) / 1024.0])
	summary.append("\n[color=#988979]阻断问题必须修复；建议项不会阻止导出，但可能降低长局的可推理性。[/color]\n")
	if errors.is_empty():
		summary.append("[color=#8eb490]✓ 没有结构性阻断问题。[/color]")
	else:
		for value in errors:
			summary.append("[color=#c85a63]● %s[/color]" % _report_safe(str(value)))
	if warnings.is_empty():
		summary.append("[color=#8eb490]✓ 没有发现明显重复、冲突或内容缺口。[/color]")
	else:
		for value in warnings:
			summary.append("[color=#d7b860]◆ %s[/color]" % _report_safe(str(value)))
	_audit_summary.text = "\n".join(summary)


func _refresh_preflight() -> void:
	if _preflight_gates == null:
		return
	var raw := _joined_text()
	var rule_count := int(_latest_report.get("rule_count", 0))
	var danger_count := int(_latest_report.get("danger_count", 0))
	var gates := [
		{"name": "存在离开条件", "pass": _contains_pattern(raw, "出口|离开|逃离|通关|解除"), "hint": "给玩家一个能够调查、积累并验证的长期目标。"},
		{"name": "存在可观察证据", "pass": _contains_pattern(raw, "观察|看见|听见|发现|征兆|颜色|声音|气味|影子|广播|灯光"), "hint": "危险必须先留下征兆，不能只靠随机惩罚。"},
		{"name": "存在明确后果", "pass": _contains_pattern(raw, "否则|后果|死亡|失踪|污染|受伤|代价|扣除|永远"), "hint": "规则被遵守或违反后，世界应产生可以感知的变化。"},
		{"name": "存在真假或例外", "pass": _contains_pattern(raw, "错误|伪装|欺骗|不可信|真假|例外|可能"), "hint": "保留不确定性，让玩家能够交叉验证，而不是机械背诵。"},
		{"name": "规则数量足够", "pass": rule_count >= 5, "hint": "建议至少 5 条有效规则，当前 %d 条。" % rule_count},
		{"name": "高危效果克制", "pass": danger_count <= maxi(2, _chapters.size()), "hint": "当前 %d 个标记；高危动效应只用于真正的诡异点。" % danger_count},
	]
	var passed := 0
	var gate_lines: Array[String] = []
	for index in gates.size():
		var gate: Dictionary = gates[index]
		var ok := bool(gate.get("pass", false))
		if ok:
			passed += 1
		gate_lines.append("[font_size=18][color=%s]%s  %02d  %s[/color][/font_size]\n[color=#988979]    %s[/color]\n" % ["#8eb490" if ok else "#c85a63", "✓" if ok else "×", index + 1, _report_safe(str(gate.get("name", "闸门"))), _report_safe(str(gate.get("hint", "")))])
	gate_lines.push_front("[color=#d7b860][font_size=21]%d / %d 项通过[/font_size][/color]\n" % [passed, gates.size()])
	_preflight_gates.text = "\n".join(gate_lines)

	var character_count := raw.length()
	var token_estimate := maxi(1, int(ceil(float(character_count) / 2.2)))
	_preflight_context.text = "[color=#c2a56c]CONTEXT  ·  %d 字符  ·  约 %d tokens[/color]\n\n%s" % [character_count, token_estimate, SafeBBCode.prepare(raw, false)]


func _refresh_header_status() -> void:
	var errors: Array = _latest_report.get("errors", [])
	var warnings: Array = _latest_report.get("warnings", [])
	if errors.is_empty():
		_status_label.text = "READY / 结构可用  ·  %d 条建议" % warnings.size()
		_status_label.add_theme_color_override("font_color", UIFactory.C_GREEN)
	else:
		_status_label.text = "NEEDS REVIEW  ·  %d 个阻断问题" % errors.size()
		_status_label.add_theme_color_override("font_color", UIFactory.C_RED)
	if _draft_enabled:
		_draft_label.text = "自动草稿已开启%s" % ("  ·  有未导出改动" if _dirty else "")
	else:
		_draft_label.text = "自动草稿已暂停"


func _locate_audit_item(item_index: int) -> void:
	var metadata: Variant = _audit_list.get_item_metadata(item_index)
	if not metadata is Dictionary:
		return
	var chapter_index := int(metadata.get("chapter", -1))
	var line_index := int(metadata.get("line", 0))
	_set_mode(0)
	_select_chapter(chapter_index)
	_content_editor.set_caret_line(clampi(line_index, 0, maxi(0, _content_editor.get_line_count() - 1)))
	_content_editor.set_caret_column(0)
	_content_editor.center_viewport_to_caret()
	_content_editor.grab_focus()


func _reset_search_state() -> void:
	_search_chapter = -1
	_search_offset = 0
	if _search_feedback != null:
		_search_feedback.text = ""


func _search_next() -> void:
	var query := _search_edit.text.strip_edges()
	if query.is_empty():
		_search_feedback.text = "请输入关键词"
		_search_edit.grab_focus()
		return
	if _chapters.is_empty():
		_search_feedback.text = "档案为空"
		return
	var query_lower := query.to_lower()
	var start_chapter := _search_chapter if _search_chapter >= 0 else maxi(0, _current_index)
	for step in _chapters.size():
		var chapter_index := (start_chapter + step) % _chapters.size()
		var chapter: Dictionary = _chapters[chapter_index]
		var title_text := str(chapter.get("title", ""))
		var content := str(chapter.get("content", ""))
		var offset := _search_offset if step == 0 and chapter_index == _search_chapter else 0
		var combined := "%s\n%s" % [title_text, content]
		var found_position := combined.to_lower().find(query_lower, offset)
		if found_position >= 0:
			if found_position < title_text.length():
				_reveal_search_result(chapter_index, -1, found_position, query.length())
			else:
				_reveal_search_result(chapter_index, found_position - title_text.length() - 1, 0, query.length())
			_search_chapter = chapter_index
			_search_offset = found_position + query.length()
			return
	_search_feedback.text = "没有更多结果"
	_search_chapter = -1
	_search_offset = 0


func _reveal_search_result(chapter_index: int, content_position: int, title_position: int, length: int) -> void:
	_set_mode(0)
	_select_chapter(chapter_index)
	if content_position < 0:
		_chapter_title.grab_focus()
		_chapter_title.select(title_position, title_position + length)
	else:
		var location := _line_column_for_position(_content_editor.text, content_position)
		var end_location := _line_column_for_position(_content_editor.text, content_position + length)
		_content_editor.select(int(location.x), int(location.y), int(end_location.x), int(end_location.y))
		_content_editor.center_viewport_to_caret()
		_content_editor.grab_focus()
	_search_feedback.text = "位于第 %d 章" % (chapter_index + 1)


func _line_column_for_position(text_value: String, position: int) -> Vector2i:
	var before := text_value.substr(0, clampi(position, 0, text_value.length()))
	var parts := before.split("\n", true)
	return Vector2i(parts.size() - 1, str(parts[parts.size() - 1]).length())


func _request_import() -> void:
	var dialog := FileDialog.new()
	dialog.title = "导入规则档案"
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.txt, *.md ; 规则文档"])
	dialog.file_selected.connect(func(path: String) -> void:
		_import_file(path)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.72)


func _import_file(path: String) -> void:
	var result := RuleDocumentData.from_file_path(path)
	var error_text := str(result.get("error", ""))
	if not error_text.is_empty():
		_show_message("导入失败", error_text)
		return
	var document: RuleDocumentData = result.get("document") as RuleDocumentData
	if document == null or document.is_empty():
		_show_message("导入失败", "没有从文件中解析出可用章节。")
		return
	var imported: Array[Dictionary] = []
	for chapter in document.chapters:
		imported.append({"title": str(chapter.get("title", "全文")), "content": str(chapter.get("content", ""))})
	var replace_action := func() -> void:
		_chapters = imported
		_current_index = 0
		_dirty = true
		_mark_structure_changed()
		_show_message("导入完成", "已读取 %d 个章节。原文档仍保留在磁盘中。" % _chapters.size())
	if _dirty:
		_confirm("替换当前档案", "导入会替换当前工坊内容。自动草稿会保留替换后的版本，是否继续？", replace_action)
	else:
		replace_action.call()


func _request_export() -> void:
	_latest_report = _validate_document()
	_refresh_all(false)
	var errors: Array = _latest_report.get("errors", [])
	if not errors.is_empty():
		_show_message("暂时无法导出", "请先修复 %d 个阻断问题。详情已显示在实时检查与全局审查中。" % errors.size())
		return
	var dialog := FileDialog.new()
	dialog.title = "导出规则档案"
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.current_file = "%s.txt" % _safe_file_name(_document_title())
	dialog.filters = PackedStringArray(["*.txt ; 纯文本规则", "*.md ; Markdown 文档"])
	dialog.file_selected.connect(func(path: String) -> void:
		_export_file(path)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.72)


func _export_file(path: String) -> void:
	var actual_path := path
	if actual_path.get_extension().is_empty():
		actual_path += ".txt"
	var file := FileAccess.open(actual_path, FileAccess.WRITE)
	if file == null:
		_show_message("导出失败", "无法写入目标文件：%s" % error_string(FileAccess.get_open_error()))
		return
	var write_succeeded := file.store_string(_joined_text())
	var write_error := file.get_error()
	file.close()
	if not write_succeeded:
		_show_message("导出失败", "写入过程中发生错误：%s。当前改动仍标记为未导出。" % error_string(write_error))
		return
	_dirty = false
	_refresh_header_status()
	_show_message("导出完成", "规则档案已保存到：\n%s" % actual_path)


func _validate_and_start() -> void:
	_latest_report = _validate_document()
	_refresh_all(false)
	var errors: Array = _latest_report.get("errors", [])
	if not errors.is_empty():
		_set_mode(1)
		_show_message("还不能开始", "档案仍有 %d 个阻断问题。修复后才能交给叙事核心。" % errors.size())
		return
	_save_draft()
	start_requested.emit(_joined_text(), _document_title())


func _toggle_draft(enabled: bool) -> void:
	_draft_enabled = enabled
	_refresh_header_status()
	if enabled:
		_save_draft()


func _save_draft() -> bool:
	if not _draft_enabled:
		return false
	var config := ConfigFile.new()
	config.set_value("draft", "text", _joined_text())
	config.set_value("draft", "title", _document_title())
	config.set_value("draft", "updated_at", Time.get_datetime_string_from_system())
	var result := config.save(DRAFT_PATH)
	if result == OK:
		_draft_label.add_theme_color_override("font_color", UIFactory.C_MUTED)
		_draft_label.text = "自动草稿已同步  ·  %s" % Time.get_time_string_from_system()
		_refresh_draft_state()
		return true
	_draft_label.text = "自动草稿保存失败  ·  %s" % error_string(result)
	_draft_label.add_theme_color_override("font_color", UIFactory.C_RED)
	return false


func _refresh_draft_state() -> void:
	if _restore_draft_button == null:
		return
	var config := ConfigFile.new()
	if config.load(DRAFT_PATH) != OK:
		_restore_draft_button.visible = false
		return
	var text_value := str(config.get_value("draft", "text", ""))
	_restore_draft_button.visible = not text_value.strip_edges().is_empty() and text_value != _joined_text()
	if _restore_draft_button.visible:
		_restore_draft_button.tooltip_text = "草稿时间：%s" % str(config.get_value("draft", "updated_at", "未知"))


func _restore_draft() -> void:
	var config := ConfigFile.new()
	if config.load(DRAFT_PATH) != OK:
		_show_message("没有草稿", "未找到可恢复的本地草稿。")
		return
	var text_value := str(config.get_value("draft", "text", ""))
	if text_value.strip_edges().is_empty():
		_show_message("没有草稿", "本地草稿为空。")
		return
	var restore_action := func() -> void:
		var document := RuleDocumentData.from_text(text_value, "全文")
		_chapters.clear()
		for chapter in document.chapters:
			_chapters.append({"title": str(chapter.get("title", "全文")), "content": str(chapter.get("content", ""))})
		_current_index = 0
		_dirty = true
		_mark_structure_changed()
	_confirm("恢复自动草稿", "恢复会替换当前工坊内容，是否继续？", restore_action)


func _confirm_clear_draft() -> void:
	_confirm("清空自动草稿", "确定清空本机保存的规则工坊草稿？当前编辑内容不会被删除。", _clear_draft)


func _clear_draft() -> void:
	_refresh_timer.stop()
	var config := ConfigFile.new()
	config.set_value("draft", "text", "")
	config.set_value("draft", "updated_at", Time.get_datetime_string_from_system())
	var result := config.save(DRAFT_PATH)
	if result != OK:
		_draft_label.text = "草稿清空失败  ·  %s" % error_string(result)
		_draft_label.add_theme_color_override("font_color", UIFactory.C_RED)
		return
	_restore_draft_button.visible = false
	_draft_label.add_theme_color_override("font_color", UIFactory.C_MUTED)
	_draft_label.text = "本地草稿已清空"


func _request_close() -> void:
	if not _dirty:
		hide()
		return
	var message := "当前档案有未导出的改动。"
	if _draft_enabled:
		if _save_draft():
			message += " 自动草稿已保存，之后可从工坊恢复。"
		else:
			message += " 自动草稿保存失败；关闭后这些改动可能无法恢复。"
	message += "\n确定关闭规则工坊吗？"
	_confirm("关闭规则工坊", message, hide)


func _show_message(dialog_title: String, message: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = dialog_title
	dialog.dialog_text = message
	dialog.min_size = Vector2i(540, 180)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(600, 220))


func _confirm(dialog_title: String, message: String, action: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = dialog_title
	dialog.dialog_text = message
	dialog.min_size = Vector2i(560, 190)
	dialog.ok_button_text = "确定"
	dialog.cancel_button_text = "取消"
	dialog.confirmed.connect(func() -> void:
		action.call()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(620, 230))


func _joined_text() -> String:
	var document := RuleDocumentData.new()
	for chapter in _chapters:
		document.chapters.append({"title": str(chapter.get("title", "")), "content": str(chapter.get("content", ""))})
	return document.joined_text()


func _document_title() -> String:
	if _chapters.is_empty():
		return "未命名规则档案"
	var first_title := str(_chapters[0].get("title", "")).strip_edges()
	return first_title if not first_title.is_empty() else "未命名规则档案"


func _unique_title(base: String) -> String:
	var candidate := base.strip_edges()
	if candidate.is_empty():
		candidate = "新章节"
	var suffix := 2
	while _title_exists(candidate):
		candidate = "%s %d" % [base, suffix]
		suffix += 1
	return candidate


func _title_exists(value: String) -> bool:
	for chapter in _chapters:
		if str(chapter.get("title", "")).strip_edges().to_lower() == value.strip_edges().to_lower():
			return true
	return false


func _total_rule_count() -> int:
	var total := 0
	for chapter in _chapters:
		total += _count_rule_lines(str(chapter.get("content", "")))
	return total


func _count_rule_lines(content: String) -> int:
	var count := 0
	for line in content.split("\n", true):
		if not SafeBBCode.plain_text(str(line)).strip_edges().is_empty():
			count += 1
	return count


func _validate_bbcode_tags(content: String) -> Array[String]:
	var supported := {
		"b": true, "i": true, "u": true, "s": true, "center": true,
		"code": true, "indent": true, "blood": true, "shake": true,
		"dread": true, "font_size": true, "color": true, "bgcolor": true,
		"quote": true, "spoiler": true, "br": true,
	}
	var tag_regex := RegEx.new()
	tag_regex.compile("\\[(/?)([A-Za-z0-9_]+)(?:=[^\\]]+|\\s+[^\\]]*)?\\]")
	var stack: Array[String] = []
	var problems: Array[String] = []
	for tag_match in tag_regex.search_all(content):
		var raw_tag := tag_match.get_string(0)
		var closing := tag_match.get_string(1) == "/"
		var tag := tag_match.get_string(2).to_lower()
		if not supported.has(tag):
			_append_unique(problems, "不支持标签 %s" % raw_tag)
			continue
		if tag == "br":
			if closing or raw_tag.to_lower() != "[br]":
				_append_unique(problems, "换行标签只能写作 [br]")
			continue
		if not closing and not _valid_bbcode_opening(tag, raw_tag):
			_append_unique(problems, "标签参数不安全或格式错误：%s" % raw_tag)
			continue
		if not closing:
			stack.append(tag)
			continue
		if stack.is_empty():
			_append_unique(problems, "关闭标签 %s 前没有对应的开始标签" % raw_tag)
			continue
		if stack.back() == tag:
			stack.pop_back()
			continue
		_append_unique(problems, "标签嵌套顺序错误：%s 应在 [/%s] 之后关闭" % [raw_tag, stack.back()])
		var matching_index := stack.rfind(tag)
		if matching_index >= 0:
			while stack.size() > matching_index:
				stack.pop_back()
	for unclosed_index in range(stack.size() - 1, -1, -1):
		_append_unique(problems, "标签 [%s] 没有关闭" % stack[unclosed_index])
	return problems


func _valid_bbcode_opening(tag: String, raw_tag: String) -> bool:
	var lowered := raw_tag.to_lower()
	if tag in ["color", "bgcolor"]:
		var color_regex := RegEx.new()
		color_regex.compile("^\\[(?:color|bgcolor)=#[0-9a-f]{6,8}\\]$")
		return color_regex.search(lowered) != null
	if tag == "font_size":
		var size_regex := RegEx.new()
		size_regex.compile("^\\[font_size=(?:1[0-9]|2[0-8])\\]$")
		return size_regex.search(lowered) != null
	if tag == "dread":
		var dread_regex := RegEx.new()
		dread_regex.compile("^\\[dread(?:\\s+strength=(?:0(?:\\.[0-9]+)?|1(?:\\.0+)?))?\\]$")
		return dread_regex.search(lowered) != null
	return lowered == "[%s]" % tag


func _append_unique(target: Array[String], value: String) -> void:
	if not target.has(value):
		target.append(value)


func _contains_pattern(text_value: String, pattern: String) -> bool:
	var regex := RegEx.new()
	return regex.compile(pattern) == OK and regex.search(text_value) != null


func _normalize_rule(value: String) -> String:
	var normalized := value.to_lower()
	var prefix_regex := RegEx.new()
	prefix_regex.compile("^\\s*(?:\\d+[.、．)]|[-*•])\\s*")
	normalized = prefix_regex.sub(normalized, "")
	var punctuation := RegEx.new()
	punctuation.compile("[\\s，。；：、！？,.!?:;‘’“”\"'（）()【】\\[\\]<>《》]+")
	return punctuation.sub(normalized, "", true)


func _polarity_key(value: String) -> String:
	var key := _normalize_rule(value)
	for word in ["不要", "禁止", "不得", "必须", "应当", "应该", "可以", "立即", "请"]:
		key = key.replace(word, "")
	return key


func _report_safe(value: String) -> String:
	return value.replace("[", "〔").replace("]", "〕")


func _safe_file_name(value: String) -> String:
	var safe := value
	for forbidden in ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"]:
		safe = safe.replace(forbidden, "_")
	return safe.strip_edges() if not safe.strip_edges().is_empty() else "规则档案"


func _motion_allowed() -> bool:
	if not is_inside_tree():
		return true
	var settings := get_node_or_null("/root/AppSettings")
	return settings == null or not bool(settings.get("reduced_motion"))
