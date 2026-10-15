extends Area2D

const PARTICLE_TEXTURE: Texture2D = preload("res://art/cold_pillar_particle.png")
const COLD_EFFECT_COLOR := Color(0.0, 0.933333, 1.0, 1.0)
const COLD_PILLAR_DAMAGE_MIN := 3
const COLD_PILLAR_DAMAGE_MAX := 5

@onready var sprite: Sprite2D = $Sprite2D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_change_to_particle_after_delay()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		body.call("take_damage", randi_range(COLD_PILLAR_DAMAGE_MIN, COLD_PILLAR_DAMAGE_MAX))
	if body.is_in_group("enemies") and body.has_method("apply_slow"):
		body.call("apply_slow", 3.0, 0.5, COLD_EFFECT_COLOR)


func start_grow_animation() -> void:
	var final_scale := scale
	var final_position := position
	var sprite_half_height: float = sprite.get_rect().size.y * sprite.scale.y / 2.0
	scale.y = 0.0
	var grow_tween := create_tween()
	grow_tween.set_trans(Tween.TRANS_BACK)
	grow_tween.set_ease(Tween.EASE_OUT)
	grow_tween.set_parallel(true)
	grow_tween.tween_property(self, "scale", final_scale, 0.35)
	grow_tween.tween_property(self, "position", final_position - Vector2(0, sprite_half_height).rotated(rotation), 0.35)


func _change_to_particle_after_delay() -> void:
	await get_tree().create_timer(0.5).timeout
	if not is_inside_tree():
		return

	sprite.texture = PARTICLE_TEXTURE
	await get_tree().create_timer(0.25).timeout
	queue_free()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
