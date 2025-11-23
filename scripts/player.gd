extends CharacterBody2D

const BulletScene_DEFAULT := preload("res://scenes/bullets/bullet.tscn")
const BulletScene_SHOTGUN := preload("res://scenes/bullets/shotgun_bullet.tscn")
const BulletScene_SNIPER  := preload("res://scenes/bullets/sniper_bullet.tscn")


# UI
@onready var hp_fill: TextureProgressBar = $"../UI/HPBar/HPFill"
@onready var hp_label: Label = $"../UI/HPLabel"
@onready var ammo_label: Label = $"../UI/AmmoUI/AmmoLabel"
@onready var coin_label: Label = $"../UI/CoinUI/CoinLabel"
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var muzzle: Marker2D = $Gun/Muzzle

var alt_fire_cooldown_timer: float = 0.0

# Runtime stats (filled from GameConfig / GameState in _ready)
var speed: float
var max_health: int
var fire_rate: float
var knockback_strength: float
var knockback_duration: float
var invincible_time: float
var max_ammo: int

# State
var health: int = 0
var ammo: int = 0
var fire_timer: float = 0.0

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

enum AltWeaponType { NONE, SHOTGUN, SNIPER, TURRET }
var alt_weapon: AltWeaponType = AltWeaponType.NONE

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
	invincible_timer = max(invincible_timer, duration)




# --------------------------------------------------------------------
# READY
# --------------------------------------------------------------------

func _ready() -> void:
	# Design defaults from GameConfig
	speed              = GameConfig.player_move_speed
	knockback_strength = GameConfig.player_knockback_strength
	knockback_duration = GameConfig.player_knockback_duration
	invincible_time    = GameConfig.player_invincible_time

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
	_process_shooting(delta)


# --------------------------------------------------------------------
# TIMERS
# --------------------------------------------------------------------

func _update_timers(delta: float) -> void:
	if invincible_timer > 0.0:
		invincible_timer -= delta

	if knockback_timer > 0.0:
		knockback_timer -= delta
	else:
		knockback = Vector2.ZERO

	if alt_fire_cooldown_timer > 0.0:
		alt_fire_cooldown_timer -= delta


# --------------------------------------------------------------------
# MOVEMENT & AIM
# --------------------------------------------------------------------

func _process_movement(_delta: float) -> void:
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


# --------------------------------------------------------------------
# SHOOTING
# --------------------------------------------------------------------

func _process_shooting(delta: float) -> void:
	fire_timer -= delta

	# always use current run fire_rate from GameState (upgrades can change it)
	fire_rate = GameState.fire_rate

	if Input.is_action_pressed("shoot") and fire_timer <= 0.0:
		shoot()
		fire_timer = fire_rate

	# Alt fire (modular: shotgun / sniper / etc.)
	if Input.is_action_just_pressed("alt_fire") \
			and alt_fire_cooldown_timer <= 0.0 \
			and GameState.ammo > 0 \
			and alt_weapon != AltWeaponType.NONE:
		_do_alt_fire()



func add_ammo(amount: int) -> void:
	ammo = clampi(ammo + amount, 0, max_ammo)
	GameState.ammo = ammo

func _do_alt_fire() -> void:
	if alt_weapon == AltWeaponType.NONE:
		return
		
	if alt_weapon == AltWeaponType.TURRET:
		return


	var data = GameState.ALT_WEAPON_DATA[alt_weapon]

	# cooldown
	alt_fire_cooldown_timer = data.get("cooldown", 1.0)

	# pick the right fire function
	match alt_weapon:
		AltWeaponType.SHOTGUN:
			_fire_weapon(data)
		AltWeaponType.SNIPER:
			_fire_weapon(data)

func _fire_weapon(data: Dictionary) -> void:
	# spend ammo
	ammo = max(ammo - 1, 0)
	GameState.ammo = ammo

	# get settings
	var bullet_scene: PackedScene = data["bullet_scene"]
	var bullet_speed: float = data["bullet_speed"]
	var pellets: int = data.get("pellets", 1)
	var spread_deg: float = data.get("spread_degrees", 0.0)
	var spread_rad: float = deg_to_rad(spread_deg)
	var damage: float = data.get("damage", 1.0)

	var base_dir := (aim_cursor_pos - muzzle.global_position).normalized()
	var start_offset := -float(pellets - 1) / 2.0

	for i in range(pellets):
		var angle := (start_offset + i) * spread_rad
		var dir := base_dir.rotated(angle)

		var bullet = bullet_scene.instantiate()
		bullet.global_position = muzzle.global_position
		bullet.direction = dir
		bullet.speed = bullet_speed
		bullet.damage = damage   # 👈 THIS is new
		get_tree().current_scene.add_child(bullet)

	# recoil
	var recoil_strength = data.get("recoil", 0.0)
	knockback = -base_dir * recoil_strength
	knockback_timer = 0.15



