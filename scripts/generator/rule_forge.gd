class_name RuleForgeService
extends RefCounted

const DEFAULT_PACK_PATH := "res://content/rule_packs/apartment/fragments.json"
const SeedRngScript := preload("res://scripts/generator/seed_rng.gd")


static func forge(seed: int, pack_path: String = DEFAULT_PACK_PATH, minimum_fragments: int = 12, maximum_fragments: int = 18) -> Dictionary:
	var loaded := _load_pack(pack_path)
	if not bool(loaded.ok):
		return loaded
	var pack: Dictionary = loaded.pack
	var fragments: Array = pack.fragments
	var rng := SeedRngScript.new(seed)
	var chain_ids: Array[String] = []
	for fragment in fragments:
		var chain_id := str(fragment.get("chainId", ""))
		if not chain_id.is_empty() and chain_id not in chain_ids:
			chain_ids.append(chain_id)
	chain_ids.sort()
	if chain_ids.is_empty():
		return _failure("主题没有可用出口链。")
	var chain_id: String = chain_ids[rng.pick_index(chain_ids.size())]

	var selected: Array[Dictionary] = []
	var steps: Array = []
	for fragment in fragments:
		if str(fragment.get("chainId", "")) == chain_id:
			steps.append(fragment)
	steps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("chainOrder", 0)) < int(b.get("chainOrder", 0)))
	for step in steps:
		selected.append(_forged_rule(step))

	# Pull in reliable supporters until every exit-chain requirement is granted.
	for _guard in range(64):
		var missing := _first_missing_capability(selected)
		if missing.is_empty():
			break
		var candidates: Array = []
		for fragment in fragments:
			if missing in _string_array(fragment.get("grants", [])) and not _selected_has(selected, str(fragment.id)):
				candidates.append(fragment)
		if candidates.is_empty():
			return _failure("出口链需要能力“%s”，但主题没有规则能提供它。" % missing)
		selected.append(_forged_rule(candidates[rng.pick_index(candidates.size())]))
	if not _first_missing_capability(selected).is_empty():
		return _failure("出口链依赖无法在安全上限内闭合。")

	var minimum := maxi(4, minimum_fragments)
	var maximum := maxi(minimum, maximum_fragments)
	var pool: Array = []
	for fragment in fragments:
		if not _selected_has(selected, str(fragment.id)):
			pool.append(fragment)
	rng.shuffle(pool)
	var target := mini(maximum, minimum + rng.pick_index(maximum - minimum + 1))
	while not pool.is_empty() and selected.size() < target:
		selected.append(_forged_rule(pool.pop_front()))
	if selected.size() < minimum:
		return _failure("主题可用规则碎片不足（%d/%d）。" % [selected.size(), minimum])

	# Keep at least five authored chapters represented whenever the pack allows it.
	var chapters: Array[String] = _string_array(pack.chapters)
	var wanted_chapters := mini(5, chapters.size())
	for _guard in range(64):
		var present := _present_chapters(selected)
		if present.size() >= wanted_chapters:
			break
		var missing_chapter := ""
		for chapter in chapters:
			if chapter not in present:
				missing_chapter = chapter
				break
		var replacement := -1
		for index in range(pool.size()):
			if str(pool[index].chapter) == missing_chapter:
				replacement = index
				break
		if replacement < 0:
			break
		var evict := -1
		for _attempt in range(8):
			var candidate := rng.pick_index(selected.size())
			var rule: Dictionary = selected[candidate]
			if _is_chain_step(rule.fragment) or bool(rule.fragment.get("lockTruth", false)):
				continue
			if _chapter_count(selected, str(rule.fragment.chapter)) > 1:
				evict = candidate
				break
		if evict < 0:
			break
		var incoming: Dictionary = pool[replacement]
		pool[replacement] = selected[evict].fragment
		selected[evict] = _forged_rule(incoming)

	var chain_requires := _collect_capabilities(selected, "requires", true)
	for rule in selected:
		if _is_chain_step(rule.fragment) or bool(rule.fragment.get("lockTruth", false)):
			continue
		for ban in _string_array(rule.fragment.get("bans", [])):
			if ban in chain_requires:
				rule.truth = "false"

	var handled_pairs: Array[String] = []
	for first_index in range(selected.size()):
		for other_id in _string_array(selected[first_index].fragment.get("contradicts", [])):
			var pair_key := "%s|%s" % [selected[first_index].fragment.id, other_id]
			if pair_key in handled_pairs:
				continue
			handled_pairs.append(pair_key)
			var partner := _selected_index(selected, other_id)
			if partner < 0 or bool(selected[first_index].fragment.get("lockTruth", false)) or bool(selected[partner].fragment.get("lockTruth", false)):
				continue
			var first_false := rng.coin_flip()
			selected[first_index if first_false else partner].truth = "false"
			selected[partner if first_false else first_index].truth = "true"

	for rule in selected:
		if _is_chain_step(rule.fragment) or bool(rule.fragment.get("lockTruth", false)) or str(rule.truth) == "false":
			continue
		var in_pair := false
		for pair_key in handled_pairs:
			if pair_key.begins_with(str(rule.fragment.id) + "|") or pair_key.ends_with("|" + str(rule.fragment.id)):
				in_pair = true
				break
		if not in_pair and rng.pick_index(5) == 0:
			rule.truth = "false"

	for rule in selected:
		if str(rule.truth) != "true" or _is_chain_step(rule.fragment) or bool(rule.fragment.get("lockTruth", false)):
			continue
		for ban in _string_array(rule.fragment.get("bans", [])):
			if ban in chain_requires:
				rule.truth = "false"

	var tamper_candidates: Array = []
	for index in range(selected.size()):
		var rule: Dictionary = selected[index]
		if str(rule.truth) == "true" and bool(rule.fragment.get("tamperable", false)) and not _is_chain_step(rule.fragment):
			tamper_candidates.append(index)
	rng.shuffle(tamper_candidates)
	var tamper_count := 0 if tamper_candidates.is_empty() else 1 + rng.pick_index(mini(2, tamper_candidates.size()))
	for index in range(tamper_count):
		selected[int(tamper_candidates[index])].tamper_target = true

	for rule in selected:
		var filled := _fill_slots(str(rule.fragment.pattern), rule.fragment.get("slots", {}), rng)
		rule.text = filled.text
		rule.slot_choices = filled.choices
		if bool(rule.tamper_target) and not str(rule.fragment.get("tampered", "")).is_empty():
			rule.tampered_text = _fill_slots_with_choices(str(rule.fragment.tampered), rule.slot_choices)

	var ordered: Array[Dictionary] = []
	var sections: Array[String] = []
	for chapter in chapters:
		var chapter_rules: Array[Dictionary] = []
		for rule in selected:
			if str(rule.fragment.chapter) == chapter:
				chapter_rules.append(rule)
		if chapter_rules.is_empty():
			continue
		var lines: Array[String] = ["<%s>" % chapter]
		for index in range(chapter_rules.size()):
			var rule: Dictionary = chapter_rules[index]
			var line := "%d. %s" % [index + 1, rule.text]
			if bool(rule.tamper_target):
				line = "%d. [blood]%s[/blood]" % [index + 1, rule.text]
			lines.append(line)
			ordered.append(rule)
		sections.append("\n".join(lines))

	var solvability := _check_solvability(ordered)
	if not bool(solvability.ok):
		return _failure("生成规则未通过可解性检查：%s" % "；".join(solvability.issues))
	var meta_fragments: Array[Dictionary] = []
	var tamper_plans: Array[Dictionary] = []
	for rule in ordered:
		var entry := {"id": str(rule.fragment.id), "chapter": str(rule.fragment.chapter), "truth": str(rule.truth), "tamperTarget": bool(rule.tamper_target)}
		if _is_chain_step(rule.fragment):
			entry.chainId = str(rule.fragment.chainId)
			entry.chainOrder = int(rule.fragment.chainOrder)
		if not rule.slot_choices.is_empty():
			entry.slots = rule.slot_choices.duplicate(true)
		meta_fragments.append(entry)
		if bool(rule.tamper_target) and not str(rule.tampered_text).is_empty():
			tamper_plans.append({"id": str(rule.fragment.id), "chapter": str(rule.fragment.chapter), "original": str(rule.text), "tampered": str(rule.tampered_text)})
	var meta := {"version": 1, "seed": seed & 0xFFFFFFFF, "theme": str(pack.theme), "chainId": chain_id, "fragments": meta_fragments, "tamperPlans": tamper_plans}
	return {"ok": true, "error": "", "theme_id": str(pack.theme), "display_name": str(pack.displayName), "document_text": "\n\n".join(sections) + "\n", "rules": ordered, "meta": meta, "pack": pack}


