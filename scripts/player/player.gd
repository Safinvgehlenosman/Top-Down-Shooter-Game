extends CharacterBody2D

const BulletScene_DEFAULT := preload("res://scenes/bullets/bullet.tscn")
const BulletScene_SHOTGUN := preload("res://scenes/bullets/shotgun_bullet.tscn")
const BulletScene_SNIPER  := preload("res://scenes/bullets/sniper_bullet.tscn")
const DashGhostScene := preload("res://scenes/dash_ghost.tscn")

var dash_ghost_interval: float = 0.03
var dash_ghost_timer: float = 0.0

@onready var gun: Node = $Gun
@onready var health_component: Node = $Health
@onready var ability_component: Node = $Ability
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var muzzle: Marker2D = $Gun/Muzzle

# Runtime stats (filled from GameConfig / GameState in _ready)
var speed: float
var max_health: int
var knockback_strength: float
var knockback_duration: float
var invincible_time: float
var alt_weapon: int = GameState.AltWeaponType.NONE


# State
var health: int = 0


# Knockback
var knockback: Vector2 = Vector2.ZERO
var knockback_timer: float = 0.0

# Invincibility
var invincible_timer: float = 0.0

var is_dead: bool = false
var weapon_enabled: bool = true  # Disabled in hub

# --- AIM / INPUT MODE ------------------------------------------------

const AIM_DEADZONE: float = 0.25
const AIM_CURSOR_SPEED: float = 800.0  # tweak speed of controller cursor
const AIM_SMOOTH: float = 10.0  # higher = snappier, lower = floatier


enum AimMode { MOUSE, CONTROLLER }
var aim_mode: AimMode = AimMode.MOUSE

var aim_dir: Vector2 = Vector2.RIGHT

# one shared cursor for mouse + controller
var aim_cursor_pos: Vector2 = Vector2.ZERO
var last_mouse_pos: Vector2 = Vector2.ZERO

func grant_spawn_invincibility(duration: float) -> void:
	if health_component and health_component.has_method("grant_spawn_invincibility"):
		health_component.grant_spawn_invincibility(duration)

# --------------------------------------------------------------------
# READY
# --------------------------------------------------------------------

func _ready() -> void:
	# Design defaults from GameConfig
	speed              = GameConfig.player_move_speed
	knockback_strength = GameConfig.player_knockback_strength
	knockback_duration = GameConfig.player_knockback_duration
	invincible_time    = GameConfig.player_invincible_time
	
	# gun.init_from_state() removed (function does not exist)
	gun.connect("recoil_requested", _on_gun_recoil_requested)

	# --- HealthComponent wiring ---
	if health_component:
		# Player-specific config for the generic Health component
		health_component.invincible_time = GameConfig.player_invincible_time

		health_component.connect("damaged", Callable(self, "_on_health_damaged"))
		health_component.connect("healed",  Callable(self, "_on_health_healed"))
		health_component.connect("died",    Callable(self, "_on_health_died"))

	# --- AbilityComponent wiring (optional sync) ---
	if ability_component and ability_component.has_method("sync_from_gamestate"):
		ability_component.sync_from_gamestate()
	
	# --- Listen for alt weapon changes ---
	GameState.alt_weapon_changed.connect(func(_new_weapon): sync_from_gamestate())

	var design_max_health: int = GameConfig.player_max_health

	var _design_max_ammo: int   = GameConfig.player_max_ammo
	var design_fire_rate: float = GameConfig.player_fire_rate
	var design_pellets: int    = GameConfig.alt_fire_bullet_count

	# --- Sync with GameState (current run data) ---

	# Initialize GameState once (first run)
	if GameState.max_health == 0:
		GameState.max_health = design_max_health
		GameState.health     = design_max_health

	if GameState.fire_rate <= 0.0:
		GameState.fire_rate = design_fire_rate
	
	if GameState.move_speed <= 0.0:
		GameState.move_speed_base = GameConfig.player_move_speed
		GameState.move_speed = GameState.move_speed_base

	if GameState.shotgun_pellets <= 0:
		GameState.shotgun_pellets = design_pellets

	# Local copies from current run (+ push into HealthComponent)
	sync_from_gamestate()
	alt_weapon = GameState.alt_weapon

	# Aim setup
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	aim_cursor_pos = get_global_mouse_position()
	last_mouse_pos = get_viewport().get_mouse_position()


# --------------------------------------------------------------------
# PROCESS
# --------------------------------------------------------------------

