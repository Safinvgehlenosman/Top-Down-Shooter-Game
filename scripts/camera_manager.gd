extends Node

@export var player: CharacterBody2D

@export var Camera_Room0: PhantomCamera2D
@export var Camera_Room1: PhantomCamera2D
@export var Camera_Room2: PhantomCamera2D   # 👈 NEW – third room camera

var current_camera_room: int = 0


func update_current_room(body, room_a: int, room_b: int) -> void:
	if body != player:
		return

	var before := current_camera_room

	match current_camera_room:
		room_a:
			current_camera_room = room_b
		room_b:
			current_camera_room = room_a
		_:
			# We got to this doorway but the room state says something else (e.g. 2).
			# Recover by snapping to room_b (the "other side" of this door).
			current_camera_room = room_b

	if current_camera_room != before:
		update_camera()



func update_camera() -> void:
	# 👇 now handle 3 cameras instead of 2
	var cameras = [Camera_Room0, Camera_Room1, Camera_Room2]
	for camera in cameras:
		if camera != null:
			camera.priority = 0

	match current_camera_room:
		0:
			if Camera_Room0:
				Camera_Room0.priority = 1
		1:
			if Camera_Room1:
				Camera_Room1.priority = 1
		2:
			if Camera_Room2:
				Camera_Room2.priority = 1


func _on_room_01_body_entered(body: Node2D) -> void:
	# transition between room 0 and room 1
	update_current_room(body, 0, 1)



func _on_room_02_body_entered(body: Node2D) -> void:
	update_current_room(body, 1, 2)
