extends Node2D

signal slime_killed

@export var slime_sprites: Array[SpriteFrames] = []
@export var min_speed: float = 30.0
@export var max_speed: float = 80.0
@export var spawn_margin: float = 50.0

@onready var sfx_squish: AudioStreamPlayer = $SFX_Squish
@onready var sprite: AnimatedSprite2D = $Sprite

var speed: float = 0.0
var direction: int = 1
var screen_width: float = 0.0
var spawn_delay: float = 3.0
var is_dying: bool = false

func _ready() -> void:
	sprite.visible = false
	
	screen_width = get_viewport_rect().size.x
	direction = 1 if randf() > 0.5 else -1
	sprite.flip_h = (direction > 0)
	speed = randf_range(min_speed, max_speed)
	scale = Vector2(3.0, 3.0)
	
	if direction > 0:
		position.x = -spawn_margin
	else:
		position.x = screen_width + spawn_margin
	
	position.y = randf_range(100, get_viewport_rect().size.y - 100)
	
	# Pick random slime sprite
	if slime_sprites.size() > 0:
		sprite.sprite_frames = slime_sprites.pick_random()
	
	# ALWAYS play animation after assignment
	if sprite.sprite_frames:
		sprite.play("moving")
	
	# Setup click detection
	var click_area = get_node_or_null("ClickArea")
	if click_area:
		click_area.input_pickable = true
		click_area.input_event.connect(_on_click_area_input_event)

func _process(delta: float) -> void:
	if spawn_delay > 0:
		spawn_delay -= delta
		if spawn_delay <= 0:
			sprite.visible = true
		return
	
	if is_dying:
		return
	
	position.x += speed * direction * delta
	
	if direction > 0 and position.x > screen_width + spawn_margin:
		queue_free()
	elif direction < 0 and position.x < -spawn_margin:
		queue_free()

func _on_click_area_input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_die()

func _die() -> void:
	if is_dying:
		return
	
	is_dying = true
	speed = 0
	
	if sfx_squish:
		sfx_squish.play()
	
	if sprite.sprite_frames and sprite.sprite_frames.has_animation("death"):
		sprite.play("death")
		await sprite.animation_finished
		sprite.pause()
		await get_tree().create_timer(0.5).timeout
	
	slime_killed.emit()