extends SceneTree


func _initialize() -> void:
	var image := Image.create_empty(160, 90, false, Image.FORMAT_RGBA8)
	image.fill(Color("#261b16"))
	var save_path := RuleTalesSaveService.autosave_path(1)
	var result := RuleTalesSaveService.write_thumbnail_for_save(save_path, image)
	_expect(bool(result.get("ok", false)), "thumbnail write failed: %s" % str(result.get("error", "")))
	var thumbnail_path := RuleTalesSaveService.thumbnail_for_save(save_path)
	_expect(FileAccess.file_exists(thumbnail_path), "thumbnail file missing")
	var loaded := Image.load_from_file(thumbnail_path)
	_expect(not loaded.is_empty(), "thumbnail cannot be decoded")
	_expect(loaded.get_width() == 480 and loaded.get_height() == 270, "thumbnail dimensions are not 480x270")
	print("THUMBNAIL_SMOKE_OK")
	quit(0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("THUMBNAIL_SMOKE_FAILED: %s" % message)
	quit(1)
