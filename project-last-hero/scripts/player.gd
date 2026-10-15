extends CharacterBody2D


signal health_changed(current_health: int, maximum_health: int)
signal mana_changed(current_mana: int, maximum_mana: int)
signal arrows_changed(current_arrows: int)

const ARROW_SCENE: PackedScene = preload("res://scene_assets/arrow.tscn")
const BOW_TEXTURE: Texture2D = preload("res://art/player_bow.png")
const BOW_ARROW_TEXTURE: Texture2D = preload("res://art/player_bow&arrow.png")
const BOW_NO_ARROWS_TEXTURE: Texture2D = preload("res://art/player_bow_noArrows.png")
const SPEED = 300.0
const DASH_SPEED = 600.0
const DASH_DURATION = 0.15
const DASH_COOLDOWN = 0.5
const ATTACK_DURATION = 0.4
const ATTACK_DAMAGE_START := 0.25
const ATTACK_COOLDOWN = 0.3
const ATTACK_MOVE_SPEED = 50.0
const STAB_LUNGE_SPEED = 250.0
const SWORD_DAMAGE_MIN := 8
const SWORD_DAMAGE_MAX := 12
const SWORD_ATTACK_POSITION := Vector2(0.0, -32.0)
const SWORD_STAB_POSITION := Vector2(0.0, -52.0)
const SWORD_SWING_ANGLE := PI * 0.6
const COMBO_RESET_TIME = 0.8
const SHIELD_POSITION := Vector2(0.0, -28.0)
const SHIELD_ROTATION_OFFSET := PI / 2.0
const SHIELD_ANIMATION_SPEED := 12.0
const SHIELD_MOVE_SPEED_MULTIPLIER := 0.5
const SHIELD_KNOCKBACK_SPEED := 260.0
const SHIELD_KNOCKBACK_DURATION := 0.15
const BOW_COOLDOWN := 0.25
const BOW_MIN_DRAW_TIME := 0.15
const BOW_MAX_DRAW_TIME := 2.0
const ARROW_MIN_SPEED := 450.0
const ARROW_MAX_SPEED := 1100.0
const INVINCIBILITY_DURATION := 1.0
const INVINCIBILITY_BLINK_INTERVAL := 0.1
const INVINCIBILITY_COLOR := Color(0.0, 0.2, 0.0, 1.0)
const MANA_REGEN_INTERVAL := 5.0
const ARROW_REGEN_INTERVAL := 3.0

@export var max_health := 100
@export var max_mana := 10
@export var max_arrows := 15

var last_direction := Vector2.DOWN
var dash_direction := Vector2.ZERO
var dash_speed := DASH_SPEED
var dash_time_left := 0.0
var dash_cooldown_left := 0.0
var dash_blocked_until_release := false
var attack_direction := Vector2.DOWN
var attack_time_left := 0.0
var attack_cooldown_left := 0.0
var bow_cooldown_left := 0.0
var bow_draw_time := 0.0
var health := 0
var mana := 0
var arrows_remaining := 0
var arrow_regen_time_left := ARROW_REGEN_INTERVAL
var mana_regen_time_left := MANA_REGEN_INTERVAL
var invincibility_time_left := 0.0
var invincibility_blink_time_left := 0.0
var shield_knockback_time_left := 0.0
var shield_knockback_velocity := Vector2.ZERO
var combo_reset_time_left := 0.0
var combo_step := 0
var combo_queued := false
var attack_hit_bodies: Array[Node2D] = []
var bow_equipped := false
var bow_started_empty := false
var spell_attack_armed := false
var spell_attack_blocked := false
var rest_area_count := 0
var rest_label_offset := Vector2.ZERO
var sword_idle_position := Vector2.ZERO
var sword_idle_rotation := 0.0
var shield_idle_position := Vector2.ZERO
var shield_idle_rotation := 0.0

@onready var sword: Node2D = $sword
@onready var sword_area: Area2D = $sword/Area2D
@onready var sword_collision: CollisionShape2D = $sword/Area2D/CollisionShape2D
@onready var shield: Node2D = $shield
@onready var shield_area: Area2D = $shield/Area2D
@onready var shield_collision: CollisionShape2D = $shield/Area2D/CollisionShape2D
@onready var bow: Node2D = $bow
@onready var bow_sprite: Sprite2D = $bow/Sprite2D
@onready var rest_label: Label = $rest
@onready var player_color_rect: ColorRect = find_child("ColorRect", true, false) as ColorRect

