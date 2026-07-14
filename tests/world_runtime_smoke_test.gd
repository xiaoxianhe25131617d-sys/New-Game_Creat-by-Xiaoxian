extends Node

var _failures: Array[String] = []


func _ready() -> void:
	var packed := load("res://map/MainWorld.tscn") as PackedScene
	if packed == null:
		push_error("world_runtime_smoke_test: MainWorld.tscn failed to load")
		get_tree().quit(1)
		return
	var world := packed.instantiate() as MindscapeWorld
	add_child(world)
	world.build(GameData.default_state())
	_expect(world.is_in_group("world"), "world registers its runtime group")
	_expect(world.interactables.size() > GameData.NPCS.size(), "runtime interactables are created")
	_expect(world.get_node_or_null("NPC_guide_old_man") != null, "NPCs are created from markers")
	_expect(world.get_node_or_null("UndergroundPortal") != null, "underground portal is created from its marker")
	_expect(world.puzzle_nodes.has("texture_wall"), "puzzles are created from markers")
	var guide := world.get_node_or_null("NPC_guide_old_man") as Node2D
	if guide != null:
		_expect(guide.global_position.is_equal_approx(world.get_marker_position(&"npcs", &"guide_old_man")), "NPC position matches its authored marker")
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("world_runtime_smoke_test: PASS")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("world_runtime_smoke_test: %s" % failure)
	get_tree().quit(1)
