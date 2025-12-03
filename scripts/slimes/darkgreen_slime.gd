extends "res://scripts/slimes/base_slime.gd"

func _ready() -> void:
	is_fast_slime = true  # Fast slimes never retreat
	
	# Reduce speed by 25% (was too fast)
	speed *= 0.75
	wander_speed *= 0.75
	base_move_speed *= 0.75
	base_wander_speed *= 0.75
	
	super._ready()
