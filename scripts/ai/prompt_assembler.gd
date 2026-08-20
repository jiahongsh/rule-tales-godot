class_name TurnPromptAssembler
extends RefCounted


static func build(phase: String, action: String, rules: RuleDocumentData, state: RuleTalesGameState, facts: StructuredFactStore, history: Array, recent_count: int, relevant_count: int) -> Dictionary:
	var rule_index := RuleFragmentIndex.new()
	rule_index.rebuild(rules)
	var query := _rule_query(action, state, facts)
	var rule_selection := rule_index.select(query)
	var history_trace := MemorySearch.select(history, query, recent_count, relevant_count)
	var messages: Array[Dictionary] = []
	messages.append({"role": "system", "content": _system_prompt(phase, rule_index.prompt_text(rule_selection))})
	messages.append({"role": "system", "content": "客户端权威状态（只能通过 patch 候选修改）：\n%s" % JSON.stringify(state.data)})
	messages.append({"role": "system", "content": "结构化长期事实：\n%s" % JSON.stringify(facts.prompt_snapshot())})
	var included := {}
	for index in history_trace.relevant_indices:
		if index >= 0 and index < history.size():
			included[index] = true
			messages.append({"role": str(history[index].role), "content": "[可能过时的相关历史]\n%s" % str(history[index].content)})
	for index in history_trace.recent_indices:
		if index >= 0 and index < history.size() and not included.has(index):
			messages.append({"role": str(history[index].role), "content": str(history[index].content)})
	if phase == "initial":
		messages.append({"role": "user", "content": "根据已检索规则生成初始场景和三个可执行选项。地图初始必须为空。"})
	elif history.is_empty() or str(history.back().get("content", "")) != action:
		messages.append({"role": "user", "content": action})
	return {"messages": messages, "rule_selection": rule_selection, "history_trace": history_trace, "query": query}


static func _system_prompt(phase: String, selected_rules: String) -> String:
	return """你是规则怪谈调查跑团的叙事核心。保持克制、具体、可推理的中文恐怖氛围，不替玩家行动。
本回合只允许使用下列检索规则；rule_refs 只能填写其中存在的 ID：
%s

只输出一个 JSON 对象，不要 Markdown 围栏：
{
  "narration_bbcode": "叙事，可用安全 BBCode",
  "choices": ["三个不同取向的行动"],
  "rule_refs": ["实际采用的规则ID"],
  "memory_ops": [
    {"op":"upsert","id":"稳定ID","kind":"clue|character|location|triggered_rule|open_event","title":"标题","detail_bbcode":"详情"},
    {"op":"resolve","id":"已有的 open_event ID","resolution_bbcode":"如何完成该事件"}
  ],
  "patch": {
    "elapsed_minutes": 0,
    "weather_set": "可选",
    "stats_delta": {"health":0,"sanity":0,"stamina":0},
    "inventory_ops": [{"op":"add|remove","id":"id","name":"名称","description_bbcode":"描述","quantity":1}],
    "status_bbcode_set": "状态句",
    "map": {"discover":[],"connect":[],"current":""},
    "ending": {"type":"survival|escape|missing|contamination|special","title":"标题","summary_bbcode":"总结"}
  }
}
memory_ops 每回合最多 8 项。upsert 只能使用 op、id、kind、title、detail_bbcode；resolve 只能用于已有 open_event，并且只能使用 op、id、resolution_bbcode。缺失字段表示不变。初始回合不得发现地图；行动回合才可根据真实探索增加图节点。状态、物品、结局都必须有本轮叙事依据。结局必须引用本轮检索规则。phase=%s""" % [selected_rules, phase]


static func _rule_query(action: String, state: RuleTalesGameState, facts: StructuredFactStore) -> String:
	var current_label := ""
	var current_id := str(state.data.map.get("current", ""))
	for node in state.data.map.nodes:
		if str(node.id) == current_id: current_label = str(node.label); break
	var active_facts: Array[String] = []
	for fact in facts.records:
		if str(fact.status) == "active": active_facts.append("%s %s" % [fact.title, SafeBBCode.plain_text(str(fact.detail_bbcode))])
	return "%s 天气%s 地点%s 状态%s %s" % [action, state.data.weather, current_label, SafeBBCode.plain_text(str(state.data.status_bbcode)), " ".join(active_facts.slice(0, 12))]
