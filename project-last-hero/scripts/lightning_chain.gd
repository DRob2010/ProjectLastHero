extends Area2D

const MAX_CHAIN_SEGMENTS := 8
const SEGMENT_DELAY := 0.02
const LIGHTNING_GROUP := "lightning_chain_effect"
const FINISH_LINGER_TIME := 0.0
const ENEMY_GROUP := "enemies"
const LIGHTNING_DAMAGE_MIN := 6
const LIGHTNING_DAMAGE_MAX := 8

var direction := Vector2.UP
var chain_index := 0
var shooter: Node2D
var protected_target: Node2D
var blocked := false
var hit_targets: Array[Node2D] = []
var initial_cast_range := 0.0
@export var segment_distance := 38.0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	add_to_group(LIGHTNING_GROUP)
	body_entered.connect(_on_body_entered)
	_create_next_segment()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func setup(new_direction: Vector2, new_chain_index: int, new_shooter: Node2D, new_protected_target: Node2D, new_hit_targets: Array[Node2D] = [], new_initial_cast_range: float = -1.0) -> void:
	direction = new_direction.normalized()
	chain_index = new_chain_index
	shooter = new_shooter
	protected_target = new_protected_target
	if new_hit_targets.is_empty():
		hit_targets = []
	else:
		hit_targets = new_hit_targets
	initial_cast_range = MAX_CHAIN_SEGMENTS * segment_distance if new_initial_cast_range <= 0.0 else new_initial_cast_range
	rotation = direction.angle() + PI / 2.0


func _create_next_segment() -> void:
	await get_tree().create_timer(SEGMENT_DELAY).timeout
	if blocked or not is_inside_tree():
		return
	if chain_index + 1 >= MAX_CHAIN_SEGMENTS:
		_remove_chain_after_delay()
		return

	var chain_scene := load("res://scene_assets/lightning_chain.tscn") as PackedScene
	var next_segment: Area2D = chain_scene.instantiate() as Area2D
	get_tree().current_scene.add_child(next_segment)
	next_segment.global_position = global_position + direction * segment_distance
	if next_segment.has_method("setup"):
		next_segment.setup(direction, chain_index + 1, shooter, protected_target, hit_targets, initial_cast_range)


func _on_body_entered(body: Node2D) -> void:
	if blocked or body == shooter or body == protected_target or hit_targets.has(body):
		return

	blocked = true
	if body.has_method("take_damage"):
		hit_targets.append(body)
		body.take_damage(randi_range(LIGHTNING_DAMAGE_MIN, LIGHTNING_DAMAGE_MAX))
		var next_enemy: Node2D = _find_next_enemy(body)
		_remove_chain()
		if next_enemy and chain_index + 1 < MAX_CHAIN_SEGMENTS:
			_spawn_jump_segment(body.global_position, next_enemy.global_position)
	else:
		_remove_chain()


func _find_next_enemy(from_enemy: Node2D) -> Node2D:
	var closest_enemy: Node2D = null
	var closest_distance_squared: float = initial_cast_range * initial_cast_range
	for candidate in get_tree().get_nodes_in_group(ENEMY_GROUP):
		if not (candidate is Node2D) or candidate == shooter or candidate == protected_target:
			continue
		var enemy: Node2D = candidate as Node2D
		if hit_targets.has(enemy) or not enemy.has_method("take_damage"):
			continue
		var distance_squared: float = from_enemy.global_position.distance_squared_to(enemy.global_position)
		if distance_squared <= closest_distance_squared:
			closest_distance_squared = distance_squared
			closest_enemy = enemy
	return closest_enemy


func _spawn_jump_segment(from_position: Vector2, to_position: Vector2) -> void:
	var jump_direction: Vector2 = from_position.direction_to(to_position)
	if jump_direction == Vector2.ZERO:
		return
	var chain_scene := load("res://scene_assets/lightning_chain.tscn") as PackedScene
	var jump_segment: Area2D = chain_scene.instantiate() as Area2D
	get_tree().current_scene.add_child(jump_segment)
	jump_segment.global_position = from_position
	if jump_segment.has_method("setup"):
		jump_segment.setup(jump_direction, chain_index + 1, shooter, protected_target, hit_targets, initial_cast_range)


func _remove_chain_after_delay() -> void:
	await get_tree().create_timer(FINISH_LINGER_TIME).timeout
	_remove_chain()


func _remove_chain() -> void:
	for segment in get_tree().get_nodes_in_group(LIGHTNING_GROUP):
		segment.queue_free()
