extends Node

signal damaged(amount: int)
signal healed(amount: int)
signal died

var max_health: int = 0
var health: int = 0

var invincible_time: float = 0.0
var invincible_timer: float = 0.0

var is_dead: bool = false


func _ready() -> void:
	# Initialize from GameState when the run starts.
	# GameState.start_new_run() already sets max_health and health.
	max_health = GameState.max_health
	health = GameState.health

	# Player invincibility duration from config
	invincible_time = GameConfig.player_invincible_time


func _physics_process(delta: float) -> void:
	# Handle invincibility countdown
	if invincible_timer > 0.0:
		invincible_timer -= delta


func grant_spawn_invincibility(duration: float) -> void:
	# Used when spawning player or entering rooms etc.
	invincible_timer = max(invincible_timer, duration)


func sync_from_gamestate() -> void:
	# Called when upgrades change max HP or refill HP
	max_health = GameState.max_health
	health = GameState.health


func take_damage(amount: int) -> void:
	if amount == 0:
		return

	# 🔥 God mode: ignore positive damage completely
	if amount > 0 and GameState.debug_god_mode:
		return

	# DAMAGE (amount > 0)
	if amount > 0:
		if invincible_timer > 0.0:
			return
		invincible_timer = invincible_time

		if owner and owner.has_node("SFX_Hurt"):
			owner.get_node("SFX_Hurt").play()

		emit_signal("damaged", amount)

	# HEAL (amount < 0)
	elif amount < 0:
		emit_signal("healed", -amount)

	# amount can be negative: damage = minus, heal = plus
	var new_health := clampi(
		GameState.health - amount,
		0,
		GameState.max_health
	)

	GameState.set_health(new_health)

	# Death check
	if amount > 0 and GameState.health <= 0:
		emit_signal("died")
