extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var sfx_spawn: AudioStreamPlayer2D = $SFX_Spawn

var door_open: bool = false
var door_locked: bool = false  # NEW: Track locked state
var player_in_range: bool = false
var is_transitioning: bool = false  # NEW

# Interact prompt
var interact_prompt: Label

# Hover animation (same as chest)
var hover_time: float = 0.0
var base_prompt_pos: Vector2
@export var hover_amplitude: float = 3.0
@export var hover_speed: float = 2.0


func _ready() -> void:
	visible = true  # Always visible from start
	door_locked = true  # Start locked for combat rooms (GameManager sets to false for hub/shop)
	
	# Ensure high z-index for visibility
	if animated_sprite:
		animated_sprite.z_index = 10
		animated_sprite.z_as_relative = false
	
	# Get reference to InteractPrompt
	interact_prompt = get_node_or_null("InteractPrompt")
	
	# Hide interact_prompt by default
	if interact_prompt:
		interact_prompt.visible = false
		base_prompt_pos = interact_prompt.position
	
	if animated_sprite:
		animated_sprite.play("default")
		if not animated_sprite.animation_finished.is_connected(_on_animation_finished):
			animated_sprite.animation_finished.connect(_on_animation_finished)
	
	# Connect signals
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	# Check for E key input
	if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("interact"):
		if player_in_range and door_open:
			if door_locked:
				print("[EXIT DOOR] Player tried to use locked door")
				# TODO: Play locked sound or show hint
				return
			if not is_transitioning:
				_enter_shop()
	
	# Hover animation for prompt (same as chest)
	if interact_prompt and interact_prompt.visible:
		hover_time += delta
		var offset_y := sin(hover_time * hover_speed) * hover_amplitude
		interact_prompt.position.y = base_prompt_pos.y + offset_y


func open(play_sound: bool = true) -> void:
	door_open = true
	visible = true
	
	if animated_sprite:
		animated_sprite.play("default")
	
	if sfx_spawn and play_sound:
		sfx_spawn.play()
	
	# Check if player is already in the area when door opens
	await get_tree().process_frame  # Wait one frame for physics to update
	for body in get_overlapping_bodies():
		if body.is_in_group("player"):
			player_in_range = true
			if animated_sprite:
				animated_sprite.play("open")
			if interact_prompt:
				interact_prompt.visible = true
				hover_time = 0.0
			break


func set_locked(locked: bool) -> void:
	"""Set the locked state of the door."""
	door_locked = locked
	_update_visual_state()


func _update_visual_state() -> void:
	"""Update door visual based on locked state."""
	if not animated_sprite:
		return
	# You can add different animations for locked/unlocked here if you have them
	# For now, just ensure we're playing the default animation
	if not door_open:
		animated_sprite.play("default")

func unlock_and_open(play_sound: bool = true) -> void:
	"""Unlock and open the door (called when room is cleared)."""
	print("[EXIT DOOR] unlock_and_open called - setting locked to false")
	door_locked = false
	open(play_sound)
	print("[EXIT DOOR] Door state after unlock: locked=%s, open=%s" % [door_locked, door_open])


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	
	player_in_range = true
	
	if door_locked:
		print("[EXIT DOOR] Player touched locked door")
		# Show prompt even when locked so player knows it's there
		if interact_prompt and door_open:
			interact_prompt.visible = true
			hover_time = 0.0
		return
	
	if not door_open:
		return
	
	# Door is unlocked and open
	if animated_sprite:
		animated_sprite.play("open")
	
	if interact_prompt:
		interact_prompt.visible = true
		hover_time = 0.0


func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	
	player_in_range = false
	
	# Hide prompt
	if interact_prompt:
		interact_prompt.visible = false
	
	# Play close animation
	if animated_sprite and door_open:
		animated_sprite.play("close")


func _on_animation_finished() -> void:
	# After close animation finishes, return to default
	if animated_sprite and animated_sprite.animation == "close":
		animated_sprite.play("default")


func _enter_shop() -> void:
	if door_locked:
		return  # Can't enter locked door
	
	is_transitioning = true
	
	# Hide prompt immediately
	if interact_prompt:
		interact_prompt.visible = false
	
	# Start fade to black
	FadeTransition.fade_in()
	
	# Wait for fade to finish
	await FadeTransition.fade_in_finished
	
	# Trigger room transition via GameManager
	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm and gm.has_method("on_player_reached_exit"):
		gm.on_player_reached_exit()
	
	is_transitioning = false