class_name RuleTalesGameState
extends RefCounted

const SCHEMA_VERSION := 2
const ENDING_TYPES := ["none", "survival", "escape", "missing", "contamination", "special"]
const TERMINAL_ENDING_TYPES := ["survival", "escape", "missing", "contamination", "special"]
const INT32_MIN := -2_147_483_648
const INT32_MAX := 2_147_483_647
const MAX_TEXT_UNITS := 64 * 1024
const MAX_IDENTIFIER_UNITS := 96
const MAX_COORDINATE := 50

var data: Dictionary = {}


func _init() -> void:
	reset()


func reset() -> void:
	data = {
		"schema_version": SCHEMA_VERSION,
		"day": 1,
		"minute_of_day": 20 * 60 + 13,
		"weather": "阴",
		"stats": {"health": 100, "sanity": 100, "stamina": 100},
		"inventory": [],
		"status_bbcode": "[color=#aab7b2]呼吸平稳，但安静得能听见自己的心跳。[/color]",
		"map": {"nodes": [], "edges": [], "current": ""},
		"ending": {"type": "none", "title": "", "summary_bbcode": ""},
		"run_mode": false,
		"days_limit": 0,
		"route_node": "",
	}


func clock_text() -> String:
	var minute := int(data.minute_of_day) % 1440
	return "%02d:%02d" % [minute / 60, minute % 60]


func is_terminal() -> bool:
	return str(data.ending.get("type", "none")) != "none"


func inventory_total() -> int:
	var total := 0
	for item in data.inventory:
		total += int(item.get("quantity", 0))
	return total


func inventory_item(item_id: String) -> Dictionary:
	for item in data.inventory:
		if str(item.get("id", "")) == item_id:
			return item
	return {}


func apply_patch(patch: Dictionary, allow_map: bool = true) -> Dictionary:
	var unknown := _unknown_key(patch, ["elapsed_minutes", "weather_set", "stats_delta", "inventory_ops", "status_bbcode_set", "map", "ending"])
	if not unknown.is_empty():
		return {"ok": false, "error": "patch 包含未知字段 %s。" % unknown, "changes": []}
	if is_terminal() and not patch.is_empty():
		return {"ok": false, "error": "故事已经进入终局，不能继续应用状态补丁。", "changes": []}
	var candidate: Dictionary = data.duplicate(true)
	var changes: Array[String] = []
	var error := _apply_public_patch(candidate, patch, allow_map, changes)
	if not error.is_empty():
		return {"ok": false, "error": error, "changes": []}
	data = candidate
	return {"ok": true, "error": "", "changes": changes}


