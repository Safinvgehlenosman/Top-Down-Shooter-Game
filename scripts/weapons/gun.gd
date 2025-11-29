extends Node2D

const BulletScene_DEFAULT := preload("res://scenes/bullets/bullet.tscn")
const BulletScene_SHOTGUN := preload("res://scenes/bullets/shotgun_bullet.tscn")
const BulletScene_SNIPER  := preload("res://scenes/bullets/sniper_bullet.tscn")

@onready var sprite: Sprite2D = $Sprite2D
@onready var muzzle: Marker2D = $Muzzle
@onready var sfx_shoot: AudioStreamPlayer2D = $"../SFX_Shoot"
@onready var sfx_shotgun: AudioStreamPlayer2D = $"../SFX_Shoot_Shotgun"
@onready var sfx_empty: AudioStreamPlayer2D = $"../SFX_Empty"

signal recoil_requested(direction: Vector2, strength: float)

var fire_rate: float = 0.0
var fire_timer: float = 0.0
var alt_fire_cooldown_timer: float = 0.0
var empty_sound_cooldown: float = 0.0

var alt_weapon: int = GameState.AltWeaponType.NONE


func init_from_state() -> void:
	fire_rate = GameState.fire_rate
	print("[Gun] Initialized from GameState - fire_rate:", fire_rate)


func update_timers(delta: float) -> void:
	# Use raw delta - gun timers ignore slowmo/bullet time
	# (Players can shoot at full speed even during bullet time ability)
	var dt := delta

	if fire_timer > 0.0:
		fire_timer -= dt

	if alt_fire_cooldown_timer > 0.0:
		alt_fire_cooldown_timer -= dt
	
	if empty_sound_cooldown > 0.0:
		empty_sound_cooldown -= dt


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

	# 🔥 CALCULATE FINAL DAMAGE
	var base_damage: float = GameConfig.bullet_base_damage
	var damage_multiplier: float = GameState.primary_damage
	var final_damage: float = base_damage * damage_multiplier

	if GameState.debug_laser_mode:
		fire_timer = 0.0
		final_damage = 9999.0
	else:
		if GameState.fire_rate <= 0.0:
			GameState.fire_rate = GameConfig.player_fire_rate
		# Fire rate is a cooldown - divide by fire_rate_bonus to make it faster
		var fire_rate_multiplier = 1.0 + GameState.fire_rate_bonus_percent
		var cooldown = max(GameState.fire_rate / fire_rate_multiplier, 0.01)
		fire_timer = cooldown

	# Burst logic – number of bullets per shot
	var burst = max(1, GameState.primary_burst_count)
	var spread_deg := 6.0
	var spread_rad := deg_to_rad(spread_deg)
	var start_offset := -float(burst - 1) / 2.0

	print("[Gun] Firing - Base:", base_damage, "x Multiplier:", damage_multiplier, "= Final:", final_damage, "| Burst:", burst, "| Fire Rate:", GameState.fire_rate)

	for i in range(burst):
		var angle := (start_offset + i) * spread_rad
		var dir := aim_dir.rotated(angle)

		var bullet := BulletScene_DEFAULT.instantiate()
		bullet.global_position = muzzle.global_position
		bullet.direction = dir
		bullet.damage = int(final_damage)
		var m := float(GameState.primary_bullet_size_multiplier)
		bullet.scale = bullet.scale * Vector2(m, m)
		get_tree().current_scene.add_child(bullet)

	if sfx_shoot:
		sfx_shoot.pitch_scale = 1.0  # Normal pitch for primary
		sfx_shoot.play()


# --------------------------------------------------------------------
# ALT FIRE (SHOTGUN / SNIPER / FLAMETHROWER)
# --------------------------------------------------------------------

