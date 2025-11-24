extends CharacterBody2D

const BulletScene_DEFAULT := preload("res://scenes/bullets/bullet.tscn")
const BulletScene_SHOTGUN := preload("res://scenes/bullets/shotgun_bullet.tscn")
const BulletScene_SNIPER  := preload("res://scenes/bullets/sniper_bullet.tscn")
const DashGhostScene := preload("res://scenes/dash_ghost.tscn")

var dash_ghost_interval: float = 0.03
var dash_ghost_timer: float = 0.0

@onready var gun: Node = $Gun
@onready var health_component: Node = $Health



# UI
@onready var hp_fill: TextureProgressBar = $"../UI/HPBar/HPFill"
@onready var hp_label: Label = $"../UI/HPLabel"
@onready var ammo_label: Label = $"../UI/AmmoUI/AmmoLabel"
@onready var coin_label: Label = $"../UI/CoinUI/CoinLabel"
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var muzzle: Marker2D = $Gun/Muzzle


# Runtime stats (filled from GameConfig / GameState in _ready)
var speed: float
var max_health: int
var knockback_strength: float
var knockback_duration: float
var invincible_time: float

# State
var health: int = 0


# Knockback
var knockback: Vector2 = Vector2.ZERO
var knockback_timer: float = 0.0

# Invincibility
var invincible_timer: float = 0.0

var is_dead: bool = false

# --- AIM / INPUT MODE ------------------------------------------------

const AIM_DEADZONE: float = 0.25
const AIM_CURSOR_SPEED: float = 800.0  # tweak speed of controller cursor
const AIM_SMOOTH: float = 10.0  # higher = snappier, lower = floatier

const AltWeaponType = GameState.AltWeaponType
var alt_weapon: AltWeaponType = AltWeaponType.NONE


enum AbilityType { NONE, DASH, SLOWMO }
var ability: AbilityType = AbilityType.NONE

var ability_cooldown_left: float = 0.0
var ability_active_left: float = 0.0

var is_dashing: bool = false
var dash_dir: Vector2 = Vector2.ZERO
var dash_speed: float = 0.0

var slowmo_running: bool = false
var base_speed: float = 0.0


const ALT_WEAPON_DATA = {
	AltWeaponType.SHOTGUN: {
		"cooldown": 0.7,
	},
	AltWeaponType.SNIPER: {
		"cooldown": 1.2,
	},
}



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
	base_speed         = speed
	knockback_duration = GameConfig.player_knockback_duration
	invincible_time    = GameConfig.player_invincible_time
	
	gun.init_from_state()
	gun.connect("recoil_requested", _on_gun_recoil_requested)

	# --- HealthComponent wiring ---
	if health_component:
		# Make sure health_component is in sync with GameState at start
		if health_component.has_method("sync_from_gamestate"):
			health_component.sync_from_gamestate()

		# Connect health signals
		health_component.connect("damaged", Callable(self, "_on_health_damaged"))
		health_component.connect("healed", Callable(self, "_on_health_healed"))
		health_component.connect("died", Callable(self, "_on_health_died"))

	var design_max_health: int = GameConfig.player_max_health
	var design_max_ammo: int = GameConfig.player_max_ammo
	var design_fire_rate: float = GameConfig.player_fire_rate
	var design_pellets: int = GameConfig.alt_fire_bullet_count

	# --- Sync with GameState (current run data) ---

	# Initialize GameState once (first run)
	if GameState.max_health == 0:
		GameState.max_health = design_max_health
		GameState.health = design_max_health

	if GameState.fire_rate <= 0.0:
		GameState.fire_rate = design_fire_rate

	if GameState.shotgun_pellets <= 0:
		GameState.shotgun_pellets = design_pellets

	# Local copies from current run
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
	coin_label.text = str(GameState.coins)
	if alt_weapon == AltWeaponType.NONE or alt_weapon == AltWeaponType.TURRET:
		ammo_label.text = "-/-"
	else:
		ammo_label.text = "%d/%d" % [GameState.ammo, GameState.max_ammo]

	_update_crosshair()
	


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	_update_timers(delta)
	_process_movement(delta)
	_update_aim_direction(delta)
	_process_aim()
	_process_ability_input(delta)
	
	if is_dashing:
		dash_ghost_timer -= delta
		if dash_ghost_timer <= 0.0:
			_spawn_dash_ghost()
			dash_ghost_timer = dash_ghost_interval
	
	gun.update_timers(delta)

	var is_shooting := Input.is_action_pressed("shoot")
	var is_alt_fire := Input.is_action_just_pressed("alt_fire")

# you already keep track of aim_dir and aim_cursor_pos in Player
	gun.handle_primary_fire(is_shooting, aim_dir)
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

	# --- Ability timers ---
	if ability_cooldown_left > 0.0:
		ability_cooldown_left = max(ability_cooldown_left - delta, 0.0)

	if ability_active_left > 0.0:
		ability_active_left -= delta
		if ability_active_left <= 0.0:
			_end_ability()




# --------------------------------------------------------------------
# MOVEMENT & AIM
# --------------------------------------------------------------------

