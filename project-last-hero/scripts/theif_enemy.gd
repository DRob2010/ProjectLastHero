extends CharacterBody2D

const DAGGER_THROW_SCENE: PackedScene = preload("res://scene_assets/dagger_throw.tscn")
const BURN_COLOR := Color(0.901961, 0.360784, 0.0, 1.0)
const BURN_DURATION := 3.0
const BURN_DAMAGE_INTERVAL := 1.0


@export var speed := 200.0
@export var target_path: NodePath = NodePath("../player")
@export var health := 50
@export var attack_damage := 10
@export var attack_cooldown := 0.8
@export var attack_duration := 0.28
@export var attack_windup_duration := 0.36
@export var attack_reach := 22.0
@export var throw_delay := 2.0
@export var throw_cooldown := 1.2
@export var throw_speed := 650.0
@export var throw_damage := 10
@export var throw_animation_duration := 0.28
@export var throw_windup_duration := 0.36
@export var retreat_speed := 180.0
@export var retreat_duration := 0.18
@export var path_refresh_interval := 0.15
@export var notice_distance := 48.0

var target: CharacterBody2D
var home_position := Vector2.ZERO
var max_health := 50
var is_dead := false
var original_collision_layer := 1
var original_collision_mask := 1
var attack_cooldown_left := 0.0
var attack_windup_time_left := 0.0
var attack_time_left := 0.0
var retreat_time_left := 0.0
var retreat_direction := Vector2.ZERO
var throw_time := 0.0
var throw_cooldown_left := 0.0
var throw_windup_time_left := 0.0
var throw_animation_time_left := 0.0
var throw_projectile_spawned := false
var path_refresh_time_left := 0.0
var navigation_map_ready := false
var wall_slide_time_left := 0.0
var wall_slide_direction := Vector2.ZERO
var dagger_throw_idle_position := Vector2.ZERO
var dagger_throw_idle_rotation := 0.0
var dagger_throw_position := Vector2.ZERO
var attack_hit := false
var dagger_idle_position := Vector2.ZERO
var dagger_idle_rotation := 0.0
var dagger_attack_position := Vector2.ZERO
var shine_original_scale := Vector2.ONE
var throw_shine_original_scale := Vector2.ONE
var enemy_original_color := Color.WHITE
var damage_flash_tween: Tween
var burn_time_left := 0.0
var burn_tick_time_left := 0.0
var slow_time_left := 0.0
var movement_speed_multiplier := 1.0

@onready var dagger_thrust: Area2D = $daggerThrust
@onready var dagger_thrust_collision: CollisionShape2D = $daggerThrust/CollisionShape2D
@onready var dagger_throw_visual: Area2D = $daggerThrow
@onready var dagger_throw_collision: CollisionShape2D = $daggerThrow/CollisionShape2D
@onready var shine: Sprite2D = $daggerThrust/shine
@onready var throw_shine: Sprite2D = $daggerThrow/shine
@onready var attack_area: Area2D = $attackArea
@onready var body_collision: CollisionShape2D = $CollisionShape2D
@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D
@onready var burn_effect: ColorRect = $effect
@onready var enemy_color_rect: ColorRect = $ColorRect


func take_damage(amount: int) -> void:
	if is_dead:
		return
	health -= amount
	_flash_when_damaged()
	if health <= 0:
		_mark_dead_for_save()
		_set_dead_state()


func _set_dead_state() -> void:
	is_dead = true
	health = 0
	_cancel_combat()
	visible = false
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	if body_collision:
		body_collision.set_deferred("disabled", true)
	if attack_area:
		attack_area.set_deferred("monitoring", false)
	if dagger_thrust:
		dagger_thrust.set_deferred("monitoring", false)
	if dagger_thrust_collision:
		dagger_thrust_collision.set_deferred("disabled", true)
	if dagger_throw_visual:
		dagger_throw_visual.set_deferred("monitoring", false)
	if dagger_throw_collision:
		dagger_throw_collision.set_deferred("disabled", true)


func set_dead_state() -> void:
	_set_dead_state()


