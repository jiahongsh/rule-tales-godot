extends Node

signal rules_changed
signal state_changed(changes: Array)
signal history_changed
signal facts_changed
signal choices_changed(choices: Array)
signal busy_changed(busy: bool, message: String)
signal error_occurred(message: String, details: String)
signal notice(message: String)
signal ai_configuration_required(action: String)
signal autosave_written(time_text: String, path: String)
signal diagnostics_changed
signal ending_reached
signal day_rolled(new_day: int)
signal anomaly_pending(encounter: Dictionary)
signal routes_pending(route_set: Dictionary)
signal tamper_changed
signal meta_awarded(points: int, profile: Dictionary)

const OFFLINE_RULE_PATH := "res://content/rules/night_archive/rules.txt"
const OFFLINE_FLOW_PATH := "res://content/demos/night_archive/offline_flow.json"
const RuleForgeScript := preload("res://scripts/generator/rule_forge.gd")
const RunSystemsScript := preload("res://scripts/engine/run_systems.gd")
const MetaProfileScript := preload("res://scripts/persistence/meta_profile.gd")

var rules := RuleDocumentData.new()
var state := RuleTalesGameState.new()
var facts := StructuredFactStore.new()
var history: Array[Dictionary] = []
var choices: Array[String] = []
var key_choices: Array[Dictionary] = []
var timeline: Array[Dictionary] = []
var discovered_rule_ids: Array[String] = []
var completed_turns := 0
var story_title := "未命名规则档案"
var rule_source_path := ""
var archive_id := ""
var offline_demo := false
var busy := false
var diagnostics: Dictionary = {}
var run_config: Dictionary = {"enabled": false, "seed": 0, "theme_id": "", "days_limit": 0}
var forge_meta: Dictionary = {}
var rule_pack: Dictionary = {}
var tamper_plans: Array[Dictionary] = []
var tamper_status := "pending"
var tamper_trigger_day := 0
var resolved_anomaly_rounds: Array[String] = []
var identified_anomaly_ids: Array[String] = []
var pending_anomaly: Dictionary = {}
var pending_routes: Dictionary = {}
var meta_rewarded := false

var _ai: AiGateway
var _request_serial := 0
var _active_request := 0
var _active_phase := ""
var _active_action := ""
var _pending_choices: Array[String] = []
var _pending_selection: Dictionary = {}
var _offline_flow: Dictionary = {}


func _ready() -> void:
	_ai = AiGateway.new()
	add_child(_ai)
	_ai.completed.connect(_on_ai_completed)
	_ai.failed.connect(_on_ai_failed)
	_load_offline_flow()


func reset_session() -> void:
	if busy: cancel_generation()
	state = RuleTalesGameState.new()
	facts = StructuredFactStore.new()
	history.clear(); choices.clear(); key_choices.clear(); timeline.clear(); discovered_rule_ids.clear()
	completed_turns = 0; diagnostics = {}; _pending_choices.clear(); _pending_selection = {}
	_active_request = 0; _active_phase = ""; _active_action = ""; offline_demo = false; archive_id = ""
	run_config = {"enabled": false, "seed": 0, "theme_id": "", "days_limit": 0}; forge_meta = {}; rule_pack = {}
	tamper_plans.clear(); tamper_status = "pending"; tamper_trigger_day = 0
	resolved_anomaly_rounds.clear(); identified_anomaly_ids.clear(); pending_anomaly = {}; pending_routes = {}; meta_rewarded = false
	_set_busy(false, "")


func start_offline_demo() -> bool:
	var text := FileAccess.get_file_as_string(OFFLINE_RULE_PATH)
	if text.is_empty():
		error_occurred.emit("无法打开离线体验规则。", OFFLINE_RULE_PATH)
		return false
	return import_rules_text(text, "夜间档案室", OFFLINE_RULE_PATH, true, "night_archive") and _start_after_import()


func start_bundled_rules(path: String, title: String) -> bool:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		error_occurred.emit("无法打开内置规则。", path)
		return false
	if not import_rules_text(text, title, path, false, title): return false
	return _start_after_import()


func start_seed_run(seed: int, days_limit: int = 7) -> bool:
	if busy:
		return false
	var forged: Dictionary = RuleForgeScript.forge(seed)
	if not bool(forged.ok):
		error_occurred.emit("无法生成规则种子。", str(forged.error))
		return false
	if not import_rules_text(str(forged.document_text), str(forged.display_name), "规则种子 · %s" % str(forged.theme_id), false, "seed:%s:%d" % [str(forged.theme_id), seed & 0xFFFFFFFF]):
		return false
	run_config = {"enabled": true, "seed": seed & 0xFFFFFFFF, "theme_id": str(forged.theme_id), "days_limit": clampi(days_limit, 3, 14)}
	forge_meta = forged.meta.duplicate(true)
	rule_pack = forged.pack.duplicate(true)
	state.data.run_mode = true
	state.data.days_limit = int(run_config.days_limit)
	tamper_plans = []
	for value in forge_meta.get("tamperPlans", []):
		if value is Dictionary and not str(value.get("id", "")).is_empty() and not str(value.get("original", "")).is_empty() and not str(value.get("tampered", "")).is_empty() and str(value.original) != str(value.tampered):
			tamper_plans.append(value.duplicate(true))
	if not tamper_plans.is_empty():
		var span := maxi(1, int(run_config.days_limit) - 3)
		tamper_trigger_day = 2 + int(run_config.seed) % span
	_emit_all()
	write_autosave()
	return start_new_story()


func import_rules_path(path: String, begin_story: bool = true) -> bool:
	var parsed: Dictionary = RuleDocumentData.from_file_path(path)
	if not str(parsed.error).is_empty():
		error_occurred.emit("无法导入规则。", str(parsed.error))
		return false
	var document: RuleDocumentData = parsed.document
	reset_session()
	rules = document
	rule_source_path = path
	story_title = path.get_file().get_basename()
	archive_id = "custom"
	_emit_all()
	write_autosave()
	return start_new_story() if begin_story else true


