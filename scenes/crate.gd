extends Area2D

@export var CoinScene: PackedScene


func _spawn_loot() -> void:
	if CoinScene:
		var coin := CoinScene.instantiate()
		coin.global_position = global_position
		get_tree().current_scene.add_child(coin)



func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("bullet"):
		_spawn_loot()
		queue_free()
