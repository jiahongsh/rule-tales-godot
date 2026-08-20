@tool
class_name BloodTextEffect
extends RichTextEffect

var bbcode := "blood"


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var wet := (sin(char_fx.elapsed_time * 1.35 + char_fx.relative_index * 0.17) + 1.0) * 0.5
	wet = pow(wet, 3.2)
	var dry_color := Color("#681f27")
	var wet_color := Color("#a34045")
	char_fx.color = Color("#21090c") if char_fx.outline else dry_color.lerp(wet_color, wet * 0.58)
	return true