func import_rules_text(text: String, title: String, source: String = "", is_offline: bool = false, stable_archive_id: String = "custom") -> bool:
	var document := RuleDocumentData.from_text(text)
	if document.is_empty():
		error_occurred.emit("无法导入规则。", "文档中没有可读取的文字。")
		return false
	reset_session()
	rules = document; rules.source_path = source
	rule_source_path = source; story_title = title; archive_id = stable_archive_id; offline_demo = is_offline
	_emit_all()
	write_autosave()
	return true


func _start_after_import() -> bool:
	return start_new_story()


func start_new_story() -> bool:
	if rules.is_empty():
		error_occurred.emit("无法开始故事。", "请先导入规则怪谈文本。")
		return false
	if busy: return false
	if not offline_demo and not AppSettings.has_live_ai():
		ai_configuration_required.emit("开始故事")
		error_occurred.emit("这份规则档案需要连接 AI。", "请在设置中填写 Endpoint、模型与 API Key；密钥不会写入存档。")
		return false
	_request_turn("initial", "开始故事")
	return true


func submit_action(action: String) -> bool:
	var cleaned := action.strip_edges()
	if cleaned.is_empty() or busy: return false
	if state.is_terminal():
		notice.emit("这份档案已经封存。可保存结局，或返回大厅开始新的故事。")
		return false
	if cleaned.length() > 4000:
		error_occurred.emit("行动描述过长。", "单次行动最多 4000 个字符。")
		return false
	if not offline_demo and not AppSettings.has_live_ai():
		ai_configuration_required.emit(cleaned)
		error_occurred.emit("当前档案需要重新连接 AI。", "API Key 不随存档保存。配置接口后可重新提交本次行动。")
		return false
	_pending_choices = choices.duplicate()
	history.append({"role": "user", "content": cleaned, "id": "u-%d" % (history.size() + 1)})
	choices.clear(); history_changed.emit(); choices_changed.emit(choices)
	_request_turn("action", cleaned)
	return true


func display_rules() -> RuleDocumentData:
	if tamper_status != "active" or tamper_plans.is_empty():
		return rules
	var text := rules.joined_text()
	var plan: Dictionary = tamper_plans[0]
	text = text.replace(str(plan.original), str(plan.tampered))
	return RuleDocumentData.from_text(text)


func identify_tamper(guessed_text: String) -> int:
	if tamper_status != "active" or tamper_plans.is_empty():
		return -1
	var plan: Dictionary = tamper_plans[0]
	if _normalized_tamper_text(guessed_text) != _normalized_tamper_text(str(plan.tampered)):
		var rejected := state.apply_patch({"stats_delta": {"sanity": -2}}, false)
		if rejected.ok: state_changed.emit(["错误指认：理智 -2"])
		write_autosave()
		return 0
	tamper_status = "identified"
	var operations := [
		{"op": "resolve", "id": "event_archive_tampered", "resolution_bbcode": "你逐条核对，找出了被篡改的那一条，并以记忆恢复了原文。"},
		{"op": "upsert", "id": "tamper_seen_through", "kind": "triggered_rule", "title": "识破档案篡改", "detail_bbcode": "被篡改的规则位于章节“%s”。" % str(plan.chapter)}]
	var candidate_state := RuleTalesGameState.new()
	var copy_error := candidate_state.replace_from_dict(state.data)
	if not copy_error.is_empty(): return -1
	var candidate_facts := facts.clone()
	var fact_result := candidate_facts.apply_operations(operations, completed_turns + 1)
	var state_result := candidate_state.apply_patch({"stats_delta": {"sanity": 4}}, false)
	if not fact_result.ok or not state_result.ok:
		tamper_status = "active"
		return -1
	state = candidate_state; facts = candidate_facts
	var changes: Array = ["识破篡改：理智 +4"]
	if fact_result.ok: facts_changed.emit()
	if state_result.ok: state_changed.emit(changes)
	tamper_changed.emit(); write_autosave()
	return 1


func resolve_pending_anomaly(player_reported_anomaly: bool) -> Dictionary:
	if pending_anomaly.is_empty() or not bool(state.data.run_mode) or state.is_terminal():
		return {"ok": false, "error": "当前没有等待判断的异常。"}
	var encounter: Dictionary = pending_anomaly.duplicate(true)
	if str(encounter.round_id) in resolved_anomaly_rounds:
		pending_anomaly = {}
		return {"ok": false, "error": "该异常已经完成判断。"}
	var correct: bool = bool(encounter.anomalous) == player_reported_anomaly
	var candidate_state := RuleTalesGameState.new()
	var copy_error := candidate_state.replace_from_dict(state.data)
	if not copy_error.is_empty():
		return {"ok": false, "error": copy_error}
	var state_result := candidate_state.apply_patch({"elapsed_minutes": 5 if correct else 15, "stats_delta": {"sanity": 3} if correct else {"sanity": -6, "stamina": -3}}, false)
	if not state_result.ok:
		return {"ok": false, "error": str(state_result.error)}
	var decision := "判定为异常并原路返回" if player_reported_anomaly else "判定为正常并继续前进"
	var detail := "%s。判断%s。%s" % [decision, "正确" if correct else "错误", str(encounter.reveal_bbcode)]
	var candidate_facts := facts.clone()
	var fact_result := candidate_facts.apply_operations([{"op": "upsert", "id": "anomaly_round_%s" % str(encounter.round_id), "kind": "triggered_rule", "title": "异常校验：%s" % str(encounter.title), "detail_bbcode": detail}], completed_turns + 1)
	if not fact_result.ok:
		return {"ok": false, "error": str(fact_result.error)}
	state = candidate_state
	facts = candidate_facts
	resolved_anomaly_rounds.append(str(encounter.round_id))
	if correct and bool(encounter.anomalous) and str(encounter.anomaly_id) not in identified_anomaly_ids:
		identified_anomaly_ids.append(str(encounter.anomaly_id))
	pending_anomaly = {}
	var consequence := "识破了观察中的真伪" if correct else "误判了观察中的真伪"
	key_choices.append({"turn": maxi(1, completed_turns), "action": "%s：%s" % [str(encounter.title), decision], "consequence": consequence, "rule_refs": []})
	while key_choices.size() > 8: key_choices.remove_at(6)
	var changes: Array = state_result.changes.duplicate(); changes.append_array(fact_result.changes)
	state_changed.emit(changes); facts_changed.emit(); write_autosave()
	return {"ok": true, "correct": correct, "result_bbcode": "[b]判断%s。[/b] %s\n[color=%s]%s[/color]" % ["正确" if correct else "错误", str(encounter.reveal_bbcode), "#a9c69f" if correct else "#d4a3a3", "理智 +3，时间推进 5 分钟。" if correct else "理智 -6，体力 -3，时间推进 15 分钟。"], "changes": changes}


