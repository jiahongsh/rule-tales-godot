class_name AiGateway
extends Node

signal completed(request_id: int, content: String, raw_response: Dictionary)
signal failed(request_id: int, message: String, detail: String)

const MAX_RESPONSE_BYTES := 8 * 1024 * 1024

var _http: HTTPRequest
var _active_id := 0


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.name = "TurnRequest"
	_http.timeout = 120.0
	_http.use_threads = true
	_http.body_size_limit = MAX_RESPONSE_BYTES
	_http.accept_gzip = true
	# Bearer credentials must never be replayed to a redirect target. The caller
	# must provide the final OpenAI-compatible endpoint explicitly.
	_http.max_redirects = 0
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


func _exit_tree() -> void:
	cancel_active()


func send_chat(request_id: int, url: String, api_key: String, model: String, messages: Array, temperature: float, max_tokens: int) -> Error:
	if _active_id != 0:
		return ERR_BUSY
	if not _allowed_url(url):
		return ERR_INVALID_PARAMETER
	var payload := {
		"model": model,
		"messages": messages,
		"temperature": temperature,
		"max_tokens": max_tokens,
		"stream": false,
		"response_format": {"type": "json_object"}
	}
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json",
		"Authorization: Bearer %s" % api_key
	])
	_active_id = request_id
	var error := _http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		_active_id = 0
	return error


func cancel_active() -> void:
	if _active_id != 0:
		_http.cancel_request()
		_active_id = 0


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var request_id := _active_id
	_active_id = 0
	if request_id == 0:
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		failed.emit(request_id, "AI 请求未完成。", "网络结果：%d" % result)
		return
	if response_code < 200 or response_code >= 300:
		failed.emit(request_id, "AI 接口返回错误。", "HTTP %d：%s" % [response_code, body.get_string_from_utf8().left(1000)])
		return
	var parser := JSON.new()
	var parse_error := parser.parse(body.get_string_from_utf8())
	if parse_error != OK or not parser.data is Dictionary:
		failed.emit(request_id, "AI 响应不是有效 JSON。", "第 %d 行：%s" % [parser.get_error_line(), parser.get_error_message()])
		return
	var response: Dictionary = parser.data
	var choices: Array = response.get("choices", [])
	if choices.is_empty() or not choices[0] is Dictionary:
		failed.emit(request_id, "AI 响应缺少 choices。", JSON.stringify(response).left(1000))
		return
	var message: Dictionary = choices[0].get("message", {})
	var content := str(message.get("content", "")).strip_edges()
	if content.is_empty():
		failed.emit(request_id, "AI 响应内容为空。", "请检查模型名称及接口兼容性。")
		return
	completed.emit(request_id, content, response)


func _allowed_url(url: String) -> bool:
	var lowered := url.strip_edges().to_lower()
	if lowered.begins_with("https://"):
		return true
	return lowered == "http://127.0.0.1" \
		or lowered.begins_with("http://127.0.0.1:") \
		or lowered.begins_with("http://127.0.0.1/") \
		or lowered == "http://localhost" \
		or lowered.begins_with("http://localhost:") \
		or lowered.begins_with("http://localhost/")
