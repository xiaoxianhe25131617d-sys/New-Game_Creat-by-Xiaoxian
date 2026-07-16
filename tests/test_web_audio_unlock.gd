extends Node

var failures: Array[String] = []

func _ready() -> void:
	await _test_first_pressed_input_restarts_web_bgm()
	_test_every_view_bgm_uses_native_stream_looping()
	_test_switching_view_replaces_the_playing_bgm()
	if failures.is_empty():
		print("PASS: Web audio unlock checks")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)

func _test_first_pressed_input_restarts_web_bgm() -> void:
	var manager := load("res://scripts/audio_manager.gd").new() as Node
	add_child(manager)
	if not manager.has_method("_unlock_web_audio_from_input"):
		failures.append("Web audio must expose a first-input BGM unlock path")
		manager.free()
		return
	manager.set("_web_audio_requires_gesture", true)
	manager.set("_web_audio_unlocked", false)
	var bgm_player := manager.get("bgm_player") as AudioStreamPlayer
	bgm_player.stop()
	var key_event := InputEventKey.new()
	key_event.pressed = true
	manager.call("_input", key_event)
	await get_tree().process_frame
	if not bool(manager.get("_web_audio_unlocked")):
		failures.append("The first pressed Web input must unlock audio")
	if not bgm_player.playing:
		failures.append("The first pressed Web input must restart the selected BGM")
	manager.free()

func _test_every_view_bgm_uses_native_stream_looping() -> void:
	var manager := load("res://scripts/audio_manager.gd").new() as Node
	add_child(manager)
	var bgm_cache := manager.get("bgm_cache") as Dictionary
	for view_name in bgm_cache:
		var stream := bgm_cache.get(view_name) as AudioStreamMP3
		if stream == null or not stream.loop:
			failures.append("BGM for '%s' must loop natively on Web" % view_name)
	manager.free()

func _test_switching_view_replaces_the_playing_bgm() -> void:
	var manager := load("res://scripts/audio_manager.gd").new() as Node
	add_child(manager)
	manager.call("set_view", "adhd")
	var bgm_player := manager.get("bgm_player") as AudioStreamPlayer
	var bgm_cache := manager.get("bgm_cache") as Dictionary
	if bgm_player.stream != bgm_cache.get("adhd") or not bgm_player.playing:
		failures.append("Switching to ADHD view must immediately play its BGM")
	manager.call("set_view", "blind")
	if bgm_player.stream != bgm_cache.get("blind") or not bgm_player.playing:
		failures.append("Switching to blind view must immediately play its BGM")
	manager.free()