func replace_from_dict(value: Dictionary) -> String:
	var schema_result := _read_integer(value.get("schema_version", SCHEMA_VERSION), 1, SCHEMA_VERSION, "schema_version")
	if not bool(schema_result.ok):
		return str(schema_result.error)
	var day_result := _read_integer(value.get("day", null), 1, INT32_MAX, "day")
	if not bool(day_result.ok):
		return str(day_result.error)
	var time_result := _read_integer(value.get("minute_of_day", null), 0, 1439, "minute_of_day")
	if not bool(time_result.ok):
		return str(time_result.error)
	if not value.get("weather") is String:
		return "weather 必须是字符串。"
	var weather := str(value.get("weather", "")).strip_edges()
	if weather.is_empty() or _qt_text_length(weather) > MAX_TEXT_UNITS:
		return "weather 为空或过长。"

	var raw_stats: Variant = value.get("stats", null)
	if not raw_stats is Dictionary or raw_stats.is_empty():
		return "stats 必须是非空对象。"
	var normalized_stats: Dictionary = {}
	for raw_key in raw_stats:
		if not raw_key is String or not _valid_identifier(str(raw_key)):
			return "stats 包含无效名称。"
		var stat_result := _read_integer(raw_stats[raw_key], 0, 100, "stats.%s" % str(raw_key))
		if not bool(stat_result.ok):
			return str(stat_result.error)
		normalized_stats[str(raw_key)] = int(stat_result.value)

	var raw_inventory: Variant = value.get("inventory", null)
	if not raw_inventory is Array:
		return "inventory 必须是数组。"
	var normalized_inventory: Array[Dictionary] = []
	var item_ids: Dictionary = {}
	for index in raw_inventory.size():
		var item_result := _normalized_saved_item(raw_inventory[index], index)
		if not bool(item_result.ok):
			return str(item_result.error)
		var item: Dictionary = item_result.value
		if int(item.quantity) == 0 or item_ids.has(str(item.id)):
			return "背包不允许数量为 0 或重复 id 的物品。"
		item_ids[str(item.id)] = true
		normalized_inventory.append(item)

	if not value.get("status_bbcode") is String:
		return "status_bbcode 必须是有效字符串。"
	var status := str(value.get("status_bbcode", ""))
	if _qt_text_length(status) > MAX_TEXT_UNITS:
		return "status_bbcode 必须是有效字符串。"

	var map_result := _normalized_saved_map(value.get("map", null))
	if not bool(map_result.ok):
		return "map: %s" % str(map_result.error)

	var normalized_ending := {"type": "none", "title": "", "summary_bbcode": ""}
	if value.has("ending"):
		if not value.get("ending") is Dictionary:
			return "ending 必须是对象。"
		var raw_ending: Dictionary = value.ending
		if not (raw_ending.get("type") is String and str(raw_ending.type) == "none"):
			var ending_result := _normalized_terminal_ending(raw_ending)
			if not bool(ending_result.ok):
				return "ending: %s" % str(ending_result.error)
			normalized_ending = ending_result.value

	var run_mode := false
	if value.has("run_mode"):
		if not value.run_mode is bool:
			return "run_mode 必须是布尔值。"
		run_mode = bool(value.run_mode)
	var days_limit := 0
	if value.has("days_limit"):
		var days_result := _read_integer(value.days_limit, 0, 365, "days_limit")
		if not bool(days_result.ok):
			return str(days_result.error)
		days_limit = int(days_result.value)
	var route_node := ""
	if value.has("route_node"):
		if not value.route_node is String or _qt_text_length(str(value.route_node)) > MAX_IDENTIFIER_UNITS:
			return "route_node 必须是 96 字以内的字符串。"
		route_node = str(value.route_node)

	data = {
		"schema_version": int(schema_result.value),
		"day": int(day_result.value),
		"minute_of_day": int(time_result.value),
		"weather": weather,
		"stats": normalized_stats,
		"inventory": normalized_inventory,
		"status_bbcode": status,
		"map": map_result.value,
		"ending": normalized_ending,
		"run_mode": run_mode,
		"days_limit": days_limit,
		"route_node": route_node,
	}
	return ""


