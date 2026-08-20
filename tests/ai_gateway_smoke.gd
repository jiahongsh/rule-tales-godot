extends Node

var _failures: Array[String] = []
var _completed: Dictionary = {}
var _failed: Dictionary = {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var gateway := AiGateway.new()
	add_child(gateway)
	await get_tree().process_frame
	_expect(gateway._http.max_redirects == 0, "携带 Bearer Token 的请求必须禁用自动重定向。")
	_expect(gateway._allowed_url("https://api.deepseek.com/v1/chat/completions"), "HTTPS AI 地址应被允许。")
	_expect(gateway._allowed_url("http://127.0.0.1:8080/v1/chat/completions"), "本机回环调试地址应被允许。")
	_expect(not gateway._allowed_url("http://localhost.evil.example/v1/chat/completions"), "伪装成 localhost 的远程主机必须被拒绝。")
	_expect(not gateway._allowed_url("http://api.example.com/v1/chat/completions"), "远程明文 HTTP 必须被拒绝。")

	gateway.completed.connect(func(request_id: int, content: String, raw: Dictionary) -> void:
		_completed = {"id": request_id, "content": content, "raw": raw})
	gateway.failed.connect(func(request_id: int, message: String, detail: String) -> void:
		_failed = {"id": request_id, "message": message, "detail": detail})

	gateway._active_id = 41
	var response := {"choices": [{"message": {"content": "{\"ok\":true}"}}]}
	gateway._on_request_completed(
		HTTPRequest.RESULT_SUCCESS,
		200,
		PackedStringArray(),
		JSON.stringify(response).to_utf8_buffer())
	_expect(int(_completed.get("id", 0)) == 41 and str(_completed.get("content", "")) == "{\"ok\":true}", "有效 OpenAI 兼容响应应发出 completed。")

	_failed.clear()
	gateway._active_id = 42
	gateway._on_request_completed(
		HTTPRequest.RESULT_SUCCESS,
		401,
		PackedStringArray(),
		"{\"error\":\"invalid key\"}".to_utf8_buffer())
	_expect(int(_failed.get("id", 0)) == 42 and str(_failed.get("detail", "")).contains("HTTP 401"), "非 2xx 响应应保留请求 ID 与 HTTP 状态。")

	gateway.free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("AI_GATEWAY_SMOKE_OK")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("AI_GATEWAY_SMOKE_FAILED:%d" % _failures.size())
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
