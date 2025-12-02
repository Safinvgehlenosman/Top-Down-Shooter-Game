extends "res://scripts/slimes/base_slime.gd"

func _ready() -> void:
	is_fast_slime = true  # Fast slimes never retreat
	super._ready()
