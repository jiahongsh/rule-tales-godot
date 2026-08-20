class_name StructuredFactStore
extends RefCounted

## Qt FactStore-compatible authoritative long-term facts.
##
## Canonical persisted records use first_seen_turn / last_updated_turn.  The
## loader also accepts the early Godot prototype's updated_turn field and
## normalizes it immediately, so every later save is portable between engines.

const KINDS := ["clue", "character", "location", "triggered_rule", "open_event"]
const STATUSES := ["active", "resolved"]
const MAX_FACTS := 512
const MAX_OPERATIONS := 8
const MAX_TITLE_LENGTH := 160
const MAX_DETAIL_LENGTH := 2400

var records: Array[Dictionary] = []


func clear() -> void:
	records.clear()


func clone() -> StructuredFactStore:
	var copy := StructuredFactStore.new()
	copy.records = records.duplicate(true)
	return copy


func load_records(raw_records: Variant) -> Dictionary:
	if not raw_records is Array:
		return {"ok": false, "error": "facts 必须是数组。"}
	var source: Array = raw_records
	if source.size() > MAX_FACTS:
		return {"ok": false, "error": "结构化事实超过 %d 条。" % MAX_FACTS}
	var candidate: Array[Dictionary] = []
	var known_ids: Dictionary = {}
	for index in source.size():
		var raw: Variant = source[index]
		if not raw is Dictionary:
			return {"ok": false, "error": "facts[%d] 必须是对象。" % index}
		var record: Dictionary = raw
		var allowed := ["id", "kind", "title", "detail_bbcode", "status", "resolution_bbcode", "first_seen_turn", "last_updated_turn", "updated_turn"]
		var unknown := _unknown_key(record, allowed)
		if not unknown.is_empty():
			return {"ok": false, "error": "facts[%d] 包含未知字段：%s。" % [index, unknown]}
		for required_text_key in ["id", "kind", "title", "detail_bbcode", "status"]:
			if not record.get(required_text_key) is String:
				return {"ok": false, "error": "facts[%d].%s 必须是字符串。" % [index, required_text_key]}
		var fact_id := str(record.get("id", "")).strip_edges()
		var kind := str(record.get("kind", "")).strip_edges()
		var title := str(record.get("title", "")).strip_edges()
		var detail := str(record.get("detail_bbcode", "")).strip_edges()
		var status := str(record.get("status", "")).strip_edges()
		if not _valid_id(fact_id) or known_ids.has(fact_id):
			return {"ok": false, "error": "facts[%d].id 无效或重复。" % index}
		if kind not in KINDS:
			return {"ok": false, "error": "facts[%d].kind 不受支持。" % index}
		if title.is_empty() or title.length() > MAX_TITLE_LENGTH:
			return {"ok": false, "error": "facts[%d].title 为空或过长。" % index}
		if detail.is_empty() or detail.length() > MAX_DETAIL_LENGTH:
			return {"ok": false, "error": "facts[%d].detail_bbcode 为空或过长。" % index}
		if status not in STATUSES:
			return {"ok": false, "error": "facts[%d].status 无效。" % index}

		var legacy_turn: Variant = record.get("updated_turn", 0)
		var first_value: Variant = record.get("first_seen_turn", legacy_turn)
		var updated_value: Variant = record.get("last_updated_turn", legacy_turn if record.has("updated_turn") else first_value)
		if not _is_nonnegative_integer(first_value) or not _is_nonnegative_integer(updated_value):
			return {"ok": false, "error": "facts[%d] 的回合编号必须是非负整数。" % index}
		var first_turn := int(first_value)
		var updated_turn := int(updated_value)
		if updated_turn < first_turn:
			return {"ok": false, "error": "facts[%d].last_updated_turn 不能早于 first_seen_turn。" % index}

		var canonical := {
			"id": fact_id,
			"kind": kind,
			"title": title,
			"detail_bbcode": detail,
			"status": status,
			"first_seen_turn": first_turn,
			"last_updated_turn": updated_turn,
		}
		if record.has("resolution_bbcode"):
			if not record.get("resolution_bbcode") is String:
				return {"ok": false, "error": "facts[%d].resolution_bbcode 必须是字符串。" % index}
			var resolution := str(record.get("resolution_bbcode", "")).strip_edges()
			if resolution.length() > MAX_DETAIL_LENGTH:
				return {"ok": false, "error": "facts[%d].resolution_bbcode 过长。" % index}
			if not resolution.is_empty():
				canonical["resolution_bbcode"] = resolution
		known_ids[fact_id] = true
		candidate.append(canonical)
	records = candidate
	return {"ok": true, "error": ""}


