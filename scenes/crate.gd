extends Area2D

@export var CoinScene: PackedScene
@export var AmmoScene: PackedScene
@export var HeartScene: PackedScene  # optional


func _spawn_loot() -> void:
	var roll := randf()

	var coin_chance := GameConfig.crate_coin_drop_chance
	var ammo_chance := GameConfig.crate_ammo_drop_chance
	var heart_chance := GameConfig.crate_heart_drop_chance

	# total chance covered by all drops
	var total := coin_chance + ammo_chance + heart_chance

	if total <= 0.0:
		return  # nothing can drop, bail early

	# normalize roll within [0, total)
	roll *= total

	if roll < ammo_chance:
		if AmmoScene:
			var ammo := AmmoScene.instantiate()
			ammo.global_position = global_position
			get_tree().current_scene.add_child(ammo)
	elif roll < ammo_chance + coin_chance:
		if CoinScene:
			var coin := CoinScene.instantiate()
			coin.global_position = global_position
			get_tree().current_scene.add_child(coin)
	else:
		if HeartScene:
			var heart := HeartScene.instantiate()
			heart.global_position = global_position
			get_tree().current_scene.add_child(heart)




func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("bullet"):
		_spawn_loot()
		queue_free()
