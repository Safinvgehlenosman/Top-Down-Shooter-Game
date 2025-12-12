extends "res://scripts/bullets/base_bullet.gd"


 # Override to handle wallpierce synergy and sniper phasing rounds
func _on_body_entered(body: Node2D) -> void:
	# If either the old synergy flag or the new phasing flag is active,
	# sniper bullets ignore walls/tiles and only collide with enemies.
	var phasing_active := false
	phasing_active = phasing_active or GameState.has_sniper_wallpierce_synergy
	# New flag set by sniper_phasing_rounds upgrade
	phasing_active = phasing_active or GameState.sniper_wall_phasing

	if phasing_active:
		if body.is_in_group("enemy"):
			if body.has_method("take_damage"):
				body.take_damage(damage)
			queue_free()  # Only despawn on enemy hit
		# Otherwise ignore walls/tiles and continue flying
	else:
		# Normal behavior - hit anything
		if body.is_in_group("enemy"):
			if body.has_method("take_damage"):
				body.take_damage(damage)
		queue_free()  # Despawn on any collision
