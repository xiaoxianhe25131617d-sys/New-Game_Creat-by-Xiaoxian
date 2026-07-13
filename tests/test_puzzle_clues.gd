extends Node

var failures: Array[String] = []

func _ready() -> void:
	_test_nine_grid_dismiss_threshold()
	_test_password_clue_order()
	_test_plain_book_has_no_marker_brackets()
	if failures.is_empty():
		print("PASS: puzzle clue checks")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)

func _test_nine_grid_dismiss_threshold() -> void:
	if PuzzleNineGrid.should_dismiss_for_key_count(3):
		failures.append("Three simultaneous keys must not dismiss the answer flash")
	if not PuzzleNineGrid.should_dismiss_for_key_count(4):
		failures.append("More than three simultaneous keys must dismiss the answer flash")

func _test_password_clue_order() -> void:
	if PuzzleNPCPassword.CORRECT_PASSWORD != [4, 8, 2, 5, 7]:
		failures.append("Password must map 小笑到怎别 to 48257")
	var expected := ["小", "笑", "到", "怎", "别"]
	for index in range(5):
		var line: Dictionary = (GameData.DIALOGUES["npc_cipher_%d" % (index + 1)] as Array)[0]
		var combined := str(line.get("text", "")) + str(line.get("subtext", ""))
		if not combined.contains(expected[index]):
			failures.append("NPC clue %d must contain %s" % [index + 1, expected[index]])

func _test_plain_book_has_no_marker_brackets() -> void:
	if PuzzleNPCPassword.CIPHER_TEXT.contains("「") or PuzzleNPCPassword.CIPHER_TEXT.contains("」"):
		failures.append("Normal-view password book text must not show marker brackets")