func render_map_bbcode() -> String:
	var map_data: Dictionary = data.map
	var nodes: Array = map_data.nodes
	if nodes.is_empty():
		return "[color=#77817d][i]雾里还没有留下可辨认的路径……继续探索，地图会从脚步之后显形。[/i][/color]"
	var min_x := int(nodes[0].x)
	var max_x := min_x
	var min_y := int(nodes[0].y)
	var max_y := min_y
	for node in nodes:
		min_x = mini(min_x, int(node.x))
		max_x = maxi(max_x, int(node.x))
		min_y = mini(min_y, int(node.y))
		max_y = maxi(max_y, int(node.y))
	var width := (max_x - min_x) * 4 + 1
	var height := (max_y - min_y) * 2 + 1
	var grid: Array[Array] = []
	for _y in height:
		var row: Array[String] = []
		for _x in width:
			row.append(" ")
		grid.append(row)
	var by_id: Dictionary = {}
	for node in nodes:
		by_id[str(node.id)] = node
	for edge in map_data.edges:
		if not by_id.has(str(edge.get("from", ""))) or not by_id.has(str(edge.get("to", ""))):
			continue
		var from_node: Dictionary = by_id[str(edge.from)]
		var to_node: Dictionary = by_id[str(edge.to)]
		var from_x := (int(from_node.x) - min_x) * 4
		var from_y := (int(from_node.y) - min_y) * 2
		var to_x := (int(to_node.x) - min_x) * 4
		var to_y := (int(to_node.y) - min_y) * 2
		if from_x != to_x:
			var horizontal_direction := 1 if to_x > from_x else -1
			var x := from_x + horizontal_direction
			while x != to_x:
				_put_map_connector(grid, x, from_y, width, height, "-")
				x += horizontal_direction
		if from_y != to_y:
			_put_map_connector(grid, to_x, from_y, width, height, "+")
			var vertical_direction := 1 if to_y >= from_y else -1
			var y := from_y + vertical_direction
			while y != to_y:
				_put_map_connector(grid, to_x, y, width, height, "|")
				y += vertical_direction
	for node in nodes:
		var grid_x := (int(node.x) - min_x) * 4
		var grid_y := (int(node.y) - min_y) * 2
		grid[grid_y][grid_x] = "@" if str(node.id) == str(map_data.current) else str(node.symbol)
	var rows: Array[String] = []
	for row in grid:
		rows.append("".join(row).rstrip(" "))
	while not rows.is_empty() and rows.back().is_empty():
		rows.pop_back()
	var result := "[code]%s[/code]" % "\n".join(rows)
	if by_id.has(str(map_data.current)):
		result += "\n[color=#d6b96b][b]@ 当前位置：[/b][/color]%s" % str(by_id[str(map_data.current)].label)
	result += "\n[color=#788783]图例：[/color]"
	for node in nodes:
		result += "\n[color=#8fa8a3]%s[/color] %s" % ["@" if str(node.id) == str(map_data.current) else str(node.symbol), str(node.label)]
	return result


