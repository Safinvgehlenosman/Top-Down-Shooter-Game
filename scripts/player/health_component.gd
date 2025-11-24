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
	# Same semantics as your old Player.take_damage:
	# amount > 0  => damage
	# amount < 0  => heal
	# amount = 0  => no-op

	if is_dead:
		return
	if amount == 0:
		return

	# DAMAGE
	if amount > 0:
		# Respect invincibility
		if invincible_timer > 0.0:
			return

		# start invincibility frames
		invincible_timer = invincible_time

		var new_health := clampi(health - amount, 0, max_health)
		var actual_damage := health - new_health

		if actual_damage == 0:
			return

		health = new_health
		GameState.set_health(health)
		emit_signal("damaged", actual_damage)

		if health <= 0:
			is_dead = true
			emit_signal("died")

	# HEAL
	elif amount < 0:
		var heal_amount := -amount
		var new_health := clampi(health + heal_amount, 0, max_health)
		var actual_heal := new_health - health

		if actual_heal == 0:
			return

		health = new_health
		GameState.set_health(health)
		emit_signal("healed", actual_heal)
