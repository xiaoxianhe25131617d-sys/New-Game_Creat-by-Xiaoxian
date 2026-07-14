extends SceneTree

const MAIN_SCRIPT_PATH := "res://scripts/main.gd"

var _failures: Array[String] = []


func _initialize() -> void:
	var source := FileAccess.get_file_as_string(MAIN_SCRIPT_PATH)
	_expect(not source.is_empty(), "main.gd must be readable")
	_expect(source.contains("const CAMERA_VIEW_OFFSET := Vector2(0.0, 28.0)"), "camera view shifts down by 28 pixels")
	_expect(source.contains("camera.offset = CAMERA_VIEW_OFFSET"), "gameplay camera applies the framing offset")
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("camera_framing_contract_test: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error("camera_framing_contract_test: %s" % failure)
	quit(1)
