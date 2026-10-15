extends CanvasLayer

const SPELL_WHEEL_TEXTURE: Texture2D = preload("res://art/spell_wheel.png")
const SPELL_WHEEL_SELECT_TEXTURE: Texture2D = preload("res://art/spell_wheel_select.png")
const SAVE_PATH := "user://savegame.json"

@export var player_path: NodePath = NodePath("../player")
@export var fairy_path: NodePath = NodePath("../fairy")
@export var camera_path: NodePath = NodePath("../Camera2D")
@export var spell_wheel_center_offset := Vector2.ZERO

@onready var health_bar: ProgressBar = find_child("Health", true, false) as ProgressBar
@onready var mana_bar: ProgressBar = find_child("Mana", true, false) as ProgressBar
@onready var arrows_remaining_label: Label = find_child("arrows_remaining", true, false) as Label
@onready var spell_wheel: Control = find_child("SpellWheel", true, false) as Control
@onready var spell_wheel_info: Control = find_child("SpellWheelInfo", true, false) as Control
@onready var spell_wheel_unavailable: Control = find_child("SpellWheelOverlay", true, false) as Control
@onready var spell_wheel_marker: Control = find_child("SpellWheelMarker", true, false) as Control
@onready var pause_menu: Control = find_child("PauseMenu", true, false) as Control
@onready var pause_save_button: Button = find_child("Button", true, false) as Button
@onready var pause_return_button: Button = find_child("Button2", true, false) as Button
@onready var pause_quit_button: Button = find_child("Button3", true, false) as Button
@onready var rest_fade: ColorRect = find_child("RestFade", true, false) as ColorRect
@onready var spell_wheel_slots: Array[TextureRect] = [
	$SpellWheel/TextureRect,
	$SpellWheel/TextureRect2,
	$SpellWheel/TextureRect3,
	$SpellWheel/TextureRect4
]
@onready var spell_labels: Array[Label] = [
	$SpellWheelInfo/SpellSlot1/Text,
	$SpellWheelInfo/SpellSlot2/Text,
	$SpellWheelInfo/SpellSlot3/Text,
	$SpellWheelInfo/SpellSlot4/Text
]
@onready var spell_wheel_unavailable_slots: Array[TextureRect] = [
	$SpellWheelOverlay/TextureRect,
	$SpellWheelOverlay/TextureRect2,
	$SpellWheelOverlay/TextureRect3,
	$SpellWheelOverlay/TextureRect4
]

var player: CharacterBody2D
var fairy: Node2D
var camera: Camera2D
var fairy_auras: Array[ColorRect] = []
var spell_mouse_offset := Vector2.ZERO
var spell_wheel_was_visible := false
var selected_spell_text := ""
var rest_in_progress := false
const SPELL_MARKER_RADIUS := 80.0


func _ready() -> void:
	# The pause UI must keep processing input after the scene tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	if pause_menu:
		pause_menu.visible = false
	if pause_save_button:
		pause_save_button.pressed.connect(_save_game)
	if pause_return_button:
		pause_return_button.pressed.connect(_on_pause_return_pressed)
	if pause_quit_button:
		pause_quit_button.pressed.connect(_on_pause_quit_pressed)
	if rest_fade:
		rest_fade.visible = false
		rest_fade.color.a = 0.0

	fairy = get_node_or_null(fairy_path) as Node2D
	camera = get_node_or_null(camera_path) as Camera2D
	if fairy:
		var aura: ColorRect = fairy.find_child("Aura", true, false) as ColorRect
		var aura2: ColorRect = fairy.find_child("Aura2", true, false) as ColorRect
		if aura:
			fairy_auras.append(aura)
		if aura2:
			fairy_auras.append(aura2)
		if fairy.has_signal("spell_cast"):
			fairy.spell_cast.connect(_on_fairy_spell_cast)

	if spell_wheel:
		spell_wheel.visible = false
	if spell_wheel_info:
		spell_wheel_info.visible = false
	if spell_wheel_unavailable:
		spell_wheel_unavailable.visible = false
	for unavailable_slot in spell_wheel_unavailable_slots:
		unavailable_slot.visible = true
	if spell_wheel_marker:
		spell_wheel_marker.visible = false

	player = get_node_or_null(player_path) as CharacterBody2D
	if not health_bar or not player or not player.has_method("take_damage"):
		return

	var maximum_health: int = int(player.get("max_health"))
	var current_health: int = int(player.get("health"))
	health_bar.max_value = maximum_health
	health_bar.value = current_health
	player.connect("health_changed", _on_player_health_changed)
	if mana_bar and player.has_signal("mana_changed"):
		var maximum_mana: int = int(player.get("max_mana"))
		var current_mana: int = int(player.get("mana"))
		mana_bar.max_value = maximum_mana
		mana_bar.value = current_mana
		player.connect("mana_changed", _on_player_mana_changed)
	if arrows_remaining_label and player.has_signal("arrows_changed"):
		arrows_remaining_label.text = "X " + str(int(player.get("arrows_remaining")))
		player.connect("arrows_changed", _on_player_arrows_changed)
	_load_game()


