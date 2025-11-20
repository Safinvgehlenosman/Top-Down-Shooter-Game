extends Area2D

@export_file("*.tscn")
var target_scene: String = ""   # 👈 where this door leads

var door_open: bool = false

func _ready() -> void:
	monitoring = true
	monitorable = true
	print("ExitDoor ready. Monitoring:", monitoring, " Mask:", collision_mask)

func open() -> void:
	door_open = true
	visible = true
	$SFX_Spawn.play()

func _on_ExitDoor_body_entered(body: Node2D) -> void:
	print("DOOR (local) entered by:", body)
	if not door_open:
		print("door not open yet, ignore")
		return
	if not body.is_in_group("player"):
		print("not player, ignore")
		return
	if target_scene == "":
		print("⚠ No target_scene set on ExitDoor")
		return

	print("changing to:", target_scene)
	get_tree().change_scene_to_file(target_scene)
