extends Area2D

const FLIP_INTERVAL := 0.08
const FIRESTARTER_DAMAGE_MIN := 8
const FIRESTARTER_DAMAGE_MAX := 10

@export var speed := 550.0
@export var lifetime := 2.0
@export var max_distance := 600.0

var direction := Vector2.UP
var start_position := Vector2.ZERO
var shooter: Node2D
var protected_target: Node2D
var flip_time_left := FLIP_INTERVAL

@onready var sprite: Sprite2D = $Sprite2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	body_entered.connect(_on_body_entered)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func setup(new_direction: Vector2, new_speed: float, new_shooter: Node2D, new_protected_target: Node2D) -> void:
	direction = new_direction.normalized()
	speed = new_speed
	shooter = new_shooter
	protected_target = new_protected_target
	start_position = global_position
	rotation = direction.angle() + PI / 2.0


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	flip_time_left -= delta
	if flip_time_left <= 0.0:
		flip_time_left = FLIP_INTERVAL
		sprite.flip_h = not sprite.flip_h
	lifetime -= delta
	if lifetime <= 0.0 or global_position.distance_to(start_position) >= max_distance:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body == shooter or body == protected_target:
		return
	if body.has_method("take_damage"):
		body.take_damage(randi_range(FIRESTARTER_DAMAGE_MIN, FIRESTARTER_DAMAGE_MAX))
		if body.has_method("apply_burn"):
			body.call("apply_burn")
		queue_free()
	elif body is StaticBody2D:
		queue_free()
