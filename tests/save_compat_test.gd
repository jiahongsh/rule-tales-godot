extends Node

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_legacy_fact_normalization()
	_test_qt_document_round_trip()
	if _failures.is_empty():
		print("SAVE_COMPAT_OK")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SAVE_COMPAT_FAILED:%d" % _failures.size())
	get_tree().quit(1)


func _test_legacy_fact_normalization() -> void:
	var store := StructuredFactStore.new()
	var result := store.load_records([{
		"id": "legacy_lobby",
		"kind": "location",
		"title": "旧大厅",
		"detail_bbcode": "由早期 Godot 存档载入。",
		"status": "active",
		"updated_turn": 4,
	}])
	_expect(bool(result.get("ok", false)), "早期 Godot 的 updated_turn 事实应可读取。")
	if not bool(result.get("ok", false)):
		return
	var record: Dictionary = store.records[0]
	_expect(not record.has("updated_turn"), "旧回合字段应在内存中立即移除。")
	_expect(int(record.get("first_seen_turn", -1)) == 4 and int(record.get("last_updated_turn", -1)) == 4, "旧回合字段应规范化为 Qt 双回合字段。")


func _test_qt_document_round_trip() -> void:
	GameSession.reset_session()
	var initial_state := RuleTalesGameState.new()
	var max_state_text := "态".repeat(64 * 1024)
	initial_state.data.day = 2_147_483_647
	initial_state.data.status_bbcode = max_state_text
	initial_state.data.inventory = [{"id": "qt_bulk", "name": "Qt 整箱物资", "description_bbcode": max_state_text, "quantity": 2_147_483_647}]
	initial_state.data.map = {
		"nodes": [
			{"id": "qt_west", "label": "西端", "symbol": "!", "x": -50, "y": 0},
			{"id": "qt_east", "label": "东端", "symbol": "~", "x": 50, "y": 0},
		],
		"edges": [{"from": "qt_west", "to": "qt_east"}],
		"current": "qt_east",
	}
	initial_state.data.days_limit = 365
	initial_state.data.route_node = "R".repeat(96)
	var qt_document := {
		"save_schema": 1,
		"story_title": "Qt 兼容档案",
		"rule_source_path": "C:/portable/rules.txt",
		"offline_demo": false,
		"rules_text": "<总则>\n不要回应凌晨广播。",
		"state": initial_state.data.duplicate(true),
		"facts": [{
			"id": "event_broadcast",
			"kind": "open_event",
			"title": "查明广播来源",
			"detail_bbcode": "广播仍在重复你的名字。",
			"status": "resolved",
			"resolution_bbcode": "在值班室切断了旧线路。",
			"first_seen_turn": 1,
			"last_updated_turn": 3,
		}],
		"history": [
			{"role": "assistant", "content": "走廊尽头传来广播。", "id": "a-1"},
			{"role": "user", "content": "检查值班室。", "id": "u-2"},
		],
		"choices": ["离开值班室", "检查线路", "记录频率"],
		"discovered_rules": ["r1_1"],
		"key_choices": [{"turn": 2, "action": "检查值班室", "consequence": "找到了旧线路", "rule_refs": ["r1_1"]}],
		"timeline": [],
		"run_config": {"enabled": true, "seed": 741, "theme": "campus", "days_limit": 7},
		"meta_awarded": true,
		"tamper_plans": [],
		"tamper_status": 2,
		"tamper_trigger_day": 2,
		"resolved_anomaly_rounds": ["night_1_mirror"],
		"identified_anomalies": ["mirror_delay"],
		"completed_turns": 3,
	}
	var snapshot: Dictionary = qt_document.duplicate(true)
	snapshot.erase("timeline")
	snapshot.erase("rules_text")
	snapshot.erase("rule_source_path")
	snapshot.history_windowed = true
	qt_document.timeline = [{"id": "turn_3", "turn": 3, "label": "切断广播", "timestamp": "2026-08-12T20:13:00Z", "key_moment": true, "snapshot": snapshot}]

	var parser := JSON.new()
	_expect(parser.parse(JSON.stringify(qt_document)) == OK, "Qt 兼容测试文档应可序列化。")
	if not parser.data is Dictionary:
		return
	var load_result: Dictionary = GameSession.load_document(parser.data)
	_expect(bool(load_result.get("ok", false)), "Qt schema 1 文档应可直接载入 Godot。")
	if not bool(load_result.get("ok", false)):
		return
	_expect(GameSession.story_title == "Qt 兼容档案" and GameSession.completed_turns == 3, "Qt 标题与回合数应保留。")
	_expect(int(GameSession.state.data.day) == 2_147_483_647 and int(GameSession.state.data.days_limit) == 365 and str(GameSession.state.data.route_node).length() == 96, "Qt GameState 数值与路线边界应跨 JSON 保留。")
	_expect(int(GameSession.state.inventory_item("qt_bulk").quantity) == 2_147_483_647 and str(GameSession.state.inventory_item("qt_bulk").description_bbcode) == max_state_text, "Qt INT_MAX 库存与 64KiB 文本应跨 JSON 保留。")
	_expect(int(GameSession.state.data.map.nodes[0].x) == -50 and int(GameSession.state.data.map.nodes[1].x) == 50, "Qt ±50 地图坐标应跨 JSON 保留。")
	_expect(str(GameSession.run_config.get("theme_id", "")) == "campus", "Qt run_config.theme 应迁移到 theme_id。")
	_expect(GameSession.meta_rewarded and GameSession.identified_anomaly_ids == ["mirror_delay"], "Qt 元奖励与异常字段别名应读取。")
	_expect(GameSession.facts.records.size() == 1 and str(GameSession.facts.records[0].get("resolution_bbcode", "")) == "在值班室切断了旧线路。", "Qt 事实结案字段应完整保留。")

	var exported: Dictionary = GameSession.to_dict()
	var saved_fact: Dictionary = exported.get("facts", [])[0]
	_expect(saved_fact.has("first_seen_turn") and saved_fact.has("last_updated_turn") and not saved_fact.has("updated_turn"), "再次保存必须输出 Qt 规范事实字段。")
	_expect(str(exported.get("run_config", {}).get("theme", "")) == "campus", "Godot 存档应同时写出 Qt run_config.theme。")
	_expect(exported.get("meta_awarded", false) == true and exported.get("identified_anomalies", []) == ["mirror_delay"], "Godot 存档应写出 Qt 顶层别名。")

	GameSession.timeline.clear()
	GameSession._append_timeline("action", "检查线路", true)
	var generated_snapshot: Dictionary = GameSession.timeline[0].get("snapshot", {})
	_expect(not generated_snapshot.has("timeline") and not generated_snapshot.has("rules_text") and not generated_snapshot.has("rule_source_path"), "时间线快照应裁掉 Qt 指定的大字段。")
	_expect(bool(generated_snapshot.get("history_windowed", false)), "时间线快照应标记 history_windowed。")

	var before_invalid: Dictionary = GameSession.to_dict()
	var invalid: Dictionary = before_invalid.duplicate(true)
	invalid.timeline = [{"id": "bad", "turn": "3", "label": "损坏节点", "timestamp": "", "key_moment": true, "snapshot": {"state": {}}}]
	var rejected: Dictionary = GameSession.load_document(invalid)
	_expect(not bool(rejected.get("ok", false)), "字段类型损坏的时间线必须被拒绝。")
	_expect(GameSession.to_dict() == before_invalid, "存档校验失败不得污染当前会话。")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
