extends Node

@export var player: CharacterBody2D

@export var Camera_Room0: PhantomCamera2D
@export var Camera_Room1: PhantomCamera2D

var current_camera_room: int = 0

func update_current_room(body, room_a, room_b):
	if body == player:
		match current_camera_room:
			room_a:
				current_camera_room = room_b
			room_b:
				current_camera_room = room_a
		update_camera()

func update_camera():
	var cameras = [Camera_Room0, Camera_Room1]
	for camera in cameras:
		if camera != null:
			camera.priority = 0
	
	match current_camera_room:
		0:
			Camera_Room0.priority = 1
		1:
			Camera_Room1.priority = 1

func _on_room_01_body_entered(body: Node2D) -> void:
	update_current_room(body, 0, 1)
