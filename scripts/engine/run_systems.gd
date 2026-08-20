class_name SeedRunSystems
extends RefCounted

const SeedRngScript := preload("res://scripts/generator/seed_rng.gd")
const _FALLBACK_LOCATIONS := ["走廊尽头", "楼梯间", "天台", "地下室", "一层大厅", "电梯间"]


static func days_left(state: RuleTalesGameState) -> int:
	if not bool(state.data.run_mode) or int(state.data.days_limit) <= 0:
		return 0
	return maxi(0, int(state.data.days_limit) - int(state.data.day) + 1)


static func is_timeout(state: RuleTalesGameState) -> bool:
	return bool(state.data.run_mode) and int(state.data.days_limit) > 0 and int(state.data.day) > int(state.data.days_limit) and not state.is_terminal()


static func timeout_ending() -> Dictionary:
	return {"type": "missing", "title": "期限耗尽的巡查记录", "summary_bbcode": "你在规则覆盖区内耗尽了全部期限。巡查记录显示你仍在走廊里行走，只是不再回应任何呼叫。档案将此案列为失踪。"}


static func route_choices(seed: int, locations: Array, day: int, days_limit: int) -> Dictionary:
	var mixed_seed := (seed ^ ((day * 2654435761) & 0xFFFFFFFF)) & 0xFFFFFFFF
	var rng := SeedRngScript.new(mixed_seed)
	var pool: Array = locations.duplicate() if not locations.is_empty() else _FALLBACK_LOCATIONS.duplicate()
	rng.shuffle(pool)
	var count := mini(pool.size(), 2 + rng.pick_index(2))
	var progress := clampf((day - 1) / float(days_limit - 1), 0.0, 1.0) if days_limit > 1 else 0.0
	var danger_percent := 15 + int(45.0 * progress)
	var options: Array[Dictionary] = []
	for index in range(count):
		var roll := rng.pick_index(100)
		var risk := "dangerous" if roll < danger_percent else ("uneasy" if roll < danger_percent + 35 else "calm")
		var hints: Array = _risk_hints(risk)
		options.append({"id": "route_d%d_%d" % [day, index], "label": str(pool[index]), "risk": risk, "risk_label": {"calm": "平静", "uneasy": "骚动", "dangerous": "凶险"}[risk], "hint_bbcode": str(hints[rng.pick_index(hints.size())])})
	return {"day": day, "options": options}


static func anomaly_for_night(seed: int, finished_day: int, templates: Array) -> Dictionary:
	if finished_day <= 0 or templates.is_empty():
		return {}
	var order: Array = range(templates.size())
	var order_rng := SeedRngScript.new((seed ^ 0xA17E4D39) & 0xFFFFFFFF)
	order_rng.shuffle(order)
	var source: Dictionary = templates[int(order[(finished_day - 1) % order.size()])]
	var state_seed := (seed ^ ((finished_day * 2654435761) & 0xFFFFFFFF) ^ 0x6C8E9CF5) & 0xFFFFFFFF
	var anomalous := SeedRngScript.new(state_seed).coin_flip()
	return {"round_id": "night_%d_%s" % [finished_day, str(source.id)], "anomaly_id": str(source.id), "title": str(source.title), "location": str(source.location), "observation_bbcode": str(source.anomalous if anomalous else source.normal), "reveal_bbcode": str(source.reveal), "finished_day": finished_day, "anomalous": anomalous}


static func award_for_run(ending_type: String, rating: String, discovered_ratio: float) -> int:
	var ending_base: int = int({"escape": 100, "special": 80, "survival": 60, "missing": 15, "contamination": 10}.get(ending_type, 0))
	var multiplier: float = float({"S": 1.5, "A": 1.2, "B": 1.0, "C": 0.8, "D": 0.6}.get(rating.strip_edges().to_upper(), 1.0))
	return roundi(ending_base * multiplier) + roundi(40.0 * clampf(discovered_ratio, 0.0, 1.0))


static func _risk_hints(risk: String) -> Array:
	match risk:
		"dangerous": return ["[i]有什么在那个方向等着你过去。[/i]", "[i]地面有拖拽的痕迹，方向单一。[/i]", "[i]你的登记卡突然变得冰凉。[/i]"]
		"uneasy": return ["[i]隐约有规律的滴水声，节奏不太对。[/i]", "[i]那个方向的灯比别处暗一档。[/i]", "[i]你闻到了铁锈味，很淡，但一直在。[/i]"]
		_: return ["[i]那边安静得反常，连呼吸声都显得多余。[/i]", "[i]灯光稳定，影子保持在脚下。[/i]", "[i]空气里有陈旧但干净的气味。[/i]"]