var player_original_color := Color.WHITE


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	health = max_health
	mana = max_mana
	arrows_remaining = max_arrows
	health_changed.emit(health, max_health)
	mana_changed.emit(mana, max_mana)
	arrows_changed.emit(arrows_remaining)
	if player_color_rect:
		player_original_color = player_color_rect.color
	sword_idle_position = sword.position
	sword_idle_rotation = sword.rotation
	shield_idle_position = shield.position
	shield_idle_rotation = shield.rotation
	sword.visible = true
	sword_area.monitoring = false
	sword_collision.disabled = true
	sword_area.body_entered.connect(_on_sword_body_entered)
	shield.visible = true
	shield_area.monitoring = false
	shield_collision.disabled = true
	shield_area.body_entered.connect(_on_shield_body_entered)
	shield_area.area_entered.connect(_on_shield_area_entered)
	bow.visible = false
	bow_sprite.texture = BOW_TEXTURE
	rest_label_offset = rest_label.position
	rest_label.top_level = true
	rest_label.visible = false
	_update_rest_label_transform()
	# Characters can pass through one another, while their collision with walls
	# remains unchanged. Add exceptions for enemies that already exist in the scene.
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is CollisionObject2D:
			add_collision_exception_with(enemy as CollisionObject2D)


func _physics_process(_delta: float) -> void:
	_update_mana_regeneration(_delta)
	_update_arrow_regeneration(_delta)
	if not Input.is_action_pressed("dash"):
		dash_blocked_until_release = false

	var block_current_attack: bool = spell_attack_blocked
	if Input.is_action_just_pressed("attack") and spell_attack_armed:
		spell_attack_armed = false
		spell_attack_blocked = true
		block_current_attack = true

	# Input.get_vector() combines the four actions and normalizes diagonal input,
	# so moving diagonally is not faster than moving horizontally or vertically.
	var direction := Input.get_vector("moveLeft", "moveRight", "moveUp", "moveDown")
	if direction != Vector2.ZERO:
		last_direction = direction
		# The player's artwork faces upward by default, so rotate the body
		# until its local up direction matches the movement direction.
		rotation = last_direction.angle() + PI / 2.0

	if Input.is_action_just_pressed("weaponSwap") and attack_time_left <= 0.0:
		_toggle_weapon()

	var is_shielding: bool = not bow_equipped and Input.is_action_pressed("shielding") and attack_time_left <= 0.0
	var is_focusing_enemy: bool = Input.is_action_pressed("shielding") and attack_time_left <= 0.0
	if is_focusing_enemy:
		var nearest_enemy: Node2D = _get_nearest_visible_enemy()
		if nearest_enemy:
			var enemy_direction: Vector2 = global_position.direction_to(nearest_enemy.global_position)
			if enemy_direction != Vector2.ZERO:
				# Focus changes the player's facing, but does not replace the
				# movement direction used by dash.
				rotation = enemy_direction.angle() + PI / 2.0
	if bow_equipped and Input.is_action_just_pressed("attack") and not block_current_attack:
		bow_started_empty = arrows_remaining <= 0
	var is_drawing_bow: bool = bow_equipped and Input.is_action_pressed("attack") and not block_current_attack
	if is_drawing_bow:
		bow_sprite.texture = BOW_NO_ARROWS_TEXTURE if bow_started_empty or arrows_remaining <= 0 else BOW_ARROW_TEXTURE
	else:
		bow_sprite.texture = BOW_TEXTURE
	if bow_equipped:
		if Input.is_action_just_pressed("attack") and not block_current_attack:
			bow_draw_time = 0.0
		if Input.is_action_pressed("attack") and not block_current_attack:
			bow_draw_time += _delta
	else:
		bow_draw_time = 0.0
	shield.visible = not bow_equipped
	shield_area.monitoring = is_shielding
	shield_collision.disabled = not is_shielding
	var shield_target_position: Vector2 = SHIELD_POSITION if is_shielding else shield_idle_position
	var shield_target_rotation: float = shield_idle_rotation + SHIELD_ROTATION_OFFSET if is_shielding else shield_idle_rotation
	var shield_animation_weight: float = min(_delta * SHIELD_ANIMATION_SPEED, 1.0)
	shield.position = shield.position.lerp(shield_target_position, shield_animation_weight)
	shield.rotation = lerp_angle(shield.rotation, shield_target_rotation, shield_animation_weight)
	if dash_cooldown_left > 0.0:
		dash_cooldown_left -= _delta
	if attack_cooldown_left > 0.0:
		attack_cooldown_left -= _delta
	if bow_cooldown_left > 0.0:
		bow_cooldown_left -= _delta
	_update_invincibility(_delta)
	if shield_knockback_time_left > 0.0:
		shield_knockback_time_left -= _delta
	if combo_reset_time_left > 0.0:
		combo_reset_time_left -= _delta
	elif attack_time_left <= 0.0:
		combo_step = 0

	if attack_time_left > 0.0:
		attack_time_left -= _delta
		var attack_progress: float = 1.0 - (attack_time_left / ATTACK_DURATION)
		var sword_damage_active: bool = attack_progress >= ATTACK_DAMAGE_START
		sword_area.monitoring = sword_damage_active
		sword_collision.disabled = not sword_damage_active
		if combo_step == 3:
			sword.rotation = sword_idle_rotation
		else:
			var first_swing_angle: float = sword_idle_rotation + SWORD_SWING_ANGLE if combo_step == 1 else sword_idle_rotation - SWORD_SWING_ANGLE
			var second_swing_angle: float = sword_idle_rotation - SWORD_SWING_ANGLE if combo_step == 1 else sword_idle_rotation + SWORD_SWING_ANGLE
			if attack_progress < 0.333:
				var first_progress: float = attack_progress * 3.0
				sword.rotation = lerp(sword_idle_rotation, first_swing_angle, first_progress)
			elif attack_progress < 0.666:
				var second_progress: float = (attack_progress - 0.333) * 3.0
				sword.rotation = lerp(first_swing_angle, second_swing_angle, second_progress)
			else:
				var return_progress: float = (attack_progress - 0.666) * 3.0
				sword.rotation = lerp(second_swing_angle, sword_idle_rotation, return_progress)

		if attack_progress < 0.5:
			var outward_progress: float = attack_progress * 2.0
			var attack_position: Vector2 = SWORD_STAB_POSITION if combo_step == 3 else SWORD_ATTACK_POSITION
			sword.position = sword_idle_position.lerp(attack_position, outward_progress)
		else:
			var inward_progress: float = (attack_progress - 0.5) * 2.0
			var attack_position: Vector2 = SWORD_STAB_POSITION if combo_step == 3 else SWORD_ATTACK_POSITION
			sword.position = attack_position.lerp(sword_idle_position, inward_progress)
		if attack_time_left <= 0.0:
			_end_attack()

	if Input.is_action_just_pressed("attack") and not block_current_attack and not bow_equipped and not is_shielding:
		if attack_time_left > 0.0:
			if combo_step < 3:
				combo_queued = true
		elif attack_cooldown_left <= 0.0:
			if combo_step == 0 or combo_step == 3:
				combo_step = 1
			else:
				combo_step += 1
			_start_attack()

	if bow_equipped and Input.is_action_just_released("attack") and not block_current_attack:
		if not bow_started_empty and bow_draw_time >= BOW_MIN_DRAW_TIME and bow_cooldown_left <= 0.0:
			_fire_arrow()
		bow_draw_time = 0.0
	if Input.is_action_just_released("attack"):
		bow_started_empty = false
		spell_attack_blocked = false

	if shield_knockback_time_left > 0.0:
		velocity = shield_knockback_velocity
	elif dash_time_left > 0.0 and attack_time_left <= 0.0:
		dash_time_left -= _delta
		velocity = dash_direction * dash_speed
	elif attack_time_left > 0.0:
		dash_time_left = 0.0
		if combo_step == 3:
			# The stab ignores movement input but lunges in the facing direction.
			velocity = attack_direction * STAB_LUNGE_SPEED
		else:
			velocity = direction * ATTACK_MOVE_SPEED
	else:
		if Input.is_action_just_pressed("dash") and not dash_blocked_until_release and dash_cooldown_left <= 0.0 and attack_time_left <= 0.0:
			dash_direction = last_direction
			dash_speed = DASH_SPEED * 1.5
			dash_time_left = DASH_DURATION
			dash_cooldown_left = DASH_COOLDOWN
			velocity = dash_direction * dash_speed
		else:
			var movement_speed: float = SPEED
			if is_shielding:
				movement_speed *= SHIELD_MOVE_SPEED_MULTIPLIER
			velocity = direction * movement_speed

	move_and_slide()
	_update_rest_label_transform()