func choose_route(option_id: String) -> Dictionary:
	if pending_routes.is_empty():
		return {"ok": false, "error": "当前没有待选择路线。"}
	for option in pending_routes.get("options", []):
		if str(option.get("id", "")) == option_id:
			state.data.route_node = str(option.label)
			pending_routes = {}
			state_changed.emit(["路线区域：%s" % str(option.label)])
			write_autosave()
			return {"ok": true, "option": option}
	return {"ok": false, "error": "路线选项已经失效。"}


func cancel_generation() -> void:
	if not busy: return
	_ai.cancel_active()
	var action := _active_action; var phase := _active_phase
	_active_request = 0; _active_phase = ""; _active_action = ""
	if phase == "action" and not history.is_empty() and str(history.back().role) == "user" and str(history.back().content) == action:
		history.pop_back(); history_changed.emit()
	choices = _pending_choices.duplicate(); _pending_choices.clear(); choices_changed.emit(choices)
	diagnostics.outcome = "cancelled"; diagnostics.outcome_detail = "用户中止生成；状态未改变。"
	_set_busy(false, ""); diagnostics_changed.emit(); notice.emit("本次推演已中止；状态没有改变。")


func _request_turn(phase: String, action: String) -> void:
	if busy: return
	_request_serial += 1; _active_request = _request_serial; _active_phase = phase; _active_action = action
	_set_busy(true, "正在从规则中编织初始场景……" if phase == "initial" else "正在判断行动造成的涟漪……")
	var assembly := TurnPromptAssembler.build(phase, action, rules, state, facts, history, AppSettings.recent_count, AppSettings.relevant_count)
	_pending_selection = assembly.rule_selection
	diagnostics = {
		"turn_number": completed_turns + 1, "phase": phase, "action": action,
		"mode": "offline_demo" if offline_demo else "live_api", "outcome": "pending",
		"timestamp": Time.get_datetime_string_from_system(true), "rule_selection": assembly.rule_selection,
		"history_trace": assembly.history_trace, "raw_patch": {}, "raw_response": {},
		"estimated_input_tokens": _estimate_tokens(JSON.stringify(assembly.messages)), "max_output_tokens": AppSettings.max_tokens
	}
	diagnostics_changed.emit()
	if offline_demo:
		var serial := _active_request
		await get_tree().create_timer(0.42).timeout
		if busy and _active_request == serial:
			_commit_turn(_make_offline_turn(phase, action), false)
		return
	var error := _ai.send_chat(_active_request, AppSettings.chat_url(), AppSettings.api_key, AppSettings.model, assembly.messages, AppSettings.temperature, AppSettings.max_tokens)
	if error != OK:
		_fail_turn("无法创建 AI 请求。", error_string(error))


func _on_ai_completed(request_id: int, content: String, raw_response: Dictionary) -> void:
	if request_id != _active_request or not busy: return
	diagnostics.raw_response = raw_response
	var parsed := _parse_turn_envelope(content)
	if not parsed.ok:
		_fail_turn("AI 返回的回合格式无效。", str(parsed.error))
		return
	_commit_turn(parsed.turn, true)


func _on_ai_failed(request_id: int, message: String, detail: String) -> void:
	if request_id == _active_request and busy: _fail_turn(message, detail)