func _process(_delta: float) -> void:
	_update_save_button_state()
	if get_tree().paused:
		return
	if spell_wheel:
		var spell_select_held: bool = Input.is_action_pressed("spellSelect")
		spell_wheel.visible = spell_select_held
		if spell_wheel_info:
			spell_wheel_info.visible = spell_select_held
		if spell_wheel_unavailable:
			spell_wheel_unavailable.visible = spell_select_held
		if spell_wheel_marker:
			spell_wheel_marker.visible = spell_select_held
			if spell_select_held and not spell_wheel_was_visible:
				spell_mouse_offset = Vector2.ZERO
			if spell_select_held:
				_update_spell_marker_from_controller(_delta)
				var wheel_center: Vector2 = spell_wheel.get_global_transform_with_canvas() * (spell_wheel.size / 2.0)
				wheel_center += spell_wheel_center_offset
				spell_wheel_marker.position = wheel_center + spell_mouse_offset - spell_wheel_marker.size / 2.0
				_update_spell_wheel_selection(spell_wheel_marker.position + spell_wheel_marker.size / 2.0)
			else:
				if spell_wheel_was_visible:
					_apply_spell_aura()
				_clear_spell_wheel_selection()
		spell_wheel_was_visible = spell_select_held


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not event.is_echo():
		if rest_in_progress:
			get_viewport().set_input_as_handled()
			return
		if player and player.has_method("is_resting") and player.call("is_resting"):
			_start_rest()
			get_viewport().set_input_as_handled()
			return
		_set_game_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()
		return
	if get_tree().paused and event.is_action_pressed("dash") and not event.is_echo():
		var focused_control: Control = get_viewport().gui_get_focus_owner()
		if focused_control is BaseButton:
			(focused_control as BaseButton).pressed.emit()
			get_viewport().set_input_as_handled()
			return
	if not spell_wheel_was_visible:
		return
	if event is InputEventMouseMotion:
		spell_mouse_offset += event.relative
		if spell_mouse_offset.length() > SPELL_MARKER_RADIUS:
			spell_mouse_offset = spell_mouse_offset.normalized() * SPELL_MARKER_RADIUS


func _on_pause_return_pressed() -> void:
	_set_game_paused(false)


func _start_rest() -> void:
	if rest_in_progress or not rest_fade:
		return
	rest_in_progress = true
	if player and player.has_method("set_rest_prompt_visible"):
		player.call("set_rest_prompt_visible", false)
	get_tree().paused = true
	rest_fade.visible = true
	rest_fade.color.a = 0.0

	var fade_out_tween := rest_fade.create_tween()
	fade_out_tween.tween_property(rest_fade, "color:a", 1.0, 0.5)
	await fade_out_tween.finished
	_respawn_enemies_and_heal_player()

	var fade_in_tween := rest_fade.create_tween()
	fade_in_tween.tween_property(rest_fade, "color:a", 0.0, 0.5)
	await fade_in_tween.finished
	rest_fade.visible = false
	get_tree().paused = false
	if player and player.has_method("set_rest_prompt_visible"):
		player.call("set_rest_prompt_visible", true)
	rest_in_progress = false


