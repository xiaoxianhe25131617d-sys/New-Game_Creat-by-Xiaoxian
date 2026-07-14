extends Control
class_name AlbumPuzzleUI

const PUZZLE_TEXTURES: Array[Texture2D] = [
	preload("res://assets/album/friends_01.png"),
	preload("res://assets/album/friends_02.png"),
	preload("res://assets/album/friends_03.png"),
]
const PUZZLE_NAMES := ["苹果树下", "午后合照", "一起寻找"]
const PIECES_PER_PUZZLE := 9
const SOURCE_PIECE_SIZE := 342.0
const DISPLAY_PIECE_SIZE := 136.0
const BOARD_ORIGIN := Vector2(86, 126)
const TRAY_ORIGIN := Vector2(610, 132)
const SNAP_DISTANCE := 54.0

var state: Dictionary
var save_callback: Callable
var album_panel: Panel
var board_layer: Control
var piece_layer: Control
var tab_buttons: Array[Button] = []
var status_label: Label
var active_puzzle := 0
var dragging_piece: TextureRect
var dragging_piece_id := ""
var dragging_target := Vector2.ZERO
var dragging_offset := Vector2.ZERO

static func collectible_id(puzzle_index: int, piece_index: int) -> String:
	return "collectible_%02d" % (puzzle_index * PIECES_PER_PUZZLE + piece_index)

static func should_snap(piece_position: Vector2, target_position: Vector2) -> bool:
	return piece_position.distance_to(target_position) <= SNAP_DISTANCE

func setup(active_state: Dictionary, on_save: Callable) -> void:
	state = active_state
	save_callback = on_save
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	_show_puzzle(0)

func _build_ui() -> void:
	var dimmer := ColorRect.new()
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color("#050711", 0.94)
	add_child(dimmer)

	album_panel = Panel.new()
	album_panel.set_anchors_preset(Control.PRESET_CENTER)
	album_panel.position = Vector2(-560, -310)
	album_panel.size = Vector2(1120, 620)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("#171421")
	panel_style.border_color = Color("#8b7353")
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(6)
	album_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(album_panel)

	var title := Label.new()
	title.text = "纪念相册"
	title.position = Vector2(32, 18)
	title.size = Vector2(220, 40)
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("#ffe8a0"))
	album_panel.add_child(title)

	for index in range(PUZZLE_NAMES.size()):
		var tab := Button.new()
		tab.text = PUZZLE_NAMES[index]
		tab.position = Vector2(290 + index * 180, 18)
		tab.size = Vector2(164, 42)
		tab.pressed.connect(_show_puzzle.bind(index))
		album_panel.add_child(tab)
		tab_buttons.append(tab)

	var close_button := Button.new()
	close_button.text = "×"
	close_button.tooltip_text = "关闭相册"
	close_button.position = Vector2(1052, 18)
	close_button.size = Vector2(44, 42)
	close_button.add_theme_font_size_override("font_size", 24)
	close_button.pressed.connect(queue_free)
	album_panel.add_child(close_button)

	board_layer = Control.new()
	board_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	board_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	album_panel.add_child(board_layer)
	piece_layer = Control.new()
	piece_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	piece_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	album_panel.add_child(piece_layer)

	status_label = Label.new()
	status_label.position = Vector2(610, 555)
	status_label.size = Vector2(450, 32)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 17)
	status_label.add_theme_color_override("font_color", Color("#9fdad4"))
	album_panel.add_child(status_label)

func _show_puzzle(puzzle_index: int) -> void:
	active_puzzle = puzzle_index
	for button_index in range(tab_buttons.size()):
		tab_buttons[button_index].disabled = button_index == active_puzzle
	for child in board_layer.get_children():
		child.queue_free()
	for child in piece_layer.get_children():
		child.queue_free()
	dragging_piece = null
	dragging_piece_id = ""

	var frame := Panel.new()
	frame.position = BOARD_ORIGIN - Vector2(8, 8)
	frame.size = Vector2(DISPLAY_PIECE_SIZE * 3.0 + 16.0, DISPLAY_PIECE_SIZE * 3.0 + 16.0)
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color("#0b0c14")
	frame_style.border_color = Color("#bea878")
	frame_style.set_border_width_all(3)
	frame.add_theme_stylebox_override("panel", frame_style)
	board_layer.add_child(frame)

	var collected: Array = state.get("collectibles", []) as Array
	var saved_positions: Dictionary = state.get("album_piece_positions", {}) as Dictionary
	for piece_index in range(PIECES_PER_PUZZLE):
		var target := _target_position(piece_index)
		var placeholder := ColorRect.new()
		placeholder.position = target + Vector2(2, 2)
		placeholder.size = Vector2(DISPLAY_PIECE_SIZE - 4, DISPLAY_PIECE_SIZE - 4)
		placeholder.color = Color("#222332") if collected.has(collectible_id(active_puzzle, piece_index)) else Color("#0d0e17")
		placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		board_layer.add_child(placeholder)

		var id := collectible_id(active_puzzle, piece_index)
		if not collected.has(id):
			continue
		var piece := _make_piece(piece_index)
		var stored_position: Variant = saved_positions.get(id, _tray_position(piece_index))
		piece.position = stored_position as Vector2 if stored_position is Vector2 else _tray_position(piece_index)
		piece.set_meta("locked", should_snap(piece.position, target))
		if bool(piece.get_meta("locked", false)):
			piece.position = target
		piece.gui_input.connect(_on_piece_input.bind(piece, id, target))
		piece_layer.add_child(piece)

	_update_status()