func apply_operations(operations: Array, completed_turn: int) -> Dictionary:
	if operations.size() > MAX_OPERATIONS:
		return {"ok": false, "error": "memory_ops 每回合最多 %d 项。" % MAX_OPERATIONS, "changes": []}
	var candidate: Array[Dictionary] = records.duplicate(true)
	var changes: Array[String] = []
	var turn := maxi(0, completed_turn)
	for operation_index in operations.size():
		var raw: Variant = operations[operation_index]
		if not raw is Dictionary:
			return {"ok": false, "error": "memory_ops[%d] 必须是对象。" % operation_index, "changes": []}
		var operation: Dictionary = raw
		if not operation.get("op") is String or not operation.get("id") is String:
			return {"ok": false, "error": "memory_ops[%d] 的 op 和 id 必须是字符串。" % operation_index, "changes": []}
		var op := str(operation.get("op", "")).strip_edges()
		var fact_id := str(operation.get("id", "")).strip_edges()
		if not _valid_id(fact_id):
			return {"ok": false, "error": "memory_ops[%d].id 只能使用 1–64 个字母、数字、点、横线和下划线。" % operation_index, "changes": []}
		var fact_index := _find_in(candidate, fact_id)
		if op == "upsert":
			var unknown := _unknown_key(operation, ["op", "id", "kind", "title", "detail_bbcode"])
			if not unknown.is_empty():
				return {"ok": false, "error": "memory_ops[%d] 包含未知字段：%s。" % [operation_index, unknown], "changes": []}
			for required_text_key in ["kind", "title", "detail_bbcode"]:
				if not operation.get(required_text_key) is String:
					return {"ok": false, "error": "memory_ops[%d].%s 必须是字符串。" % [operation_index, required_text_key], "changes": []}
			var kind := str(operation.get("kind", "")).strip_edges()
			var title := str(operation.get("title", "")).strip_edges()
			var detail := str(operation.get("detail_bbcode", "")).strip_edges()
			if kind not in KINDS:
				return {"ok": false, "error": "memory_ops[%d].kind 不受支持。" % operation_index, "changes": []}
			if title.is_empty() or title.length() > MAX_TITLE_LENGTH or detail.is_empty() or detail.length() > MAX_DETAIL_LENGTH:
				return {"ok": false, "error": "memory_ops[%d] 的 title 或 detail_bbcode 为空或过长。" % operation_index, "changes": []}
			if fact_index < 0:
				if candidate.size() >= MAX_FACTS:
					return {"ok": false, "error": "结构化事实已达到 %d 条上限。" % MAX_FACTS, "changes": []}
				candidate.append({"id": fact_id, "kind": kind, "title": title, "detail_bbcode": detail, "status": "active", "first_seen_turn": turn, "last_updated_turn": turn})
				changes.append("记录事实：%s" % title)
			else:
				if str(candidate[fact_index].get("kind", "")) != kind:
					return {"ok": false, "error": "memory_ops[%d] 不能改变已有事实的 kind。" % operation_index, "changes": []}
				candidate[fact_index]["title"] = title
				candidate[fact_index]["detail_bbcode"] = detail
				candidate[fact_index]["last_updated_turn"] = turn
				changes.append("更新事实：%s" % title)
		elif op == "resolve":
			var unknown := _unknown_key(operation, ["op", "id", "resolution_bbcode"])
			if not unknown.is_empty():
				return {"ok": false, "error": "memory_ops[%d] 包含未知字段：%s。" % [operation_index, unknown], "changes": []}
			if not operation.get("resolution_bbcode") is String:
				return {"ok": false, "error": "memory_ops[%d].resolution_bbcode 必须是字符串。" % operation_index, "changes": []}
			var resolution := str(operation.get("resolution_bbcode", "")).strip_edges()
			if resolution.is_empty() or resolution.length() > MAX_DETAIL_LENGTH:
				return {"ok": false, "error": "memory_ops[%d].resolution_bbcode 为空或过长。" % operation_index, "changes": []}
			if fact_index < 0 or str(candidate[fact_index].get("kind", "")) != "open_event":
				return {"ok": false, "error": "memory_ops[%d] 只能解决已存在的 open_event。" % operation_index, "changes": []}
			candidate[fact_index]["status"] = "resolved"
			candidate[fact_index]["resolution_bbcode"] = resolution
			candidate[fact_index]["last_updated_turn"] = turn
			changes.append("事件解决：%s" % str(candidate[fact_index].get("title", fact_id)))
		else:
			return {"ok": false, "error": "memory_ops[%d].op 仅允许 upsert 或 resolve。" % operation_index, "changes": []}
	records = candidate
	return {"ok": true, "error": "", "changes": changes}


func prompt_snapshot(max_records: int = 120, max_characters: int = 16000) -> Array:
	var ordered := records.duplicate(true)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_priority := _priority(a)
		var b_priority := _priority(b)
		if a_priority != b_priority:
			return a_priority < b_priority
		var a_turn := int(a.get("last_updated_turn", 0))
		var b_turn := int(b.get("last_updated_turn", 0))
		if a_turn != b_turn:
			return a_turn > b_turn
		return str(a.get("id", "")) < str(b.get("id", "")))
	var result: Array = []
	var used_characters := 0
	for record in ordered:
		if result.size() >= maxi(0, max_records):
			break
		var encoded_size := JSON.stringify(record).to_utf8_buffer().size()
		if used_characters + encoded_size > maxi(0, max_characters):
			continue
		result.append(record.duplicate(true))
		used_characters += encoded_size
	return result


func _priority(record: Dictionary) -> int:
	if str(record.get("status", "active")) != "active":
		return 5
	return {"open_event": 0, "triggered_rule": 1, "clue": 2, "character": 3, "location": 4}.get(str(record.get("kind", "")), 5)


func _find_in(values: Array, fact_id: String) -> int:
	for index in values.size():
		if str(values[index].get("id", "")) == fact_id:
			return index
	return -1


func _valid_id(value: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z0-9_.-]{1,64}$")
	return pattern.search(value) != null


func _is_nonnegative_integer(value: Variant) -> bool:
	if value is int:
		return int(value) >= 0
	if value is float:
		return is_finite(float(value)) and float(value) >= 0.0 and floor(float(value)) == float(value)
	return false


func _unknown_key(value: Dictionary, allowed: Array) -> String:
	for key in value:
		if str(key) not in allowed:
			return str(key)
	return ""