func _respawn_enemies_and_heal_player() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.has_method("respawn_at_home"):
			enemy.call("respawn_at_home")
	get_tree().current_scene.set_meta("dead_enemy_names", [])
	if player and player.has_method("restore_full_health"):
		player.call("restore_full_health")


func _save_game() -> void:
	if not player or _enemies_see_player():
		return

	var enemy_states: Dictionary = {}
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy_states[str(enemy.name)] = true

	var dead_enemy_names: Array = _get_dead_enemy_names()
	for enemy_name in dead_enemy_names:
		enemy_states[str(enemy_name)] = false

	var save_data: Dictionary = {
		"player_position": {
			"x": player.global_position.x,
			"y": player.global_position.y
		},
		"fairy_position": _position_to_dictionary(fairy.global_position) if fairy else {},
		"camera_position": _position_to_dictionary(camera.global_position) if camera else {},
		"enemy_states": enemy_states
	}
	var save_file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if save_file:
		save_file.store_string(JSON.stringify(save_data))
		save_file.close()


func _update_save_button_state() -> void:
	if not pause_save_button:
		return
	var save_allowed: bool = not _enemies_see_player()
	pause_save_button.disabled = not save_allowed
	pause_save_button.text = "Save" if save_allowed else "can't save now"


func _enemies_see_player() -> bool:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.has_method("is_player_noticed") and enemy.call("is_player_noticed"):
			return true
	return false


func _load_game() -> void:
	if not player or not FileAccess.file_exists(SAVE_PATH):
		return

	var save_file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not save_file:
		return
	var parsed_data = JSON.parse_string(save_file.get_as_text())
	save_file.close()
	if not parsed_data is Dictionary:
		return

	var save_data: Dictionary = parsed_data
	var saved_position = save_data.get("player_position", {})
	if saved_position is Dictionary and saved_position.has("x") and saved_position.has("y"):
		player.global_position = Vector2(
			float(saved_position["x"]),
			float(saved_position["y"])
		)

	var saved_fairy_position = save_data.get("fairy_position", {})
	if fairy and saved_fairy_position is Dictionary:
		var restored_fairy_position = _position_from_dictionary(saved_fairy_position)
		if restored_fairy_position != null:
			if fairy.has_method("restore_saved_position"):
				fairy.call("restore_saved_position", restored_fairy_position)
			else:
				fairy.global_position = restored_fairy_position

	var saved_camera_position = save_data.get("camera_position", {})
	if camera and saved_camera_position is Dictionary:
		var restored_camera_position = _position_from_dictionary(saved_camera_position)
		if restored_camera_position != null:
			if camera.has_method("restore_saved_position"):
				camera.call("restore_saved_position", restored_camera_position)
			else:
				camera.global_position = restored_camera_position

	var enemy_states = save_data.get("enemy_states", {})
	if not enemy_states is Dictionary:
		return
	var dead_enemy_names: Array = []
	for enemy_name in enemy_states:
		if not bool(enemy_states[enemy_name]):
			dead_enemy_names.append(str(enemy_name))
	get_tree().current_scene.set_meta("dead_enemy_names", dead_enemy_names)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if str(enemy.name) in dead_enemy_names:
			if enemy.has_method("set_dead_state"):
				enemy.call("set_dead_state")
			else:
				enemy.queue_free()


func _get_dead_enemy_names() -> Array:
	var scene := get_tree().current_scene
	if scene and scene.has_meta("dead_enemy_names"):
		return scene.get_meta("dead_enemy_names") as Array
	return []


func _position_to_dictionary(position: Vector2) -> Dictionary:
	return {"x": position.x, "y": position.y}


func _position_from_dictionary(saved_position: Dictionary):
	if not saved_position.has("x") or not saved_position.has("y"):
		return null
	return Vector2(float(saved_position["x"]), float(saved_position["y"]))


func _on_pause_quit_pressed() -> void:
	get_tree().quit()


