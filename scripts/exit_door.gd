extends Area2D

@export_file("*.tscn")
var target_scene: String = ""   # 👈 where this door leads

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

	get_tree().change_scene_to_file(target_scene)
	
