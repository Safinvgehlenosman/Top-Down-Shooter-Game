extends Area2D

var door_open: bool = false

func open() -> void:
	door_open = true
	visible = true
	$SFX_Spawn.play()




func _on_body_entered(body: Node2D) -> void:
	if not door_open:
		return
	if not body.is_in_group("player"):
		return

	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm and gm.has_method("on_player_reached_exit"):
		gm.on_player_reached_exit()
