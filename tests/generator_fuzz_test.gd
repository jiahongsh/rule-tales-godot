extends SceneTree

const RuleForgeScript := preload("res://scripts/generator/rule_forge.gd")


func _initialize() -> void:
	for seed in range(1000):
		var forged: Dictionary = RuleForgeScript.forge(seed)
		if not bool(forged.ok):
			push_error("GENERATOR_FUZZ_FAILED seed=%d error=%s" % [seed, str(forged.error)])
			quit(1)
			return
		var document := RuleDocumentData.from_text(str(forged.document_text))
		if document.chapters.size() < 5:
			push_error("GENERATOR_FUZZ_FAILED seed=%d chapters=%d" % [seed, document.chapters.size()])
			quit(1)
			return
		var false_count := 0
		var tamper_count := 0
		for rule in forged.rules:
			if str(rule.truth) == "false": false_count += 1
			if bool(rule.tamper_target):
				tamper_count += 1
				if str(rule.truth) != "true" or str(rule.tampered_text).is_empty():
					push_error("GENERATOR_FUZZ_FAILED seed=%d invalid_tamper" % seed)
					quit(1)
					return
		if tamper_count > 2:
			push_error("GENERATOR_FUZZ_FAILED seed=%d false=%d tamper=%d" % [seed, false_count, tamper_count])
			quit(1)
			return
	print("GENERATOR_FUZZ_OK:1000")
	quit(0)
