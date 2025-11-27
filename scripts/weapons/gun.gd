extends Node2D

const BulletScene_DEFAULT := preload("res://scenes/bullets/bullet.tscn")
const BulletScene_SHOTGUN := preload("res://scenes/bullets/shotgun_bullet.tscn")
const BulletScene_SNIPER  := preload("res://scenes/bullets/sniper_bullet.tscn")

@onready var sprite: Sprite2D = $Sprite2D
@onready var muzzle: Marker2D = $Muzzle
@onready var sfx_shoot: AudioStreamPlayer2D = $"../SFX_Shoot"
@onready var sfx_shotgun: AudioStreamPlayer2D = $"../SFX_Shoot_Shotgun"

signal recoil_requested(direction: Vector2, strength: float)

var fire_rate: float = 0.0
var fire_timer: float = 0.0
var alt_fire_cooldown_timer: float = 0.0

const AltWeaponType = GameState.ALT_WEAPON_NONE


func init_from_state() -> void:
	fire_rate = GameState.fire_rate


func update_timers(delta: float) -> void:
	var dt := delta
	if Engine.time_scale > 0.0:
		dt = delta / Engine.time_scale

	if fire_timer > 0.0:
		fire_timer -= dt

	if alt_fire_cooldown_timer > 0.0:
		alt_fire_cooldown_timer -= dt


func add_ammo(amount: int) -> void:
	GameState.set_ammo(GameState.ammo + amount)


# --------------------------------------------------------------------
# PRIMARY FIRE
# --------------------------------------------------------------------

func handle_primary_fire(is_pressed: bool, aim_dir: Vector2) -> void:
	if not is_pressed:
		return

	if not GameState.debug_laser_mode and fire_timer > 0.0:
		return

	var damage: float = GameState.primary_damage

	if GameState.debug_laser_mode:
		fire_timer = 0.0
		damage = 9999.0
	else:
		if GameState.fire_rate <= 0.0:
			GameState.fire_rate = GameConfig.player_fire_rate
		var cooldown = max(GameState.fire_rate, 0.01)
		fire_timer = cooldown

	# Burst logic – number of bullets per shot
	var burst = max(1, GameState.primary_burst_count)
	var spread_deg := 6.0
	var spread_rad := deg_to_rad(spread_deg)
	var start_offset := -float(burst - 1) / 2.0

	for i in range(burst):
		var angle := (start_offset + i) * spread_rad
		var dir := aim_dir.rotated(angle)

		var bullet := BulletScene_DEFAULT.instantiate()
		bullet.global_position = muzzle.global_position
		bullet.direction = dir
		bullet.damage = damage
		get_tree().current_scene.add_child(bullet)

	if sfx_shoot:
		sfx_shoot.play()


# --------------------------------------------------------------------
# ALT FIRE (SHOTGUN / SNIPER / FLAMETHROWER)
# --------------------------------------------------------------------

func handle_alt_fire(is_pressed: bool, aim_pos: Vector2) -> void:
	if not is_pressed:
		return

	var alt_weapon := GameState.alt_weapon

	if alt_weapon == GameState.ALT_WEAPON_NONE or alt_weapon == GameState.ALT_WEAPON_TURRET:
		return

	if alt_weapon == GameState.ALT_WEAPON_FLAMETHROWER:
		_handle_flamethrower_fire(aim_pos)
		return

	if alt_fire_cooldown_timer > 0.0:
		return

	if GameState.ammo <= 0 and not GameState.debug_infinite_ammo:
		return

	var data: Dictionary = GameState.ALT_WEAPON_DATA.get(alt_weapon, {})
	if data.is_empty():
		return

	alt_fire_cooldown_timer = data.get("cooldown", 1.0)
	_fire_weapon(data, aim_pos)


# --------------------------------------------------------------------
# FLAMETHROWER LOGIC
# --------------------------------------------------------------------

func _handle_flamethrower_fire(aim_pos: Vector2) -> void:
	if GameState.ammo <= 0 and not GameState.debug_infinite_ammo:
		return

	var data: Dictionary = GameState.ALT_WEAPON_DATA.get(GameState.ALT_WEAPON_FLAMETHROWER, {})
	if data.is_empty():
		return

	var bullet_scene: PackedScene = data["bullet_scene"]
	var bullet_speed: float = data.get("bullet_speed", 50.0)

	var spread_deg: float = data.get("spread_degrees", 35.0)
	var spread_rad: float = deg_to_rad(spread_deg)
	var pellets: int = data.get("pellets", 3)

	var damage: float = data.get("damage", 0.0)
	var recoil_strength: float = data.get("recoil", 0.0)
	var ammo_cost: int = data.get("ammo_cost", 1)
	var base_lifetime: float = data.get("flame_lifetime", 0.35)

	var base_dir := (aim_pos - muzzle.global_position).normalized()

	for i in range(pellets):
		var angle := randf_range(-spread_rad, spread_rad)
		var dir := base_dir.rotated(angle)

		var bullet = bullet_scene.instantiate()
		bullet.global_position = muzzle.global_position
		bullet.direction = dir
		bullet.speed = bullet_speed
		bullet.damage = damage

		if "lifetime" in bullet:
			bullet.lifetime = base_lifetime * randf_range(0.75, 1.15)

		get_tree().current_scene.add_child(bullet)

	if not GameState.debug_infinite_ammo:
		var new_ammo = max(GameState.ammo - ammo_cost, 0)
		GameState.set_ammo(new_ammo)

	emit_signal("recoil_requested", -base_dir, recoil_strength)


# --------------------------------------------------------------------
# GENERIC ALT FIRE (SHOTGUN / SNIPER / ETC.)
# --------------------------------------------------------------------

func _fire_weapon(data: Dictionary, aim_pos: Vector2) -> void:
	var ammo_cost: int = data.get("ammo_cost", 1)

	var new_ammo := GameState.ammo
	if not GameState.debug_infinite_ammo:
		new_ammo = max(GameState.ammo - ammo_cost, 0)
	GameState.set_ammo(new_ammo)

	var bullet_scene: PackedScene = data["bullet_scene"]
	var bullet_speed: float = data["bullet_speed"]
	var pellets: int = data.get("pellets", 1)
	var spread_deg: float = data.get("spread_degrees", 0.0)
	var spread_rad: float = deg_to_rad(spread_deg)
	var damage: float = data.get("damage", 1.0)
	var recoil_strength: float = data.get("recoil", 0.0)
	var bounces: int = data.get("bounces", 0)
	var explosion_radius: float = data.get("explosion_radius", 0.0)

	var base_dir := (aim_pos - muzzle.global_position).normalized()
	var start_offset := -float(pellets - 1) / 2.0

	for i in range(pellets):
		var angle := (start_offset + i) * spread_rad
		var dir := base_dir.rotated(angle)

		var bullet = bullet_scene.instantiate()
		bullet.global_position = muzzle.global_position
		bullet.direction = dir
		bullet.speed = bullet_speed
		bullet.damage = damage
		if "bounces_left" in bullet:
			bullet.bounces_left = bounces
		if "explosion_radius" in bullet:
			bullet.explosion_radius = explosion_radius
		get_tree().current_scene.add_child(bullet)

	emit_signal("recoil_requested", -base_dir, recoil_strength)
