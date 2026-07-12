extends Node

var failures: Array[String] = []

func _ready() -> void:
	await _test_dash_preserves_auto_walk_direction()
	await _test_interaction_pause_restores_auto_walk()
	_test_leaving_adhd_clears_auto_walk()
	_test_adhd_attention_overlay()
	_test_adhd_focus_tracks_player_screen_position()
	_test_adhd_radius_uses_shared_screen_scale()
	_test_attention_candidates_are_real_interactables()
	_test_npc_dialogue_suspends_and_resumes_auto_walk()
	if failures.is_empty():
		print("PASS: ADHD view regression checks")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)

func _make_player() -> MindscapePlayer:
	var player := MindscapePlayer.create()
	add_child(player)
	player.set_physics_process(false)
	player.set_view("adhd")
	return player

func _test_dash_preserves_auto_walk_direction() -> void:
	var player := _make_player()
	await get_tree().process_frame
	player.adhd_auto_dir = 1.0
	player.facing_dir = 1.0
	Input.action_press("special")
	player._physics_process(0.016)
	Input.action_release("special")
	if player.adhd_auto_dir != 1.0:
		failures.append("ADHD dash must preserve the current automatic walking direction")
	player.free()

func _test_interaction_pause_restores_auto_walk() -> void:
	var player := _make_player()
	await get_tree().process_frame
	player.adhd_auto_dir = -1.0
	player.velocity = Vector2(-320.0, 0.0)
	player.dash_time = 0.1
	if not player.has_method("suspend_for_interaction") or not player.has_method("resume_after_interaction"):
		failures.append("Player must expose interaction suspend and resume methods")
		player.free()
		return
	player.call("suspend_for_interaction")
	if player.controls_enabled:
		failures.append("Interaction suspension must disable player controls")
	if player.velocity.x != 0.0 or player.dash_time != 0.0:
		failures.append("Interaction suspension must immediately stop horizontal movement and dash")
	if player.adhd_auto_dir != -1.0:
		failures.append("Interaction suspension must retain the ADHD automatic walking direction")
	player.call("resume_after_interaction")
	if not player.controls_enabled or player.adhd_auto_dir != -1.0:
		failures.append("Interaction resume must restore controls without clearing ADHD auto-walk")
	player.free()

func _test_leaving_adhd_clears_auto_walk() -> void:
	var player := _make_player()
	player.adhd_auto_dir = 1.0
	player.set_view("normal")
	if player.adhd_auto_dir != 0.0:
		failures.append("Leaving ADHD view must clear automatic walking")
	player.free()

func _test_adhd_attention_overlay() -> void:
	var world := MindscapeWorld.new()
	add_child(world)
	world._make_background_canvas()
	var overlay := world.get_node_or_null("ViewTintCanvas/ADHDAttention") as ColorRect
	if overlay == null:
		failures.append("ADHD view must provide a full-screen attention overlay")
		world.free()
		return
	var material := overlay.material as ShaderMaterial
	if material == null or material.shader == null or material.shader.resource_path != "res://shaders/adhd_attention.gdshader":
		failures.append("ADHD attention overlay must use its dedicated screen shader")
	else:
		var radius := float(material.get_shader_parameter("radius_px"))
		var feather := float(material.get_shader_parameter("feather_px"))
		if absf(radius - 220.0) > 0.01 or absf(feather - 160.0) > 0.01:
			failures.append("ADHD attention shader must use a 220px focus radius and 160px feather")
	world.set_view_palette("adhd")
	if not overlay.visible:
		failures.append("ADHD attention overlay must be visible in ADHD view")
	world.set_view_palette("normal")
	if overlay.visible:
		failures.append("ADHD attention overlay must hide outside ADHD view")
	world.free()

func _test_adhd_focus_tracks_player_screen_position() -> void:
	var world := MindscapeWorld.new()
	add_child(world)
	world._make_background_canvas()
	var player := Node2D.new()
	player.add_to_group("player")
	player.position = Vector2(160.0, 120.0)
	world.add_child(player)
	world.call("_update_adhd_attention_shader")
	var material := world.get("adhd_attention_material") as ShaderMaterial
	var viewport_size := world.get_viewport_rect().size
	var expected := player.get_global_transform_with_canvas().origin / viewport_size
	var actual := material.get_shader_parameter("player_screen_uv") as Vector2
	if actual.distance_to(expected) > 0.001:
		failures.append("ADHD focus center must follow the player's canvas transform")
	world.free()

func _test_adhd_radius_uses_shared_screen_scale() -> void:
	var world := MindscapeWorld.new()
	add_child(world)
	world._make_background_canvas()
	world.call("_update_adhd_attention_shader")
	var material := world.get("adhd_attention_material") as ShaderMaterial
	var stretch_scale := world.get_viewport().get_stretch_transform().get_scale()
	var expected_scale := minf(absf(stretch_scale.x), absf(stretch_scale.y))
	var radius := float(material.get_shader_parameter("radius_px"))
	var feather := float(material.get_shader_parameter("feather_px"))
	if absf(radius - 220.0 * expected_scale) > 0.01 or absf(feather - 160.0 * expected_scale) > 0.01:
		failures.append("ADHD focus dimensions must use the shared window scale")
	world.free()

func _test_attention_candidates_are_real_interactables() -> void:
	var world := MindscapeWorld.new()
	add_child(world)
	var real_target := Node2D.new()
	real_target.add_to_group("interactable")
	real_target.position = Vector2(100.0, 100.0)
	world.add_child(real_target)
	var unrelated := Node2D.new()
	unrelated.position = Vector2(140.0, 100.0)
	world.add_child(unrelated)
	if not world.has_method("_get_adhd_attention_candidates"):
		failures.append("World must expose ADHD attention candidate filtering")
	else:
		var candidates: Array = world.call("_get_adhd_attention_candidates")
		if not candidates.has(real_target):
			failures.append("ADHD attention candidates must include visible interactables")
		if candidates.has(unrelated):
			failures.append("ADHD attention candidates must exclude non-interactable nodes")
	world.free()

func _test_npc_dialogue_suspends_and_resumes_auto_walk() -> void:
	var main := load("res://scripts/main.gd").new() as Node
	add_child(main)
	var player := MindscapePlayer.create()
	main.add_child(player)
	player.set_view("adhd")
	player.adhd_auto_dir = 1.0
	player.velocity.x = MindscapePlayer.SPEED
	var dialogue := DialogueBox.new()
	main.add_child(dialogue)
	var npc := MindscapeNPC.new()
	npc.setup(GameData.NPCS[0])
	main.add_child(npc)
	main.set("state", GameData.default_state().duplicate(true))
	main.set("player", player)
	main.set("dialogue", dialogue)
	main.call("talk_to_npc", npc)
	if player.controls_enabled or player.velocity.x != 0.0 or player.adhd_auto_dir != 1.0:
		failures.append("NPC dialogue must stop movement without clearing ADHD auto-walk")
	main.call("_on_dialogue_closed")
	if not player.controls_enabled or player.adhd_auto_dir != 1.0:
		failures.append("Closing NPC dialogue must resume the saved ADHD auto-walk direction")
	main.free()