func _apply_public_patch(candidate: Dictionary, patch: Dictionary, allow_map: bool, changes: Array[String]) -> String:
	if patch.has("elapsed_minutes"):
		var elapsed_result := _read_integer(patch.elapsed_minutes, 0, 1440, "elapsed_minutes")
		if not bool(elapsed_result.ok):
			return str(elapsed_result.error)
		var elapsed := int(elapsed_result.value)
		var total := int(candidate.minute_of_day) + elapsed
		var day_increment := int(total / 1440)
		if int(candidate.day) > INT32_MAX - day_increment:
			return "时间推进会使 day 超出 32 位整数范围。"
		candidate.day = int(candidate.day) + day_increment
		candidate.minute_of_day = total % 1440
		if elapsed > 0:
			changes.append("时间推进 %d 分钟" % elapsed)

	if patch.has("weather_set"):
		if not patch.weather_set is String:
			return "weather_set 必须是非空字符串。"
		var raw_weather := str(patch.weather_set)
		var weather := raw_weather.strip_edges()
		if weather.is_empty() or _qt_text_length(raw_weather) > 128:
			return "weather_set 必须是非空字符串。"
		if weather != str(candidate.weather):
			changes.append("天气：%s -> %s" % [str(candidate.weather), weather])
			candidate.weather = weather

	if patch.has("stats_delta"):
		if not patch.stats_delta is Dictionary:
			return "stats_delta 必须是对象。"
		for raw_key in patch.stats_delta:
			var key := str(raw_key)
			if not candidate.stats.has(key):
				return "未知数值状态：%s。" % key
			var delta_result := _read_integer(patch.stats_delta[raw_key], INT32_MIN, INT32_MAX, "stats_delta.%s" % key)
			if not bool(delta_result.ok):
				return str(delta_result.error)
			var before := int(candidate.stats[key])
			var after := clampi(before + int(delta_result.value), 0, 100)
			candidate.stats[key] = after
			if after != before:
				changes.append("%s：%d -> %d" % [key, before, after])

	if patch.has("inventory_ops"):
		if not patch.inventory_ops is Array:
			return "inventory_ops 必须是数组。"
		for operation_index in patch.inventory_ops.size():
			var operation_raw: Variant = patch.inventory_ops[operation_index]
			if not operation_raw is Dictionary:
				return "inventory_ops[%d] 必须是对象。" % operation_index
			var operation: Dictionary = operation_raw
			var op := str(operation.get("op", "")).strip_edges().to_lower() if operation.get("op") is String else ""
			if op not in ["add", "remove", "set"]:
				return "inventory_ops[%d].op 必须是 add/remove/set。" % operation_index
			var payload := _inventory_payload(operation)
			var item_id := str(payload.get("id", "")).strip_edges() if payload.get("id") is String else ""
			if not _valid_identifier(item_id):
				return "inventory_ops[%d].id 无效。" % operation_index
			var minimum_quantity := 0 if op == "set" else 1
			var quantity_result := _read_integer(payload.get("quantity", null), minimum_quantity, INT32_MAX, "inventory_ops[%d].quantity" % operation_index)
			if not bool(quantity_result.ok):
				return str(quantity_result.error)
			var quantity := int(quantity_result.value)
			var item_index := _inventory_index(candidate.inventory, item_id)
			if op == "remove":
				if item_index < 0 or quantity > int(candidate.inventory[item_index].quantity):
					return "背包中没有足够的 %s，无法扣除 %d 件。" % [item_id, quantity]
				var display_name := str(candidate.inventory[item_index].name)
				candidate.inventory[item_index].quantity = int(candidate.inventory[item_index].quantity) - quantity
				if int(candidate.inventory[item_index].quantity) == 0:
					candidate.inventory.remove_at(item_index)
				changes.append("失去 %s x%d" % [display_name, quantity])
				continue

			var raw_name_bbcode := str(payload.get("name_bbcode", "")) if payload.get("name_bbcode") is String else ""
			var name := raw_name_bbcode
			if name.is_empty():
				name = str(payload.get("name", "")) if payload.get("name") is String else ""
			name = name.strip_edges()
			var description := str(payload.get("description_bbcode", "")) if payload.get("description_bbcode") is String else ""
			if _qt_text_length(name) > MAX_TEXT_UNITS or _qt_text_length(description) > MAX_TEXT_UNITS:
				return "inventory_ops[%d] 的文字过长。" % operation_index

			if op == "add":
				if item_index < 0:
					if name.is_empty():
						return "新物品 %s 必须提供 name。" % item_id
					candidate.inventory.append({"id": item_id, "name": name, "description_bbcode": description, "quantity": quantity})
					item_index = candidate.inventory.size() - 1
				else:
					var total_quantity := int(candidate.inventory[item_index].quantity) + quantity
					if total_quantity > INT32_MAX:
						return "物品 %s 数量溢出。" % item_id
					candidate.inventory[item_index].quantity = total_quantity
				changes.append("获得 %s x%d" % [str(candidate.inventory[item_index].name), quantity])
				continue

			if quantity == 0:
				if item_index >= 0:
					changes.append("移除 %s" % str(candidate.inventory[item_index].name))
					candidate.inventory.remove_at(item_index)
				continue
			if item_index < 0:
				if name.is_empty():
					return "新物品 %s 必须提供 name。" % item_id
				candidate.inventory.append({"id": item_id, "name": name, "description_bbcode": description, "quantity": quantity})
			else:
				candidate.inventory[item_index].quantity = quantity
				if not name.is_empty():
					candidate.inventory[item_index].name = name
				if payload.has("description_bbcode"):
					candidate.inventory[item_index].description_bbcode = description
			changes.append("设置 %s x%d" % [name if item_index < 0 else str(candidate.inventory[item_index].name), quantity])

	if patch.has("status_bbcode_set"):
		if not patch.status_bbcode_set is String or _qt_text_length(str(patch.status_bbcode_set)) > MAX_TEXT_UNITS:
			return "status_bbcode_set 必须是有效字符串。"
		if str(candidate.status_bbcode) != str(patch.status_bbcode_set):
			candidate.status_bbcode = str(patch.status_bbcode_set)
			changes.append("玩家状态已更新")

	if patch.has("map"):
		if not allow_map:
			changes.append("首轮地图保持空白")
		else:
			var map_error := _apply_map_patch(candidate.map, patch.map, changes)
			if not map_error.is_empty():
				return map_error

	if patch.has("ending"):
		if not allow_map or not patch.ending is Dictionary:
			return "初始场景不能结束故事，ending 必须是对象。"
		var ending_result := _normalized_terminal_ending(patch.ending)
		if not bool(ending_result.ok):
			return str(ending_result.error)
		candidate.ending = ending_result.value
		changes.append("故事终局：%s" % _ending_label(str(candidate.ending.type)))
	return ""