func handle_alt_fire(is_pressed: bool, aim_pos: Vector2) -> void:
	if not is_pressed:
		return

	var current_alt: int = GameState.alt_weapon

	if current_alt == GameState.AltWeaponType.NONE \
	or current_alt == GameState.AltWeaponType.TURRET:
		return

	if current_alt == GameState.AltWeaponType.FLAMETHROWER:
		_handle_flamethrower_fire(aim_pos)
		return

	if alt_fire_cooldown_timer > 0.0:
		return

	if GameState.ammo <= 0 and not GameState.debug_infinite_ammo:
		if sfx_empty and empty_sound_cooldown <= 0.0:
			sfx_empty.play()
			empty_sound_cooldown = 0.5
		return

	var data: Dictionary = GameState.ALT_WEAPON_DATA.get(current_alt, {})
	if data.is_empty():
		return

	alt_fire_cooldown_timer = data.get("cooldown", 1.0)
	_fire_weapon(data, aim_pos, current_alt)


# --------------------------------------------------------------------
# FLAMETHROWER LOGIC
# --------------------------------------------------------------------

func _handle_flamethrower_fire(aim_pos: Vector2) -> void:
	if GameState.ammo <= 0 and not GameState.debug_infinite_ammo:
		if sfx_empty and empty_sound_cooldown <= 0.0:
			sfx_empty.play()
			empty_sound_cooldown = 0.5
		return

	var data: Dictionary = GameState.ALT_WEAPON_DATA.get(GameState.AltWeaponType.FLAMETHROWER, {})
	if data.is_empty():
		return

	var bullet_scene: PackedScene = data["bullet_scene"]
	var _bullet_speed: float = data.get("bullet_speed", 50.0)

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
		var spawn_pos := muzzle.global_position + dir * 12.0
		bullet.global_position = spawn_pos
		bullet.direction = dir

		if "target_group" in bullet:
			bullet.target_group = "enemy"

		if "burn_damage_per_tick" in bullet:
			bullet.burn_damage_per_tick = damage

		if "lifetime" in bullet:
			bullet.lifetime = base_lifetime * randf_range(0.75, 1.15)

		get_tree().current_scene.add_child(bullet)

	if not GameState.debug_infinite_ammo:
		var new_ammo = max(GameState.ammo - ammo_cost, 0)
		GameState.set_ammo(new_ammo)

	# Flamethrower: higher pitch, quieter (it shoots often)
	if sfx_shoot:
		sfx_shoot.pitch_scale = randf_range(1.3, 1.5)  # High pitched spitting sound
		sfx_shoot.volume_db = -8.0  # Quieter to not be overwhelming
		sfx_shoot.play()

	emit_signal("recoil_requested", -base_dir, recoil_strength)


# --------------------------------------------------------------------
# GENERIC ALT FIRE (SHOTGUN / SNIPER / GRENADE / SHURIKEN)
# --------------------------------------------------------------------

func _fire_weapon(data: Dictionary, aim_pos: Vector2, weapon_type: int) -> void:
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
		bullet.speed = float(bullet_speed) * 0.5
		bullet.damage = damage
		if "bounces_left" in bullet:
			bullet.bounces_left = bounces
		if "explosion_radius" in bullet:
			bullet.explosion_radius = explosion_radius
		get_tree().current_scene.add_child(bullet)

	# Play shoot sound with weapon-specific pitch
	if sfx_shoot:
		match weapon_type:
			GameState.AltWeaponType.SHOTGUN:
				sfx_shoot.pitch_scale = 0.85  # Slightly lower, punchier
				sfx_shoot.volume_db = 2.0     # Louder
			
			GameState.AltWeaponType.SNIPER:
				sfx_shoot.pitch_scale = 0.7   # Deep, powerful
				sfx_shoot.volume_db = 3.0     # Even louder
			
			GameState.AltWeaponType.GRENADE:
				sfx_shoot.pitch_scale = 0.6   # Deep bass thump
				sfx_shoot.volume_db = 1.0
			
			GameState.AltWeaponType.SHURIKEN:
				sfx_shoot.pitch_scale = 1.4   # High pitched slice
				sfx_shoot.volume_db = -2.0    # Quieter, subtle
			
			_:
				sfx_shoot.pitch_scale = 1.0
				sfx_shoot.volume_db = 0.0
		
		sfx_shoot.play()

	emit_signal("recoil_requested", -base_dir, recoil_strength)