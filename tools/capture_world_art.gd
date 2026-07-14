extends Node2D

const CAPTURES := {
	"plaza": Vector2(3400.0, 2860.0),
	"find_difference": Vector2(5000.0, 2860.0),
	"dance_hall": Vector2(5800.0, 2860.0),
	"dam_workshop": Vector2(6600.0, 2860.0),
	"lightboard_factory": Vector2(7800.0, 2860.0),
}

func _ready() -> void:
	var world := MindscapeWorld.new()
	add_child(world)
	world.build(GameData.default_state())

	var camera := Camera2D.new()
	camera.enabled = true
	camera.position = CAPTURES["plaza"]
	add_child(camera)
	for _frame in range(4):
		await get_tree().process_frame

	for capture_name in CAPTURES:
		camera.position = CAPTURES[capture_name]
		for _frame in range(24):
			await get_tree().process_frame
		var image := get_viewport().get_texture().get_image()
		if image == null:
			push_error("The active renderer cannot capture viewport images")
			get_tree().quit(1)
			return
		var error := image.save_png("/tmp/mindscape_%s.png" % capture_name)
		if error != OK:
			push_error("Could not save %s capture: %s" % [capture_name, error_string(error)])

	get_tree().quit()
