extends Node

const RunSystemsScript := preload("res://scripts/engine/run_systems.gd")

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_run_systems()
	await _test_offline_six_act_run()
	if _failures.is_empty():
		print("OFFLINE_END_TO_END_OK")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("OFFLINE_END_TO_END_FAILED:%d" % _failures.size())
	get_tree().quit(1)


func _test_run_systems() -> void:
	var state := RuleTalesGameState.new()
	state.data.run_mode = true
	state.data.days_limit = 3
	state.data.day = 2
	_expect(RunSystemsScript.days_left(state) == 2, "限时调查应包含当前日在内计算剩余天数。")
	_expect(not RunSystemsScript.is_timeout(state), "仍在期限内时不得触发超时结局。")
	state.data.day = 4
	_expect(RunSystemsScript.is_timeout(state), "超过调查期限且尚无结局时应被判定为超时。")
	_expect(str(RunSystemsScript.timeout_ending().get("type", "")) == "missing", "限时耗尽应进入失踪结局。")

	var locations: Array = ["一层大厅", "东侧走廊", "档案室", "后门"]
	var first_routes: Dictionary = RunSystemsScript.route_choices(20260812, locations, 2, 7)
	var second_routes: Dictionary = RunSystemsScript.route_choices(20260812, locations, 2, 7)
	_expect(first_routes == second_routes, "相同种子、日期与地点必须生成完全一致的路线。")
	_expect(first_routes.get("options", []).size() in [2, 3], "每晚路线应稳定生成两到三个选项。")

	var anomaly_templates: Array = [{
		"id": "mirror_delay",
		"title": "迟到的倒影",
		"location": "洗手间",
		"normal": "倒影与你同时抬手。",
		"anomalous": "倒影慢了半拍。",
		"reveal": "规则要求倒影动作同步。"
	}]
	var first_anomaly: Dictionary = RunSystemsScript.anomaly_for_night(741, 1, anomaly_templates)
	var second_anomaly: Dictionary = RunSystemsScript.anomaly_for_night(741, 1, anomaly_templates)
	_expect(first_anomaly == second_anomaly and not first_anomaly.is_empty(), "夜间异常必须由种子确定且可复现。")
	_expect(str(first_anomaly.get("round_id", "")).begins_with("night_1_"), "异常回合应保留夜晚编号。")
	_expect(RunSystemsScript.anomaly_for_night(741, 0, anomaly_templates).is_empty(), "调查开始前不得生成夜间异常。")


