extends Node

var failures: Array[String] = []

func _ready() -> void:
	_test_blind_overlay_uses_screen_shader()
	_test_blind_overlay_stays_fixed_to_screen()
	_test_blind_vision_uses_compact_radius()
	_test_monsters_render_below_blind_overlay()
	_test_blind_view_toggles_overlay_state()
	_test_player_screen_position_uses_canvas_transform()
	_test_inventory_and_controls_render_above_blind_mask()
	if failures.is_empty():
		print("PASS: blind vision regression checks")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)

func _test_blind_overlay_uses_screen_shader() -> void:
	var world := MindscapeWorld.new()
	add_child(world)
	world._make_background_canvas()
	var overlay := world.get_node_or_null("ViewTintCanvas/BlindVision") as ColorRect
	if overlay == null:
		failures.append("Blind vision must use a full-screen BlindVision overlay")
	else:
		var material := overlay.material as ShaderMaterial
		if material == null or material.shader == null:
			failures.append("BlindVision must use a ShaderMaterial")
		elif material.shader.resource_path != "res://shaders/blind_vision.gdshader":
			failures.append("BlindVision must use the blind vision screen shader")
	world.free()

func _test_blind_overlay_stays_fixed_to_screen() -> void:
	var world := MindscapeWorld.new()
	add_child(world)
	world._make_background_canvas()
	if world.view_tint_canvas.follow_viewport_enabled:
		failures.append("Blind vision canvas must stay fixed to the screen")
	world.free()

func _test_blind_vision_uses_compact_radius() -> void:
	var world := MindscapeWorld.new()
	add_child(world)
	world._make_background_canvas()
	var radius := float(world.blind_vision_material.get_shader_parameter("radius_px"))
	var feather := float(world.blind_vision_material.get_shader_parameter("feather_px"))
	if absf(radius - 80.0) > 0.01:
		failures.append("Blind vision radius must be 80px")
	if absf(feather - 16.0) > 0.01:
		failures.append("Blind vision feather must scale down to 16px")
	world.free()

func _test_monsters_render_below_blind_overlay() -> void:
	var world := MindscapeWorld.new()
	add_child(world)
	world._make_background_canvas()
	if world.monster_canvas.layer >= world.view_tint_canvas.layer:
		failures.append("Monster canvas must render below the blind vision overlay")
	world.free()

func _test_blind_view_toggles_overlay_state() -> void:
	var world := MindscapeWorld.new()
	add_child(world)
	world._make_background_canvas()
	world.set_view_palette("blind")
	var overlay := world.get_node_or_null("ViewTintCanvas/BlindVision") as ColorRect
	if overlay == null or not overlay.visible:
		failures.append("Blind vision overlay must be visible in blind view")
	world.set_view_palette("normal")
	if overlay != null and overlay.visible:
		failures.append("Blind vision overlay must be hidden outside blind view")
	world.free()

func _test_player_screen_position_uses_canvas_transform() -> void:
	var world := MindscapeWorld.new()
	add_child(world)
	var player := Node2D.new()
	player.add_to_group("player")
	player.position = Vector2(120.0, 80.0)
	world.add_child(player)
	var expected := player.get_global_transform_with_canvas().origin
	var actual := world._get_player_screen_position()
	if actual.distance_to(expected) > 0.01:
		failures.append("Blind vision center must use the player's canvas transform")
	world.free()

func _test_inventory_and_controls_render_above_blind_mask() -> void:
	var main := load("res://scripts/main.gd").new() as Node
	add_child(main)
	main.call("_make_hud")
	var inventory_canvas := main.get("inventory_canvas") as CanvasLayer
	var controls_canvas := main.get("controls_canvas") as CanvasLayer
	var sidebar := main.get("sidebar") as Control
	if inventory_canvas == null or inventory_canvas.layer <= 500:
		failures.append("Inventory canvas must render above the blind vision mask")
	if inventory_canvas != null and inventory_canvas.follow_viewport_enabled:
		failures.append("Inventory canvas must stay fixed to the screen")
	if sidebar == null or sidebar.get_parent() != inventory_canvas:
		failures.append("Inventory sidebar must use the dedicated inventory canvas")
	if controls_canvas == null or controls_canvas.layer <= inventory_canvas.layer:
		failures.append("View controls must render above the inventory canvas")
	if controls_canvas != null and controls_canvas.follow_viewport_enabled:
		failures.append("View controls must stay fixed to the screen")
	main.call("_set_blind_hud_visible", true)
	if (main.get("hud_label") as Control).visible or (main.get("objective_label") as Control).visible or (main.get("prompt_label") as Control).visible:
		failures.append("World HUD labels must hide in blind view")
	if not sidebar.visible:
		failures.append("Inventory sidebar must remain visible in blind view")
	main.call("_set_blind_hud_visible", false)
	if not (main.get("hud_label") as Control).visible or not (main.get("objective_label") as Control).visible or not (main.get("prompt_label") as Control).visible:
		failures.append("World HUD labels must restore after leaving blind view")
	main.free()
