extends Node2D

const BulletScene_DEFAULT := preload("res://scenes/bullets/bullet.tscn")
const BulletScene_SHOTGUN := preload("res://scenes/bullets/shotgun_bullet.tscn")
const BulletScene_SNIPER  := preload("res://scenes/bullets/sniper_bullet.tscn")

@onready var sprite: Sprite2D = $Sprite2D
@onready var muzzle: Marker2D = $Muzzle
@onready var sfx_shoot: AudioStreamPlayer2D = $"../SFX_Shoot"
@onready var sfx_shotgun: AudioStreamPlayer2D = $"../SFX_Shoot_Shotgun"

signal recoil_requested(direction: Vector2, strength: float)

# basic weapon stats (copied from GameState)
var fire_rate: float = 0.0
var fire_timer: float = 0.0
var alt_fire_cooldown_timer: float = 0.0
# local enum so this script knows the alt-weapon type
const AltWeaponType = GameState.AltWeaponType


func init_from_state() -> void:
	fire_rate = GameState.fire_rate


func update_timers(delta: float) -> void:
	if fire_timer > 0.0:
		fire_timer -= delta
	if alt_fire_cooldown_timer > 0.0:
		alt_fire_cooldown_timer -= delta

func add_ammo(amount: int) -> void:
	GameState.set_ammo(GameState.ammo + amount)


# --------------------------------------------------------------------
# PRIMARY FIRE
# --------------------------------------------------------------------

func handle_primary_fire(is_pressed: bool, aim_dir: Vector2) -> void:
	if not is_pressed:
		return
	if fire_timer > 0.0:
		return

	# If weapon has a magazine (max_ammo > 0), require ammo.
	# If max_ammo == 0, primary fire is "infinite ammo".
	if GameState.max_ammo > 0 and GameState.ammo <= 0:
		return

	# reset fire timer (shots per second)
	fire_timer = 0.0 / max(fire_rate, 0.01)

	var bullet := BulletScene_DEFAULT.instantiate()
	bullet.global_position = muzzle.global_position
	bullet.direction = aim_dir
	get_tree().current_scene.add_child(bullet)

	if GameState.max_ammo > 0:
		GameState.set_ammo(GameState.ammo - 1)

	if sfx_shoot:
		sfx_shoot.play()




# --------------------------------------------------------------------
# ALT FIRE (SHOTGUN / SNIPER)
# --------------------------------------------------------------------

func handle_alt_fire(is_pressed: bool, aim_pos: Vector2) -> void:
	if not is_pressed:
		return

	# Always read current weapon from GameState
	var alt_weapon := GameState.alt_weapon

	# no alt weapon / turret handled elsewhere
	print("Alt weapon is:", alt_weapon)
	if alt_weapon == GameState.AltWeaponType.NONE or alt_weapon == GameState.AltWeaponType.TURRET:
		print("No weapon connected")
		return

	if alt_fire_cooldown_timer > 0.0:
		return
	if GameState.ammo <= 0:
		return

	var data: Dictionary = GameState.ALT_WEAPON_DATA.get(alt_weapon, {})
	if data.is_empty():
		return

	alt_fire_cooldown_timer = data.get("cooldown", 1.0)
	_fire_weapon(data, aim_pos)



func _fire_weapon(data: Dictionary, aim_pos: Vector2) -> void:
	# How much ammo this alt shot should cost (defaults to 1)
	var ammo_cost: int = data.get("ammo_cost", 1)

	var new_ammo = max(GameState.ammo - ammo_cost, 0)
	GameState.set_ammo(new_ammo)


	# settings
	var bullet_scene: PackedScene = data["bullet_scene"]
	var bullet_speed: float = data["bullet_speed"]
	var pellets: int = data.get("pellets", 1)
	var spread_deg: float = data.get("spread_degrees", 0.0)
	var spread_rad: float = deg_to_rad(spread_deg)
	var damage: float = data.get("damage", 1.0)
	var recoil_strength: float = data.get("recoil", 0.0)

	# BASE DIRECTION
	var base_dir := (aim_pos - muzzle.global_position).normalized()
	var start_offset := -float(pellets - 1) / 2.0

	# FIRE MULTIPLE PELLETS, NO EXTRA AMMO COST
	for i in range(pellets):
		var angle := (start_offset + i) * spread_rad
		var dir := base_dir.rotated(angle)

		var bullet = bullet_scene.instantiate()
		bullet.global_position = muzzle.global_position
		bullet.direction = dir
		bullet.speed = bullet_speed
		bullet.damage = damage
		get_tree().current_scene.add_child(bullet)

	# recoil
	emit_signal("recoil_requested", -base_dir, recoil_strength)


	var cam := get_tree().get_first_node_in_group("camera")
	if cam and cam.has_method("shake"):
		cam.shake(GameConfig.knockback_shake_strength, GameConfig.knockback_shake_duration)
