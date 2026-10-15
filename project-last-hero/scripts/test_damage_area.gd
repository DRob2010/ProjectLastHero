extends Node2D


@export var damage := 10
@export var damage_interval := 0.25

@onready var damage_area: Area2D = $Area2D

var player_inside: Node2D
var damage_time_left := 0.0


func _ready() -> void:
	damage_area.body_entered.connect(_on_damage_area_body_entered)
	damage_area.body_exited.connect(_on_damage_area_body_exited)


func _physics_process(delta: float) -> void:
	if not player_inside:
		return

	damage_time_left -= delta
	if damage_time_left <= 0.0:
		damage_time_left = damage_interval
		player_inside.take_damage(damage)


func _on_damage_area_body_entered(body: Node2D) -> void:
	if body.has_method("take_damage"):
		player_inside = body
		damage_time_left = 0.0


func _on_damage_area_body_exited(body: Node2D) -> void:
	if body == player_inside:
		player_inside = null