func respawn_at_home() -> void:
	is_dead = false
	health = max_health
	global_position = home_position
	visible = true
	set_physics_process(true)
	collision_layer = original_collision_layer
	collision_mask = original_collision_mask
	if body_collision:
		body_collision.set_deferred("disabled", false)
	if attack_area:
		attack_area.set_deferred("monitoring", true)
	burn_time_left = 0.0
	slow_time_left = 0.0
	movement_speed_multiplier = 1.0
	burn_effect.visible = false
	_cancel_combat()


func _mark_dead_for_save() -> void:
	var scene := get_tree().current_scene
	if not scene:
		return
	var dead_enemy_names: Array = scene.get_meta("dead_enemy_names", []) as Array
	var enemy_name := str(name)
	if not dead_enemy_names.has(enemy_name):
		dead_enemy_names.append(enemy_name)
		scene.set_meta("dead_enemy_names", dead_enemy_names)


func _ready() -> void:
	target = get_node_or_null(target_path) as CharacterBody2D
	home_position = global_position
	max_health = health
	original_collision_layer = collision_layer
	original_collision_mask = collision_mask
	# Keep character bodies from physically pushing each other. Attack Areas still
	# detect the player because this only affects CharacterBody2D collisions.
	if target:
		add_collision_exception_with(target)
		target.add_collision_exception_with(self)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy != self and enemy is CollisionObject2D:
			add_collision_exception_with(enemy as CollisionObject2D)
			(enemy as CollisionObject2D).add_collision_exception_with(self)
	enemy_original_color = enemy_color_rect.color
	burn_effect.visible = false
	# Keep the dagger exactly where it was placed in the scene while idle.
	dagger_idle_position = dagger_thrust.position
	dagger_idle_rotation = dagger_thrust.rotation
	dagger_attack_position = attack_area.position + Vector2(0.0, -attack_reach)
	dagger_throw_idle_position = dagger_throw_visual.position
	dagger_throw_idle_rotation = dagger_throw_visual.rotation
	dagger_throw_position = attack_area.position
	if shine:
		shine_original_scale = shine.scale
		shine.scale = Vector2.ZERO
	if throw_shine:
		throw_shine_original_scale = throw_shine.scale
		throw_shine.scale = Vector2.ZERO
	if dagger_thrust:
		dagger_thrust.monitoring = false
	if dagger_thrust_collision:
		dagger_thrust_collision.disabled = true
	dagger_throw_visual.monitoring = false
	dagger_throw_collision.disabled = true
	dagger_thrust.body_entered.connect(_on_dagger_body_entered)
	navigation_agent.path_desired_distance = 8.0
	navigation_agent.target_desired_distance = 36.0
	navigation_agent.radius = 28.0
	# The baked navigation path handles wall routing. Local avoidance can keep
	# the thief trapped in an obstacle's avoidance radius, so leave it off.
	navigation_agent.avoidance_enabled = false


func _flash_when_damaged() -> void:
	if not enemy_color_rect:
		return
	if damage_flash_tween and damage_flash_tween.is_valid():
		damage_flash_tween.kill()
	enemy_color_rect.color = Color("982c35")
	damage_flash_tween = create_tween()
	damage_flash_tween.tween_property(enemy_color_rect, "color", enemy_original_color, 0.12)


func apply_burn() -> void:
	burn_time_left = BURN_DURATION
	burn_tick_time_left = BURN_DAMAGE_INTERVAL
	burn_effect.color = BURN_COLOR
	burn_effect.visible = true


func apply_slow(duration: float = 3.0, speed_multiplier: float = 0.5, effect_color: Color = Color(0.0, 0.933333, 1.0, 1.0)) -> void:
	slow_time_left = duration
	movement_speed_multiplier = speed_multiplier
	if burn_time_left <= 0.0:
		burn_effect.color = effect_color
		burn_effect.visible = true


func _update_slow(delta: float) -> void:
	if slow_time_left <= 0.0:
		return

	slow_time_left -= delta
	if slow_time_left <= 0.0:
		slow_time_left = 0.0
		movement_speed_multiplier = 1.0
		if burn_time_left <= 0.0:
			burn_effect.visible = false