func _commit_turn(turn: Dictionary, from_live_api: bool) -> void:
	if not busy or _active_request == 0: return
	var previous_day := int(state.data.day)
	var selected_ids: Array = _pending_selection.get("trace", {}).get("selected_ids", [])
	var guard_error := ClientRuleGuard.validate(_active_action, str(turn.narration_bbcode), turn.patch, turn.memory_ops, turn.rule_refs, selected_ids, _active_phase)
	if not guard_error.is_empty():
		_fail_turn("客户端规则裁判拒绝了状态修改。", guard_error)
		return
	var candidate_state := RuleTalesGameState.new()
	var state_error := candidate_state.replace_from_dict(state.data)
	if not state_error.is_empty():
		_fail_turn("当前状态无法复制。", state_error); return
	var state_result := candidate_state.apply_patch(turn.patch, _active_phase != "initial")
	if not state_result.ok:
		_fail_turn("状态补丁未通过校验。", str(state_result.error)); return
	var candidate_guard_error := ClientRuleGuard.validate_candidate(rules, state, candidate_state)
	if not candidate_guard_error.is_empty():
		_fail_turn("本回合与规则档案发生明确冲突，已拒绝应用。", candidate_guard_error); return
	if RunSystemsScript.is_timeout(candidate_state):
		candidate_state.data.ending = RunSystemsScript.timeout_ending()
		state_result.changes.append("期限耗尽：自动进入失踪结局")
	var candidate_facts := facts.clone()
	var fact_result := candidate_facts.apply_operations(turn.memory_ops, completed_turns + 1)
	if not fact_result.ok:
		_fail_turn("事实记忆补丁未通过校验。", str(fact_result.error)); return
	var committed_phase := _active_phase; var committed_action := _active_action
	state = candidate_state; facts = candidate_facts
	for rule_id in turn.rule_refs:
		if str(rule_id) not in discovered_rule_ids: discovered_rule_ids.append(str(rule_id))
	history.append({"role": "assistant", "content": str(turn.narration_bbcode), "id": "a-%d" % (history.size() + 1)})
	if state.is_terminal():
		choices.clear()
	else:
		choices = _normalized_choices(turn.choices)
	completed_turns += 1
	var all_changes: Array = state_result.changes.duplicate(); all_changes.append_array(fact_result.changes)
	var key_moment: bool = committed_phase == "initial" or not turn.rule_refs.is_empty() or not turn.memory_ops.is_empty() or state.is_terminal()
	if key_moment and committed_phase == "action":
		key_choices.append({"turn": completed_turns, "action": committed_action.left(500), "consequence": "；".join(all_changes.slice(0, 3)), "rule_refs": turn.rule_refs.duplicate()})
		while key_choices.size() > 8: key_choices.remove_at(6)
	diagnostics.raw_patch = turn.patch.duplicate(true); diagnostics.raw_memory_ops = turn.memory_ops.duplicate(true); diagnostics.raw_rule_refs = turn.rule_refs.duplicate()
	diagnostics.outcome = "accepted"; diagnostics.outcome_detail = "状态补丁、事实记忆与规则引用均已通过。"
	_active_request = 0; _active_phase = ""; _active_action = ""; _pending_choices.clear(); _pending_selection = {}
	_set_busy(false, "")
	history_changed.emit(); state_changed.emit(all_changes); facts_changed.emit(); choices_changed.emit(choices); diagnostics_changed.emit()
	_append_timeline(committed_phase, committed_action, key_moment)
	write_autosave()
	if committed_phase == "action" and bool(state.data.run_mode) and int(state.data.day) > previous_day and not state.is_terminal():
		_handle_day_rollover(previous_day)
	if state.is_terminal():
		_award_meta_if_needed()
		ending_reached.emit()
	if from_live_api: notice.emit("AI 回合已通过客户端校验并提交。")


func _fail_turn(message: String, detail: String) -> void:
	var phase := _active_phase; var action := _active_action
	_active_request = 0; _active_phase = ""; _active_action = ""; _pending_selection = {}
	if phase == "action" and not history.is_empty() and str(history.back().role) == "user" and str(history.back().content) == action:
		history.pop_back(); history_changed.emit()
	if phase == "action": choices = _pending_choices.duplicate(); choices_changed.emit(choices)
	_pending_choices.clear(); diagnostics.outcome = "rejected"; diagnostics.outcome_detail = "%s %s" % [message, detail]
	_set_busy(false, ""); diagnostics_changed.emit(); error_occurred.emit(message, detail)


func _make_offline_turn(phase: String, action: String) -> Dictionary:
	if phase == "initial":
		var first_title := "未命名规则" if rules.chapters.is_empty() else str(rules.chapters[0].title)
		var narration := str(_offline_flow.get("initial", {}).get("narration", "")).replace("{chapter}", first_title).replace("{chapter_count}", str(rules.chapters.size()))
		return {"narration_bbcode": narration, "choices": _offline_flow.initial.choices.duplicate(), "rule_refs": [], "memory_ops": [], "patch": {
			"weather_set": "细雨", "inventory_ops": [
				{"op": "add", "id": "sealed_water", "name": "密封饮用水", "description_bbcode": "[color=#9fb7bb]标签被水汽泡皱，瓶盖仍然完整。[/color]", "quantity": 2},
				{"op": "add", "id": "visitor_card", "name": "褪色访客证", "description_bbcode": "[i]背面用铅笔写着：不要替别人刷卡。[/i]", "quantity": 1}],
			"status_bbcode_set": "[color=#c8bca9]你衣角微湿，呼吸平稳。未知带来的不安尚且可以压住。[/color]"}}
	var stage := clampi(completed_turns - 1, 0, 5)
	var examines := _contains_any(action, ["影子", "镜", "反光", "回头", "确认", "观察", "注视", "查看"])
	var checks_rules := _contains_any(action, ["规则", "档案", "守则", "翻开", "核对", "章节", "记录"])
	var waits := _contains_any(action, ["等待", "停留", "原地", "不动", "倾听"])
	var uses_item := _contains_any(action, ["喝", "使用", "拿出", "取出", "访客证", "水", "物品"])
	var unsettling := examines or _contains_any(action, ["黑", "声音", "追", "血", "尸", "敲门", "广播"])
	var response := "你的行动打破了原有的平衡。远处传来门锁回弹的轻响，一条此前被黑暗遮住的路径显出了边界。 "
	if checks_rules: response = "你没有急着相信记忆，而是把纸页举到灯下逐字比对。其中一行的墨色比刚才更深，像是有人在纸背重新描过。 "
	elif examines: response = "你压住本能，没有立刻移开视线。那处异常因此露出破绽：它能复制你的轮廓，却总比你的呼吸慢半拍。 "
	elif uses_item: response = "物品离开背包的一刻，附近的感应灯依次亮起。这里似乎会记录每一次取用，也会记录取用者的名字。 "
	elif waits: response = "你让自己彻底静止。大约半分钟后，仍有另一串脚步继续向前，最终停在一扇原本不存在的门前。 "
	var beat: Dictionary = _offline_flow.beats[stage]
	var narration := "[color=#8fa5b2]你的行动[/color]　[color=#d7bd82][b]%s[/b][/color]\n\n%s\n\n%s\n\n[quote]调查进度：%d / 6。离线体验会继续推进事件、地点与出口线索。[/quote]" % [action, response, beat.narration, stage + 1]
	var patch := {"elapsed_minutes": clampi(action.length() / 4 + 2, 2, 18), "stats_delta": {"stamina": -1}, "status_bbcode_set": "[color=#c69b9b]你能维持镇定，但余光开始反复确认同一个角落。[/color]" if unsettling else "[color=#c8bca9]你保持警觉，呼吸略快，仍能清楚判断方向。[/color]"}
	if unsettling: patch.stats_delta.sanity = -2
	var water := state.inventory_item("sealed_water")
	var requested := _water_count(action)
	if not water.is_empty() and requested > 0: patch.inventory_ops = [{"op": "remove", "id": "sealed_water", "quantity": mini(requested, int(water.quantity))}]
	var memory_ops: Array = []
	if _contains_any(action, ["进入", "前往", "抵达", "探索", "查看", "调查", "推门", "绕到", "穿过", "上楼", "下楼", "离开", "走向", "沿着"]):
		var number: int = state.data.map.nodes.size(); var node_id := "trace_%d" % (number + 1)
		var locations: Array = _offline_flow.locations
		var label := str(locations[number]) if number < locations.size() else "档案外区域 %d" % (number + 1)
		var map_patch := {"discover": [{"id": node_id, "label": label, "symbol": "O" if number == 0 else "o", "x": number % 9, "y": int(number / 9)}], "connect": [], "current": node_id}
		if not str(state.data.map.current).is_empty(): map_patch.connect.append({"from": state.data.map.current, "to": node_id})
		patch.map = map_patch
		memory_ops.append({"op": "upsert", "id": "location_%s" % node_id, "kind": "location", "title": label, "detail_bbcode": "玩家在第 %d 回合亲自探索到此处；地图节点为 %s。" % [completed_turns + 1, node_id]})
	if stage >= 5 and _contains_any(action, ["逃出", "逃离", "越过后门", "离开校园", "离开公寓", "离开医院", "离开车站"]):
		patch.ending = {"type": "escape", "title": "门外没有广播", "summary_bbcode": "[color=#d8bd78][b]你越过了规则覆盖的边界。[/b][/color]\n身后的灯一盏盏熄灭，却没有任何脚步追出来。你活着离开了，至于带走了什么，档案仍拒绝作答。"}
		var selected: Array = _pending_selection.get("trace", {}).get("selected_ids", [])
		return {"narration_bbcode": narration, "choices": [], "rule_refs": [] if selected.is_empty() else [selected[0]], "memory_ops": memory_ops, "patch": patch}
	return {"narration_bbcode": narration, "choices": beat.choices.duplicate(), "rule_refs": [], "memory_ops": memory_ops, "patch": patch}