func _fire_shotgun() -> void:
	# spend ammo
	ammo = max(ammo - 1, 0)
	GameState.ammo = ammo

	# --- SHOTGUN / ALT FIRE SFX ---
	var shot := $SFX_Shoot_Shotgun

	# Main deep blast
	shot.pitch_scale = 0.7
	shot.play()

	# Extra layers for oomph
	for i in range(4):
		shot.pitch_scale = randf_range(0.35, 0.55)
		shot.play()

	# pellet count still uses GameState (so your upgrade works!)
	var bullet_count: int = GameState.shotgun_pellets
	var spread_degrees: float = GameConfig.alt_fire_spread_degrees
	var spread_radians: float = deg_to_rad(spread_degrees)

	# use aim_cursor_pos instead of raw mouse so it works with controller too
	var target_pos := aim_cursor_pos
	var base_dir: Vector2 = (target_pos - muzzle.global_position).normalized()
	var start_index: float = -float(bullet_count - 1) / 2.0

	for i in range(bullet_count):
		var angle_offset: float = (start_index + float(i)) * spread_radians
		var dir: Vector2 = base_dir.rotated(angle_offset)

		var bullet := BulletScene_SHOTGUN.instantiate()
		bullet.global_position = muzzle.global_position
		bullet.direction = dir
		get_tree().current_scene.add_child(bullet)

	# recoil: push player opposite of shot direction
	var recoil_dir: Vector2 = -base_dir

	var base_pellets: int = GameConfig.alt_fire_bullet_count
	var current_pellets: int = GameState.shotgun_pellets
	var extra_pellets: int = max(current_pellets - base_pellets, 0)

	var recoil_multiplier: float = 1.0 + float(extra_pellets) * 0.10
	var recoil_strength: float = GameConfig.alt_fire_recoil_strength * recoil_multiplier

	knockback = recoil_dir * recoil_strength
	knockback_timer = GameConfig.alt_fire_recoil_duration

	var cam := get_tree().get_first_node_in_group("camera")
	if cam and cam.has_method("shake"):
		cam.shake(GameConfig.knockback_shake_strength, GameConfig.knockback_shake_duration)

func _fire_sniper() -> void:
	ammo = max(ammo - 1, 0)
	GameState.ammo = ammo

	$SFX_Shoot.play()

	var target_pos := aim_cursor_pos
	var dir := (target_pos - muzzle.global_position).normalized()

	var bullet := BulletScene_SNIPER.instantiate()
	bullet.global_position = muzzle.global_position
	bullet.direction = dir

	get_tree().current_scene.add_child(bullet)



func shoot() -> void:
	$SFX_Shoot.play()

	var bullet := BulletScene_DEFAULT.instantiate()
	bullet.global_position = muzzle.global_position

	var mouse_pos := get_global_mouse_position()
	var dir := (mouse_pos - muzzle.global_position).normalized()
	bullet.direction = dir

	get_tree().current_scene.add_child(bullet)




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
	if is_dead:
		return
	if amount == 0:
		return

	# DAMAGE (amount > 0)
	if amount > 0:
		if invincible_timer > 0.0:
			return
		invincible_timer = invincible_time

		$SFX_Hurt.play()
		_play_hit_feedback()

	# HEAL (amount < 0)
	elif amount < 0:
		_play_heal_feedback()

	# amount can be negative: damage = minus, heal = plus
	GameState.health = clampi(
		GameState.health - amount,
		0,
		GameState.max_health
	)
	health = GameState.health

	update_health_bar()

	if amount > 0 and health <= 0:
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
	health = GameState.health

	max_ammo = GameState.max_ammo
	ammo = GameState.ammo

	fire_rate = GameState.fire_rate

	# 🔥 ALSO SYNC ALT WEAPON
	alt_weapon = GameState.alt_weapon
	
	if alt_weapon == AltWeaponType.TURRET:
		$Turret.visible = true
		$Turret.configure(GameState.ALT_WEAPON_DATA[AltWeaponType.TURRET])
	else:
		$Turret.visible = false


	# Update HP UI to match
	update_health_bar()
