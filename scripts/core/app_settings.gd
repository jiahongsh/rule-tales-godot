extends Node

signal settings_changed

const SETTINGS_PATH := "user://settings.cfg"
const WINDOW_SIZES := [
	Vector2i(960, 600),
	Vector2i(1280, 720),
	Vector2i(1440, 810),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
]
const FRAME_RATE_LIMITS := [30, 60, 120, 144, 0]
const WINDOW_MODE_IDS := ["windowed", "borderless_fullscreen"]

var provider: String = "offline"
var endpoint: String = "https://api.deepseek.com"
var model: String = "deepseek-v4-flash"
var api_key: String = "" # Process memory only. Never persisted.
var recent_count: int = 15
var relevant_count: int = 5
var temperature: float = 0.85
var max_tokens: int = 1800
var text_scale: int = 100
var horror_level: int = 2
var shake_intensity: int = 65
var reduced_motion: bool = false
var high_contrast: bool = false
var choice_hints: bool = true
var confirm_risky: bool = false
var auto_scroll: bool = true
var sound_enabled: bool = true
var master_volume: int = 38
var effects_mix: int = 85
var ambience_mix: int = 65
var debug_observer: bool = false
var window_width: int = 1440
var window_height: int = 810
var max_fps: int = 60
var window_mode: String = "windowed"
var _display_apply_serial := 0


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	provider = _string_value(config, "ai", "provider", provider)
	endpoint = _string_value(config, "ai", "endpoint", endpoint)
	model = _string_value(config, "ai", "model", model)
	recent_count = clampi(int(config.get_value("context", "recent", recent_count)), 1, 60)
	relevant_count = clampi(int(config.get_value("context", "relevant", relevant_count)), 0, 30)
	temperature = clampf(float(config.get_value("generation", "temperature", temperature)), 0.0, 2.0)
	max_tokens = clampi(int(config.get_value("generation", "max_tokens", max_tokens)), 256, 8192)
	text_scale = clampi(int(config.get_value("display", "text_scale", text_scale)), 90, 130)
	horror_level = clampi(int(config.get_value("display", "horror_level", horror_level)), 0, 2)
	shake_intensity = clampi(int(config.get_value("display", "shake_intensity", shake_intensity)), 0, 100)
	reduced_motion = bool(config.get_value("display", "reduced_motion", reduced_motion))
	high_contrast = bool(config.get_value("display", "high_contrast", high_contrast))
	choice_hints = bool(config.get_value("gameplay", "choice_hints", choice_hints))
	confirm_risky = bool(config.get_value("gameplay", "confirm_risky", confirm_risky))
	auto_scroll = bool(config.get_value("gameplay", "auto_scroll", auto_scroll))
	sound_enabled = bool(config.get_value("audio", "enabled", sound_enabled))
	master_volume = clampi(int(config.get_value("audio", "master", master_volume)), 0, 100)
	effects_mix = clampi(int(config.get_value("audio", "effects_mix", effects_mix)), 0, 100)
	ambience_mix = clampi(int(config.get_value("audio", "ambience_mix", ambience_mix)), 0, 100)
	debug_observer = bool(config.get_value("developer", "debug_observer", debug_observer))
	var stored_window_size := Vector2i(
		int(config.get_value("display", "window_width", window_width)),
		int(config.get_value("display", "window_height", window_height)))
	if stored_window_size in WINDOW_SIZES:
		window_width = stored_window_size.x
		window_height = stored_window_size.y
	var stored_max_fps := int(config.get_value("display", "max_fps", max_fps))
	if stored_max_fps in FRAME_RATE_LIMITS:
		max_fps = stored_max_fps
	var stored_window_mode := str(config.get_value("display", "window_mode", window_mode))
	if stored_window_mode in WINDOW_MODE_IDS:
		window_mode = stored_window_mode