static func _load_pack(path: String) -> Dictionary:
	var parser := JSON.new()
	var error := parser.parse(FileAccess.get_file_as_string(path))
	if error != OK or not parser.data is Dictionary:
		return _failure("主题包 JSON 第 %d 行：%s" % [parser.get_error_line(), parser.get_error_message()])
	var pack: Dictionary = parser.data
	if str(pack.get("theme", "")).is_empty() or str(pack.get("displayName", "")).is_empty():
		return _failure("主题包缺少 theme 或 displayName。")
	if not pack.get("chapters", []) is Array or not pack.get("fragments", []) is Array or pack.fragments.is_empty():
		return _failure("主题包缺少章节或规则碎片。")
	var seen := {}
	for fragment in pack.fragments:
		if not fragment is Dictionary:
			return _failure("主题包包含格式错误的碎片。")
		var fragment_id := str(fragment.get("id", ""))
		if fragment_id.is_empty() or seen.has(fragment_id) or str(fragment.get("chapter", "")).is_empty() or str(fragment.get("pattern", "")).is_empty():
			return _failure("主题包包含缺字段或重复 ID 的碎片。")
		seen[fragment_id] = true
	for fragment in pack.fragments:
		for other in _string_array(fragment.get("contradicts", [])):
			if not seen.has(other):
				return _failure("规则 %s 引用了不存在的冲突规则 %s。" % [fragment.id, other])
	return {"ok": true, "error": "", "pack": pack}


