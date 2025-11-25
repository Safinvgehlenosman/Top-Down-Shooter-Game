extends Node

signal damaged(amount: int)
signal healed(amount: int)
signal died

@export var freeze_target_path: NodePath      # e.g. "AnimatedSprite2D"
@export var freeze_material: ShaderMaterial   # the blue frozen material


var _freeze_target: CanvasItem = null
var _freeze_original_material: Material = null

@export var use_gamestate: bool = false  # true for player, false for enemies
@export var max_health: int = 1
var health: int = 0

@export var invincible_time: float = 0.0
var invincible_timer: float = 0.0

var is_dead: bool = false

# --- BURN STATUS -----------------------------------------------------
var burn_time_left: float = 0.0
var burn_tick_interval: float = 0.3
var burn_tick_timer: float = 0.0
var burn_damage_per_tick: float = 0.0
var burn_damage_accumulator: float = 0.0

# --- FREEZE STATUS ---------------------------------------------------
# 1.0 = normal speed, 0.3 = 70% slower, etc.
var freeze_time_left: float = 0.0
var freeze_speed_factor: float = 1.0


func _ready() -> void:
	if use_gamestate:
		max_health = GameState.max_health
		health = GameState.health
		invincible_time = GameConfig.player_invincible_time
	else:
		health = max_health

	# 🔵 freeze target lookup (NOTE: use self, not owner)
	if freeze_target_path != NodePath(""):
		var n = get_node_or_null(freeze_target_path)
		if n and n is CanvasItem:
			_freeze_target = n
			_freeze_original_material = _freeze_target.material



func _physics_process(delta: float) -> void:
	if invincible_timer > 0.0:
		invincible_timer -= delta

	_update_burn(delta)
	_update_freeze(delta)


func grant_spawn_invincibility(duration: float) -> void:
	invincible_timer = max(invincible_timer, duration)


func sync_from_gamestate() -> void:
	if use_gamestate:
		max_health = GameState.max_health
		health = GameState.health


# --------------------------------------------------------------------
# PUBLIC API
# --------------------------------------------------------------------

func take_damage(amount: int) -> void:
	_apply_damage(amount, false)


func heal(amount: int) -> void:
	if amount <= 0:
		return
	_apply_damage(-amount, true)


func apply_burn(dmg_per_tick: float, duration: float, interval: float) -> void:
	if duration <= 0.0 or dmg_per_tick <= 0.0:
		return

	burn_time_left = duration
	burn_damage_per_tick = dmg_per_tick
	burn_tick_interval = max(0.05, interval)
	burn_tick_timer = 0.0


func apply_freeze(speed_factor: float, duration: float) -> void:
	# speed_factor between 0.1–1.0 (1 = no slow)
	if duration <= 0.0:
		return

	freeze_time_left = duration
	freeze_speed_factor = clamp(speed_factor, 0.1, 1.0)
	_set_frozen_visual(true)


func get_move_slow_factor() -> float:
	# Player / enemies can query this to scale their movement
	return freeze_speed_factor


# --------------------------------------------------------------------
# INTERNAL DAMAGE HANDLING
# --------------------------------------------------------------------

func _apply_damage(amount: float, ignore_invincibility: bool) -> void:
	if amount == 0.0 or is_dead:
		return

	var is_damage := amount > 0.0

	if is_damage:
		# God mode only matters for the player
		if use_gamestate and GameState.debug_god_mode:
			return

		if invincible_timer > 0.0 and not ignore_invincibility:
			return

		if not ignore_invincibility:
			invincible_timer = invincible_time

		if not ignore_invincibility and owner and owner.has_node("SFX_Hurt"):
			owner.get_node("SFX_Hurt").play()

		emit_signal("damaged", int(amount))
	else:
		emit_signal("healed", int(-amount))

	# Apply to local health (HP stays int)
	var new_health := clampi(health - int(round(amount)), 0, max_health)
	health = new_health

	# Mirror into GameState for player
	if use_gamestate:
		GameState.set_health(new_health)

	if is_damage and health <= 0:
		is_dead = true
		emit_signal("died")


# --------------------------------------------------------------------
# BURN & FREEZE UPDATE
# --------------------------------------------------------------------

func _update_burn(delta: float) -> void:
	if burn_time_left <= 0.0:
		return

	burn_time_left -= delta
	burn_tick_timer -= delta

	if burn_tick_timer <= 0.0:
		burn_tick_timer += burn_tick_interval
		burn_damage_accumulator += burn_damage_per_tick

		if burn_damage_accumulator >= 1.0:
			var dmg_to_apply := int(burn_damage_accumulator)
			burn_damage_accumulator -= dmg_to_apply
			_apply_damage(dmg_to_apply, true)

	if burn_time_left <= 0.0:
		burn_damage_per_tick = 0.0
		burn_damage_accumulator = 0.0


func _update_freeze(delta: float) -> void:
	if freeze_time_left <= 0.0:
		return

	freeze_time_left -= delta

	if freeze_time_left <= 0.0:
		freeze_speed_factor = 1.0
		_set_frozen_visual(false)

func _set_frozen_visual(active: bool) -> void:
	if _freeze_target == null:
		return

	if active:
		if freeze_material:
			_freeze_target.material = freeze_material
	else:
		_freeze_target.material = _freeze_original_material