func _parse_turn_envelope(content: String) -> Dictionary:
	var cleaned := content.strip_edges()
	if cleaned.begins_with("```"):
		cleaned = cleaned.substr(cleaned.find("\n") + 1)
		if cleaned.ends_with("```"): cleaned = cleaned.left(cleaned.length() - 3).strip_edges()
	var parser := JSON.new(); var error := parser.parse(cleaned)
	if error != OK or not parser.data is Dictionary:
		return {"ok": false, "error": "JSON 第 %d 行：%s" % [parser.get_error_line(), parser.get_error_message()]}
	var raw: Dictionary = parser.data
	var narration := str(raw.get("narration_bbcode", "")).strip_edges()
	if narration.is_empty() or narration.length() > 120000: return {"ok": false, "error": "叙事正文为空或过长。"}
	var parsed_choices := _normalized_choices(raw.get("choices", []))
	var patch: Dictionary = raw.get("patch", {}) if raw.get("patch", {}) is Dictionary else {}
	var memory_ops: Array = raw.get("memory_ops", []) if raw.get("memory_ops", []) is Array else []
	var refs: Array[String] = []
	if raw.get("rule_refs", []) is Array:
		for value in raw.rule_refs:
			var rule_id := str(value).strip_edges()
			if not rule_id.is_empty() and rule_id not in refs: refs.append(rule_id)
	return {"ok": true, "turn": {"narration_bbcode": narration, "choices": parsed_choices, "patch": patch, "memory_ops": memory_ops, "rule_refs": refs}}


func _normalized_choices(raw: Variant) -> Array[String]:
	var result: Array[String] = []
	if raw is Array:
		for value in raw:
			var choice := str(value).strip_edges()
			if not choice.is_empty() and choice.length() <= 500 and choice not in result: result.append(choice)
			if result.size() >= 3: break
	return result


func _append_timeline(phase: String, action: String, key_moment: bool) -> void:
	var snapshot := to_dict(false)
	snapshot.erase("timeline")
	snapshot.erase("rules_text")
	snapshot.erase("rule_source_path")
	if snapshot.history.size() > 20: snapshot.history = snapshot.history.slice(snapshot.history.size() - 20)
	snapshot.history_windowed = true
	var label := "档案启封" if phase == "initial" else ("关键选择：%s" % action if key_moment else "行动：%s" % action)
	timeline.append({"id": "turn_%d_%d" % [completed_turns, Time.get_ticks_msec()], "turn": completed_turns, "label": label.left(500), "timestamp": Time.get_datetime_string_from_system(true), "key_moment": key_moment or state.is_terminal(), "snapshot": snapshot})
	while timeline.size() > 24: timeline.pop_front()


func investigation_score() -> int:
	if not state.is_terminal(): return 0
	var score: int = int({"special": 35, "escape": 30, "survival": 25, "missing": 5, "contamination": 0}.get(str(state.data.ending.type), 0))
	score += int((int(state.data.stats.health) + int(state.data.stats.sanity) + int(state.data.stats.stamina)) / 3.0 * 15.0 / 100.0)
	var total_rules := RuleFragmentIndex.new(); total_rules.rebuild(rules)
	if total_rules.fragments.size() > 0: score += mini(35, int(discovered_rule_ids.size() * 35.0 / total_rules.fragments.size()))
	var clue_count := 0
	for fact in facts.records:
		if str(fact.kind) in ["clue", "triggered_rule"]: clue_count += 1
	score += mini(15, clue_count * 3)
	return clampi(score, 0, 100)


