class_name DrivingHUD
extends CanvasLayer

@export var car_path: NodePath = ^"../Car"

@onready var speed_label: Label = $SpeedLabel
@onready var state_label: Label = $StateLabel
@onready var controls_label: Label = $ControlsLabel
@onready var speedometer: Control = $Speedometer

var car: Node
var mode: String = "DRIVING"


func _ready() -> void:
	car = get_node_or_null(car_path)
	if not is_instance_valid(car):
		push_error("HUD car_path does not point to the car node.")


func set_mode(new_mode: String) -> void:
	mode = new_mode
	speedometer.visible = new_mode != "ON_FOOT"
	_update_controls_text()


func _process(_delta: float) -> void:
	if not is_instance_valid(car):
		return

	var speed: int = int(roundf(float(car.get("speed_kph"))))
	var state: String = str(car.get("drive_state"))
	var grounded: int = int(car.get("grounded_wheels"))
	var drive_force: float = float(car.get("drive_force_newtons"))
	var roll: float = float(car.get("roll_degrees"))
	var steer: float = float(car.get("steering_degrees"))
	var steer_limit: float = float(car.get("steering_limit_degrees"))
	var slip: float = float(car.get("slip_angle_degrees"))
	var front_slip: float = float(car.get("front_tire_slip_degrees"))
	var rear_slip: float = float(car.get("rear_tire_slip_degrees"))
	var yaw_rate: float = float(car.get("yaw_rate_degrees"))
	var target_yaw_rate: float = float(car.get("target_yaw_rate_degrees"))
	var turn_radius: float = float(car.get("commanded_turn_radius"))
	var boost: bool = bool(car.get("boost_active"))

	speed_label.text = "%03d km/h" % speed
	if boost:
		speed_label.text += "   BOOST"
	var radius_text: String = "--" if turn_radius <= 0.0 else "%.1fm" % turn_radius
	state_label.text = "Drive:%s  G:%d/4  Force:%.1fkN  Roll:%+.1f  Steer:%+.1f/%.1f  R:%s  Slip:%+.1f  Tire:F%.1f/R%.1f  Yaw:%+.1f/%+.1f deg/s" % [state, grounded, drive_force / 1000.0, roll, steer, steer_limit, radius_text, slip, front_slip, rear_slip, yaw_rate, target_yaw_rate]
	_update_controls_text()


func _update_controls_text() -> void:
	if mode == "EXITING":
		controls_label.text = "Opening driver door..."
	elif mode == "ENTERING":
		controls_label.text = "Closing driver door..."
	elif mode == "ON_FOOT":
		controls_label.text = "WASD / arrows: walk   Shift: sprint   S / Down: backpedal   E near driver door: enter vehicle"
	else:
		controls_label.text = "WASD / arrows: drive   Shift: boost   Space: handbrake   E: exit vehicle   R: reset   F8: damage on/off   F9: repair dents"