func block_dash_until_release() -> void:
	dash_blocked_until_release = true


func enter_rest_area() -> void:
	rest_area_count += 1
	rest_label.visible = true


func exit_rest_area() -> void:
	rest_area_count = max(rest_area_count - 1, 0)
	rest_label.visible = rest_area_count > 0


func is_resting() -> bool:
	return rest_area_count > 0 and rest_label.visible


func set_rest_prompt_visible(should_show: bool) -> void:
	rest_label.visible = should_show and rest_area_count > 0


func restore_full_health() -> void:
	health = max_health
	invincibility_time_left = 0.0
	health_changed.emit(health, max_health)


func _update_rest_label_transform() -> void:
	if not rest_label:
		return
	rest_label.global_position = global_position + rest_label_offset
	rest_label.rotation = 0.0


func _get_nearest_visible_enemy() -> Node2D:
	var viewport_size: Vector2 = get_viewport_rect().size
	var inverse_canvas_transform: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	var world_corner_a: Vector2 = inverse_canvas_transform * Vector2.ZERO
	var world_corner_b: Vector2 = inverse_canvas_transform * viewport_size
	var visible_world_rect: Rect2 = Rect2(
		Vector2(min(world_corner_a.x, world_corner_b.x), min(world_corner_a.y, world_corner_b.y)),
		Vector2(abs(world_corner_b.x - world_corner_a.x), abs(world_corner_b.y - world_corner_a.y))
	)

	var nearest_enemy: Node2D = null
	var nearest_distance_squared := INF
	for candidate in get_tree().get_nodes_in_group("enemies"):
		if not candidate is Node2D or candidate == self or not candidate.has_method("take_damage"):
			continue
		var enemy: Node2D = candidate as Node2D
		if not visible_world_rect.has_point(enemy.global_position):
			continue
		var distance_squared: float = global_position.distance_squared_to(enemy.global_position)
		if distance_squared < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			nearest_enemy = enemy

	return nearest_enemy


