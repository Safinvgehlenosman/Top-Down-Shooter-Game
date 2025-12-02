extends "res://scripts/bullets/base_bullet.gd"


# Override to handle wallpierce synergy
func _on_body_entered(body: Node2D) -> void:
	# SYNERGY 2: Sniper wallpierce - ignore walls/tiles, only hit enemies
	if GameState.has_sniper_wallpierce_synergy:
		if body.is_in_group("enemy"):
			if body.has_method("take_damage"):
				body.take_damage(damage)
			queue_free()  # Only despawn on enemy hit
		# Ignore walls - don't queue_free, bullet continues
	else:
		# Normal behavior - hit anything
		if body.is_in_group("enemy"):
			if body.has_method("take_damage"):
				body.take_damage(damage)
		queue_free()  # Despawn on any collision
