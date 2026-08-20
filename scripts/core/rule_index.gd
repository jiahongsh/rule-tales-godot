class_name RuleFragmentIndex
extends RefCounted

var fragments: Array[Dictionary] = []


func rebuild(document: RuleDocumentData) -> void:
	fragments.clear()
	var source_order := 0
	for chapter_index in range(document.chapters.size()):
		var chapter: Dictionary = document.chapters[chapter_index]
		var lines := _fragment_lines(str(chapter.content))
		for fragment_index in range(lines.size()):
			fragments.append({
				"id": "r%d_%d" % [chapter_index + 1, fragment_index + 1],
				"chapter": str(chapter.title), "text_bbcode": lines[fragment_index],
				"source_order": source_order, "global": _is_global(str(chapter.title), chapter_index)
			})
			source_order += 1


func select(query: String, relevant_count: int = 10, global_count: int = 5, maximum_characters: int = 7000) -> Dictionary:
	var selected: Array[Dictionary] = []
	var selected_ids := {}; var budget := {"used": 0}
	var global_ids: Array[String] = []; var relevant_ids: Array[String] = []
	var append_fragment := func(index: int, global: bool) -> void:
		if index < 0 or index >= fragments.size(): return
		var fragment: Dictionary = fragments[index]
		if selected_ids.has(fragment.id): return
		var cost := str(fragment.chapter).length() + str(fragment.text_bbcode).length() + 48
		if int(budget.used) + cost > maximum_characters: return
		selected_ids[fragment.id] = true; selected.append(fragment); budget.used = int(budget.used) + cost
		if global: global_ids.append(fragment.id)
		else: relevant_ids.append(fragment.id)
	var globals_added := 0
	for index in range(fragments.size()):
		if globals_added >= global_count: break
		if bool(fragments[index].global):
			append_fragment.call(index, true); globals_added += 1
	var searchable: Array[Dictionary] = []
	for fragment in fragments: searchable.append({"content": "%s %s" % [fragment.chapter, fragment.text_bbcode]})
	for index in MemorySearch.ranked_indices(searchable, query, relevant_count): append_fragment.call(index, false)
	var fallback := 0
	while selected.size() < 4 and fallback < fragments.size(): append_fragment.call(fallback, false); fallback += 1
	selected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.source_order) < int(b.source_order))
	var ids: Array[String] = []
	for fragment in selected: ids.append(str(fragment.id))
	return {"fragments": selected, "trace": {"query": query, "indexed_fragments": fragments.size(), "selected_characters": int(budget.used), "global_ids": global_ids, "relevant_ids": relevant_ids, "selected_ids": ids}}


func prompt_text(selection: Dictionary) -> String:
	var blocks: Array[String] = []
	for fragment in selection.fragments:
		blocks.append("[RULE id=%s chapter=%s]\n%s\n[/RULE]" % [fragment.id, fragment.chapter, fragment.text_bbcode])
	return "\n\n".join(blocks)


func _fragment_lines(content: String) -> Array[String]:
	var output: Array[String] = []
	for raw in content.replace("\r", "").split("\n", false):
		var line := str(raw).strip_edges()
		if line.is_empty(): continue
		while line.length() > 420:
			var cut := 420
			for delimiter in ["。", "！", "？", "；"]:
				var found := line.rfind(delimiter, 420)
				if found >= 180: cut = mini(cut, found + 1)
			output.append(line.left(cut).strip_edges()); line = line.substr(cut).strip_edges()
		if not line.is_empty(): output.append(line)
	return output


func _is_global(title: String, chapter_index: int) -> bool:
	if chapter_index == 0: return true
	for keyword in ["总则", "总览", "基础", "通用", "须知", "封面", "身份核验", "入校"]:
		if title.contains(keyword): return true
	return false