func _make_piece(piece_index: int) -> TextureRect:
	var atlas := AtlasTexture.new()
	atlas.atlas = PUZZLE_TEXTURES[active_puzzle]
	atlas.region = Rect2(
		float(piece_index % 3) * SOURCE_PIECE_SIZE,
		float(piece_index / 3) * SOURCE_PIECE_SIZE,
		SOURCE_PIECE_SIZE,
		SOURCE_PIECE_SIZE
	)
	var piece := TextureRect.new()
	piece.texture = atlas
	piece.size = Vector2.ONE * DISPLAY_PIECE_SIZE
	piece.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	piece.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	piece.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	piece.mouse_filter = Control.MOUSE_FILTER_STOP
	return piece

func _on_piece_input(event: InputEvent, piece: TextureRect, id: String, target: Vector2) -> void:
	if bool(piece.get_meta("locked", false)):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			dragging_piece = piece
			dragging_piece_id = id
			dragging_target = target
			dragging_offset = event.position
			piece.move_to_front()
		else:
			_finish_drag()
		accept_event()

func _input(event: InputEvent) -> void:
	if dragging_piece == null:
		return
	if event is InputEventMouseMotion:
		dragging_piece.position = album_panel.get_local_mouse_position() - dragging_offset
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_finish_drag()
		get_viewport().set_input_as_handled()

func _finish_drag() -> void:
	if dragging_piece == null:
		return
	if should_snap(dragging_piece.position, dragging_target):
		dragging_piece.position = dragging_target
		dragging_piece.set_meta("locked", true)
	var positions: Dictionary = state.get("album_piece_positions", {}) as Dictionary
	positions[dragging_piece_id] = dragging_piece.position
	state["album_piece_positions"] = positions
	dragging_piece = null
	dragging_piece_id = ""
	_check_completion()
	_save()

func _check_completion() -> void:
	for child in piece_layer.get_children():
		if child is TextureRect and not bool(child.get_meta("locked", false)):
			return
	var collected: Array = state.get("collectibles", []) as Array
	for piece_index in range(PIECES_PER_PUZZLE):
		if not collected.has(collectible_id(active_puzzle, piece_index)):
			return
	var completed: Array = state.get("album_puzzles_completed", []) as Array
	if not completed.has(active_puzzle):
		completed.append(active_puzzle)
		state["album_puzzles_completed"] = completed
		var album: Array = state.get("album", []) as Array
		var entry := "拼图：%s" % PUZZLE_NAMES[active_puzzle]
		if not album.has(entry):
			album.append(entry)
		state["album"] = album
	_update_status()

func _update_status() -> void:
	var collected: Array = state.get("collectibles", []) as Array
	var count := 0
	for piece_index in range(PIECES_PER_PUZZLE):
		if collected.has(collectible_id(active_puzzle, piece_index)):
			count += 1
	var completed: Array = state.get("album_puzzles_completed", []) as Array
	status_label.text = "拼图已完成，照片回到了相册" if completed.has(active_puzzle) else "已找到 %d / 9 块" % count

func _target_position(piece_index: int) -> Vector2:
	return BOARD_ORIGIN + Vector2(piece_index % 3, piece_index / 3) * DISPLAY_PIECE_SIZE

func _tray_position(piece_index: int) -> Vector2:
	return TRAY_ORIGIN + Vector2(piece_index % 3, piece_index / 3) * (DISPLAY_PIECE_SIZE + 8.0)

func _save() -> void:
	if save_callback.is_valid():
		save_callback.call()
