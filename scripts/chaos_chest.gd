extends Area2D

##
## ChaosChest.gd
## Hades-style challenge chest - shows ONLY chaos upgrades
## Uses signal pattern to let GameManager handle UI via existing shop system
##

signal chaos_chest_opened(chaos_upgrade: Dictionary)

@onready var sprite: Sprite2D = $Sprite2D
@onready var interact_prompt: Label = $InteractPrompt
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var light: PointLight2D = $PointLight2D
@onready var sfx_spawn: AudioStreamPlayer2D = $SFX_Spawn
@onready var sfx_despawn: AudioStreamPlayer2D = $SFX_Despawn

var player_in_range: bool = false
var is_opened: bool = false


func _ready() -> void:
	# Set up interaction signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	# Hide prompt initially
	if interact_prompt:
		interact_prompt.visible = false
	
	# Set chaos chest color (purple/magenta)
	if sprite:
		sprite.modulate = Color(0.8, 0.2, 0.8)
	
	if light:
		light.color = Color(0.8, 0.2, 0.8)
		light.energy = 1.5
	
	# Play spawn sound
	if sfx_spawn:
		sfx_spawn.play()
	
	print("[ChaosChest] Chaos chest initialized and ready!")


func _process(_delta: float) -> void:
	# Check for player interaction
	if player_in_range and not is_opened and Input.is_action_just_pressed("interact"):
		_on_player_interact()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = true
		if interact_prompt and not is_opened:
			interact_prompt.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = false
		if interact_prompt:
			interact_prompt.visible = false


func _on_player_interact() -> void:
	"""Player pressed E on the chaos chest"""
	if is_opened:
		return
	
	is_opened = true
	
	# Hide interaction prompt
	if interact_prompt:
		interact_prompt.visible = false
	
	print("[ChaosChest] Player interacted with chaos chest!")
	
	# Get chaos upgrade
	var chaos_upgrade = _get_chaos_upgrade()
	
	if chaos_upgrade.is_empty():
		push_error("[ChaosChest] ERROR: No chaos upgrade found!")
		is_opened = false
		if interact_prompt:
			interact_prompt.visible = true
		return
	
	print("[ChaosChest] Emitting signal with chaos upgrade: ", chaos_upgrade.get("text"))
	
	# Emit signal for GameManager to handle via shop UI
	chaos_chest_opened.emit(chaos_upgrade)
	
	# Despawn chest
	_despawn_chest()


func _get_chaos_upgrade() -> Dictionary:
	"""Find and return a chaos upgrade from the database"""
	var UpgradesDB = preload("res://scripts/Upgrades_DB.gd")
	var all_upgrades = UpgradesDB.get_all()
	
	# Filter for chaos upgrades
	var chaos_upgrades: Array = []
	
	for upgrade in all_upgrades:
		var upgrade_rarity = upgrade.get("rarity")
		
		# Check if it's CHAOS rarity
		if upgrade_rarity == UpgradesDB.Rarity.CHAOS:
			chaos_upgrades.append(upgrade)
		elif upgrade.get("effect") == "chaos_challenge":
			# Fallback: check by effect type
			chaos_upgrades.append(upgrade)
	
	if chaos_upgrades.is_empty():
		push_error("[ChaosChest] No chaos upgrades found in database!")
		return {}
	
	# Pick one random chaos upgrade
	var selected = chaos_upgrades.pick_random()
	print("[ChaosChest] Selected: ", selected.get("text"))
	
	return selected


func _despawn_chest() -> void:
	"""Fade out and remove the chest"""
	print("[ChaosChest] Despawning chest...")
	
	# Play despawn sound
	if sfx_despawn:
		sfx_despawn.play()
	
	# Hide collision
	if collision:
		collision.set_deferred("disabled", true)
	
	# Fade out animation
	var tween = create_tween()
	tween.tween_property(sprite, "modulate:a", 0.0, 0.5)
	if light:
		tween.parallel().tween_property(light, "energy", 0.0, 0.5)
	
	# Queue free after animation
	tween.tween_callback(queue_free)
