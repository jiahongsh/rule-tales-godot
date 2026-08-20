class_name RuleDocumentData
extends RefCounted

const MAXIMUM_RULE_BYTES := 512 * 1024

var chapters: Array[Dictionary] = []
var source_path: String = ""


static func from_text(text: String, untitled_title: String = "全文") -> RuleDocumentData:
	var document := RuleDocumentData.new()
	var normalized := text.trim_prefix("\uFEFF").replace("\r\n", "\n").replace("\r", "\n")
	normalized = normalized.replace("\u2028", "\n").replace("\u2029", "\n")
	var marker := RegEx.new()
	marker.compile("^\\s*<([^<>\\r\\n]+)>\\s*$")
	var pending: Array[String] = []
	var current_title := ""
	var saw_marker := false
	for raw_line in normalized.split("\n", true):
		var line := str(raw_line)
		var match := marker.search(line)
		if match == null:
			pending.append(line)
			continue
		var new_title := match.get_string(1).strip_edges()
		if new_title.is_empty():
			pending.append(line)
			continue
		if not saw_marker:
			document._append_chapter("前言", pending, false)
		else:
			document._append_chapter(current_title, pending, true)
		pending.clear()
		current_title = new_title
		saw_marker = true
	if saw_marker:
		document._append_chapter(current_title, pending, true)
	else:
		document._append_chapter(untitled_title.strip_edges() if not untitled_title.strip_edges().is_empty() else "全文", pending, false)
	return document


static func from_file_path(path: String) -> Dictionary:
	var result := {"document": null, "error": ""}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		result.error = "无法打开规则文件：%s" % error_string(FileAccess.get_open_error())
		return result
	var length := file.get_length()
	if length <= 0 or length > MAXIMUM_RULE_BYTES:
		result.error = "规则文件为空或超过 512 KB。请拆分过长档案后再导入。"
		return result
	var bytes := file.get_buffer(length)
	file.close()
	var text := ""
	if bytes.size() >= 3 and bytes[0] == 0xEF and bytes[1] == 0xBB and bytes[2] == 0xBF:
		text = bytes.slice(3).get_string_from_utf8()
	elif bytes.size() >= 2 and bytes[0] == 0xFF and bytes[1] == 0xFE:
		text = bytes.slice(2).get_string_from_utf16()
	else:
		text = bytes.get_string_from_utf8()
	var document := from_text(text)
	document.source_path = path
	if document.is_empty():
		result.error = "文档中没有可读取的文字。"
		return result
	result.document = document
	return result


func is_empty() -> bool:
	return chapters.is_empty()


func joined_text() -> String:
	var sections: Array[String] = []
	for chapter in chapters:
		sections.append("<%s>\n%s" % [chapter.title, chapter.content])
	return "\n\n".join(sections)


func _append_chapter(title: String, raw_lines: Array[String], keep_empty: bool) -> void:
	var first := 0
	while first < raw_lines.size() and raw_lines[first].strip_edges().is_empty():
		first += 1
	var last := raw_lines.size()
	while last > first and raw_lines[last - 1].strip_edges().is_empty():
		last -= 1
	var kept: Array[String] = []
	for index in range(first, last):
		kept.append(raw_lines[index])
	var content := "\n".join(kept)
	if keep_empty or not content.is_empty():
		chapters.append({"title": title, "content": content})
