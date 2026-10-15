extends StaticBody2D

const PARTICLE_TEXTURE: Texture2D = preload("res://art/stone_wall_particle.png")

@export var lifetime := 8.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_polygon: CollisionPolygon2D = $CollisionPolygon2D
@onready var navigation_obstacle: NavigationObstacle2D = $NavigationObstacle2D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# The obstacle is dynamic, so the navigation map updates without rebuilding
	# the entire level navigation polygon.
	call_deferred("_force_navigation_update")
	await get_tree().create_timer(lifetime).timeout
	sprite.texture = PARTICLE_TEXTURE
	collision_polygon.disabled = true
	navigation_obstacle.affect_navigation_mesh = false
	_force_navigation_update()
	await get_tree().create_timer(0.1).timeout
	queue_free()


func _force_navigation_update() -> void:
	if not is_inside_tree():
		return
	var navigation_region: NavigationRegion2D = get_tree().current_scene.find_child("NavigationRegion2D", true, false) as NavigationRegion2D
	if navigation_region:
		NavigationServer2D.map_force_update(navigation_region.get_navigation_map())


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


# Called every frame. 'delta' is the elapsed time since the previous frame.
