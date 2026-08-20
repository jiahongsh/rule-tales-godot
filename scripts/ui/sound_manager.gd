class_name RuleTalesSoundManager
extends Node

const SFX_PATHS := {
	"click": "res://assets/audio/sfx/click.wav", "page": "res://assets/audio/sfx/page.wav",
	"commit": "res://assets/audio/sfx/commit.wav", "reveal": "res://assets/audio/sfx/reveal.wav",
	"danger": "res://assets/audio/sfx/danger.wav", "denied": "res://assets/audio/sfx/denied.wav",
	"item": "res://assets/audio/sfx/item.wav", "map": "res://assets/audio/sfx/map.wav",
	"damage": "res://assets/audio/sfx/damage.wav", "recover": "res://assets/audio/sfx/recover.wav",
	"ending_escape": "res://assets/audio/sfx/ending_escape.wav", "ending_lost": "res://assets/audio/sfx/ending_lost.wav"
}

var _sfx: AudioStreamPlayer
var _ambience: AudioStreamPlayer
var _audio_available := true


func _ready() -> void:
	_audio_available = AudioServer.get_driver_name() != "Dummy"
	_sfx = AudioStreamPlayer.new(); _sfx.name = "SFX"; _sfx.max_polyphony = 8; add_child(_sfx)
	_ambience = AudioStreamPlayer.new(); _ambience.name = "Ambience"; add_child(_ambience)
	AppSettings.settings_changed.connect(_apply_volume)
	_apply_volume()


func _exit_tree() -> void:
	# Explicitly release active playback before the node leaves the tree. This
	# also keeps headless test and editor shutdowns from retaining WAV playbacks.
	if _sfx != null:
		_sfx.stop()
		_sfx.stream = null
	if _ambience != null:
		_ambience.stop()
		_ambience.stream = null


func cue(name: String) -> void:
	if not _audio_available or not AppSettings.sound_enabled or not SFX_PATHS.has(name): return
	var stream := load(str(SFX_PATHS[name])) as AudioStream
	if stream == null: return
	_sfx.stream = stream
	_sfx.pitch_scale = 0.97 + randf() * 0.06
	_sfx.play()


func set_ambience(kind: String) -> void:
	if not _audio_available:
		return
	var path := "res://assets/audio/ambience/ambient_%s.wav" % kind
	if not ResourceLoader.exists(path): path = "res://assets/audio/ambience/ambient_drone.wav"
	var stream := load(path) as AudioStream
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(stream as AudioStreamWAV).loop_end = (stream as AudioStreamWAV).data.size() / 2
	_ambience.stream = stream
	if AppSettings.sound_enabled and stream != null: _ambience.play()


func _apply_volume() -> void:
	var master := clampf(AppSettings.master_volume / 100.0, 0.0, 1.0)
	_sfx.volume_linear = master * AppSettings.effects_mix / 100.0
	_ambience.volume_linear = master * AppSettings.ambience_mix / 100.0
	if not AppSettings.sound_enabled:
		_sfx.stop(); _ambience.stop()
	elif _audio_available and _ambience.stream != null and not _ambience.playing:
		_ambience.play()