func _update_burn(delta: float) -> void:
	if burn_time_left <= 0.0:
		return

	burn_time_left -= delta
	burn_tick_time_left -= delta
	if burn_tick_time_left <= 0.0:
		burn_tick_time_left += BURN_DAMAGE_INTERVAL
		take_damage(1)

	if burn_time_left <= 0.0:
		burn_time_left = 0.0
		burn_tick_time_left = 0.0
		if slow_time_left > 0.0:
			burn_effect.visible = true
		else:
			burn_effect.visible = false


func _physics_process(delta: float) -> void:
	if not target:
		velocity = Vector2.ZERO
		return

	_update_burn(delta)
	_update_slow(delta)
	var action_delta: float = delta * movement_speed_multiplier
	attack_cooldown_left = max(attack_cooldown_left - action_delta, 0.0)
	retreat_time_left = max(retreat_time_left - action_delta, 0.0)
	throw_cooldown_left = max(throw_cooldown_left - action_delta, 0.0)
	path_refresh_time_left = max(path_refresh_time_left - delta, 0.0)
	wall_slide_time_left = max(wall_slide_time_left - delta, 0.0)
	var navigation_map: RID = navigation_agent.get_navigation_map()
	navigation_map_ready = navigation_map.is_valid() and NavigationServer2D.map_get_iteration_id(navigation_map) > 0
	if not _is_target_noticed():
		_return_home(delta)
		move_and_slide()
		return

	_update_throw_animation(action_delta)

	var target_in_attack_area: bool = attack_area.overlaps_body(target)
	if target_in_attack_area:
		throw_time = 0.0
	elif attack_windup_time_left <= 0.0 and attack_time_left <= 0.0 and retreat_time_left <= 0.0 and throw_windup_time_left <= 0.0 and throw_animation_time_left <= 0.0:
		throw_time += action_delta
		if throw_time >= throw_delay and throw_cooldown_left <= 0.0:
			_start_throw_windup()
			throw_time = 0.0
	var direction: Vector2 = global_position.direction_to(target.global_position)
	if direction != Vector2.ZERO:
		rotation = direction.angle() + PI / 2.0

	if retreat_time_left > 0.0:
		velocity = retreat_direction * retreat_speed * movement_speed_multiplier
	elif throw_windup_time_left > 0.0:
		throw_windup_time_left -= action_delta
		velocity = Vector2.ZERO
		_update_throw_shine()
		if throw_windup_time_left <= 0.0:
			if throw_shine:
				throw_shine.scale = Vector2.ZERO
			_throw_dagger()
	elif attack_windup_time_left > 0.0:
		attack_windup_time_left -= action_delta
		attack_time_left = 0.0
		velocity = Vector2.ZERO
		_update_attack_shine()
		if attack_windup_time_left <= 0.0:
			_begin_dagger_attack()
	elif attack_time_left > 0.0:
		attack_time_left -= action_delta
		velocity = Vector2.ZERO
		var attack_progress: float = 1.0 - (attack_time_left / attack_duration)
		if attack_progress < 0.5:
			dagger_thrust.position = dagger_idle_position.lerp(
				dagger_attack_position, attack_progress * 2.0
			)
		else:
			dagger_thrust.position = dagger_idle_position.lerp(
				dagger_attack_position, (1.0 - attack_progress) * 2.0
			)
		dagger_thrust.rotation = 0.0
		if attack_time_left <= 0.0:
			_end_attack()
	elif not target_in_attack_area:
		var chase_direction: Vector2
		if wall_slide_time_left > 0.0 and not _has_clear_line_to_target():
			chase_direction = wall_slide_direction
		elif _has_clear_line_to_target():
			chase_direction = direction
		else:
			chase_direction = _get_navigation_direction_to(target.global_position)
		velocity = chase_direction * speed * movement_speed_multiplier
	elif attack_cooldown_left <= 0.0:
		velocity = Vector2.ZERO
		_start_attack()
	else:
		velocity = Vector2.ZERO

	move_and_slide()
	_record_wall_collision(direction, target_in_attack_area)


func _record_wall_collision(target_direction: Vector2, target_in_attack_area: bool) -> void:
	if target_in_attack_area or get_slide_collision_count() == 0:
		return

	for collision_index in get_slide_collision_count():
		var collision: KinematicCollision2D = get_slide_collision(collision_index)
		if not (collision.get_collider() is StaticBody2D):
			continue

		var wall_normal: Vector2 = collision.get_normal()
		var tangent_direction: Vector2 = Vector2(-wall_normal.y, wall_normal.x)
		if tangent_direction.dot(target_direction) < 0.0:
			tangent_direction = -tangent_direction
		wall_slide_direction = tangent_direction.normalized()
		wall_slide_time_left = 1.5
		return