func _process(_delta: float) -> void:
	_update_crosshair()


func _physics_process(delta: float) -> void:
	if is_dead:
		return

    # Regeneration removed

	_update_timers(delta)
	_process_movement(delta)
	_update_aim_direction(delta)
	_process_aim()
	
	gun.update_timers(delta)

	var is_shooting := Input.is_action_pressed("shoot")
	var is_alt_fire := Input.is_action_pressed("alt_fire")

	# Disable shooting in hub or while invisible (EXCEPT shuriken synergy)
	if weapon_enabled and not GameState.player_invisible:
		gun.handle_primary_fire(is_shooting, aim_dir)
		gun.handle_alt_fire(is_alt_fire, aim_cursor_pos)
	elif weapon_enabled and GameState.player_invisible:
		# ⭐ SYNERGY 1: Allow shuriken shooting while invisible
		if GameState.has_invis_shuriken_synergy and GameState.alt_weapon == GameState.AltWeaponType.SHURIKEN:
			gun.handle_alt_fire(is_alt_fire, aim_cursor_pos)


func _on_gun_recoil_requested(dir: Vector2, strength: float) -> void:
	knockback = dir * strength
	knockback_timer = knockback_duration

# --------------------------------------------------------------------
# TIMERS
# --------------------------------------------------------------------

func _update_timers(delta: float) -> void:
	# NOTE: invincibility is now handled inside HealthComponent

	if knockback_timer > 0.0:
		knockback_timer -= delta
	else:
		knockback = Vector2.ZERO

# --------------------------------------------------------------------
# MOVEMENT & AIM
# --------------------------------------------------------------------

func _process_movement(_delta: float) -> void:
	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input_dir.y = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")

	if input_dir != Vector2.ZERO:
		input_dir = input_dir.normalized()

	# ⭐ Always read current speed from GameState (for chaos challenges)
	var current_speed: float = GameState.move_speed

	# Ask HealthComponent how slowed we are (1.0 = normal)
	var slow_factor: float = 1.0
	if health_component and health_component.has_method("get_move_slow_factor"):
		slow_factor = health_component.get_move_slow_factor()

	# Ask AbilityComponent if a dash is active
	if ability_component and ability_component.has_method("get_dash_velocity"):
		var dash_velocity: Vector2 = ability_component.get_dash_velocity()
		if dash_velocity != Vector2.ZERO:
			# Dash ignores slow (nice counterplay). Remove if you want frozen dashes too.
			velocity = dash_velocity
		else:
			velocity = input_dir * current_speed * slow_factor
	else:
		velocity = input_dir * current_speed * slow_factor

	# Apply knockback on top of input movement
	if knockback_timer > 0.0:
		velocity += knockback

	move_and_slide()


# choose input mode & update aim_dir
func _update_aim_direction(delta: float) -> void:
	var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	var mouse_pos := get_global_mouse_position()

	# 1) Controller input → move virtual cursor
	if stick.length() >= AIM_DEADZONE:
		aim_mode = AimMode.CONTROLLER
		stick = stick.normalized()

		var target_pos: Vector2 = aim_cursor_pos + stick * AIM_CURSOR_SPEED * delta
		var t: float = clamp(AIM_SMOOTH * delta, 0.0, 1.0)

		aim_cursor_pos = aim_cursor_pos.lerp(target_pos, t)

	# 2) Mouse movement → override cursor
	else:
		if mouse_pos.distance_to(last_mouse_pos) > 0.5:
			aim_mode = AimMode.MOUSE
			aim_cursor_pos = mouse_pos
			last_mouse_pos = mouse_pos

	# 3) Keep cursor inside viewport
	var vp := get_viewport()
	aim_cursor_pos.x = clamp(aim_cursor_pos.x, 0.0, vp.size.x)
	aim_cursor_pos.y = clamp(aim_cursor_pos.y, 0.0, vp.size.y)

	# 4) Aim direction: from player to cursor
	var vec := aim_cursor_pos - global_position
	if vec.length() > 0.001:
		aim_dir = vec.normalized()
	else:
		aim_dir = Vector2.RIGHT

func _process_aim() -> void:
	# Flip player sprite
	if aim_dir.x > 0.0:
		animated_sprite.flip_h = false
	elif aim_dir.x < 0.0:
		animated_sprite.flip_h = true

	# Rotate gun to face aim_dir (works for mouse + controller)
	if has_node("Gun"):
		gun.rotation = aim_dir.angle()