func investigation_rating() -> String:
	var score := investigation_score()
	if score >= 85: return "S"
	if score >= 70: return "A"
	if score >= 55: return "B"
	if score >= 40: return "C"
	return "D"


func to_dict(include_timeline: bool = true) -> Dictionary:
	var compatible_run_config := run_config.duplicate(true)
	compatible_run_config.theme = str(run_config.get("theme_id", run_config.get("theme", "")))
	var tamper_status_code := ["pending", "active", "identified"].find(tamper_status)
	var document := {"save_schema": RuleTalesSaveService.SAVE_SCHEMA, "story_title": story_title, "archive_id": archive_id, "rule_source_path": rule_source_path, "offline_demo": offline_demo, "rules_text": rules.joined_text(), "state": state.data.duplicate(true), "facts": facts.records.duplicate(true), "history": history.duplicate(true), "choices": choices.duplicate(), "discovered_rules": discovered_rule_ids.duplicate(), "key_choices": key_choices.duplicate(true), "completed_turns": completed_turns,
		"run_config": compatible_run_config, "forge_meta": forge_meta.duplicate(true), "rule_pack": rule_pack.duplicate(true),
		"tamper_plans": tamper_plans.duplicate(true), "tamper_status": maxi(0, tamper_status_code), "tamper_status_name": tamper_status, "tamper_trigger_day": tamper_trigger_day,
		"resolved_anomaly_rounds": resolved_anomaly_rounds.duplicate(), "identified_anomalies": identified_anomaly_ids.duplicate(), "identified_anomaly_ids": identified_anomaly_ids.duplicate(),
		"pending_anomaly": pending_anomaly.duplicate(true), "pending_routes": pending_routes.duplicate(true), "meta_awarded": meta_rewarded, "meta_rewarded": meta_rewarded}
	document.timeline = timeline.duplicate(true) if include_timeline else []
	return document


func load_document(document: Dictionary) -> Dictionary:
	var raw_save_schema: Variant = document.get("save_schema", null)
	if not _is_json_integer(raw_save_schema) or int(raw_save_schema) != RuleTalesSaveService.SAVE_SCHEMA:
		return {"ok": false, "error": "不支持的存档版本。"}
	var loaded_rules := RuleDocumentData.from_text(str(document.get("rules_text", "")))
	if loaded_rules.is_empty(): return {"ok": false, "error": "存档缺少规则内容。"}
	if not document.get("state", {}) is Dictionary: return {"ok": false, "error": "存档缺少有效状态。"}
	var loaded_state := RuleTalesGameState.new(); var error := loaded_state.replace_from_dict(document.state)
	if not error.is_empty(): return {"ok": false, "error": "状态损坏：%s" % error}
	var loaded_facts := StructuredFactStore.new()
	var fact_load := loaded_facts.load_records(document.get("facts", []))
	if not bool(fact_load.ok): return {"ok": false, "error": "事实记忆损坏：%s" % str(fact_load.error)}
	var history_load := _normalized_saved_history(document.get("history", null))
	if not bool(history_load.ok): return {"ok": false, "error": str(history_load.error)}
	var key_choice_load := _normalized_saved_key_choices(document.get("key_choices", []))
	if not bool(key_choice_load.ok): return {"ok": false, "error": str(key_choice_load.error)}
	var timeline_load := _normalized_saved_timeline(document.get("timeline", []))
	if not bool(timeline_load.ok): return {"ok": false, "error": str(timeline_load.error)}
	if not document.get("choices", null) is Array: return {"ok": false, "error": "存档的选项格式错误。"}
	var loaded_discovered: Array[String] = []
	var raw_discovered: Variant = document.get("discovered_rules", [])
	if not raw_discovered is Array: return {"ok": false, "error": "存档的已发现规则格式错误。"}
	for value in raw_discovered:
		if value is String and not str(value).is_empty() and str(value).length() <= 64 and str(value) not in loaded_discovered:
			loaded_discovered.append(str(value))
	var raw_completed_turns: Variant = document.get("completed_turns", 0)
	if not _is_json_integer(raw_completed_turns) or int(raw_completed_turns) < 0:
		return {"ok": false, "error": "存档的完成回合数无效。"}
	reset_session(); rules = loaded_rules; state = loaded_state; facts = loaded_facts
	story_title = str(document.get("story_title", "未命名规则档案")); rule_source_path = str(document.get("rule_source_path", "")); offline_demo = bool(document.get("offline_demo", false)); archive_id = str(document.get("archive_id", "night_archive" if offline_demo else "custom"))
	history = _dictionary_array(history_load.get("value", []))
	choices = _normalized_choices(document.choices); discovered_rule_ids = loaded_discovered
	key_choices = _dictionary_array(key_choice_load.get("value", []))
	timeline = _dictionary_array(timeline_load.get("value", []))
	completed_turns = int(raw_completed_turns)
	var raw_run: Dictionary = document.get("run_config", {}) if document.get("run_config", {}) is Dictionary else {}
	run_config = {"enabled": bool(raw_run.get("enabled", false)), "seed": int(raw_run.get("seed", 0)) & 0xFFFFFFFF, "theme_id": str(raw_run.get("theme_id", raw_run.get("theme", ""))), "days_limit": maxi(0, int(raw_run.get("days_limit", 0)))}
	forge_meta = document.get("forge_meta", {}).duplicate(true) if document.get("forge_meta", {}) is Dictionary else {}
	rule_pack = document.get("rule_pack", {}).duplicate(true) if document.get("rule_pack", {}) is Dictionary else {}
	if rule_pack.is_empty() and bool(run_config.enabled): rule_pack = _load_default_rule_pack()
	tamper_plans = []
	for value in document.get("tamper_plans", []):
		if value is Dictionary: tamper_plans.append(value.duplicate(true))
	var raw_tamper_status: Variant = document.get("tamper_status", "pending")
	tamper_status = ["pending", "active", "identified"][clampi(int(raw_tamper_status), 0, 2)] if raw_tamper_status is int or raw_tamper_status is float else str(raw_tamper_status)
	if tamper_status not in ["pending", "active", "identified"]: tamper_status = "pending"
	tamper_trigger_day = maxi(0, int(document.get("tamper_trigger_day", 0)))
	resolved_anomaly_rounds = []
	for value in document.get("resolved_anomaly_rounds", []): resolved_anomaly_rounds.append(str(value))
	identified_anomaly_ids = []
	for value in document.get("identified_anomaly_ids", document.get("identified_anomalies", [])): identified_anomaly_ids.append(str(value))
	pending_anomaly = document.get("pending_anomaly", {}).duplicate(true) if document.get("pending_anomaly", {}) is Dictionary else {}
	pending_routes = document.get("pending_routes", {}).duplicate(true) if document.get("pending_routes", {}) is Dictionary else {}
	meta_rewarded = bool(document.get("meta_rewarded", document.get("meta_awarded", false)))
	_emit_all(); return {"ok": true, "error": ""}


