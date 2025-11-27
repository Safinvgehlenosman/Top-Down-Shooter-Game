extends Area2D

var is_opened: bool = false
var player_nearby: bool = false
var interact_prompt: Label

# Hover animation
var hover_time: float = 0.0
var base_prompt_pos: Vector2
@export var hover_amplitude: float = 3.0
@export var hover_speed: float = 2.0

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var sfx_spawn: AudioStreamPlayer2D = get_node_or_null("SFX_Spawn")
@onready var sfx_open: AudioStreamPlayer2D = get_node_or_null("SFX_Open")


func _ready() -> void:
	add_to_group("room_cleanup")
	
	# Get reference to InteractPrompt
	interact_prompt = get_node_or_null("InteractPrompt")
	
	# Hide interact_prompt by default
	if interact_prompt:
		interact_prompt.visible = false
		base_prompt_pos = interact_prompt.position
	
	# Play spawn sound
	if sfx_spawn:
		sfx_spawn.play()
	
	# Connect body_exited signal (body_entered is already connected in scene)
	body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	# Check for interact input
	if Input.is_action_just_pressed("interact"):
		if player_nearby and not is_opened:
			_open_chest()

	# Hover animation for prompt
	if interact_prompt and interact_prompt.visible and not is_opened:
		hover_time += delta
		var offset_y := sin(hover_time * hover_speed) * hover_amplitude
		interact_prompt.position.y = base_prompt_pos.y + offset_y


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_nearby = true
		# Show interact prompt if not opened
		if not is_opened and interact_prompt:
			interact_prompt.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_nearby = false
		# Hide interact prompt
		if interact_prompt:
			interact_prompt.visible = false


func _open_chest() -> void:
	# Mark as opened
	is_opened = true
	
	# Hide interact prompt
	if interact_prompt:
		interact_prompt.visible = false
	
	# Disable collision
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	
	# Play open sound if exists
	if sfx_open:
		sfx_open.play()
	
	# Get ShopUI and open as chest
	var shop_ui = get_tree().get_first_node_in_group("shop")
	if shop_ui and shop_ui.has_method("open_as_chest"):
		shop_ui.open_as_chest(self)