# Crosshair follows shared cursor (mouse + controller)
func _update_crosshair() -> void:
	var crosshair := get_tree().get_first_node_in_group("crosshair")
	if crosshair == null:
		return

	crosshair.global_position = aim_cursor_pos

# --------------------------------------------------------------------
# FEEDBACK (HIT / HEAL)
# --------------------------------------------------------------------

func _play_hit_feedback() -> void:
	# Camera shake
	var cam := get_tree().get_first_node_in_group("camera")
	if cam and cam.has_method("shake"):
		cam.shake(GameConfig.hit_shake_strength, GameConfig.hit_shake_duration)

	# Red screen flash
	var flash := get_tree().get_first_node_in_group("screen_flash")
	if flash and flash.has_method("flash"):
		flash.flash()

func _play_heal_feedback() -> void:
	# Green screen flash (no shake)
	var flash := get_tree().get_first_node_in_group("screen_flash_heal")
	if flash and flash.has_method("flash"):
		flash.flash()

# --------------------------------------------------------------------
# HEALTH & DAMAGE
# --------------------------------------------------------------------

func take_damage(amount: int) -> void:
	# God mode only for the player, not for every HealthComponent user
	if amount > 0 and GameState.debug_god_mode:
		return

	# Wrapper so enemies can still call player.take_damage(amount)
	if health_component and health_component.has_method("take_damage"):
		health_component.take_damage(amount)


func _on_health_damaged(_amount: int) -> void:
	# Sync GameState from component
	if health_component:
		GameState.set_health(health_component.health)

	# Play hurt SFX + camera/screen feedback
	if has_node("SFX_Hurt"):
		$SFX_Hurt.play()
	_play_hit_feedback()
	# UI is updated via GameState.health_changed -> ui.gd


func _on_health_healed(_amount: int) -> void:
	if health_component:
		GameState.set_health(health_component.health)

	_play_heal_feedback()
	# UI is updated via GameState.health_changed -> ui.gd


func _on_health_died() -> void:
	# Make sure GameState HP is 0
	GameState.set_health(0)

	# Mark player as dead so _physics_process stops
	is_dead = true
	die()


func add_coin() -> void:
	GameState.add_coins(1)

func apply_knockback(from_position: Vector2) -> void:
	var dir := (global_position - from_position).normalized()
	knockback = dir * knockback_strength
	knockback_timer = knockback_duration


func die() -> void:
	is_dead = true

	# Disable gun logic so it stops rotating/aiming
	if has_node("Gun"):
		gun.process_mode = Node.PROCESS_MODE_DISABLED

	# Hide crosshair
	var crosshair := get_tree().get_first_node_in_group("crosshair")
	if crosshair:
		crosshair.visible = false

	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm and gm.has_method("on_player_died"):
		gm.on_player_died()

# --------------------------------------------------------------------
# UI BARS
# --------------------------------------------------------------------

func sync_from_gamestate() -> void:
	# Core stats from GameState
	max_health = GameState.max_health
	health     = GameState.health
	
	# Apply move speed from GameState
	speed = GameState.move_speed

	# Push into generic HealthComponent
	if health_component:
		health_component.max_health = max_health
		health_component.health     = health

	# Also tell AbilityComponent to resync (e.g. after unlocks)
	if ability_component and ability_component.has_method("sync_from_gamestate"):
		ability_component.sync_from_gamestate()

	# 🔥 ALSO SYNC ALT WEAPON
	alt_weapon = GameState.alt_weapon  # 0–3

	# Turret visual + config
	if has_node("Turret"):
		var turret = $Turret

		if alt_weapon == GameState.AltWeaponType.TURRET:
			turret.visible = true

			var data: Dictionary = GameState.ALT_WEAPON_DATA.get(GameState.alt_weapon, {})
			if not data.is_empty() and turret.has_method("configure"):
				turret.configure(data)
		else:
			turret.visible = false


# --------------------------------------------------------------------
# HUB MODE - Disable/Enable Weapon
# --------------------------------------------------------------------

func set_weapon_enabled(enabled: bool) -> void:
	"""Enable or disable the player's weapon (used in hub)."""
	weapon_enabled = enabled
	if gun:
		gun.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
		gun.visible = enabled
	
	# Also hide/show crosshair
	var crosshair := get_tree().get_first_node_in_group("crosshair")
	if crosshair:
		crosshair.visible = enabled
	
	# Hide turret in hub
	if has_node("Turret"):
		var turret = $Turret
		if not enabled:
			turret.visible = false
