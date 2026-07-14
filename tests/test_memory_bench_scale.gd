extends Node

const WorldScript := preload("res://scripts/world.gd")

func _ready() -> void:
	var world := WorldScript.new()
	add_child(world)
	var anchor := world._add_memory_bench(Vector2.ZERO)
	var bench := anchor.find_child("BenchTexture", true, false) as Sprite2D
	if bench == null or bench.texture == null:
		push_error("Memory anchor has no bench texture")
		world.free()
		get_tree().quit(1)
		return

	var texture_size := bench.texture.get_size()
	var original_scale := minf(132.0 / texture_size.x, 76.0 / texture_size.y)
	var expected_scale := Vector2.ONE * original_scale * (2.0 / 3.0)
	if not bench.scale.is_equal_approx(expected_scale):
		push_error("Memory anchor bench must be scaled to two thirds of its original size")
		world.free()
		get_tree().quit(1)
		return

	print("PASS: memory bench scale is two thirds of the original size")
	world.free()
	get_tree().quit(0)