func _get_navigation_direction() -> Vector2:
	return _get_navigation_direction_to(target.global_position)


func _get_navigation_direction_to(destination: Vector2) -> Vector2:
	if not navigation_map_ready:
		return Vector2.ZERO

	if path_refresh_time_left <= 0.0:
		navigation_agent.target_position = destination
		path_refresh_time_left = path_refresh_interval

	if navigation_agent.is_navigation_finished():
		return Vector2.ZERO

	var next_path_position: Vector2 = navigation_agent.get_next_path_position()
	if next_path_position == global_position:
		return Vector2.ZERO
	return global_position.direction_to(next_path_position)


func _is_target_noticed() -> bool:
	if not target or not is_instance_valid(target):
		return false
	# Notice range is based on the active camera viewport. An enemy that is
	# outside the camera should not wake up just because the player is visible.
	var enemy_screen_position: Vector2 = get_viewport().get_canvas_transform() * global_position
	var screen_rect := Rect2(Vector2.ZERO, get_viewport_rect().size)
	return screen_rect.grow(notice_distance).has_point(enemy_screen_position)


func is_player_noticed() -> bool:
	return not is_dead and _is_target_noticed()


func _return_home(delta: float) -> void:
	_cancel_combat()
	wall_slide_time_left = 0.0
	if global_position.distance_to(home_position) <= navigation_agent.target_desired_distance:
		velocity = Vector2.ZERO
		return

	# Refresh immediately when switching from pursuit to the home path.
	path_refresh_time_left = 0.0
	var home_direction: Vector2 = _get_navigation_direction_to(home_position)
	if home_direction == Vector2.ZERO:
		home_direction = global_position.direction_to(home_position)
	if home_direction != Vector2.ZERO:
		rotation = home_direction.angle() + PI / 2.0
	velocity = home_direction * speed * movement_speed_multiplier


func _cancel_combat() -> void:
	attack_cooldown_left = 0.0
	attack_windup_time_left = 0.0
	attack_time_left = 0.0
	retreat_time_left = 0.0
	throw_time = 0.0
	throw_windup_time_left = 0.0
	throw_animation_time_left = 0.0
	throw_projectile_spawned = false
	if shine:
		shine.scale = Vector2.ZERO
	if throw_shine:
		throw_shine.scale = Vector2.ZERO
	if dagger_thrust:
		dagger_thrust.position = dagger_idle_position
		dagger_thrust.rotation = dagger_idle_rotation
		dagger_thrust.monitoring = false
	if dagger_thrust_collision:
		dagger_thrust_collision.disabled = true
	if dagger_throw_visual:
		dagger_throw_visual.position = dagger_throw_idle_position
		dagger_throw_visual.rotation = dagger_throw_idle_rotation
		dagger_throw_visual.visible = true


func _has_clear_line_to_target() -> bool:
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
		global_position,
		target.global_position
	)
	query.exclude = [get_rid(), target.get_rid()]
	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	return not (hit.get("collider") is StaticBody2D)


func _start_attack() -> void:
	throw_time = 0.0
	attack_windup_time_left = attack_windup_duration
	attack_time_left = 0.0
	attack_cooldown_left = attack_cooldown
	attack_hit = false
	if dagger_thrust:
		dagger_thrust.position = dagger_idle_position
		dagger_thrust.rotation = dagger_idle_rotation
		dagger_thrust.monitoring = false
	if dagger_thrust_collision:
		dagger_thrust_collision.disabled = true
	if shine:
		shine.scale = Vector2.ZERO


func _update_attack_shine() -> void:
	_update_shine(shine, shine_original_scale, attack_windup_time_left, attack_windup_duration)


func _update_throw_shine() -> void:
	_update_shine(throw_shine, throw_shine_original_scale, throw_windup_time_left, throw_windup_duration)


