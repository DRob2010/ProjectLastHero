extends CharacterBody2D

signal spell_cast(spell_name: String)

const FIRESTARTER_SCENE: PackedScene = preload("res://scene_assets/firestarter.tscn")
const COLD_PILLAR_SCENE: PackedScene = preload("res://scene_assets/cold_pillar.tscn")
const LIGHTNING_CHAIN_SCENE: PackedScene = preload("res://scene_assets/lightning_chain.tscn")
const STONE_WALL_SCENE: PackedScene = preload("res://scene_assets/stone_wall.tscn")
const LIGHTNING_GROUP := "lightning_chain_effect"
const COLD_PILLAR_DISTANCE := 240.0
const LIGHTNING_START_DISTANCE := 28.0
const STONE_WALL_DISTANCE := 100.0

@export var speed := 250.0
@export var player_path: NodePath = NodePath("../player")
@export var follow_distance := 4.0
@export var max_distance_from_player := 200.0

var player: Node2D
var marker_points: Array[Marker2D] = []
var selected_spell := ""
var hold_saved_position_once := false


func set_selected_spell(spell_name: String) -> void:
	selected_spell = spell_name


func _ready() -> void:
	player = get_node_or_null(player_path) as Node2D
	if player:
		var marker_container: Node = player.get_node_or_null("followPoints")
		var marker_source: Node = marker_container if marker_container else player
		for point_number in range(1, 5):
			var marker: Marker2D = marker_source.get_node_or_null("pos" + str(point_number)) as Marker2D
			if marker and marker.get_node_or_null("Area2D") is Area2D:
				marker_points.append(marker)


func _physics_process(_delta: float) -> void:
	if hold_saved_position_once:
		hold_saved_position_once = false
		velocity = Vector2.ZERO
		return

	if Input.is_action_just_pressed("attack"):
		var spell_was_cast := false
		if selected_spell == "Firestarter":
			spell_was_cast = _throw_firestarter()
		elif selected_spell == "Cold\nPillar":
			spell_was_cast = _cast_cold_pillar()
		elif selected_spell == "Lightning Chain":
			spell_was_cast = _cast_lightning_chain()
		elif selected_spell == "Stone Wall":
			spell_was_cast = _cast_stone_wall()
		if spell_was_cast:
			selected_spell = ""

	if not get_tree().get_nodes_in_group(LIGHTNING_GROUP).is_empty():
		velocity = Vector2.ZERO
		return

	if not player:
		velocity = Vector2.ZERO
		return

	var target_marker: Marker2D = _get_available_marker()
	var destination: Vector2 = target_marker.global_position if target_marker else player.global_position
	var current_speed: float = speed
	if player and global_position.distance_to(player.global_position) > max_distance_from_player:
		destination = player.global_position
		if player is CharacterBody2D:
			current_speed = max(speed, (player as CharacterBody2D).velocity.length())

	var distance_to_destination: float = global_position.distance_to(destination)
	if distance_to_destination > follow_distance:
		var direction: Vector2 = global_position.direction_to(destination)
		velocity = direction * current_speed
	else:
		velocity = Vector2.ZERO

	move_and_slide()


func restore_saved_position(saved_position: Vector2) -> void:
	global_position = saved_position
	hold_saved_position_once = true


func _throw_firestarter() -> bool:
	if not player or not player.has_method("consume_mana") or not player.consume_mana(2):
		return false

	var firestarter: Area2D = FIRESTARTER_SCENE.instantiate() as Area2D
	get_tree().current_scene.add_child(firestarter)
	firestarter.global_position = global_position

	var direction: Vector2 = _get_spell_target_direction(global_position)

	if firestarter.has_method("setup"):
		firestarter.setup(direction, 550.0, self, player)
	spell_cast.emit("Firestarter")
	return true


func _cast_cold_pillar() -> bool:
	if not player or not player.has_method("consume_mana") or not player.consume_mana(4):
		return false

	var cold_pillar: Area2D = COLD_PILLAR_SCENE.instantiate() as Area2D
	get_tree().current_scene.add_child(cold_pillar)
	var direction: Vector2 = Vector2.UP.rotated(player.global_rotation).normalized()
	var focused_enemy: Node2D = _get_focused_enemy()
	if focused_enemy and player.global_position.distance_to(focused_enemy.global_position) <= COLD_PILLAR_DISTANCE:
		cold_pillar.global_position = focused_enemy.global_position
	else:
		cold_pillar.global_position = player.global_position + direction * COLD_PILLAR_DISTANCE
	cold_pillar.rotation = 0.0
	if cold_pillar.has_method("start_grow_animation"):
		cold_pillar.start_grow_animation()
	spell_cast.emit("Cold\nPillar")
	return true


func _cast_lightning_chain() -> bool:
	if not player or not player.has_method("consume_mana") or not player.consume_mana(3):
		return false

	var lightning_chain: Area2D = LIGHTNING_CHAIN_SCENE.instantiate() as Area2D
	get_tree().current_scene.add_child(lightning_chain)
	var direction: Vector2 = _get_spell_target_direction(global_position)
	lightning_chain.global_position = global_position + direction * LIGHTNING_START_DISTANCE
	if lightning_chain.has_method("setup"):
		lightning_chain.setup(direction, 0, self, player)
	spell_cast.emit("Lightning Chain")
	return true


func _get_spell_target_direction(origin: Vector2) -> Vector2:
	var fallback_direction: Vector2 = Vector2.UP.rotated(player.global_rotation).normalized()
	var focused_enemy: Node2D = _get_focused_enemy()
	if focused_enemy:
		var target_direction: Vector2 = origin.direction_to(focused_enemy.global_position)
		if target_direction != Vector2.ZERO:
			return target_direction
	return fallback_direction


func _get_focused_enemy() -> Node2D:
	if player and player.has_method("get_focused_enemy"):
		return player.call("get_focused_enemy") as Node2D
	return null


func _cast_stone_wall() -> bool:
	if not player or not player.has_method("consume_mana") or not player.consume_mana(5):
		return false

	var stone_wall: StaticBody2D = STONE_WALL_SCENE.instantiate() as StaticBody2D
	get_tree().current_scene.add_child(stone_wall)
	var direction := Vector2.UP.rotated(player.global_rotation).normalized()
	stone_wall.global_position = player.global_position + direction * STONE_WALL_DISTANCE
	stone_wall.rotation = player.global_rotation
	if stone_wall.has_method("start_grow_animation"):
		stone_wall.start_grow_animation()
	spell_cast.emit("Stone Wall")
	return true


func _get_available_marker() -> Marker2D:
	# Prefer the closest clear point from pos1/pos2.
	var primary_marker: Marker2D = _get_closest_clear_marker(0, 2)
	if primary_marker:
		return primary_marker

	# Use pos3/pos4 only when both primary points are blocked.
	return _get_closest_clear_marker(2, 4)


func _get_closest_clear_marker(start_index: int, end_index: int) -> Marker2D:
	var closest_marker: Marker2D
	var closest_distance: float = INF
	var checked_end: int = min(end_index, marker_points.size())

	for marker_index in range(start_index, checked_end):
		var marker: Marker2D = marker_points[marker_index]
		var marker_area := marker.get_node_or_null("Area2D") as Area2D
		if marker_area and not _area_is_touching_wall(marker_area):
			var marker_distance: float = global_position.distance_to(marker.global_position)
			if marker_distance < closest_distance:
				closest_marker = marker
				closest_distance = marker_distance

	return closest_marker


func _area_is_touching_wall(area: Area2D) -> bool:
	for body in area.get_overlapping_bodies():
		if body is StaticBody2D:
			return true
	return false