func _test_offline_six_act_run() -> void:
	GameSession.reset_session()
	var started := GameSession.start_offline_demo()
	_expect(started, "离线六幕应无需 API 即可启动。")
	await _wait_for_offline_turn()
	_expect(not GameSession.busy, "离线初始场景应在等待后完成提交。")
	_expect(GameSession.offline_demo and GameSession.archive_id == "night_archive", "离线体验必须装载固定的夜间档案。")
	_expect(GameSession.completed_turns == 1, "初始场景应作为第 1 回合写入。")
	_expect(GameSession.history.size() == 1 and GameSession.choices.size() == 3, "初始场景应生成叙事与三个行动选项。")
	_expect(not GameSession.state.is_terminal(), "初始场景不得提前进入结局。")
	_expect(GameSession.state.data.map.nodes.is_empty(), "初始地图必须保持空白，等待玩家亲自探索。")
	_expect(int(GameSession.state.inventory_item("sealed_water").get("quantity", 0)) == 2, "离线开局应提供两瓶密封饮用水。")
	_expect(int(GameSession.state.inventory_item("visitor_card").get("quantity", 0)) == 1, "离线开局应提供一张褪色访客证。")
	_expect(GameSession.timeline.size() == 1 and bool(GameSession.timeline[0].get("key_moment", false)), "档案启封应成为第一个关键时间线节点。")
	_expect(_latest_autosave_matches(1, false), "初始场景提交后应写入可读取的自动存档。")

	var actions: Array[String] = [
		"进入档案室，检查最近的门牌与出口",
		"收起半张疏散图，调查没有编号的走廊",
		"走向值班室，阻止广播继续预告自己的行动",
		"立刻离开失物招领室，前往广播控制室",
		"沿着控制室外廊前往后门安全通道",
		"穿过后门并逃离规则区域"
	]
	for action_index in actions.size():
		var before_turn := GameSession.completed_turns
		var submitted := GameSession.submit_action(actions[action_index])
		_expect(submitted, "第 %d 幕行动应被会话接受。" % (action_index + 1))
		if not submitted:
			return
		await _wait_for_offline_turn()
		_expect(not GameSession.busy, "第 %d 幕行动不应在等待后仍处于生成状态。" % (action_index + 1))
		_expect(GameSession.completed_turns == before_turn + 1, "第 %d 幕应且只应推进一个回合。" % (action_index + 1))
		_expect(str(GameSession.diagnostics.get("outcome", "")) == "accepted", "第 %d 幕状态补丁应通过客户端裁判。" % (action_index + 1))
		if GameSession.busy or GameSession.completed_turns != before_turn + 1:
			return

	_expect(GameSession.completed_turns == 7, "初始场景加六幕行动应累计为 7 回合。")
	_expect(GameSession.history.size() == 13, "六幕结束后历史应包含 7 条叙事与 6 条玩家行动。")
	_expect(GameSession.choices.is_empty(), "到达终局后不得继续显示普通行动选项。")
	_expect(GameSession.state.is_terminal(), "完成第六幕逃离行动后必须进入明确结局。")
	_expect(str(GameSession.state.data.ending.get("type", "")) == "escape", "从后门离开应达成逃脱结局。")
	_expect(str(GameSession.state.data.ending.get("title", "")) == "门外没有广播", "离线逃脱结局应展示固定结局标题。")
	_expect(GameSession.state.data.map.nodes.size() == 6 and GameSession.state.data.map.edges.size() == 5, "六次探索应形成六节点、五连线的渐进地图。")
	_expect(str(GameSession.state.data.map.current) == "trace_6", "终局当前位置应落在第六个探索节点。")
	_expect(GameSession.facts.records.size() == 6, "每个探索地点都应进入结构化事实记忆。")
	_expect(GameSession.timeline.size() == 7, "每个已提交回合都应留下时间线节点。")
	_expect(bool(GameSession.timeline.back().get("key_moment", false)), "结局回合必须标记为关键时间线节点。")
	_expect(GameSession.key_choices.size() == 6, "六幕探索行动应形成六条关键选择回顾。")
	_expect(GameSession.investigation_score() > 0, "明确结局必须生成非零调查评分。")
	_expect(_latest_autosave_matches(7, true), "终局提交后自动存档应包含结局与完整时间线。")

	var manual_result: Dictionary = GameSession.save_manual(6)
	_expect(bool(manual_result.get("ok", false)), "终局应可写入第六手动槽位。")
	var manual_read: Dictionary = RuleTalesSaveService.read_document(RuleTalesSaveService.manual_path(6))
	_expect(bool(manual_read.get("ok", false)), "手动槽位必须能通过 JSON 完整性校验。")
	if bool(manual_read.get("ok", false)):
		var saved_document: Dictionary = manual_read.document
		_expect(int(saved_document.get("completed_turns", 0)) == 7, "手动存档应保存终局回合数。")
		_expect(saved_document.get("timeline", []).size() == 7, "手动存档应保存完整回合时间线。")
		_expect(str(saved_document.get("state", {}).get("ending", {}).get("type", "")) == "escape", "手动存档应保存逃脱结局。")
	var summary: Dictionary = RuleTalesSaveService.slot_summary(6)
	_expect(not bool(summary.get("empty", true)) and int(summary.get("turn", 0)) == 7, "存档槽摘要应反映终局档案与回合数。")

	GameSession.reset_session()
	var restored_auto := GameSession.restore_autosave()
	_expect(restored_auto, "清空内存会话后应能恢复最新自动存档。")
	if not restored_auto:
		return
	_expect(GameSession.completed_turns == 7 and GameSession.state.is_terminal(), "自动存档恢复后应回到完整逃脱结局。")

	if GameSession.timeline.is_empty():
		_expect(false, "自动存档恢复后必须保留可回溯的时间线。")
		return
	var first_checkpoint: Dictionary = GameSession.timeline.front()
	var restart_result: Dictionary = GameSession.restart_from_checkpoint(str(first_checkpoint.get("id", "")))
	_expect(bool(restart_result.get("ok", false)), "应允许从档案启封这个关键节点重新开始。")
	_expect(GameSession.completed_turns == 1 and not GameSession.state.is_terminal(), "时间线回溯应恢复第 1 回合的非终局状态。")
	_expect(GameSession.history.size() == 1 and GameSession.choices.size() == 3, "时间线回溯应恢复当时的叙事与三个选项。")
	_expect(GameSession.timeline.size() == 1, "回溯后应丢弃所选节点之后的时间线进度。")

	var load_manual_result: Dictionary = GameSession.load_manual(6)
	_expect(bool(load_manual_result.get("ok", false)), "回溯后仍应能读取终局手动存档。")
	_expect(GameSession.completed_turns == 7 and str(GameSession.state.data.ending.type) == "escape", "手动存档读取应完整恢复终局。")


func _wait_for_offline_turn() -> void:
	for _attempt in 40:
		if not GameSession.busy:
			return
		await get_tree().create_timer(0.05).timeout


func _latest_autosave_matches(expected_turn: int, terminal: bool) -> bool:
	var paths: Array[String] = RuleTalesSaveService.autosaves_newest_first()
	if paths.is_empty():
		return false
	var read: Dictionary = RuleTalesSaveService.read_document(paths[0])
	if not bool(read.get("ok", false)):
		return false
	var document: Dictionary = read.document
	var state_document: Dictionary = document.get("state", {})
	var ending_document: Dictionary = state_document.get("ending", {})
	return int(document.get("completed_turns", -1)) == expected_turn \
		and (str(ending_document.get("type", "none")) != "none") == terminal \
		and document.get("timeline", []).size() == expected_turn


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
