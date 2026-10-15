extends Area2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("enter_rest_area"):
		body.call("enter_rest_area")


func _on_body_exited(body: Node2D) -> void:
	if body.has_method("exit_rest_area"):
		body.call("exit_rest_area")