func _update_shine(shining_sprite: Sprite2D, original_scale: Vector2, time_left: float, duration: float) -> void:
	if not shining_sprite:
		return
	var shine_progress: float = 1.0 - (time_left / duration)
	if shine_progress < 0.5:
		shining_sprite.scale = original_scale * (shine_progress * 2.0)
	else:
		shining_sprite.scale = original_scale * ((1.0 - shine_progress) * 2.0)


func _begin_dagger_attack() -> void:
	attack_time_left = attack_duration
	if dagger_thrust:
		dagger_thrust.position = dagger_idle_position
		dagger_thrust.rotation = dagger_idle_rotation
	if dagger_thrust:
		dagger_thrust.monitoring = true
	if dagger_thrust_collision:
		dagger_thrust_collision.disabled = false


func _throw_dagger() -> void:
	throw_cooldown_left = throw_cooldown
	throw_animation_time_left = throw_animation_duration
	throw_projectile_spawned = false
	if dagger_throw_visual:
		dagger_throw_visual.visible = true
		dagger_throw_visual.position = dagger_throw_idle_position
		dagger_throw_visual.rotation = dagger_throw_idle_rotation


func _start_throw_windup() -> void:
	throw_windup_time_left = throw_windup_duration
	if throw_shine:
		throw_shine.scale = Vector2.ZERO


func _spawn_thrown_dagger() -> void:
	var throw_direction: Vector2 = global_position.direction_to(target.global_position)
	if throw_direction == Vector2.ZERO:
		return
	var thrown_dagger: Area2D = DAGGER_THROW_SCENE.instantiate() as Area2D
	get_tree().current_scene.add_child(thrown_dagger)
	thrown_dagger.global_position = global_position + throw_direction * 24.0
	thrown_dagger.set("shooter", self)
	thrown_dagger.set("damage", throw_damage)
	thrown_dagger.call("setup", throw_direction, throw_speed)


func _update_throw_animation(delta: float) -> void:
	if throw_animation_time_left <= 0.0:
		return

	throw_animation_time_left -= delta
	var throw_progress: float = 1.0 - (throw_animation_time_left / throw_animation_duration)
	if throw_progress < 0.5:
		var outward_progress: float = throw_progress * 2.0
		if dagger_throw_visual:
			dagger_throw_visual.position = dagger_throw_idle_position.lerp(dagger_throw_position, outward_progress)
			dagger_throw_visual.rotation = lerp_angle(dagger_throw_idle_rotation, 0.0, outward_progress)
	else:
		var return_progress: float = (throw_progress - 0.5) * 2.0
		if dagger_throw_visual:
			dagger_throw_visual.position = dagger_throw_position.lerp(dagger_throw_idle_position, return_progress)
			dagger_throw_visual.rotation = lerp_angle(0.0, dagger_throw_idle_rotation, return_progress)
		if not throw_projectile_spawned:
			throw_projectile_spawned = true
			_spawn_thrown_dagger()
			if dagger_throw_visual:
				dagger_throw_visual.visible = false

	if throw_animation_time_left <= 0.0:
		if dagger_throw_visual:
			dagger_throw_visual.position = dagger_throw_idle_position
			dagger_throw_visual.rotation = dagger_throw_idle_rotation
			dagger_throw_visual.visible = true


func _end_attack() -> void:
	attack_time_left = 0.0
	if dagger_thrust:
		dagger_thrust.position = dagger_idle_position
		dagger_thrust.rotation = dagger_idle_rotation
	if shine:
		shine.scale = Vector2.ZERO
	dagger_thrust.monitoring = false
	dagger_thrust_collision.disabled = true
	if target:
		retreat_direction = target.global_position.direction_to(global_position)
		retreat_time_left = retreat_duration


func defuse_attack() -> void:
	if attack_time_left > 0.0:
		# The attack animation continues, but the shield disables its damage.
		attack_hit = true
		# Shield signals can fire while Godot is flushing Area2D queries, so
		# defer the physics state changes until the query is finished.
		if dagger_thrust:
			dagger_thrust.set_deferred("monitoring", false)
		if dagger_thrust_collision:
			dagger_thrust_collision.set_deferred("disabled", true)


func _on_dagger_body_entered(body: Node2D) -> void:
	if attack_time_left > 0.0 and not attack_hit and body == target and body.has_method("take_damage"):
		attack_hit = true
		body.take_damage(attack_damage)
