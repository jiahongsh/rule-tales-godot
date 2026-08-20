class_name MemorySearch
extends RefCounted


static func select(entries: Array, query: String, recent_count: int, relevant_count: int) -> Dictionary:
	var recent_indices: Array[int] = []
	var relevant_indices: Array[int] = []
	var recent_start := maxi(0, entries.size() - clampi(recent_count, 0, 60))
	for index in range(recent_start, entries.size()):
		recent_indices.append(index)
	if relevant_count > 0 and recent_start > 0:
		var query_tokens := _tokens(query)
		var ranked: Array[Dictionary] = []
		for index in range(recent_start):
			var content := str(entries[index].get("content", ""))
			var score := _score(query_tokens, _tokens(content))
			if score > 0.0:
				ranked.append({"index": index, "score": score})
		ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.score) > float(b.score) if not is_equal_approx(float(a.score), float(b.score)) else int(a.index) > int(b.index))
		for item in ranked.slice(0, mini(relevant_count, ranked.size())):
			relevant_indices.append(int(item.index))
		relevant_indices.sort()
	return {"recent_indices": recent_indices, "relevant_indices": relevant_indices}


static func ranked_indices(entries: Array, query: String, limit: int) -> Array[int]:
	var query_tokens := _tokens(query)
	var ranked: Array[Dictionary] = []
	for index in range(entries.size()):
		var score := _score(query_tokens, _tokens(str(entries[index].get("content", ""))))
		if score > 0.0: ranked.append({"index": index, "score": score})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.score) > float(b.score) if not is_equal_approx(float(a.score), float(b.score)) else int(a.index) < int(b.index))
	var output: Array[int] = []
	for item in ranked.slice(0, mini(limit, ranked.size())): output.append(int(item.index))
	return output


static func _tokens(text: String) -> Dictionary:
	var plain := SafeBBCode.plain_text(text).to_lower()
	var result := {}
	var ascii_word := ""
	var han: Array[String] = []
	for character in plain:
		var code := character.unicode_at(0)
		if (code >= 0x4E00 and code <= 0x9FFF):
			if not ascii_word.is_empty(): result[ascii_word] = int(result.get(ascii_word, 0)) + 1; ascii_word = ""
			han.append(character)
			result[character] = int(result.get(character, 0)) + 1
		elif character.is_valid_identifier() or character.is_valid_int():
			ascii_word += character
		else:
			if not ascii_word.is_empty(): result[ascii_word] = int(result.get(ascii_word, 0)) + 1; ascii_word = ""
	if not ascii_word.is_empty(): result[ascii_word] = int(result.get(ascii_word, 0)) + 1
	for index in range(han.size() - 1):
		var bigram := han[index] + han[index + 1]
		result[bigram] = int(result.get(bigram, 0)) + 2
	return result


static func _score(query: Dictionary, document: Dictionary) -> float:
	if query.is_empty() or document.is_empty(): return 0.0
	var score := 0.0
	for token in query:
		if document.has(token):
			score += (1.0 + log(1.0 + float(query[token]))) * (1.0 + log(1.0 + float(document[token]))) * (1.5 if str(token).length() > 1 else 1.0)
	return score