func get_focused_enemy() -> Node2D:
	if not Input.is_action_pressed("shielding") or attack_time_left > 0.0:
		return null
	return _get_nearest_visible_enemy()


func _start_attack() -> void:
	attack_time_left = ATTACK_DURATION
	attack_cooldown_left = ATTACK_COOLDOWN
	combo_reset_time_left = COMBO_RESET_TIME
	attack_hit_bodies.clear()
	# The player artwork faces up locally, so convert that local direction
	# through the player's rotation to get the actual world-facing direction.
	attack_direction = Vector2.UP.rotated(global_rotation).normalized()
	sword.visible = true
	sword_area.monitoring = false
	sword_collision.disabled = true
	sword.position = sword_idle_position
	sword.rotation = sword_idle_rotation


func _toggle_weapon() -> void:
	bow_equipped = not bow_equipped
	bow.visible = bow_equipped
	sword.visible = not bow_equipped
	shield.visible = not bow_equipped

	if bow_equipped:
		shield_area.monitoring = false
		shield_collision.disabled = true
		sword_area.monitoring = false
		sword_collision.disabled = true
		shield.position = shield_idle_position
		shield.rotation = shield_idle_rotation


func _fire_arrow() -> bool:
	if arrows_remaining <= 0:
		return false

	bow_cooldown_left = BOW_COOLDOWN
	arrows_remaining -= 1
	arrows_changed.emit(arrows_remaining)
	var arrow: Area2D = ARROW_SCENE.instantiate() as Area2D
	get_tree().current_scene.add_child(arrow)
	var direction: Vector2 = Vector2.UP.rotated(global_rotation).normalized()
	var charge_ratio: float = clamp((bow_draw_time - BOW_MIN_DRAW_TIME) / (BOW_MAX_DRAW_TIME - BOW_MIN_DRAW_TIME), 0.0, 1.0)
	var arrow_speed: float = lerp(ARROW_MIN_SPEED, ARROW_MAX_SPEED, charge_ratio)
	arrow.global_position = bow.global_position + direction * 18.0
	arrow.set("shooter", self)
	arrow.call("setup", direction, arrow_speed)
	return true