func _set_game_paused(should_pause: bool) -> void:
	get_tree().paused = should_pause
	if pause_menu:
		pause_menu.visible = should_pause
	Input.set_mouse_mode(
		Input.MOUSE_MODE_VISIBLE if should_pause else Input.MOUSE_MODE_CAPTURED
	)
	if should_pause and pause_return_button:
		pause_return_button.call_deferred("grab_focus")
	elif not should_pause:
		if player and player.has_method("block_dash_until_release"):
			player.call("block_dash_until_release")
		get_viewport().gui_release_focus()


func _update_spell_marker_from_controller(_delta: float) -> void:
	if Input.get_connected_joypads().is_empty():
		return

	var controller_direction := Input.get_vector(
		"spellAimLeft",
		"spellAimRight",
		"spellAimUp",
		"spellAimDown"
	)
	spell_mouse_offset = controller_direction * SPELL_MARKER_RADIUS


func _update_spell_wheel_selection(marker_position: Vector2) -> void:
	selected_spell_text = ""
	for index in spell_wheel_slots.size():
		var slot: TextureRect = spell_wheel_slots[index]
		var slot_local_position: Vector2 = slot.get_global_transform_with_canvas().affine_inverse() * marker_position
		var spell_text: String = spell_labels[index].text
		var can_select: bool = _has_enough_mana_for_spell(spell_text)
		spell_labels[index].modulate = Color.WHITE if can_select else Color(0.4, 0.4, 0.4, 1.0)
		spell_wheel_unavailable_slots[index].visible = true
		spell_wheel_unavailable_slots[index].modulate = Color(1, 1, 1, 0) if can_select else Color.WHITE
		var is_selected: bool = can_select and Rect2(Vector2.ZERO, slot.size).has_point(slot_local_position)
		slot.texture = SPELL_WHEEL_SELECT_TEXTURE if is_selected else SPELL_WHEEL_TEXTURE
		if is_selected:
			selected_spell_text = spell_text


func _clear_spell_wheel_selection() -> void:
	for slot in spell_wheel_slots:
		slot.texture = SPELL_WHEEL_TEXTURE
	for label in spell_labels:
		label.modulate = Color.WHITE
	for unavailable_slot in spell_wheel_unavailable_slots:
		unavailable_slot.modulate = Color(1, 1, 1, 0)


func _has_enough_mana_for_spell(spell_name: String) -> bool:
	var spell_cost: int = 2 if spell_name == "Firestarter" else 4 if spell_name == "Cold\nPillar" else 3 if spell_name == "Lightning Chain" else 5 if spell_name == "Stone Wall" else 0
	return spell_cost == 0 or (player and player.has_method("has_mana") and player.has_mana(spell_cost))


func _apply_spell_aura() -> void:
	if fairy_auras.is_empty():
		return

	var aura_color: Color
	match selected_spell_text:
		"Firestarter":
			aura_color = Color(0.901961, 0.360784, 0.0, 1.0)
		"Cold\nPillar":
			aura_color = Color(0.0, 0.933333, 1.0, 1.0)
		"Lightning Chain":
			aura_color = Color(1.0, 0.917647, 0.52549, 1.0)
		"Stone Wall":
			aura_color = Color(0.698039, 0.592157, 0.490196, 1.0)
		_:
			return

	for aura in fairy_auras:
		aura.color = aura_color
		aura.visible = true

	if fairy and fairy.has_method("set_selected_spell"):
		fairy.set_selected_spell(selected_spell_text)
	if player and player.has_method("arm_spell_attack"):
		player.arm_spell_attack()


func _on_fairy_spell_cast(_spell_name: String) -> void:
	for aura in fairy_auras:
		aura.visible = false


func _on_player_health_changed(current_health: int, maximum_health: int) -> void:
	health_bar.max_value = maximum_health
	health_bar.value = current_health


func _on_player_mana_changed(current_mana: int, maximum_mana: int) -> void:
	if not mana_bar:
		return
	mana_bar.max_value = maximum_mana
	mana_bar.value = current_mana


func _on_player_arrows_changed(current_arrows: int) -> void:
	if arrows_remaining_label:
		arrows_remaining_label.text = "X " + str(current_arrows)