func _apply_map_patch(map_data: Dictionary, raw_patch: Variant, changes: Array[String]) -> String:
	if not raw_patch is Dictionary:
		return "map 必须是对象。"
	var patch: Dictionary = raw_patch
	var unknown := _unknown_key(patch, ["discover", "connect", "current"])
	if not unknown.is_empty():
		return "patch.map 包含未知字段 %s。" % unknown
	if patch.has("discover"):
		if not patch.discover is Array:
			return "map.discover 必须是数组。"
		for index in patch.discover.size():
			var node_result := _normalized_map_node(patch.discover[index], "map.discover[%d]" % index)
			if not bool(node_result.ok):
				return str(node_result.error)
			var node: Dictionary = node_result.value
			if _map_node_index(map_data.nodes, str(node.id)) >= 0 or _map_has_coordinate(map_data.nodes, int(node.x), int(node.y)):
				return "发现的地图节点 id 或坐标重复。"
			map_data.nodes.append(node)
			changes.append("地图发现：%s" % str(node.label))
	if patch.has("connect"):
		if not patch.connect is Array:
			return "map.connect 必须是数组。"
		for index in patch.connect.size():
			var edge_result := _normalized_map_edge(patch.connect[index], "map.connect[%d]" % index)
			if not bool(edge_result.ok):
				return str(edge_result.error)
			var edge: Dictionary = edge_result.value
			if _map_node_index(map_data.nodes, str(edge.from)) < 0 or _map_node_index(map_data.nodes, str(edge.to)) < 0:
				return "地图连线引用了未知节点。"
			if not _edge_exists(map_data.edges, str(edge.from), str(edge.to)):
				map_data.edges.append(edge)
				changes.append("地图连接：%s <-> %s" % [str(edge.from), str(edge.to)])
	if patch.has("current"):
		if not patch.current is String:
			return "map.current 必须是字符串。"
		var current := str(patch.current).strip_edges()
		if not current.is_empty() and _map_node_index(map_data.nodes, current) < 0:
			return "map.current 引用了未知节点。"
		map_data.current = current
		if not current.is_empty():
			changes.append("当前位置：%s" % current)
	return ""


func _normalized_saved_item(raw: Variant, index: int) -> Dictionary:
	if not raw is Dictionary:
		return {"ok": false, "error": "inventory[%d] 必须是对象。" % index}
	var item: Dictionary = raw
	if not item.get("id") is String or not item.get("name") is String:
		return {"ok": false, "error": "inventory[%d] 的 id/name 必须是字符串。" % index}
	var item_id := str(item.id).strip_edges()
	var name := str(item.name).strip_edges()
	if not _valid_identifier(item_id) or name.is_empty() or _qt_text_length(name) > MAX_TEXT_UNITS:
		return {"ok": false, "error": "inventory[%d] 的 id/name 无效。" % index}
	var description := ""
	if item.has("description_bbcode"):
		if not item.description_bbcode is String:
			return {"ok": false, "error": "inventory[%d].description_bbcode 必须是字符串。" % index}
		description = str(item.description_bbcode)
	if _qt_text_length(description) > MAX_TEXT_UNITS:
		return {"ok": false, "error": "inventory[%d] 的物品描述过长。" % index}
	var quantity_result := _read_integer(item.get("quantity", null), 0, INT32_MAX, "inventory[%d].quantity" % index)
	if not bool(quantity_result.ok):
		return quantity_result
	return {"ok": true, "error": "", "value": {"id": item_id, "name": name, "description_bbcode": description, "quantity": int(quantity_result.value)}}


