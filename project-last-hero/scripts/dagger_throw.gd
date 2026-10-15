extends Area2D


@export var speed := 650.0
@export var lifetime := 2.0
@export var damage := 10
@export var max_distance := 600.0

var direction := Vector2.UP
var start_position := Vector2.ZERO
var shooter: Node2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func setup(new_direction: Vector2, new_speed: float = 650.0) -> void:
	direction = new_direction.normalized()
	speed = new_speed
	start_position = global_position
	rotation = direction.angle() + PI / 2.0


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0.0 or global_position.distance_to(start_position) >= max_distance:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body == shooter:
		return
	if body.is_in_group("enemies"):
		return
	if body.has_method("take_damage"):
		body.take_damage(damage)
		queue_free()
	elif body is StaticBody2D:
		queue_free()


func defuse_attack() -> void:
	queue_free()