static func _forged_rule(fragment: Dictionary) -> Dictionary:
	return {"fragment": fragment, "truth": str(fragment.get("truth", "true")), "text": "", "slot_choices": {}, "tamper_target": false, "tampered_text": ""}


static func _first_missing_capability(selected: Array[Dictionary]) -> String:
	var required := _collect_capabilities(selected, "requires", true)
	var granted := _collect_capabilities(selected, "grants", false)
	for capability in required:
		if capability not in granted:
			return capability
	return ""


static func _collect_capabilities(selected: Array[Dictionary], field: String, chain_only: bool) -> Array[String]:
	var output: Array[String] = []
	for rule in selected:
		if chain_only and not _is_chain_step(rule.fragment):
			continue
		if field == "grants" and str(rule.truth) == "false":
			continue
		for capability in _string_array(rule.fragment.get(field, [])):
			if capability not in output:
				output.append(capability)
	return output


static func _present_chapters(selected: Array[Dictionary]) -> Array[String]:
	var output: Array[String] = []
	for rule in selected:
		var chapter := str(rule.fragment.chapter)
		if chapter not in output:
			output.append(chapter)
	return output


static func _chapter_count(selected: Array[Dictionary], chapter: String) -> int:
	var count := 0
	for rule in selected:
		if str(rule.fragment.chapter) == chapter:
			count += 1
	return count


static func _selected_has(selected: Array[Dictionary], fragment_id: String) -> bool:
	return _selected_index(selected, fragment_id) >= 0


static func _selected_index(selected: Array[Dictionary], fragment_id: String) -> int:
	for index in range(selected.size()):
		if str(selected[index].fragment.id) == fragment_id:
			return index
	return -1


static func _is_chain_step(fragment: Dictionary) -> bool:
	return not str(fragment.get("chainId", "")).is_empty()


static func _fill_slots(pattern: String, slots: Dictionary, rng: RefCounted) -> Dictionary:
	var text := pattern
	var choices := {}
	var regex := RegEx.new()
	regex.compile("\\{([^}]+)\\}")
	for _guard in range(64):
		var found := regex.search(text)
		if found == null:
			break
		var name := found.get_string(1).strip_edges()
		var values: Array = slots.get(name, []) if slots.get(name, []) is Array else []
		var value := "" if values.is_empty() else str(values[rng.pick_index(values.size())])
		text = text.substr(0, found.get_start()) + value + text.substr(found.get_end())
		choices[name] = value
	return {"text": text, "choices": choices}


static func _fill_slots_with_choices(pattern: String, choices: Dictionary) -> String:
	var text := pattern
	var regex := RegEx.new()
	regex.compile("\\{([^}]+)\\}")
	for _guard in range(64):
		var found := regex.search(text)
		if found == null:
			break
		var value := str(choices.get(found.get_string(1).strip_edges(), ""))
		text = text.substr(0, found.get_start()) + value + text.substr(found.get_end())
	return text


static func _check_solvability(ordered: Array[Dictionary]) -> Dictionary:
	var issues: Array[String] = []
	var chain_id := ""
	var orders: Array[int] = []
	for rule in ordered:
		if not _is_chain_step(rule.fragment):
			continue
		if chain_id.is_empty():
			chain_id = str(rule.fragment.chainId)
		elif chain_id != str(rule.fragment.chainId):
			issues.append("档案混入多条出口链。")
		var order := int(rule.fragment.get("chainOrder", 0))
		if order not in orders:
			orders.append(order)
	orders.sort()
	if chain_id.is_empty():
		issues.append("档案没有出口链。")
	else:
		for index in range(orders.size()):
			if orders[index] != index + 1:
				issues.append("出口链缺少第 %d 步。" % (index + 1))
				break
		if orders.size() < 2:
			issues.append("出口链至少需要两步。")
	var required := _collect_capabilities(ordered, "requires", true)
	var granted := _collect_capabilities(ordered, "grants", false)
	for capability in required:
		if capability not in granted:
			issues.append("缺少出口能力：%s" % capability)
	for rule in ordered:
		if str(rule.truth) == "false":
			continue
		for ban in _string_array(rule.fragment.get("bans", [])):
			if ban in required:
				issues.append("可靠规则禁止了出口能力：%s" % ban)
		if str(rule.text).contains("{"):
			issues.append("规则 %s 仍有未填槽位。" % str(rule.fragment.id))
		if bool(rule.tamper_target) and (str(rule.tampered_text).is_empty() or str(rule.tampered_text) == str(rule.text)):
			issues.append("篡改位 %s 不可用。" % str(rule.fragment.id))
	return {"ok": issues.is_empty(), "issues": issues}


static func _string_array(value: Variant) -> Array[String]:
	var output: Array[String] = []
	if value is Array:
		for item in value:
			output.append(str(item))
	return output


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
