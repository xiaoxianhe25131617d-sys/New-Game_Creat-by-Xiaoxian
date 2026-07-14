extends Node

var failures: Array[String] = []

func _ready() -> void:
	_test_piece_mapping()
	_test_snap_distance()
	_test_images_are_square_and_divisible()
	if failures.is_empty():
		print("PASS: album puzzle checks")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)

func _test_piece_mapping() -> void:
	if AlbumPuzzleUI.collectible_id(0, 0) != "collectible_00":
		failures.append("First puzzle must begin at collectible_00")
	if AlbumPuzzleUI.collectible_id(2, 8) != "collectible_26":
		failures.append("Third puzzle must end at collectible_26")

func _test_snap_distance() -> void:
	if not AlbumPuzzleUI.should_snap(Vector2.ZERO, Vector2(40, 0)):
		failures.append("Pieces near their target must snap")
	if AlbumPuzzleUI.should_snap(Vector2.ZERO, Vector2(80, 0)):
		failures.append("Pieces far from their target must stay draggable")

func _test_images_are_square_and_divisible() -> void:
	for texture in AlbumPuzzleUI.PUZZLE_TEXTURES:
		if texture.get_width() != 1026 or texture.get_height() != 1026:
			failures.append("Album images must use a 1026px square canvas for exact 3x3 slicing")
