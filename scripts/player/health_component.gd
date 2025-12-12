extends Node



signal damaged(amount: int)
signal healed(amount: int)
signal died

const DamageNumberScene := preload("res://scenes/ui/damage_number.tscn")

@export var freeze_target_path: NodePath      # e.g. "AnimatedSprite2D"
@export var freeze_material: ShaderMaterial   # the blue frozen material

@export var poison_target_path: NodePath = "" # e.g. "AnimatedSprite2D"
@export var poison_material: ShaderMaterial   # the green poison material

@export var burn_target_path: NodePath = ""   # e.g. "AnimatedSprite2D"
@export var burn_material: ShaderMaterial     # the orange burn material

var _freeze_target: CanvasItem = null
var _freeze_original_material: Material = null

var _poison_target: CanvasItem = null
var _poison_original_material: Material = null

var _burn_target: CanvasItem = null
var _burn_original_material: Material = null

@export var use_gamestate: bool = false  # true for player, false for enemies
@export var max_health: int = 1
var health: int = 0

@export var invincible_time: float = 0.0
var invincible_timer: float = 0.0

var is_dead: bool = false

# --- DAMAGE NUMBER STACKING -------------------------------------------
var active_damage_number: Node2D = null
var last_damage_time: float = 0.0
const DAMAGE_COMBO_WINDOW: float = 10  # seconds to stack damage (increased for rapid fire)

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

# --- POISON STATUS ---------------------------------------------------
var poison_time_left: float = 0.0
var poison_tick_interval: float = 0.5
var poison_tick_timer: float = 0.0
var poison_damage_per_tick: float = 0.0
var poison_damage_accumulator: float = 0.0


func _ready() -> void:
		# Regen upgrades removed
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

	# 🟢 poison target lookup
	if poison_target_path != NodePath(""):
		var p = get_node_or_null(poison_target_path)
		if p and p is CanvasItem:
			_poison_target = p
			_poison_original_material = _poison_target.material

	# 🔥 burn target lookup
	if burn_target_path != NodePath(""):
		var b = get_node_or_null(burn_target_path)
		if b and b is CanvasItem:
			_burn_target = b
			_burn_original_material = _burn_target.material


func _physics_process(delta: float) -> void:
		# Regen removed
	if invincible_timer > 0.0:
		invincible_timer -= delta

	_update_burn(delta)
	_update_poison(delta)
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
	_set_burn_visual(true)


func apply_freeze(speed_factor: float, duration: float) -> void:
	# speed_factor between 0.1–1.0 (1 = no slow)
	if duration <= 0.0:
		return

	freeze_time_left = duration
	freeze_speed_factor = clamp(speed_factor, 0.1, 1.0)
	_set_frozen_visual(true)


func apply_poison(dmg_per_tick: float, duration: float, interval: float) -> void:
	# Separate DOT from burn so both can exist in the game
	if duration <= 0.0 or dmg_per_tick <= 0.0:
		return

	poison_time_left = duration
	poison_damage_per_tick = dmg_per_tick
	poison_tick_interval = max(0.05, interval)
	poison_tick_timer = 0.0
	_set_poison_visual(true)


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

	# --- PASSIVE UPGRADE: Damage Reduction ---
	if is_damage and use_gamestate:
		amount *= GameState.damage_taken_mult

	# --- PASSIVE UPGRADE: Berserker ---

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
		
		# Spawn damage number (unless disabled via meta tag)
		if not get_meta("skip_damage_numbers", false):
			_spawn_damage_number(int(amount))
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


func _spawn_damage_number(damage: int) -> void:
	if not owner:
		return
	
	var current_scene := get_tree().current_scene
	if not current_scene:
		return
	
	var current_time := Time.get_ticks_msec() / 1000.0
	
	# Check if we can stack onto existing damage number
	if active_damage_number != null and is_instance_valid(active_damage_number):
		var time_since_last := current_time - last_damage_time
		
		if time_since_last < DAMAGE_COMBO_WINDOW:
			# Add to existing number instead of spawning new
			if active_damage_number.has_method("add_damage"):

				active_damage_number.add_damage(damage)
				last_damage_time = current_time
				return
		else:
			# Combo expired - stop following on old number
			if active_damage_number.has_method("stop_following"):
				active_damage_number.stop_following()
	
	# Spawn new damage number
	var damage_number := DamageNumberScene.instantiate()
	
	# Calculate spawn position
	var spawn_offset := Vector2(randf_range(-8, 8), -20)
	var spawn_pos: Vector2 = owner.global_position + spawn_offset
	
	# ⭐ KEY FIX: Set position BEFORE adding to tree to prevent glitch
	damage_number.position = spawn_pos
	
	# Now add to tree (node will already be at correct position)
	current_scene.add_child(damage_number)
	
	# Call setup with owner as target
	damage_number.setup(damage, false, owner)
	
	# Track as active damage number
	active_damage_number = damage_number
	last_damage_time = current_time
	
	# Connect to cleanup when freed
	if not damage_number.tree_exiting.is_connected(_on_damage_number_freed):
		damage_number.tree_exiting.connect(_on_damage_number_freed)


func _on_damage_number_freed() -> void:
	active_damage_number = null


# --------------------------------------------------------------------
# BURN / POISON / FREEZE UPDATE
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
			_apply_damage(dmg_to_apply, true)  # burn ignores i-frames

	if burn_time_left <= 0.0:
		burn_damage_per_tick = 0.0
		burn_damage_accumulator = 0.0
		_set_burn_visual(false)


func _update_poison(delta: float) -> void:
	if poison_time_left <= 0.0:
		return

	poison_time_left -= delta
	poison_tick_timer -= delta

	if poison_tick_timer <= 0.0:
		poison_tick_timer += poison_tick_interval
		poison_damage_accumulator += poison_damage_per_tick

		if poison_damage_accumulator >= 1.0:
			var dmg_to_apply := int(poison_damage_accumulator)
			poison_damage_accumulator -= dmg_to_apply
			_apply_damage(dmg_to_apply, true)  # poison also ignores i-frames

	if poison_time_left <= 0.0:
		poison_damage_per_tick = 0.0
		poison_damage_accumulator = 0.0
		_set_poison_visual(false)


func _update_freeze(delta: float) -> void:
	if freeze_time_left <= 0.0:
		return

	freeze_time_left -= delta

	if freeze_time_left <= 0.0:
		freeze_speed_factor = 1.0
		_set_frozen_visual(false)


# --------------------------------------------------------------------
# VISUAL HELPERS
# --------------------------------------------------------------------

func _set_frozen_visual(active: bool) -> void:
	if _freeze_target == null:
		return

	if active:
		if freeze_material:
			_freeze_target.material = freeze_material
	else:
		_freeze_target.material = _freeze_original_material


func _set_poison_visual(active: bool) -> void:
	if _poison_target == null:
		return

	if active:
		if poison_material:
			_poison_target.material = poison_material
	else:
		_poison_target.material = _poison_original_material


func _set_burn_visual(active: bool) -> void:
	if _burn_target == null:
		return

	if active:
		if burn_material:
			_burn_target.material = burn_material
	else:
		_burn_target.material = _burn_original_material
