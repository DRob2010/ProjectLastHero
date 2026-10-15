extends Camera2D


@export var target_path: NodePath = NodePath("../CharacterBody2D")
@export var look_ahead_distance := 0.0

var target: CharacterBody2D
var last_look_direction := Vector2.ZERO
var hold_saved_position_once := false


func _ready() -> void:
	target = get_node_or_null(target_path) as CharacterBody2D
	if target:
		global_position = target.global_position


func _process(_delta: float) -> void:
	if hold_saved_position_once:
		hold_saved_position_once = false
		return
	if target:
		if target.velocity.length_squared() > 0.0:
			last_look_direction = target.velocity.normalized()

		var camera_target: Vector2 = target.global_position + last_look_direction * look_ahead_distance
		global_position = camera_target


func restore_saved_position(saved_position: Vector2) -> void:
	global_position = saved_position
	reset_smoothing()
	hold_saved_position_once = true
