@tool
extends Area2D
class_name MazeLadder

@export var ladder_color := Color("#4b515b"):
	set(value):
		ladder_color = value
		queue_redraw()

func _ready() -> void:
	queue_redraw()

func _draw() -> void:
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or not shape_node.shape is RectangleShape2D:
		return
	var size := (shape_node.shape as RectangleShape2D).size
	var left := -size.x * 0.35
	var right := size.x * 0.35
	var top := -size.y * 0.5
	var bottom := size.y * 0.5
	draw_line(Vector2(left, top), Vector2(left, bottom), ladder_color, 3.0)
	draw_line(Vector2(right, top), Vector2(right, bottom), ladder_color, 3.0)
	var rung_count := maxi(2, floori(size.y / 12.0))
	for index in range(rung_count + 1):
		var y := lerpf(top, bottom, float(index) / float(rung_count))
		draw_line(Vector2(left, y), Vector2(right, y), ladder_color, 2.0)

func contains_world_point(point: Vector2) -> bool:
	var local_point := to_local(point)
	var shape_node := $CollisionShape2D as CollisionShape2D
	var half_size := (shape_node.shape as RectangleShape2D).size * 0.5
	return absf(local_point.x) <= half_size.x and absf(local_point.y) <= half_size.y

func top_world_y() -> float:
	var shape_node := $CollisionShape2D as CollisionShape2D
	return to_global(Vector2(0, -(shape_node.shape as RectangleShape2D).size.y * 0.5)).y

func bottom_world_y() -> float:
	var shape_node := $CollisionShape2D as CollisionShape2D
	return to_global(Vector2(0, (shape_node.shape as RectangleShape2D).size.y * 0.5)).y
