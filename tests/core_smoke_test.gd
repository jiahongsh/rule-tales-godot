extends SceneTree

const SeedRngScript := preload("res://scripts/generator/seed_rng.gd")
const RuleForgeScript := preload("res://scripts/generator/rule_forge.gd")
const RunSystemsScript := preload("res://scripts/engine/run_systems.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_rule_document()
	_test_state_transaction()
	_test_qt_state_boundaries()
	_test_inventory_patch_contract()
	_test_map_patch_contract()
	_test_ending_contract()
	_test_fact_transaction()
	_test_rule_retrieval()
	_test_guard()
	_test_seed_generator()
	if _failures.is_empty():
		print("CORE_SMOKE_OK")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("CORE_SMOKE_FAILED:%d" % _failures.size())
		quit(1)


func _test_rule_document() -> void:
	var document := RuleDocumentData.from_text("序言\n<总则>\n不要回头。\n<出口>\n在天亮前离开。")
	_expect(document.chapters.size() == 3, "尖括号章节解析应保留前言与两个章节")
	_expect(str(document.chapters[1].title) == "总则", "章节标题应正确解析")


func _test_state_transaction() -> void:
	var state := RuleTalesGameState.new()
	var accepted := state.apply_patch({"elapsed_minutes": 12, "stats_delta": {"stamina": -7}})
	_expect(bool(accepted.ok), "合法状态补丁应被接受")
	_expect(int(state.data.minute_of_day) == 1225 and int(state.data.stats.stamina) == 93, "合法补丁应一次性提交")
	var before: Dictionary = state.data.duplicate(true)
	var rejected := state.apply_patch({"stats_delta": {"unknown": -1}})
	_expect(not bool(rejected.ok), "未知数值字段应被拒绝")
	_expect(state.data == before, "失败补丁不得污染权威状态")
	var initial_map := state.apply_patch({"map": {"discover": [{"id": "hall", "label": "大厅", "x": 0, "y": 0}], "current": "hall"}}, false)
	_expect(bool(initial_map.ok) and state.data.map.nodes.is_empty(), "初始回合禁用地图时不得写入地图")


func _test_fact_transaction() -> void:
	var store := StructuredFactStore.new()
	var accepted := store.apply_operations([{"op": "upsert", "id": "door", "kind": "open_event", "title": "未打开的门", "detail_bbcode": "门后有敲击声。"}], 1)
	_expect(bool(accepted.ok) and store.records.size() == 1, "合法事实应写入")
	var rejected := store.apply_operations([{"op": "resolve", "id": "missing", "resolution_bbcode": "没有这个事件。"}], 2)
	_expect(not bool(rejected.ok) and store.records.size() == 1, "无效事实批次必须整体回滚")
	var resolved := store.apply_operations([{"op": "resolve", "id": "door", "resolution_bbcode": "门已从内侧打开。"}], 3)
	_expect(bool(resolved.ok) and str(store.records[0].get("status", "")) == "resolved", "open_event 应可使用结案说明完成")
	_expect(str(store.records[0].get("resolution_bbcode", "")) == "门已从内侧打开。", "结案说明必须进入权威事实")
	_expect(int(store.records[0].get("first_seen_turn", -1)) == 1 and int(store.records[0].get("last_updated_turn", -1)) == 3, "事实应使用 Qt 的首次/末次回合字段")
	var before_invalid_type := store.records.duplicate(true)
	var invalid_type := store.apply_operations([{"op": "upsert", "id": "bad_text", "kind": "clue", "title": 123, "detail_bbcode": "数字标题不得被隐式转换。"}], 4)
	_expect(not bool(invalid_type.ok) and store.records == before_invalid_type, "事实文字字段类型错误时必须原子拒绝")


func _test_rule_retrieval() -> void:
	var document := RuleDocumentData.from_text("<总则>\n不要回应广播。\n<宿舍>\n镜子里的人影慢半拍。\n<出口>\n绿色楼梯只在停电后出现。")
	var index := RuleFragmentIndex.new()
	index.rebuild(document)
	var result := index.select("宿舍 镜子 人影", 2, 1, 7000)
	_expect(not result.fragments.is_empty(), "规则检索应返回相关片段")
	_expect(str(result.trace.query) == "宿舍 镜子 人影", "规则检索应保留调试轨迹")
	_expect(int(result.trace.selected_characters) > 0 and int(result.trace.selected_characters) <= 7000, "规则检索字符预算应被真实累计并受上限约束")


func _test_guard() -> void:
	var rejected := ClientRuleGuard.validate("站在原地", "灯光没有变化。", {"map": {"discover": []}}, [], [], [], "action")
	_expect(not rejected.is_empty(), "没有探索依据时地图补丁应被客户端裁判拒绝")
	var accepted := ClientRuleGuard.validate("进入大厅调查", "你进入大厅。", {"map": {"discover": []}}, [], [], [], "action")
	_expect(accepted.is_empty(), "有明确探索依据时地图补丁可进入后续状态校验")
	var rules := RuleDocumentData.from_text("<数值约束>\n健康必须保持在 80。\n不得携带红色钥匙。")
	var before := RuleTalesGameState.new()
	var valid_after := RuleTalesGameState.new(); valid_after.data.stats.health = 80
	_expect(ClientRuleGuard.validate_candidate(rules, before, valid_after).is_empty(), "满足明确固定值规则的候选状态应通过")
	var invalid_after := RuleTalesGameState.new(); invalid_after.data.stats.health = 70
	_expect(not ClientRuleGuard.validate_candidate(rules, before, invalid_after).is_empty(), "违反明确数值规则的状态应被客户端拒绝")
	valid_after.apply_patch({"inventory_ops": [{"op": "add", "id": "red_key", "name": "红色钥匙", "quantity": 1}]})
	_expect(not ClientRuleGuard.validate_candidate(rules, before, valid_after).is_empty(), "规则明确禁止的新增物品应被客户端拒绝")


func _test_qt_state_boundaries() -> void:
	var state := RuleTalesGameState.new()
	var max_text := "界".repeat(64 * 1024)
	var route := "R".repeat(96)
	_expect("A".to_utf16_buffer().size() == 2 and "🤖".to_utf16_buffer().size() == 4, "Godot UTF-16 缓冲区应可复现 QString 长度单位")
	var document: Dictionary = state.data.duplicate(true)
	document.day = 2_147_483_647
	document.weather = max_text
	document.stats["custom"] = 42
	document.inventory = [{"id": "bulk_item", "name": max_text, "description_bbcode": max_text, "quantity": 2_147_483_647}]
	document.status_bbcode = max_text
	document.map = {
		"nodes": [
			{"id": "far_west", "label": "西端", "symbol": "!", "x": -50, "y": -50},
			{"id": "far_east", "label": "东端", "symbol": "~", "x": 50, "y": 50},
		],
		"edges": [{"from": "far_west", "to": "far_east"}],
		"current": "far_east",
	}
	document.days_limit = 365
	document.route_node = route
	var error := state.replace_from_dict(document)
	_expect(error.is_empty(), "Qt 最大合法状态边界应完整载入：%s" % error)
	if not error.is_empty():
		return
	_expect(int(state.data.day) == 2_147_483_647 and int(state.data.days_limit) == 365, "day INT_MAX 与 days_limit 365 应保留")
	_expect(str(state.data.route_node) == route and str(state.data.status_bbcode) == max_text, "route_node 96 与 64KiB 状态文本不得截断")
	_expect(str(state.data.weather) == max_text and str(state.data.inventory[0].name) == max_text and str(state.data.inventory[0].description_bbcode) == max_text, "Qt 64KiB 文本字段不得静默截断")
	_expect(int(state.data.inventory[0].quantity) == 2_147_483_647 and int(state.data.stats.custom) == 42, "INT_MAX 库存与自定义数值应保留")
	var rendered := state.render_map_bbcode()
	_expect(rendered.contains("[code]") and rendered.contains("!") and rendered.contains("@") and rendered.contains("当前位置"), "±50 地图应完整渲染且不发生数组越界")

	var before: Dictionary = state.data.duplicate(true)
	var invalid: Dictionary = before.duplicate(true)
	invalid.day = 2_147_483_648
	_expect(not state.replace_from_dict(invalid).is_empty() and state.data == before, "day 超过 INT_MAX 必须原子拒绝")
	invalid = before.duplicate(true); invalid.days_limit = 366
	_expect(not state.replace_from_dict(invalid).is_empty() and state.data == before, "days_limit 366 必须原子拒绝")
	invalid = before.duplicate(true); invalid.route_node = "R".repeat(97)
	_expect(not state.replace_from_dict(invalid).is_empty() and state.data == before, "route_node 97 必须原子拒绝而非截断")
	invalid = before.duplicate(true); invalid.status_bbcode = "界".repeat(64 * 1024 + 1)
	_expect(not state.replace_from_dict(invalid).is_empty() and state.data == before, "64KiB+1 状态文本必须拒绝而非截断")
	invalid = before.duplicate(true); invalid.inventory[0].description_bbcode = "界".repeat(64 * 1024 + 1)
	_expect(not state.replace_from_dict(invalid).is_empty() and state.data == before, "64KiB+1 物品描述必须拒绝而非截断")
	var rollover := state.apply_patch({"elapsed_minutes": 1440})
	_expect(not bool(rollover.ok) and state.data == before, "day INT_MAX 跨日必须安全拒绝而不能溢出")


func _test_inventory_patch_contract() -> void:
	var state := RuleTalesGameState.new()
	var created := state.apply_patch({"inventory_ops": [{
		"op": "set",
		"item": {"id": "seal", "name": "普通封条", "description_bbcode": "旧描述", "quantity": 2},
		"name_bbcode": "[b]红色封条[/b]",
	}]})
	_expect(bool(created.ok), "inventory set 应支持嵌套 item 与平铺字段覆盖")
	_expect(str(state.inventory_item("seal").name) == "[b]红色封条[/b]" and int(state.inventory_item("seal").quantity) == 2, "name_bbcode 应优先于 name 并保存到名称字段")
	var updated := state.apply_patch({"inventory_ops": [{"op": "set", "id": "seal", "name_bbcode": "[i]新封条[/i]", "description_bbcode": "", "quantity": 3}]})
	_expect(bool(updated.ok) and str(state.inventory_item("seal").name) == "[i]新封条[/i]" and str(state.inventory_item("seal").description_bbcode).is_empty(), "set 应更新非空名称并允许显式清空描述")
	var added := state.apply_patch({"inventory_ops": [{"op": "add", "id": "seal", "name": "不会覆盖", "description_bbcode": "不会覆盖", "quantity": 2}]})
	_expect(bool(added.ok) and int(state.inventory_item("seal").quantity) == 5 and str(state.inventory_item("seal").name) == "[i]新封条[/i]", "add 已有物品只能增加数量")
	var removed := state.apply_patch({"inventory_ops": [{"op": "set", "id": "seal", "quantity": 0}]})
	_expect(bool(removed.ok) and state.inventory_item("seal").is_empty(), "set 0 应移除已有物品")
	var no_op := state.apply_patch({"inventory_ops": [{"op": "set", "id": "missing", "quantity": 0}]})
	_expect(bool(no_op.ok) and state.data.inventory.is_empty(), "set 0 对缺失物品应为成功的无操作")

	var maximum := state.apply_patch({"inventory_ops": [{"op": "set", "id": "bulk", "name": "整箱物资", "quantity": 2_147_483_647}]})
	_expect(bool(maximum.ok) and int(state.inventory_item("bulk").quantity) == 2_147_483_647, "inventory quantity INT_MAX 应可设置")
	var before: Dictionary = state.data.duplicate(true)
	var overflow := state.apply_patch({"weather_set": "雨", "inventory_ops": [{"op": "add", "id": "bulk", "quantity": 1}]})
	_expect(not bool(overflow.ok) and state.data == before, "库存加法溢出应回滚同批次天气修改")
	var fractional := state.apply_patch({"inventory_ops": [{"op": "set", "id": "bulk", "quantity": 1.5}]})
	_expect(not bool(fractional.ok) and state.data == before, "小数库存数量必须原子拒绝")


func _test_map_patch_contract() -> void:
	var state := RuleTalesGameState.new()
	var ignored := state.apply_patch({"map": "首轮即使格式错误也应忽略"}, false)
	_expect(bool(ignored.ok) and state.data.map.nodes.is_empty(), "allow_map=false 时应完全忽略 map 内容")
	var discovered := state.apply_patch({"map": {
		"discover": [
			{"id": "west", "label": "西界", "symbol": "!", "x": -50, "y": 0},
			{"id": "east", "label": "东界", "symbol": "~", "x": 50, "y": 0},
		],
		"connect": [{"from": "west", "to": "east"}, {"from": "east", "to": "west"}],
		"current": "east",
	}})
	_expect(bool(discovered.ok), "±50 坐标与可见 ASCII 边界符号应可发现")
	_expect(state.data.map.nodes.size() == 2 and state.data.map.edges.size() == 1, "无向重复边应静默去重")
	var before: Dictionary = state.data.duplicate(true)
	var duplicate_coordinate := state.apply_patch({"weather_set": "雨", "map": {"discover": [{"id": "duplicate", "label": "重叠", "symbol": "#", "x": 50, "y": 0}]}})
	_expect(not bool(duplicate_coordinate.ok) and state.data == before, "重复地图坐标应回滚整批补丁")
	for invalid_symbol in [" ", "[", "]", "怪", "ab"]:
		var rejected := state.apply_patch({"map": {"discover": [{"id": "bad_symbol", "label": "错误", "symbol": invalid_symbol, "x": 0, "y": 1}]}})
		_expect(not bool(rejected.ok) and state.data == before, "非法地图 symbol 应拒绝：%s" % invalid_symbol)
	var out_of_range := state.apply_patch({"map": {"discover": [{"id": "too_far", "label": "越界", "symbol": "#", "x": 51, "y": 0}]}})
	_expect(not bool(out_of_range.ok) and state.data == before, "地图坐标 51 必须拒绝")
	var fractional := state.apply_patch({"map": {"discover": [{"id": "fraction", "label": "小数", "symbol": "#", "x": 1.5, "y": 1}]}})
	_expect(not bool(fractional.ok) and state.data == before, "地图小数坐标必须拒绝")
	var unknown := state.apply_patch({"map": {"unknown": []}})
	_expect(not bool(unknown.ok) and state.data == before, "patch.map 未知字段必须拒绝")
	var public_set := state.apply_patch({"stats_set": {"health": 50}})
	_expect(not bool(public_set.ok) and state.data == before, "公开 AI patch 不得接受 Qt 未定义的 stats_set")


func _test_ending_contract() -> void:
	var state := RuleTalesGameState.new()
	var health_zero := state.apply_patch({"stats_delta": {"health": -2_147_483_648, "sanity": 2_147_483_647}})
	_expect(bool(health_zero.ok) and int(state.data.stats.health) == 0 and int(state.data.stats.sanity) == 100, "stats_delta 应接受完整 int32 并夹紧到 0..100")
	_expect(str(state.data.ending.type) == "none", "health/sanity 归零不应由客户端擅自生成结局")
	var before_delta: Dictionary = state.data.duplicate(true)
	var invalid_delta := state.apply_patch({"stats_delta": {"health": 2_147_483_648}})
	_expect(not bool(invalid_delta.ok) and state.data == before_delta, "超出 int32 的 stats_delta 必须原子拒绝")
	var fractional_delta := state.apply_patch({"stats_delta": {"health": 1.5}})
	_expect(not bool(fractional_delta.ok) and state.data == before_delta, "小数 stats_delta 必须原子拒绝")

	var title := "终".repeat(120)
	var summary := "档".repeat(64 * 1024)
	var ending := state.apply_patch({"ending": {"type": "special", "title": title, "summary_bbcode": summary}})
	_expect(bool(ending.ok) and str(state.data.ending.title) == title and str(state.data.ending.summary_bbcode) == summary, "ending title120/summary64KiB 应完整保存")
	_expect(bool(state.apply_patch({}).ok), "终局后的空补丁应保持幂等成功")
	_expect(not bool(state.apply_patch({"elapsed_minutes": 1}).ok), "终局后的非空补丁必须冻结")

	for invalid_ending in [
		{"type": "escape", "title": "终".repeat(121), "summary_bbcode": "完成"},
		{"type": "escape", "title": "完成", "summary_bbcode": "档".repeat(64 * 1024 + 1)},
		{"type": "escape", "title": "完成", "summary_bbcode": ""},
		{"type": "none", "title": "清除", "summary_bbcode": "不允许"},
		{"type": "escape", "title": "完成", "summary_bbcode": "有效", "unknown": true},
	]:
		var candidate := RuleTalesGameState.new()
		var rejected := candidate.apply_patch({"ending": invalid_ending})
		_expect(not bool(rejected.ok) and str(candidate.data.ending.type) == "none", "非法 ending 必须原子拒绝")
	var initial_candidate := RuleTalesGameState.new()
	var initial_ending := initial_candidate.apply_patch({"ending": {"type": "escape", "title": "越界", "summary_bbcode": "初始回合不能结束。"}}, false)
	_expect(not bool(initial_ending.ok) and str(initial_candidate.data.ending.type) == "none", "初始回合不得提交 ending")


func _test_seed_generator() -> void:
	var rng := SeedRngScript.new(5489)
	_expect(rng.next_u32() == 3499211612, "种子 RNG 必须与标准 MT19937 的首个输出一致")
	var first: Dictionary = RuleForgeScript.forge(20260812)
	var second: Dictionary = RuleForgeScript.forge(20260812)
	_expect(bool(first.ok), "规则种子应生成可解档案")
	_expect(str(first.get("document_text", "")) == str(second.get("document_text", "")), "相同种子必须逐字生成相同档案")
	_expect(first.get("rules", []).size() >= 12, "种子档案必须达到最小规则密度")
	var pack: Dictionary = first.get("pack", {})
	var routes: Dictionary = RunSystemsScript.route_choices(20260812, pack.get("locations", []), 3, 7)
	_expect(routes.get("options", []).size() >= 2, "限时局每夜必须产生两到三条客户端权威路线")
	_expect(RunSystemsScript.award_for_run("escape", "S", 1.0) == 190, "跨局认知点公式必须保持兼容")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
