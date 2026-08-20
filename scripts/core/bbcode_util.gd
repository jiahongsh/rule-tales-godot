class_name SafeBBCode
extends RefCounted

const SIMPLE_TAGS := {
	"b": true, "i": true, "u": true, "s": true, "center": true,
	"code": true, "indent": true, "blood": true, "dread": true,
	"font_size": true, "color": true, "bgcolor": true
}


static func prepare(input: String, allow_motion: bool = true) -> String:
	var text := input.replace("\r\n", "\n").replace("\r", "\n")
	text = text.replace("[quote]", "[indent][color=#9d8d7b]")
	text = text.replace("[/quote]", "[/color][/indent]")
	text = text.replace("[spoiler]", "[bgcolor=#171311][color=#786b60]")
	text = text.replace("[/spoiler]", "[/color][/bgcolor]")
	if allow_motion:
		text = text.replace("[shake]", "[dread strength=1.0]").replace("[/shake]", "[/dread]")
	else:
		text = text.replace("[shake]", "").replace("[/shake]", "")
	text = text.replace("[br]", "\n")
	return _whitelist(text, allow_motion)


static func plain_text(input: String) -> String:
	var regex := RegEx.new()
	regex.compile("\\[[^\\]]*\\]")
	return regex.sub(input, "", true).replace("\r", "")


static func _whitelist(text: String, allow_motion: bool) -> String:
	var regex := RegEx.new()
	regex.compile("\\[(/?)([A-Za-z0-9_]+)([^\\]]*)\\]")
	var matches := regex.search_all(text)
	if matches.is_empty():
		return text
	var output := ""
	var cursor := 0
	for match in matches:
		output += text.substr(cursor, match.get_start() - cursor)
		var closing := match.get_string(1) == "/"
		var tag := match.get_string(2).to_lower()
		var suffix := match.get_string(3)
		var accepted := SIMPLE_TAGS.has(tag)
		if tag == "dread" and not allow_motion:
			accepted = false
		if accepted and _safe_suffix(tag, suffix, closing):
			output += match.get_string(0)
		elif tag == "dread" and not allow_motion:
			pass
		else:
			output += "［" + match.get_string(0).trim_prefix("[")
		cursor = match.get_end()
	output += text.substr(cursor)
	return output


static func _safe_suffix(tag: String, suffix: String, closing: bool) -> bool:
	if closing:
		return suffix.strip_edges().is_empty()
	var trimmed := suffix.strip_edges()
	if trimmed.is_empty():
		return true
	if tag in ["color", "bgcolor"]:
		var regex := RegEx.new(); regex.compile("^=#[0-9A-Fa-f]{6,8}$")
		return regex.search(trimmed) != null
	if tag == "font_size":
		var regex := RegEx.new(); regex.compile("^=(?:1[0-9]|2[0-8])$")
		return regex.search(trimmed) != null
	if tag == "dread":
		var regex := RegEx.new(); regex.compile("^(?:strength=(?:0(?:\\.[0-9]+)?|1(?:\\.0+)?))$")
		return regex.search(trimmed) != null
	return false
