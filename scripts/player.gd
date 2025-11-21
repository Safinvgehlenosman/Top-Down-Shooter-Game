extends CharacterBody2D

const BulletScene := preload("res://scenes/bullet.tscn")

# UI
@export var health_bar_path: NodePath
@export var health_sprites: Array[Texture2D] = []

@export var ammo_bar_path: NodePath
@export var ammo_sprites: Array[Texture2D] = []

@onready var hp_fill: TextureProgressBar = $"../UI/HPBar/HPFill"
@onready var hp_label: Label = $"../UI/HPLabel"
@onready var ammo_label: Label = $"../UI/AmmoUI/AmmoLabel"
@onready var coin_label: Label = $"../UI/CoinUI/CoinLabel"
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var muzzle: Marker2D = $Gun/Muzzle

var health_bar: TextureRect
var ammo_bar: TextureRect
var alt_fire_cooldown_timer: float = 0.0

# Runtime stats (filled from GameConfig in _ready)
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


enum AimMode { MOUSE, CONTROLLER }
var aim_mode: AimMode = AimMode.MOUSE

var aim_dir: Vector2 = Vector2.RIGHT

# one shared cursor for mouse + controller
var aim_cursor_pos: Vector2 = Vector2.ZERO
var last_mouse_pos: Vector2 = Vector2.ZERO


# --------------------------------------------------------------------
# READY
# --------------------------------------------------------------------

func _ready() -> void:
	# Pull config from global GameConfig (design values)
	max_ammo           = GameConfig.player_max_ammo
	speed              = GameConfig.player_move_speed
	max_health         = GameConfig.player_max_health
	fire_rate          = GameConfig.player_fire_rate
	knockback_strength = GameConfig.player_knockback_strength
	knockback_duration = GameConfig.player_knockback_duration
	invincible_time    = GameConfig.player_invincible_time

	# --- Sync with GameState (current run data) ---

	# If GameState hasn't been initialized yet (first load),
	# give it default values for this run.
	if GameState.max_health == 0:
		GameState.max_health = max_health
		GameState.health = max_health

	if GameState.max_ammo == 0:
		GameState.max_ammo = max_ammo
		GameState.ammo = max_ammo

	# Use the values from the current run
	health = GameState.health
	ammo = GameState.ammo

	# Init UI with current run values
	update_health_bar()
	
	update_ammo_bar()
	
	# Aim setup (same as before)
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	aim_cursor_pos = get_global_mouse_position()
	last_mouse_pos = get_viewport().get_mouse_position()



# --------------------------------------------------------------------
# PROCESS
# --------------------------------------------------------------------

func _process(_delta: float) -> void:
	coin_label.text = str(GameState.coins)
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
	if Input.is_action_pressed("shoot") and fire_timer <= 0.0:
		shoot()
		fire_timer = fire_rate

	# Alt fire (right mouse / shotgun)
	if Input.is_action_just_pressed("alt_fire") \
			and alt_fire_cooldown_timer <= 0.0 \
			and ammo > 0:
		fire_laser()
		alt_fire_cooldown_timer = GameConfig.alt_fire_cooldown


func add_ammo(amount: int) -> void:
	ammo = clampi(ammo + amount, 0, max_ammo)
	GameState.ammo = ammo          # 👈 keep GameState in sync
	



func fire_laser() -> void:
	# spend ammo
	ammo = max(ammo - 1, 0)
	GameState.ammo = ammo          # 👈 sync after we change it
	update_ammo_bar()


	# --- SHOTGUN / ALT FIRE SFX ---
	var shot := $SFX_Shoot_Shotgun

	# Main deep blast
	shot.pitch_scale = 0.7
	shot.play()

	# Extra layers for oomph
	for i in range(4):
		shot.pitch_scale = randf_range(0.35, 0.55)
		shot.play()

	var bullet_count: int = GameConfig.alt_fire_bullet_count
	var spread_degrees: float = GameConfig.alt_fire_spread_degrees
	var spread_radians: float = deg_to_rad(spread_degrees)

	var base_dir: Vector2 = aim_dir
	var start_index: float = -float(bullet_count - 1) / 2.0

	for i in range(bullet_count):
		var angle_offset: float = (start_index + float(i)) * spread_radians
		var dir: Vector2 = base_dir.rotated(angle_offset)

		var bullet := BulletScene.instantiate()
		bullet.global_position = muzzle.global_position
		bullet.direction = dir
		get_tree().current_scene.add_child(bullet)

	# recoil: push player opposite of shot direction
	var recoil_dir: Vector2 = -base_dir
	knockback = recoil_dir * GameConfig.alt_fire_recoil_strength
	knockback_timer = GameConfig.alt_fire_recoil_duration
	
	var cam := get_tree().get_first_node_in_group("camera")
	if cam and cam.has_method("shake"):
		cam.shake(GameConfig.knockback_shake_strength, GameConfig.knockback_shake_duration)


func shoot() -> void:
	$SFX_Shoot.play()

	var bullet := BulletScene.instantiate()
	bullet.global_position = muzzle.global_position

	var dir := aim_dir
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
	health = clampi(health - amount, 0, max_health)
	GameState.health = health              # 👈 sync run state here

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
		hp_fill.value = lerp(hp_fill.value, GameState.health, 0.2)

	hp_label.text = "%d/%d" % [GameState.health, GameState.max_health]

	if health_bar == null or health_sprites.is_empty():
		return

	var idx: int = clampi(health, 0, health_sprites.size() - 1)
	health_bar.texture = health_sprites[idx]


func update_ammo_bar() -> void:
	if ammo_bar == null or ammo_sprites.is_empty():
		return

	var idx: int = clampi(ammo, 0, ammo_sprites.size() - 1)
	ammo_bar.texture = ammo_sprites[idx]
