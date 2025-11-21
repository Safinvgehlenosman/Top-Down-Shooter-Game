extends Area2D

@export_file("*.tscn")
var target_scene: String = ""

@export var use_shop: bool = true  # 👈 new toggle

var door_open: bool = false

func _ready() -> void:
	monitoring = true
	monitorable = true

func open() -> void:
	door_open = true
	visible = true
	$SFX_Spawn.play()

func _on_body_entered(body: Node2D) -> void:
	if not door_open:
		return
	if not body.is_in_group("player"):
		return
	if target_scene == "":
		return

	if use_shop:
		# Tell GameManager to open the shop for this target scene
		var gm := get_tree().get_first_node_in_group("game_manager")
		if gm and gm.has_method("on_player_reached_exit"):
			gm.on_player_reached_exit(target_scene)
	else:
		# Skip shop → go directly to target scene
		get_tree().change_scene_to_file(target_scene)
