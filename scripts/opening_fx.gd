extends Control

var elapsed: float = 0.0
var scene_index: int = 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	queue_redraw()

func set_scene(value: int) -> void:
	scene_index = value
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()

func _draw() -> void:
	var center := size * Vector2(0.64, 0.42)
	var pulse := 1.0 + sin(elapsed * 2.4) * 0.04
	var energy := Color("#8edcff") if scene_index < 4 else Color("#f0c98a")
	if scene_index <= 1:
		for ring in range(5):
			var radius := (48.0 + float(ring) * 34.0) * pulse
			var alpha := 0.38 - float(ring) * 0.055
			draw_arc(center, radius, elapsed * 0.5 + ring, TAU * 0.78, 48, Color(energy, alpha), 3.0)
			draw_arc(center, radius + 9.0, -elapsed * 0.35 + ring, TAU * 0.36, 32, Color("#f6e2b855"), 2.0)
		for ray in range(12):
			var angle := float(ray) * TAU / 12.0 + elapsed * 0.18
			var start := center + Vector2.from_angle(angle) * 28.0
			var end := center + Vector2.from_angle(angle) * (125.0 + 20.0 * sin(elapsed * 1.8 + ray))
			draw_line(start, end, Color(energy, 0.12), 2.0)
	elif scene_index <= 4:
		var bench_center := size * Vector2(0.5, 0.53)
		for ray in range(6):
			var angle := float(ray) * TAU / 6.0 + elapsed * 0.12
			var point := bench_center + Vector2.from_angle(angle) * (180.0 + sin(elapsed * 1.5 + ray) * 18.0)
			draw_line(bench_center, point, Color("#8edcff40"), 2.0)
			draw_circle(point, 5.0 + sin(elapsed * 2.0 + ray) * 2.0, Color("#f0c98a99"))
	else:
		var network_center := size * Vector2(0.5, 0.48)
		for ray in range(8):
			var angle := float(ray) * TAU / 8.0
			var point := network_center + Vector2.from_angle(angle) * (180.0 + sin(elapsed + ray) * 12.0)
			draw_line(network_center, point, Color("#b8e7ff66"), 2.0)
			draw_circle(point, 7.0, Color("#f6d487bb"))
		draw_circle(network_center, 18.0 + sin(elapsed * 2.2) * 3.0, Color("#8edcff88"), false, 3.0)