func save_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value("ai", "provider", provider)
	config.set_value("ai", "endpoint", endpoint)
	config.set_value("ai", "model", model)
	# api_key is deliberately absent.
	config.set_value("context", "recent", recent_count)
	config.set_value("context", "relevant", relevant_count)
	config.set_value("generation", "temperature", temperature)
	config.set_value("generation", "max_tokens", max_tokens)
	config.set_value("display", "text_scale", text_scale)
	config.set_value("display", "horror_level", horror_level)
	config.set_value("display", "shake_intensity", shake_intensity)
	config.set_value("display", "reduced_motion", reduced_motion)
	config.set_value("display", "high_contrast", high_contrast)
	config.set_value("gameplay", "choice_hints", choice_hints)
	config.set_value("gameplay", "confirm_risky", confirm_risky)
	config.set_value("gameplay", "auto_scroll", auto_scroll)
	config.set_value("audio", "enabled", sound_enabled)
	config.set_value("audio", "master", master_volume)
	config.set_value("audio", "effects_mix", effects_mix)
	config.set_value("audio", "ambience_mix", ambience_mix)
	config.set_value("developer", "debug_observer", debug_observer)
	config.set_value("display", "window_width", window_width)
	config.set_value("display", "window_height", window_height)
	config.set_value("display", "max_fps", max_fps)
	config.set_value("display", "window_mode", window_mode)
	var error := config.save(SETTINGS_PATH)
	if error == OK:
		settings_changed.emit()
	return error


func can_apply_window_changes() -> bool:
	return not Engine.is_embedded_in_editor()


func apply_runtime_display() -> bool:
	Engine.max_fps = max_fps
	# Godot's embedded game view owns the host window and explicitly does not
	# support window mode changes. Keep the saved choice for the next standalone
	# run, while still applying the frame-rate limit above.
	if not can_apply_window_changes():
		return false
	var root_window := get_tree().root
	root_window.unresizable = true
	_display_apply_serial += 1
	var serial := _display_apply_serial
	if window_mode == "borderless_fullscreen":
		root_window.mode = Window.MODE_FULLSCREEN
		return true
	root_window.mode = Window.MODE_WINDOWED
	var target_size := Vector2i(window_width, window_height)
	if target_size not in WINDOW_SIZES:
		target_size = Vector2i(1440, 810)
	_apply_windowed_size.call_deferred(target_size, serial)
	return true


func _apply_windowed_size(target_size: Vector2i, serial: int) -> void:
	# Native window managers restore the previous maximized/fullscreen geometry
	# asynchronously. Wait until the mode transition has settled before applying
	# the user-selected physical size.
	await get_tree().process_frame
	if serial != _display_apply_serial or window_mode != "windowed":
		return
	var root_window := get_tree().root
	root_window.size = target_size
	root_window.move_to_center()
	await get_tree().process_frame
	if serial == _display_apply_serial and window_mode == "windowed" and root_window.size != target_size:
		root_window.size = target_size
		root_window.move_to_center()


func has_live_ai() -> bool:
	return provider != "offline" and not api_key.strip_edges().is_empty() \
		and not model.strip_edges().is_empty() and _allowed_endpoint(endpoint)


func chat_url() -> String:
	var base := endpoint.strip_edges().trim_suffix("/")
	if base.ends_with("/chat/completions"):
		return base
	if base.ends_with("/v1"):
		return base + "/chat/completions"
	return base + "/v1/chat/completions"


func apply_preset(index: int) -> void:
	match index:
		0: # Balanced
			text_scale = 100; horror_level = 2; shake_intensity = 65
			reduced_motion = false; high_contrast = false; sound_enabled = true
			master_volume = 38; effects_mix = 85; ambience_mix = 65
		1: # Reading comfort
			text_scale = 115; horror_level = 1; shake_intensity = 25
			reduced_motion = true; high_contrast = true; sound_enabled = true
			master_volume = 28; effects_mix = 70; ambience_mix = 35
		2: # Immersive horror
			text_scale = 100; horror_level = 2; shake_intensity = 82
			reduced_motion = false; high_contrast = false; sound_enabled = true
			master_volume = 48; effects_mix = 92; ambience_mix = 82
		3: # Silent focus
			text_scale = 115; horror_level = 1; shake_intensity = 20
			reduced_motion = true; high_contrast = false; sound_enabled = false
	settings_changed.emit()


func _allowed_endpoint(value: String) -> bool:
	var lowered := value.strip_edges().to_lower()
	return lowered.begins_with("https://") or lowered.begins_with("http://127.0.0.1") \
		or lowered.begins_with("http://localhost")


func _string_value(config: ConfigFile, section: String, key: String, fallback: String) -> String:
	var value := str(config.get_value(section, key, fallback)).strip_edges()
	return fallback if value.is_empty() else value
