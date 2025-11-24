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

# --- BURN STATUS -----------------------------------------------------
var burn_time_left: float = 0.0
var burn_tick_interval: float = 0.3
var burn_tick_timer: float = 0.0
var burn_damage_per_tick: float = 0.0   # <-- float now
var burn_damage_accumulator: float = 0.0


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

	_update_burn(delta)


func grant_spawn_invincibility(duration: float) -> void:
	invincible_timer = max(invincible_timer, duration)


func sync_from_gamestate() -> void:
	if use_gamestate:
		max_health = GameState.max_health
		health = GameState.health


# --------------------------------------------------------------------
# PUBLIC DAMAGE API
# --------------------------------------------------------------------

func take_damage(amount: int) -> void:
	# Normal external damage path (hits, bullets, etc.)
	# Respects invincibility / god mode.
	_apply_damage(amount, false)


# 🔥 Burn DoT entry point
func apply_burn(dmg_per_tick: float, duration: float, interval: float) -> void:
	if duration <= 0.0 or dmg_per_tick <= 0.0:
		return

	burn_time_left = duration
	burn_damage_per_tick = dmg_per_tick
	burn_tick_interval = max(0.05, interval)
	burn_tick_timer = 0.0


# --------------------------------------------------------------------
# INTERNAL DAMAGE HANDLING
# --------------------------------------------------------------------

func _apply_damage(amount: float, ignore_invincibility: bool) -> void:
	if amount == 0.0 or is_dead:
		return

	var is_damage := amount > 0.0

	# --- DAMAGE (amount > 0) ---
	if is_damage:
		# God mode only matters for the player
		if use_gamestate and GameState.debug_god_mode:
			return

		# i-frames blocked unless this is burn (or other forced damage)
		if invincible_timer > 0.0 and not ignore_invincibility:
			return

		# Start i-frames only for "normal" hits
		if not ignore_invincibility:
			invincible_timer = invincible_time

		# Play hurt SFX only for normal hits
		if not ignore_invincibility and owner and owner.has_node("SFX_Hurt"):
			owner.get_node("SFX_Hurt").play()

		emit_signal("damaged", int(amount))

	# --- HEAL (amount < 0) ---
	elif amount < 0.0:
		emit_signal("healed", int(-amount))

	# Apply to local health (HP itself stays int)
	var new_health := clampi(health - int(round(amount)), 0, max_health)
	health = new_health

	# If this is the PLAYER component, also mirror into GameState
	if use_gamestate:
		GameState.set_health(new_health)

	# Death
	if is_damage and health <= 0:
		is_dead = true
		emit_signal("died")


# --------------------------------------------------------------------
# BURN TICK UPDATE
# --------------------------------------------------------------------

func _update_burn(delta: float) -> void:
	if burn_time_left <= 0.0:
		return

	burn_time_left -= delta
	burn_tick_timer -= delta

	if burn_tick_timer <= 0.0:
		burn_tick_timer += burn_tick_interval
		# Burn damage bypasses invincibility frames
		burn_damage_accumulator += burn_damage_per_tick

		if burn_damage_accumulator >= 1.0:
			var dmg_to_apply = int(burn_damage_accumulator)
			burn_damage_accumulator -= dmg_to_apply
			_apply_damage(dmg_to_apply, true)


	if burn_time_left <= 0.0:
		burn_damage_per_tick = 0.0