func save_manual(slot: int) -> Dictionary:
	return RuleTalesSaveService.write_document(RuleTalesSaveService.manual_path(slot), to_dict())


func load_manual(slot: int) -> Dictionary:
	var read := RuleTalesSaveService.read_document(RuleTalesSaveService.manual_path(slot))
	return load_document(read.document) if read.ok else read


func write_autosave() -> Dictionary:
	if rules.is_empty(): return {"ok": true, "error": ""}
	var result := RuleTalesSaveService.write_next_autosave(to_dict())
	if result.ok:
		autosave_written.emit(Time.get_time_string_from_system().left(5), str(result.path))
		if result.has("warning"):
			error_occurred.emit("进度已保存，但自动轮换索引未能更新。", str(result.warning))
	else: error_occurred.emit("自动存档失败。", str(result.error))
	return result


func restore_autosave() -> bool:
	for path in RuleTalesSaveService.autosaves_newest_first():
		var read := RuleTalesSaveService.read_document(path)
		if read.ok and load_document(read.document).ok: return true
	return false


func restart_from_checkpoint(checkpoint_id: String) -> Dictionary:
	for index in range(timeline.size()):
		var checkpoint: Dictionary = timeline[index]
		if str(checkpoint.id) == checkpoint_id and bool(checkpoint.key_moment):
			var kept := timeline.slice(0, index + 1)
			var snapshot: Dictionary = checkpoint.snapshot.duplicate(true)
			if not snapshot.has("save_schema"): snapshot.save_schema = RuleTalesSaveService.SAVE_SCHEMA
			if not snapshot.has("rules_text"): snapshot.rules_text = rules.joined_text()
			if not snapshot.has("story_title"): snapshot.story_title = story_title
			if not snapshot.has("rule_source_path"): snapshot.rule_source_path = rule_source_path
			var result := load_document(snapshot)
			if result.ok: timeline = kept; write_autosave()
			return result
	return {"ok": false, "error": "只能从仍在时间线中的关键节点重新开始。"}


func _handle_day_rollover(finished_day: int) -> void:
	day_rolled.emit(int(state.data.day))
	_maybe_trigger_tamper()
	var anomalies: Array = rule_pack.get("anomalies", []) if rule_pack.get("anomalies", []) is Array else []
	var encounter: Dictionary = RunSystemsScript.anomaly_for_night(int(run_config.get("seed", 0)), finished_day, anomalies)
	if not encounter.is_empty() and str(encounter.round_id) not in resolved_anomaly_rounds:
		pending_anomaly = encounter
		anomaly_pending.emit(pending_anomaly)
	var locations: Array = rule_pack.get("locations", []) if rule_pack.get("locations", []) is Array else []
	pending_routes = RunSystemsScript.route_choices(int(run_config.get("seed", 0)), locations, finished_day, int(state.data.days_limit))
	if not pending_routes.get("options", []).is_empty():
		routes_pending.emit(pending_routes)


func _maybe_trigger_tamper() -> void:
	if not bool(state.data.run_mode) or tamper_status != "pending" or tamper_plans.is_empty() or tamper_trigger_day <= 0 or int(state.data.day) < tamper_trigger_day or state.is_terminal():
		return
	tamper_status = "active"
	var result := facts.apply_operations([{"op": "upsert", "id": "event_archive_tampered", "kind": "open_event", "title": "档案被翻动过", "detail_bbcode": "整理档案时发现某一页的内容与记忆不符；需要逐条核对手中的规则。"}], completed_turns + 1)
	if result.ok: facts_changed.emit()
	tamper_changed.emit(); rules_changed.emit(); notice.emit("睡前整理档案时，你觉得某一页的折角不对。")


func _award_meta_if_needed() -> int:
	if meta_rewarded or not bool(state.data.run_mode) or not state.is_terminal():
		return 0
	var index := RuleFragmentIndex.new(); index.rebuild(rules)
	var ratio := discovered_rule_ids.size() / float(maxi(1, index.fragments.size()))
	var points: int = RunSystemsScript.award_for_run(str(state.data.ending.type), investigation_rating(), ratio)
	var result: Dictionary = MetaProfileScript.record_run(str(run_config.get("theme_id", "custom")), str(state.data.ending.type), investigation_score(), points, identified_anomaly_ids)
	if not bool(result.ok):
		error_occurred.emit("无法保存认知点记录。", str(result.error))
		return 0
	meta_rewarded = true
	meta_awarded.emit(points, result.profile)
	return points


