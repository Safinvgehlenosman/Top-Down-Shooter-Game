extends CharacterBody2D

const BulletScene := preload("res://scenes/bullet.tscn")

# UI
@export var health_bar_path: NodePath
@export var health_sprites: Array[Texture2D] = []

@export var ammo_bar_path: NodePath
@export var ammo_sprites: Array[Texture2D] = []

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
var coins: int = 0
var fire_timer: float = 0.0

# Knockback
var knockback: Vector2 = Vector2.ZERO
var knockback_timer: float = 0.0

# Invincibility
var invincible_timer: float = 0.0

var is_dead: bool = false


func _ready() -> void:
	# Pull config from global GameConfig
	max_ammo           = GameConfig.player_max_ammo
	speed              = GameConfig.player_move_speed
	max_health         = GameConfig.player_max_health
	fire_rate          = GameConfig.player_fire_rate
	knockback_strength = GameConfig.player_knockback_strength
	knockback_duration = GameConfig.player_knockback_duration
	invincible_time    = GameConfig.player_invincible_time

	# Init health & UI
	health = max_health
	health_bar = get_node(health_bar_path)
	update_health_bar()
	
	ammo = max_ammo
	ammo_bar = get_node(ammo_bar_path)
	update_ammo_bar()


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	_update_timers(delta)
	_process_movement(delta)
	_process_aim()
	_process_shooting(delta)


# --- TIMERS ---------------------------------------------------------

func _update_timers(delta: float) -> void:
	if invincible_timer > 0.0:
		invincible_timer -= delta

	if knockback_timer > 0.0:
		knockback_timer -= delta
	else:
		knockback = Vector2.ZERO
	
	if alt_fire_cooldown_timer > 0.0:
		alt_fire_cooldown_timer -= delta


# --- MOVEMENT & AIM -------------------------------------------------

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


func _process_aim() -> void:
	var mouse_pos := get_global_mouse_position()
	if mouse_pos.x > global_position.x:
		animated_sprite.flip_h = false
	elif mouse_pos.x < global_position.x:
		animated_sprite.flip_h = true


# --- SHOOTING -------------------------------------------------------

func _process_shooting(delta: float) -> void:
	fire_timer -= delta
	if Input.is_action_pressed("shoot") and fire_timer <= 0.0:
		shoot()
		fire_timer = fire_rate

	# Alt fire (right mouse / shotgun)
	if Input.is_action_just_pressed("alt_fire") \
			and alt_fire_cooldown_timer <= 0.0 \
			and ammo > 0:                      # 👈 need ammo
		fire_laser()
		alt_fire_cooldown_timer = GameConfig.alt_fire_cooldown

func add_ammo(amount: int) -> void:
	ammo = clampi(ammo + amount, 0, max_ammo)
	update_ammo_bar()
	print("Ammo:", ammo)


func fire_laser() -> void:
	# spend ammo
	ammo = max(ammo - 1, 0)
	update_ammo_bar()

# --- SHOTGUN / ALT FIRE SFX ---
	var shot := $SFX_Shoot_Shotgun

# Main deep blast
	shot.pitch_scale = 0.7
	shot.play()

# Extra layers for oomph (optional but feels great)
	for i in range(2):
		shot.pitch_scale = randf_range(0.35, 0.55)
		shot.play()



	

	var bullet_count: int = GameConfig.alt_fire_bullet_count
	var spread_degrees: float = GameConfig.alt_fire_spread_degrees
	var spread_radians: float = deg_to_rad(spread_degrees)

	var base_dir: Vector2 = (get_global_mouse_position() - muzzle.global_position).normalized()
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

	var dir := (get_global_mouse_position() - muzzle.global_position).normalized()
	bullet.direction = dir

	# bullet damage & speed are now configured on Bullet itself via GameConfig
	get_tree().current_scene.add_child(bullet)


# --- FEEDBACK (HIT / HEAL) -----------------------------------------

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


# --- HEALTH & DAMAGE -----------------------------------------------

func take_damage(amount: int) -> void:
	if is_dead:
		return
	if amount == 0:
		return

	# DAMAGE (amount > 0)
	if amount > 0:
		# Only block with i-frames on real damage
		if invincible_timer > 0.0:
			return
		invincible_timer = invincible_time

		# Audio + visual feedback
		$SFX_Hurt.play()
		_play_hit_feedback()

	# HEAL (amount < 0)
	elif amount < 0:
		_play_heal_feedback()

	# Update health (damage = minus, heal = plus because amount can be negative)
	health = clampi(health - amount, 0, max_health)
	print("Player health =", health)

	update_health_bar()

	# Only trigger death from real damage
	if amount > 0 and health <= 0:
		die()


func add_coin() -> void:
	coins += 1
	print("Coins:", coins)
	# hook for future UI update (coins bar / shop etc.)


func apply_knockback(from_position: Vector2) -> void:
	var dir := (global_position - from_position).normalized()
	knockback = dir * knockback_strength
	knockback_timer = knockback_duration   # start knockback window


func die() -> void:
	is_dead = true
	print("Player died")

	# Disable gun logic so it stops rotating/aiming
	if has_node("Gun"):
		var gun = $Gun
		gun.process_mode = Node.PROCESS_MODE_DISABLED

	# If you have a separate crosshair scene in a group, hide it too
	var crosshair := get_tree().get_first_node_in_group("crosshair")
	if crosshair:
		crosshair.visible = false
		# optionally:
		# crosshair.process_mode = Node.PROCESS_MODE_DISABLED

	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm and gm.has_method("on_player_died"):
		gm.on_player_died()




func update_health_bar() -> void:
	if health_bar == null or health_sprites.is_empty():
		return

	var idx: int = clampi(health, 0, health_sprites.size() - 1)
	health_bar.texture = health_sprites[idx]

func update_ammo_bar() -> void:
	if ammo_bar == null or ammo_sprites.is_empty():
		return

	var idx: int = clampi(ammo, 0, ammo_sprites.size() - 1)
	ammo_bar.texture = ammo_sprites[idx]