func _normalized_saved_map(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {"ok": false, "error": "地图必须是对象。"}
	var map_value: Dictionary = raw
	if not map_value.get("nodes") is Array or not map_value.get("edges") is Array:
		return {"ok": false, "error": "地图 nodes/edges 必须是数组。"}
	var nodes: Array[Dictionary] = []
	for index in map_value.nodes.size():
		var node_result := _normalized_map_node(map_value.nodes[index], "nodes[%d]" % index)
		if not bool(node_result.ok):
			return node_result
		var node: Dictionary = node_result.value
		if _map_node_index(nodes, str(node.id)) >= 0 or _map_has_coordinate(nodes, int(node.x), int(node.y)):
			return {"ok": false, "error": "地图节点 id 或坐标重复。"}
		nodes.append(node)
	var edges: Array[Dictionary] = []
	for index in map_value.edges.size():
		var edge_result := _normalized_map_edge(map_value.edges[index], "edges[%d]" % index)
		if not bool(edge_result.ok):
			return edge_result
		var edge: Dictionary = edge_result.value
		if _map_node_index(nodes, str(edge.from)) < 0 or _map_node_index(nodes, str(edge.to)) < 0:
			return {"ok": false, "error": "地图连线引用了未知节点。"}
		if not _edge_exists(edges, str(edge.from), str(edge.to)):
			edges.append(edge)
	var current := ""
	if map_value.has("current"):
		if not map_value.current is String:
			return {"ok": false, "error": "current 必须是字符串。"}
		current = str(map_value.current)
	if not current.is_empty() and _map_node_index(nodes, current) < 0:
		return {"ok": false, "error": "当前地图节点不存在。"}
	return {"ok": true, "error": "", "value": {"nodes": nodes, "edges": edges, "current": current}}


func _normalized_map_node(raw: Variant, scope: String) -> Dictionary:
	if not raw is Dictionary:
		return {"ok": false, "error": "%s 必须是对象。" % scope}
	var node: Dictionary = raw
	if not node.get("id") is String or not node.get("label") is String:
		return {"ok": false, "error": "%s 的 id/label 必须是字符串。" % scope}
	var node_id := str(node.id).strip_edges()
	var label := str(node.label).strip_edges()
	if not _valid_identifier(node_id) or label.is_empty() or _qt_text_length(label) > MAX_TEXT_UNITS:
		return {"ok": false, "error": "%s 的 id/label 无效。" % scope}
	var symbol := "o"
	if node.has("symbol"):
		if not node.symbol is String:
			return {"ok": false, "error": "%s.symbol 必须是字符串。" % scope}
		symbol = str(node.symbol)
	if not _valid_map_symbol(symbol):
		return {"ok": false, "error": "%s.symbol 必须是单个可见 ASCII 字符。" % scope}
	var x_result := _read_integer(node.get("x", null), -MAX_COORDINATE, MAX_COORDINATE, "%s.x" % scope)
	if not bool(x_result.ok):
		return x_result
	var y_result := _read_integer(node.get("y", null), -MAX_COORDINATE, MAX_COORDINATE, "%s.y" % scope)
	if not bool(y_result.ok):
		return y_result
	return {"ok": true, "error": "", "value": {"id": node_id, "label": label, "symbol": symbol, "x": int(x_result.value), "y": int(y_result.value)}}


func _normalized_map_edge(raw: Variant, scope: String) -> Dictionary:
	if not raw is Dictionary:
		return {"ok": false, "error": "%s 必须是对象。" % scope}
	var edge: Dictionary = raw
	if not edge.get("from") is String or not edge.get("to") is String:
		return {"ok": false, "error": "%s 的 from/to 必须是字符串。" % scope}
	var from_id := str(edge.get("from", "")).strip_edges()
	var to_id := str(edge.get("to", "")).strip_edges()
	if not _valid_identifier(from_id) or not _valid_identifier(to_id) or from_id == to_id:
		return {"ok": false, "error": "%s 的 from/to 无效。" % scope}
	return {"ok": true, "error": "", "value": {"from": from_id, "to": to_id}}


func _normalized_terminal_ending(raw: Dictionary) -> Dictionary:
	var unknown := _unknown_key(raw, ["type", "title", "summary_bbcode"])
	if not unknown.is_empty():
		return {"ok": false, "error": "ending 包含未知字段 %s。" % unknown}
	var ending_type := str(raw.get("type", "")).strip_edges().to_lower() if raw.get("type") is String else ""
	var title := str(raw.get("title", "")).strip_edges() if raw.get("title") is String else ""
	var summary := str(raw.get("summary_bbcode", "")).strip_edges() if raw.get("summary_bbcode") is String else ""
	if ending_type not in TERMINAL_ENDING_TYPES:
		return {"ok": false, "error": "ending.type 必须是 survival/escape/missing/contamination/special。"}
	if title.is_empty() or _qt_text_length(title) > 120 or summary.is_empty() or _qt_text_length(summary) > MAX_TEXT_UNITS:
		return {"ok": false, "error": "ending 必须包含有效的 title 与 summary_bbcode。"}
	return {"ok": true, "error": "", "value": {"type": ending_type, "title": title, "summary_bbcode": summary}}


func _inventory_payload(operation: Dictionary) -> Dictionary:
	var payload: Dictionary = operation.item.duplicate(true) if operation.get("item") is Dictionary else {}
	for key in ["id", "name", "name_bbcode", "description_bbcode", "quantity"]:
		if operation.has(key):
			payload[key] = operation[key]
	return payload


func _read_integer(value: Variant, minimum: int, maximum: int, field: String) -> Dictionary:
	if value is int:
		var integer_value := int(value)
		if integer_value < minimum or integer_value > maximum:
			return {"ok": false, "error": "%s 必须是 %d..%d 范围内的整数。" % [field, minimum, maximum]}
		return {"ok": true, "error": "", "value": integer_value}
	if value is float:
		var number := float(value)
		if not is_finite(number) or floor(number) != number or number < float(minimum) or number > float(maximum):
			return {"ok": false, "error": "%s 必须是 %d..%d 范围内的整数。" % [field, minimum, maximum]}
		return {"ok": true, "error": "", "value": int(number)}
	return {"ok": false, "error": "%s 必须是整数。" % field}


func _valid_identifier(value: String) -> bool:
	if value.is_empty() or _qt_text_length(value) > MAX_IDENTIFIER_UNITS:
		return false
	for index in value.length():
		var code := value.unicode_at(index)
		if code < 0x20 or (code >= 0x7f and code <= 0x9f) or String.chr(code).strip_edges().is_empty():
			return false
	return true


func _valid_map_symbol(value: String) -> bool:
	if value.length() != 1:
		return false
	var code := value.unicode_at(0)
	return code >= 0x21 and code <= 0x7e and value not in ["[", "]"]


func _qt_text_length(value: String) -> int:
	return int(value.to_utf16_buffer().size() / 2)


func _inventory_index(inventory: Array, item_id: String) -> int:
	for index in inventory.size():
		if str(inventory[index].get("id", "")) == item_id:
			return index
	return -1


func _map_node_index(nodes: Array, node_id: String) -> int:
	for index in nodes.size():
		if str(nodes[index].get("id", "")) == node_id:
			return index
	return -1


func _map_has_coordinate(nodes: Array, x: int, y: int) -> bool:
	for node in nodes:
		if int(node.get("x", 0)) == x and int(node.get("y", 0)) == y:
			return true
	return false


func _edge_exists(edges: Array, from_id: String, to_id: String) -> bool:
	for edge in edges:
		if (str(edge.get("from", "")) == from_id and str(edge.get("to", "")) == to_id) or (str(edge.get("from", "")) == to_id and str(edge.get("to", "")) == from_id):
			return true
	return false


func _put_map_connector(grid: Array, x: int, y: int, width: int, height: int, symbol: String) -> void:
	if x < 0 or y < 0 or x >= width or y >= height:
		return
	var cell := str(grid[y][x])
	if cell == " ":
		grid[y][x] = symbol
	elif cell != symbol:
		grid[y][x] = "+"


func _unknown_key(value: Dictionary, allowed: Array) -> String:
	for key in value:
		if str(key) not in allowed:
			return str(key)
	return ""


func _ending_label(ending_type: String) -> String:
	return {"survival": "存活结局", "escape": "逃脱结局", "missing": "失踪结局", "contamination": "污染结局", "special": "特殊结局"}.get(ending_type, "尚未结束")