func _process_movement(_delta: float) -> void:
	if is_dashing:
		# Dash overrides normal movement
		velocity = dash_dir * dash_speed
	else:
		var input_dir := Vector2.ZERO
		input_dir.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
		input_dir.y = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")

		if input_dir != Vector2.ZERO:
			input_dir = input_dir.normalized()

		velocity = input_dir * speed

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


func _process_aim() -> void:
	# Flip player sprite
	if aim_dir.x > 0.0:
		animated_sprite.flip_h = false
	elif aim_dir.x < 0.0:
		animated_sprite.flip_h = true

	# Rotate gun to face aim_dir (works for mouse + controller)
	if has_node("Gun"):
		var gun := $Gun
		gun.rotation = aim_dir.angle()


# Crosshair follows shared cursor (mouse + controller)
func _update_crosshair() -> void:
	var crosshair := get_tree().get_first_node_in_group("crosshair")
	if crosshair == null:
		return

	crosshair.global_position = aim_cursor_pos


func _process_ability_input(_delta: float) -> void:
	if ability == AbilityType.NONE:
		return

	if Input.is_action_just_pressed("ability") and ability_cooldown_left <= 0.0 and ability_active_left <= 0.0:
		_start_ability()


func _start_ability() -> void:
	var data: Dictionary = GameState.ABILITY_DATA.get(int(ability), {})
	if data.is_empty():
		return

	var ability_type: String = data.get("type", "")
	match ability_type:
		"dash":
			_start_dash(data)
		"slowmo":
			_start_slowmo(data)

func _start_dash(data: Dictionary) -> void:
	# Direction from movement or fallback to aim_dir
	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input_dir.y = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")

	if input_dir == Vector2.ZERO:
		input_dir = aim_dir

	if input_dir == Vector2.ZERO:
		return

	dash_dir = input_dir.normalized()

	var duration: float = data.get("duration", 0.12)
	var distance: float = data.get("distance", 220.0)
	dash_speed = distance / max(duration, 0.01)

	ability_active_left = duration
	ability_cooldown_left = data.get("cooldown", 5.0)

	is_dashing = true
	# 👇 So the first ghost spawns immediately
	dash_ghost_timer = 0.0

func _spawn_dash_ghost() -> void:
	if DashGhostScene == null:
		return

	var ghost := DashGhostScene.instantiate()
	ghost.global_position = global_position
	ghost.rotation = rotation  # top-down so probably 0, but safe

	# Add to main scene
	get_tree().current_scene.add_child(ghost)

	# Copy current player frame into ghost
	ghost.setup_from_player(animated_sprite)


func _start_slowmo(data: Dictionary) -> void:
	if slowmo_running:
		return

	var duration: float = data.get("duration", 3.0)
	var cooldown: float = data.get("cooldown", 30.0)
	var factor: float = data.get("factor", 0.3)

	ability_active_left = duration
	ability_cooldown_left = cooldown

	slowmo_running = true

	# Slow down the world…
	Engine.time_scale = factor
	# …but keep player speed feeling normal
	speed = base_speed / max(factor, 0.01)

func _end_ability() -> void:
	if is_dashing:
		is_dashing = false
		dash_speed = 0.0

	if slowmo_running:
		slowmo_running = false
		Engine.time_scale = 1.0
		speed = base_speed

	ability_active_left = 0.0

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
	# Keep this wrapper so enemies can still call player.take_damage(amount)
	if health_component and health_component.has_method("take_damage"):
		health_component.take_damage(amount)

func _on_health_damaged(_amount: int) -> void:
	# Play hurt SFX + camera/screen feedback
	if has_node("SFX_Hurt"):
		$SFX_Hurt.play()
	_play_hit_feedback()

	# Update HP UI to match GameState
	update_health_bar()


func _on_health_healed(_amount: int) -> void:
	_play_heal_feedback()
	update_health_bar()


func _on_health_died() -> void:
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
		var gun := $Gun
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

func update_health_bar() -> void:
	if hp_fill:
		hp_fill.max_value = GameState.max_health
		hp_fill.value = GameState.health

	if hp_label:
		hp_label.text = "%d/%d" % [GameState.health, GameState.max_health]


func sync_from_gamestate() -> void:
	# Core stats
	max_health = GameState.max_health
	health     = GameState.health

	# Also tell HealthComponent to resync
	if health_component and health_component.has_method("sync_from_gamestate"):
		health_component.sync_from_gamestate()

	# 🔥 ALSO SYNC ALT WEAPON
	alt_weapon = GameState.alt_weapon  # 0–3

	# Turret visual + config
	if has_node("Turret"):
		var turret = $Turret

		if alt_weapon == AltWeaponType.TURRET:
			turret.visible = true

			# pull the currently selected weapon's data
			var data: Dictionary = GameState.ALT_WEAPON_DATA.get(GameState.alt_weapon, {})
			# (alt_weapon == ALT_WEAPON_TURRET when we’re here)

			if not data.is_empty() and turret.has_method("configure"):
				turret.configure(data)
		else:
			turret.visible = false

	# 🌀 Ability
	ability = GameState.ability

	# Update HP UI to match
	update_health_bar()
