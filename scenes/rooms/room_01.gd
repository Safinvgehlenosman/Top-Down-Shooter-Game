extends Node2D

# Helper to find the SpawnPoints node safely
func _get_spawn_points_root() -> Node2D:
	var node := get_node_or_null("SpawnPoints")
	if node == null:
		push_warning("%s: missing 'SpawnPoints' child node" % name)
	return node

func get_spawn_points() -> Array[Node2D]:
	var result: Array[Node2D] = []

	var root := _get_spawn_points_root()
	if root == null:
		return result

	for child in root.get_children():
		if child is Node2D:
			result.append(child)

	return result


func get_player_spawn_point() -> Node2D:
	var node := get_node_or_null("PlayerSpawn")
	if node == null:
		push_warning("%s: missing 'PlayerSpawn' child node" % name)
	return node