func _end_attack() -> void:
	sword.visible = true
	sword_area.monitoring = false
	sword_collision.disabled = true
	sword.position = sword_idle_position
	sword.rotation = sword_idle_rotation
	if combo_queued and combo_step < 3:
		combo_queued = false
		combo_step += 1
		_start_attack()


func _on_sword_body_entered(body: Node2D) -> void:
	if body == self:
		return
	if attack_time_left > 0.0 and body.has_method("take_damage") and not attack_hit_bodies.has(body):
		attack_hit_bodies.append(body)
		body.take_damage(randi_range(SWORD_DAMAGE_MIN, SWORD_DAMAGE_MAX))


func _on_shield_body_entered(body: Node2D) -> void:
	if body != self and not bow_equipped and body.is_in_group("attack_collision"):
		if body.has_method("defuse_attack"):
			body.call("defuse_attack")
		_apply_shield_knockback()


func _on_shield_area_entered(area: Area2D) -> void:
	if area != sword_area and not bow_equipped and area.is_in_group("attack_collision"):
		if area.has_method("defuse_attack"):
			area.call("defuse_attack")
		elif area.get_parent() and area.get_parent().has_method("defuse_attack"):
			area.get_parent().call("defuse_attack")
		_apply_shield_knockback()


func _apply_shield_knockback() -> void:
	if not shield_area.monitoring:
		return

	var facing_direction: Vector2 = Vector2.UP.rotated(global_rotation).normalized()
	shield_knockback_velocity = -facing_direction * SHIELD_KNOCKBACK_SPEED
	shield_knockback_time_left = SHIELD_KNOCKBACK_DURATION


func has_mana(amount: int) -> bool:
	return mana >= amount


func arm_spell_attack() -> void:
	spell_attack_armed = true


func consume_mana(amount: int) -> bool:
	if not has_mana(amount):
		return false
	mana -= amount
	mana_changed.emit(mana, max_mana)
	return true


func _update_mana_regeneration(delta: float) -> void:
	if mana >= max_mana:
		mana_regen_time_left = MANA_REGEN_INTERVAL
		return

	mana_regen_time_left -= delta
	if mana_regen_time_left <= 0.0:
		mana = min(mana + 1, max_mana)
		mana_regen_time_left = MANA_REGEN_INTERVAL
		mana_changed.emit(mana, max_mana)


func _update_arrow_regeneration(delta: float) -> void:
	if arrows_remaining >= max_arrows:
		arrow_regen_time_left = ARROW_REGEN_INTERVAL
		return

	arrow_regen_time_left -= delta
	if arrow_regen_time_left <= 0.0:
		arrows_remaining = min(arrows_remaining + 1, max_arrows)
		arrow_regen_time_left = ARROW_REGEN_INTERVAL
		arrows_changed.emit(arrows_remaining)


func take_damage(amount: int) -> void:
	if invincibility_time_left > 0.0:
		return

	health = max(health - amount, 0)
	health_changed.emit(health, max_health)
	invincibility_time_left = INVINCIBILITY_DURATION
	invincibility_blink_time_left = 0.0


func _update_invincibility(delta: float) -> void:
	if invincibility_time_left <= 0.0 or not player_color_rect:
		return

	invincibility_time_left -= delta
	invincibility_blink_time_left -= delta
	if invincibility_blink_time_left <= 0.0:
		invincibility_blink_time_left = INVINCIBILITY_BLINK_INTERVAL
		if player_color_rect.color == player_original_color:
			player_color_rect.color = INVINCIBILITY_COLOR
		else:
			player_color_rect.color = player_original_color

	if invincibility_time_left <= 0.0:
		invincibility_time_left = 0.0
		player_color_rect.color = player_original_color
