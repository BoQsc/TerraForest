class_name AnalogSpeedometer
extends Control

@export var car_path: NodePath = ^"../../Car"
@export var max_speed_kph: float = 280.0

@onready var value_label: Label = $ValueLabel
@onready var unit_label: Label = $UnitLabel

var car: Node
var displayed_speed: float = 0.0

const GAUGE_SIZE: Vector2 = Vector2(200.0, 200.0)
const SCREEN_MARGIN: float = 20.0
const START_ANGLE: float = 2.4434609528 # 140 degrees
const END_ANGLE: float = 6.9813170080 # 400 degrees


func _ready() -> void:
	car = get_node_or_null(car_path)
	if not is_instance_valid(car):
		push_error("Speedometer car_path does not point to the car node.")

	# Do not rely on Control anchors when the direct parent is CanvasLayer. Position
	# the gauge explicitly from the viewport so it is always in the bottom-left.
	custom_minimum_size = GAUGE_SIZE
	size = GAUGE_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place_bottom_left()
	get_viewport().size_changed.connect(_place_bottom_left)
	queue_redraw()


func _place_bottom_left() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	position = Vector2(SCREEN_MARGIN, maxf(SCREEN_MARGIN, viewport_size.y - GAUGE_SIZE.y - SCREEN_MARGIN))
	size = GAUGE_SIZE


func _process(delta: float) -> void:
	if not is_instance_valid(car):
		return

	var target_speed: float = float(car.get("speed_kph"))
	var follow_weight: float = 1.0 - exp(-10.0 * delta)
	displayed_speed = lerpf(displayed_speed, target_speed, follow_weight)
	value_label.text = "%03d" % int(roundf(displayed_speed))
	unit_label.text = "km/h"
	queue_redraw()


func _draw() -> void:
	var center: Vector2 = Vector2(size.x * 0.5, size.y * 0.5)
	var radius: float = minf(size.x, size.y) * 0.43
	var clamped_speed: float = clampf(displayed_speed, 0.0, max_speed_kph)
	var speed_ratio: float = clamped_speed / maxf(max_speed_kph, 1.0)
	var needle_angle: float = lerpf(START_ANGLE, END_ANGLE, speed_ratio)

	draw_circle(center, radius + 8.0, Color(0.015, 0.02, 0.025, 0.86))
	draw_arc(center, radius, START_ANGLE, END_ANGLE, 72, Color(0.72, 0.75, 0.78, 0.8), 4.0, true)
	draw_arc(center, radius, START_ANGLE, needle_angle, 48, Color(0.95, 0.95, 0.92, 0.95), 5.0, true)

	for tick_index: int in range(11):
		var tick_ratio: float = float(tick_index) / 10.0
		var angle: float = lerpf(START_ANGLE, END_ANGLE, tick_ratio)
		var direction: Vector2 = Vector2(cos(angle), sin(angle))
		var inner_radius: float = radius - (15.0 if tick_index % 2 == 0 else 9.0)
		var tick_width: float = 3.0 if tick_index % 2 == 0 else 2.0
		draw_line(center + direction * inner_radius, center + direction * radius, Color(0.9, 0.9, 0.88, 0.92), tick_width, true)

	var needle_direction: Vector2 = Vector2(cos(needle_angle), sin(needle_angle))
	draw_line(center - needle_direction * 8.0, center + needle_direction * (radius - 18.0), Color(0.94, 0.23, 0.16, 1.0), 4.0, true)
	draw_circle(center, 7.0, Color(0.88, 0.9, 0.92, 1.0))
