extends "res://scripts/slimes/base_slime.gd"

func _ready() -> void:
	is_fast_slime = true  # Fast slimes never retreat
	
	# Halve normal and wander speeds (was too fast)
	speed *= 0.5
	wander_speed *= 0.5
	base_move_speed *= 0.5
	base_wander_speed *= 0.5
	
	super._ready()
