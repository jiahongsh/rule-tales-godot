@tool
class_name DreadTextEffect
extends RichTextEffect

var bbcode := "dread"


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var reduced := false
	var intensity := 65.0
	if Engine.get_main_loop() is SceneTree:
		var settings := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("AppSettings")
		if settings != null:
			reduced = bool(settings.reduced_motion) or int(settings.horror_level) <= 0
			intensity = float(settings.shake_intensity)
	if reduced:
		return true
	var strength := clampf(float(char_fx.env.get("strength", 1.0)), 0.0, 1.0)
	var amplitude := 3.4 * strength * intensity / 100.0
	var index := char_fx.relative_index
	var slow_wave := sin(char_fx.elapsed_time * 2.15 + index * 0.73)
	var irregular := sin(char_fx.elapsed_time * 3.37 + index * 1.91) * 0.42
	var tremor_gate := pow(maxf(0.0, sin(char_fx.elapsed_time * 0.83 + index * 0.035)), 5.0)
	char_fx.offset.x += (slow_wave + irregular) * amplitude * (0.22 + tremor_gate * 0.55)
	char_fx.offset.y += sin(char_fx.elapsed_time * 1.71 + index * 1.23) * amplitude * (0.13 + tremor_gate * 0.38)
	return true
