extends Node2D

@export var lifetime: float = 0.25
@export var start_alpha: float = 0.8

var time_left: float

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	time_left = lifetime

func setup_from_player(player_sprite: AnimatedSprite2D) -> void:
	# Copy the exact frame the player is currently on
	if player_sprite.sprite_frames:
		var tex: Texture2D = player_sprite.sprite_frames.get_frame_texture(
	player_sprite.animation,
	player_sprite.frame
	)
		sprite.texture = tex

	# Copy flip/scale so it faces the same way
	sprite.flip_h = player_sprite.flip_h
	sprite.flip_v = player_sprite.flip_v
	sprite.scale = player_sprite.scale

	# Start semi-transparent
	var c := sprite.modulate
	c.a = start_alpha
	sprite.modulate = c

func _process(delta: float) -> void:
	time_left -= delta
	if time_left <= 0.0:
		queue_free()
		return

	var t := time_left / lifetime
	var c := sprite.modulate
	c.a = start_alpha * t
	sprite.modulate = c
