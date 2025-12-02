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
	# Get reference to InteractPrompt
	interact_prompt = get_node_or_null("InteractPrompt")
	
	# Hide interact_prompt by default
	if interact_prompt:
		interact_prompt.visible = false
		base_prompt_pos = interact_prompt.position
	
	# Don't play spawn sound in shop (chest is always there)
	# if sfx_spawn:
	# 	sfx_spawn.play()
	
	# Connect signals
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	# Check for interact input
	if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("ui_accept"):
		if player_nearby and not is_opened:
			_open_shop()

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
			hover_time = 0.0


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_nearby = false
		# Hide interact prompt
		if interact_prompt:
			interact_prompt.visible = false


func _open_shop() -> void:
	"""Open the shop UI via GameManager."""
	# Mark as opened (can be reopened, but prevents spam)
	is_opened = true
	
	# Hide interact prompt temporarily
	if interact_prompt:
		interact_prompt.visible = false
	
	# Play open sound if exists
	if sfx_open:
		sfx_open.play()
	
	# Call GameManager to open shop UI
	var game_manager = get_tree().get_first_node_in_group("game_manager")
	if game_manager and game_manager.has_method("open_shop_from_chest"):
		game_manager.open_shop_from_chest()
	else:
		push_warning("[ShopChest] GameManager not found or missing open_shop_from_chest method!")
	
	# Allow re-opening after a short delay (in case player closes shop without buying)
	await get_tree().create_timer(1.0).timeout
	is_opened = false
	
	# Re-show prompt if player is still nearby
	if player_nearby and interact_prompt:
		interact_prompt.visible = true
