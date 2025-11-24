extends Node

signal damaged(amount: int)
signal healed(amount: int)
signal died

@export var use_gamestate: bool = false  # ✅ true for player, false for enemies

@export var max_health: int = 1
var health: int = 0

@export var invincible_time: float = 0.0
var invincible_timer: float = 0.0

var is_dead: bool = false


func _ready() -> void:
	# Player version pulls from GameState
	if use_gamestate:
		max_health = GameState.max_health
		health = GameState.health
		invincible_time = GameConfig.player_invincible_time
	else:
		# Enemies just start at their own max_health
		health = max_health


func _physics_process(delta: float) -> void:
	if invincible_timer > 0.0:
		invincible_timer -= delta


func grant_spawn_invincibility(duration: float) -> void:
	invincible_timer = max(invincible_timer, duration)


func sync_from_gamestate() -> void:
	if use_gamestate:
		max_health = GameState.max_health
		health = GameState.health


func take_damage(amount: int) -> void:
	if amount == 0 or is_dead:
		return

	# --- DAMAGE (amount > 0) ---
	if amount > 0:
		# God mode only matters for the player
		if use_gamestate and GameState.debug_god_mode:
			return

		if invincible_timer > 0.0:
			return

		invincible_timer = invincible_time

		if owner and owner.has_node("SFX_Hurt"):
			owner.get_node("SFX_Hurt").play()

		emit_signal("damaged", amount)

	# --- HEAL (amount < 0) ---
	elif amount < 0:
		emit_signal("healed", -amount)

	# Apply to local health
	var new_health := clampi(health - amount, 0, max_health)
	health = new_health

	# If this is the PLAYER component, also mirror into GameState
	if use_gamestate:
		GameState.set_health(new_health)

	# Death
	if amount > 0 and health <= 0:
		is_dead = true
		emit_signal("died")
