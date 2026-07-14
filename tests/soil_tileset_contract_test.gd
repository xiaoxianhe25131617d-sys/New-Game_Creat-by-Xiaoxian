extends SceneTree

const SOIL_TILES_PATH := "res://assets/environment/generated/soil_tiles.png"
const WORLD_TILESET_PATH := "res://map/tileset.png"

var _failures: Array[String] = []


func _initialize() -> void:
	var soil := _load_png(SOIL_TILES_PATH)
	var atlas := _load_png(WORLD_TILESET_PATH)
	_expect(not soil.is_empty(), "soil tile source must load")
	_expect(not atlas.is_empty(), "world tileset atlas must load")
	if soil.is_empty() or atlas.is_empty():
		_finish()
		return

	_expect(soil.get_size() == Vector2i(32, 16), "soil source contains two 16x16 tiles")
	_expect(atlas.get_size() == Vector2i(128, 96), "world tileset keeps its original atlas dimensions")
	var differing_variant_pixels := 0
	for y in range(16):
		for x in range(32):
			_expect(atlas.get_pixel(x, y).is_equal_approx(soil.get_pixel(x, y)), "soil source is copied into the atlas at pixel %d,%d" % [x, y])
			_expect(soil.get_pixel(x, y).a > 0.99, "soil tiles remain fully opaque")
		for x in range(16):
			if not soil.get_pixel(x, y).is_equal_approx(soil.get_pixel(x + 16, y)):
				differing_variant_pixels += 1
	_expect(differing_variant_pixels > 32, "the atlas contains two visibly different soil variants")
	_finish()


func _load_png(path: String) -> Image:
	var image := Image.new()
	var error := image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
	_expect(error == OK, "%s must be a valid PNG" % path)
	return image


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("soil_tileset_contract_test: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error("soil_tileset_contract_test: %s" % failure)
	quit(1)
