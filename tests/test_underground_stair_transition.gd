extends Node

var failures: Array[String] = []
var completion_count: int = 0

func _ready() -> void:
	var packed := load("res://scenes/UndergroundStairTransition.tscn") as PackedScene
	if packed == null:
		failures.append("Underground stair transition scene must load")
		_finish()
		return
	var transition := packed.instantiate()
	add_child(transition)

	var stream := load("res://assets/audio/enter_underground_maze.MP3") as AudioStream
	transition.configure(stream)
	var expected_duration := stream.get_length()
	if absf(float(transition.transition_duration) - expected_duration) > 0.01:
		failures.append("Transition duration must come from the configured audio stream")

	transition.completed.connect(_on_transition_completed)
	transition.play()
	transition._advance(expected_duration * 0.25)
	if absf(float(transition.progress) - 0.25) > 0.01:
		failures.append("Visual progress must stay normalized to the music duration")

	transition._advance(expected_duration * 0.75)
	transition._on_audio_finished()
	transition._advance(expected_duration)
	if completion_count != 1:
		failures.append("Transition must complete exactly once")

	transition.queue_free()
	await get_tree().process_frame

	var fallback_transition := packed.instantiate()
	add_child(fallback_transition)
	fallback_transition.configure(null)
	fallback_transition.completed.connect(_on_transition_completed)
	fallback_transition.play()
	fallback_transition._advance(fallback_transition.transition_duration)
	if completion_count != 2:
		failures.append("Transition must still complete when entry audio is unavailable")
	fallback_transition.queue_free()
	await get_tree().process_frame
	_finish()

func _on_transition_completed() -> void:
	completion_count += 1

func _finish() -> void:
	if failures.is_empty():
		print("PASS: underground stair transition checks")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
