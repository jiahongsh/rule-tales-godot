extends Node

const MainScene := preload("res://scenes/main.tscn")
const SettingsDialog := preload("res://scripts/ui/settings_dialog.gd")
const SaveDialog := preload("res://scripts/ui/save_manager_dialog.gd")
const WorkshopDialog := preload("res://scripts/ui/rule_workshop.gd")
const SeedRunDialog := preload("res://scripts/ui/seed_run_dialog.gd")


func _ready() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var mode := "lobby"
	var output := "res://artifacts/godot-lobby.png"
	var requested_window_size := Vector2i.ZERO
	var requested_window_mode := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--mode="): mode = argument.trim_prefix("--mode=")
		elif argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		elif argument.begins_with("--window-size="):
			var parts := argument.trim_prefix("--window-size=").split("x", false, 1)
			if parts.size() == 2:
				requested_window_size = Vector2i(int(parts[0]), int(parts[1]))
		elif argument.begins_with("--window-mode="):
			requested_window_mode = argument.trim_prefix("--window-mode=")
	if requested_window_size in AppSettings.WINDOW_SIZES:
		AppSettings.window_width = requested_window_size.x
		AppSettings.window_height = requested_window_size.y
	if requested_window_mode in AppSettings.WINDOW_MODE_IDS:
		AppSettings.window_mode = requested_window_mode
	get_tree().root.gui_embed_subwindows = true
	var main := MainScene.instantiate(); get_tree().root.add_child(main)
	if mode == "loading":
		await get_tree().process_frame
	else:
		while not main._startup_complete:
			await get_tree().process_frame
	print("WINDOW_STATE:size=%dx%d mode=%d unresizable=%s max_fps=%d" % [get_tree().root.size.x, get_tree().root.size.y, get_tree().root.mode, str(get_tree().root.unresizable), Engine.max_fps])
	if mode == "quit_confirmation":
		main._request_quit()
	elif mode == "prewarmed_dialog_timings":
		var openers := [
			{"label": "settings", "callable": Callable(main, "_show_settings"), "dialog": main._settings_dialog},
			{"label": "saves", "callable": Callable(main, "_show_saves"), "dialog": main._save_dialog},
			{"label": "workshop", "callable": Callable(main, "_show_workshop"), "dialog": main._workshop_dialog},
			{"label": "seed", "callable": Callable(main, "_show_seed_run"), "dialog": main._seed_run_dialog},
		]
		for spec in openers:
			var start_usec := Time.get_ticks_usec()
			spec.callable.call()
			var opened_usec := Time.get_ticks_usec()
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var drawn_usec := Time.get_ticks_usec()
			print("PREWARMED_DIALOG_TIMING:%s:open=%.2fms first_draw=%.2fms total=%.2fms" % [
				spec.label,
				(opened_usec - start_usec) / 1000.0,
				(drawn_usec - opened_usec) / 1000.0,
				(drawn_usec - start_usec) / 1000.0,
			])
			spec.dialog.hide()
	elif mode == "dialog_timings":
		var dialog_specs := [
			{"label": "settings", "script": SettingsDialog},
			{"label": "saves", "script": SaveDialog},
			{"label": "workshop", "script": WorkshopDialog},
			{"label": "seed", "script": SeedRunDialog},
		]
		for spec in dialog_specs:
			var start_usec := Time.get_ticks_usec()
			var dialog: Variant = spec.script.new()
			var instantiated_usec := Time.get_ticks_usec()
			main.add_child(dialog)
			var added_usec := Time.get_ticks_usec()
			dialog.open_dialog()
			var opened_usec := Time.get_ticks_usec()
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var drawn_usec := Time.get_ticks_usec()
			print("DIALOG_TIMING:%s:new=%.2fms add=%.2fms open=%.2fms first_draw=%.2fms total=%.2fms" % [
				spec.label,
				(instantiated_usec - start_usec) / 1000.0,
				(added_usec - instantiated_usec) / 1000.0,
				(opened_usec - added_usec) / 1000.0,
				(drawn_usec - opened_usec) / 1000.0,
				(drawn_usec - start_usec) / 1000.0,
			])
			dialog.hide()
			dialog.free()
	elif mode == "selection":
		main.lobby.show_selection()
	elif mode.begins_with("game"):
		# Follow the same signal path as a real menu click so GameView is created
		# before the initial turn writes its autosave and thumbnail.
		main.lobby.offline_requested.emit()
		if mode in ["game_busy", "game_cancelled"]:
			await get_tree().process_frame
		else:
			await get_tree().create_timer(0.65).timeout
		if main.game_view == null or GameSession.rules.is_empty():
			push_error("VISUAL_CAPTURE_START_FAILED"); get_tree().quit(1); return
		if mode == "game_cancelled":
			GameSession.cancel_generation()
			await get_tree().process_frame
		if mode == "game_map":
			GameSession.submit_action("进入档案室，调查走廊尽头的门牌")
			await get_tree().create_timer(0.65).timeout
		if mode == "game_debug": AppSettings.debug_observer = true
		if mode == "game_inventory": main.game_view._show_context(1)
		elif mode == "game_map": main.game_view._show_context(3)
		elif mode == "game_debug": main.game_view._show_context(5)
		if mode == "game_debug": print("DEBUG_TEXT:", main.game_view._debug_text.text)
	elif mode in ["settings", "settings_display", "settings_embedded_notice", "settings_apply_windowed", "workshop", "saves", "saves_auto", "seed"]:
		var dialog: Variant
		if mode in ["settings", "settings_display", "settings_embedded_notice", "settings_apply_windowed"]: dialog = SettingsDialog.new()
		elif mode == "workshop": dialog = WorkshopDialog.new()
		elif mode in ["saves", "saves_auto"]: dialog = SaveDialog.new()
		else: dialog = SeedRunDialog.new()
		main.add_child(dialog); dialog.open_dialog()
		if mode in ["settings_display", "settings_embedded_notice"]:
			dialog._show_page(3)
		if mode == "settings_embedded_notice":
			dialog.find_child("EmbeddedDisplayNotice", true, false).visible = true
		if mode == "settings_apply_windowed":
			dialog._select_provider("offline")
			var mode_option := dialog.find_child("WindowModeOption", true, false) as OptionButton
			var size_option := dialog.find_child("WindowSizeOption", true, false) as OptionButton
			mode_option.select(0)
			size_option.select(0)
			dialog._apply_and_close()
			await get_tree().process_frame
			await get_tree().process_frame
			print("SETTINGS_APPLY_STATE:size=%dx%d mode=%d" % [get_tree().root.size.x, get_tree().root.size.y, get_tree().root.mode])
		if mode == "saves_auto":
			dialog._show_page(1)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output).get_base_dir())
	var image := get_tree().root.get_texture().get_image()
	var error := image.save_png(output)
	print("VISUAL_CAPTURE:", mode, ":", image.get_width(), "x", image.get_height(), ":", error)
	get_tree().quit(0 if error == OK else 1)