func _load_offline_flow() -> void:
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(OFFLINE_FLOW_PATH)) == OK and parser.data is Dictionary: _offline_flow = parser.data


func _load_default_rule_pack() -> Dictionary:
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(RuleForgeScript.DEFAULT_PACK_PATH)) == OK and parser.data is Dictionary:
		return parser.data
	return {}


func _emit_all() -> void:
	rules_changed.emit(); state_changed.emit([]); history_changed.emit(); facts_changed.emit(); choices_changed.emit(choices); diagnostics_changed.emit()


func _set_busy(value: bool, message: String) -> void:
	busy = value; busy_changed.emit(value, message)


func _contains_any(text: String, needles: Array) -> bool:
	for needle in needles:
		if text.contains(str(needle)): return true
	return false


func _normalized_saved_history(raw: Variant) -> Dictionary:
	if not raw is Array:
		return {"ok": false, "error": "存档的历史格式错误。", "value": []}
	var source: Array = raw
	if source.size() > 20000:
		return {"ok": false, "error": "存档历史过大。", "value": []}
	var output: Array[Dictionary] = []
	for index in source.size():
		if not source[index] is Dictionary:
			return {"ok": false, "error": "存档历史第 %d 项不是对象。" % (index + 1), "value": []}
		var entry: Dictionary = source[index]
		if not entry.get("role") is String or not entry.get("content") is String:
			return {"ok": false, "error": "存档历史第 %d 项缺少有效文本。" % (index + 1), "value": []}
		var role := str(entry.get("role", ""))
		var content := str(entry.get("content", ""))
		if role not in ["user", "assistant"] or content.is_empty():
			return {"ok": false, "error": "存档包含无效对话记录。", "value": []}
		if entry.has("id") and not entry.get("id") is String:
			return {"ok": false, "error": "存档历史第 %d 项的 id 不是字符串。" % (index + 1), "value": []}
		output.append({"role": role, "content": content, "id": str(entry.get("id", ""))})
	return {"ok": true, "error": "", "value": output}


func _normalized_saved_key_choices(raw: Variant) -> Dictionary:
	if not raw is Array:
		return {"ok": false, "error": "存档的关键选择格式错误。", "value": []}
	var source: Array = raw
	if source.size() > 8:
		return {"ok": false, "error": "存档的关键选择数量异常。", "value": []}
	var output: Array[Dictionary] = []
	for index in source.size():
		if not source[index] is Dictionary:
			return {"ok": false, "error": "存档包含无效的关键选择。", "value": []}
		var entry: Dictionary = source[index]
		var turn_value: Variant = entry.get("turn", null)
		if not _is_json_integer(turn_value) or int(turn_value) <= 0 or not entry.get("action") is String:
			return {"ok": false, "error": "存档包含无效的关键选择。", "value": []}
		var action := str(entry.get("action", "")).strip_edges()
		var consequence_value: Variant = entry.get("consequence", "")
		if not consequence_value is String:
			return {"ok": false, "error": "存档包含无效的关键选择后果。", "value": []}
		var consequence := str(consequence_value).strip_edges()
		var raw_refs: Variant = entry.get("rule_refs", [])
		if not raw_refs is Array or raw_refs.size() > 32 or action.is_empty() or action.length() > 4000 or consequence.length() > 4000:
			return {"ok": false, "error": "存档包含无效的关键选择。", "value": []}
		var refs: Array[String] = []
		for ref in raw_refs:
			if ref is String:
				refs.append(str(ref))
		output.append({"turn": int(turn_value), "action": action, "consequence": consequence, "rule_refs": refs})
	return {"ok": true, "error": "", "value": output}


func _normalized_saved_timeline(raw: Variant) -> Dictionary:
	if not raw is Array:
		return {"ok": false, "error": "存档的时间线格式错误。", "value": []}
	var source: Array = raw
	if source.size() > 24:
		return {"ok": false, "error": "存档的时间线过长。", "value": []}
	var output: Array[Dictionary] = []
	var known_ids: Dictionary = {}
	for index in source.size():
		if not source[index] is Dictionary:
			return {"ok": false, "error": "存档包含无效时间线节点。", "value": []}
		var entry: Dictionary = source[index]
		var checkpoint_id := str(entry.get("id", "")) if entry.get("id") is String else ""
		var turn_value: Variant = entry.get("turn", null)
		var label := str(entry.get("label", "")) if entry.get("label") is String else ""
		var timestamp := str(entry.get("timestamp", "")) if entry.get("timestamp") is String else ""
		var snapshot: Variant = entry.get("snapshot", null)
		if checkpoint_id.is_empty() or known_ids.has(checkpoint_id) or not _is_json_integer(turn_value) or int(turn_value) <= 0 or label.is_empty() or label.length() > 500 or not entry.get("key_moment") is bool or not snapshot is Dictionary or snapshot.is_empty():
			return {"ok": false, "error": "存档包含无效时间线节点。", "value": []}
		known_ids[checkpoint_id] = true
		output.append({"id": checkpoint_id, "turn": int(turn_value), "label": label, "timestamp": timestamp, "key_moment": bool(entry.get("key_moment", false)), "snapshot": snapshot.duplicate(true)})
	return {"ok": true, "error": "", "value": output}


func _is_json_integer(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		return is_finite(float(value)) and floor(float(value)) == float(value)
	return false


func _dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is Array:
		for item in value:
			if item is Dictionary:
				result.append(item.duplicate(true))
	return result


func _water_count(action: String) -> int:
	if not action.contains("喝") or not action.contains("水"): return 0
	if action.contains("两") or action.contains("2"): return 2
	return 1


func _estimate_tokens(text: String) -> int:
	return maxi(1, ceili(text.length() / 2.4))


func _normalized_tamper_text(text: String) -> String:
	return SafeBBCode.plain_text(text).replace(" ", "").replace("　", "").replace("\n", "").strip_edges()
