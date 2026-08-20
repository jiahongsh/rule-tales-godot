class_name ClientRuleGuard
extends RefCounted


static func validate(action: String, narration: String, patch: Dictionary, memory_ops: Array, rule_refs: Array, selected_ids: Array, phase: String) -> String:
	var allowed := {}
	for rule_id in selected_ids: allowed[str(rule_id)] = true
	for rule_id in rule_refs:
		if not allowed.has(str(rule_id)):
			return "AI 引用了本回合未检索的规则：%s" % str(rule_id)
	if patch.has("ending") and rule_refs.is_empty():
		return "结局必须引用本回合实际检索到的规则。"
	for operation in memory_ops:
		if operation is Dictionary and str(operation.get("kind", "")) == "triggered_rule" and rule_refs.is_empty():
			return "没有规则引用时不能登记已触发规则。"
	var evidence := "%s %s" % [action, SafeBBCode.plain_text(narration)]
	if phase != "initial" and patch.has("inventory_ops"):
		for operation in patch.inventory_ops:
			if not operation is Dictionary: continue
			var name := str(operation.get("name", operation.get("id", "")))
			if not name.is_empty() and not _shares_object_term(name, evidence):
				return "背包变化缺少行动或叙事依据。"
	if phase == "initial" and patch.has("map"):
		return "初始场景不得生成地图。"
	if patch.has("map") and not _contains_any(evidence, ["进入", "前往", "抵达", "探索", "调查", "推门", "绕到", "穿过", "上楼", "下楼", "离开", "走向", "沿着"]):
		return "地图发现缺少明确探索依据。"
	return ""


static func validate_candidate(rules: RuleDocumentData, before: RuleTalesGameState, after: RuleTalesGameState) -> String:
	var rule_text := SafeBBCode.plain_text(rules.joined_text())
	var patterns := [
		{"source": "(健康|生命|理智|精神|体力|耐力)(?:值)?(?:必须|应当|始终|永远)?(?:保持在|保持|固定为|恒定为|等于)\\s*([0-9]{1,3})", "relation": "fixed"},
		{"source": "(健康|生命|理智|精神|体力|耐力)(?:值)?(?:不得|不能|不可)(?:低于|少于)\\s*([0-9]{1,3})", "relation": "minimum"},
		{"source": "(健康|生命|理智|精神|体力|耐力)(?:值)?(?:不得|不能|不可)(?:高于|超过)\\s*([0-9]{1,3})", "relation": "maximum"}]
	for definition in patterns:
		var regex := RegEx.new(); regex.compile(str(definition.source))
		for found in regex.search_all(rule_text):
			var stat_id := _stat_id(found.get_string(1))
			var expected := int(found.get_string(2)); var actual := int(after.data.stats.get(stat_id, -1))
			var valid := actual == expected if str(definition.relation) == "fixed" else (actual >= expected if str(definition.relation) == "minimum" else actual <= expected)
			if not valid:
				return "状态 %s=%d 与明确规则“%s”冲突。" % [stat_id, actual, found.get_string(0)]
	var forbidden := RegEx.new(); forbidden.compile("(?:禁止|不得|严禁|不允许|不能|不可)(?:携带|带走|拿走|拾取|获得|持有)\\s*([^，。；\\n]{1,18})")
	for found in forbidden.search_all(rule_text):
		var term := _clean_forbidden_term(found.get_string(1))
		if term.is_empty(): continue
		for item in after.data.inventory:
			var previous := before.inventory_item(str(item.id)); var old_quantity := 0 if previous.is_empty() else int(previous.quantity)
			if int(item.quantity) <= old_quantity: continue
			var name := SafeBBCode.plain_text(str(item.name))
			if name.contains(term) or term.contains(name):
				return "新增物品“%s”与明确规则“%s”冲突。" % [name, found.get_string(0)]
	return ""


static func _contains_any(text: String, needles: Array) -> bool:
	for needle in needles:
		if text.contains(str(needle)): return true
	return false


static func _shares_object_term(name: String, evidence: String) -> bool:
	var plain_name := SafeBBCode.plain_text(name).strip_edges()
	if plain_name.is_empty(): return false
	if evidence.contains(plain_name): return true
	for index in range(maxi(0, plain_name.length() - 1)):
		if evidence.contains(plain_name.substr(index, 2)): return true
	for character in plain_name:
		if "水卡证钥匙书药伞票纸笔灯镜瓶盒袋".contains(character) and evidence.contains(character): return true
	return plain_name.length() == 1 and evidence.contains(plain_name)


static func _stat_id(label: String) -> String:
	if label in ["健康", "生命"]: return "health"
	if label in ["理智", "精神"]: return "sanity"
	if label in ["体力", "耐力"]: return "stamina"
	return ""


static func _clean_forbidden_term(term: String) -> String:
	var cleaned := term.replace(" ", "").replace("　", "").replace("“", "").replace("”", "").replace("‘", "").replace("’", "").replace("\"", "").replace("'", "")
	for prefix in ["任何", "一切", "该", "此", "本"]:
		if cleaned.begins_with(prefix): cleaned = cleaned.trim_prefix(prefix)
	if cleaned.ends_with("的"): cleaned = cleaned.trim_suffix("的")
	return cleaned
