extends Node2D

func get_spawn_points():
	return get_tree().get_nodes_in_group("spawn_point")
