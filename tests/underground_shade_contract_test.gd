extends SceneTree

const WORLD_SCENE := "res://map/MainWorld.tscn"
const UNDERGROUND_TOP_Y := 3216.0

var _failures: Array[String] = []


func _initialize() -> void:
	var packed := load(WORLD_SCENE) as PackedScene
	_expect(packed != null, "MainWorld.tscn must load")
	if packed == null:
		_finish()
		return

	var world := packed.instantiate()
	root.add_child(world)
	var shade := world.get_node_or_null("Visuals/UndergroundShade") as ColorRect
	var ground := world.get_node_or_null("Visuals/TileMaps/Ground") as CanvasItem

	_expect(shade != null, "the authored world contains an underground shade")
	if shade != null:
		_expect(shade.position.is_equal_approx(Vector2(0.0, UNDERGROUND_TOP_Y)), "shade begins below the grass surface")
		_expect(shade.size.is_equal_approx(Vector2(11200.0, 384.0)), "shade covers the full underground world bounds")
		_expect(shade.mouse_filter == Control.MOUSE_FILTER_IGNORE, "shade never intercepts gameplay input")
		_expect(shade.material is ShaderMaterial, "shade uses the fog gradient shader")
	if shade != null and ground != null:
		_expect(shade.z_index > ground.z_index, "shade renders over the underground soil")
		_expect(shade.z_index < 0, "shade remains behind gameplay actors")

	world.free()
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("underground_shade_contract_test: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error("underground_shade_contract_test: %s" % failure)
	quit(1)
