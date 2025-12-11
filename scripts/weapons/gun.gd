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

# -------------------------------------------------------------------
# AMMO SYSTEM (for all alt weapons, primary excluded)
# -------------------------------------------------------------------
var weapon_id: String = ""
var ammo: int = 0
var max_ammo: int = 0
var reload_delay: float = 0.0
var reload_rate: float = 8.0  # Rounds per second when reloading
var time_since_last_shot: float = 0.0
var ammo_mode: String = "clip"
var shots_per_bar: int = 0
var reload_timer: float = 0.0
var is_reloading: bool = false
var is_overheated: bool = false
var is_firing_flame: bool = false
var is_firing_burst: bool = false  # for burst/multishot lockout
func _ready() -> void:
	# Connect to weapon changes
	GameState.alt_weapon_changed.connect(_on_alt_weapon_changed)


func _input(event):
	if event.is_action_pressed("reload"):
		manual_reload()

# -------------------------------------------------------------------
# MANUAL RELOAD SYSTEM
# -------------------------------------------------------------------
func manual_reload() -> void:
	# Only reload if not already reloading, not firing burst/flame, and not full
	if is_reloading:
		return
	if is_firing_burst or is_firing_flame:
		return
	if ammo_mode == "clip":
		if ammo >= max_ammo:
			return
		start_reload()
	elif ammo_mode == "continuous":
		if ammo >= max_ammo:
			return
		ammo = max_ammo
		is_overheated = false
		is_reloading = false
		reload_timer = 0.0
		_notify_ui_fuel_changed()
		sprite.play("reload")


func _on_alt_weapon_changed(_new_weapon: int) -> void:
	"""Reinitialize ammo when weapon changes."""
func _hide_fuel_ui() -> void:
	"""Helper to hide fuel UI (called deferred)."""
	if not is_inside_tree():
		return
	var ui = get_tree().get_first_node_in_group("ui")
	if ui and ui.has_method("hide_alt_weapon_fuel"):
		ui.hide_alt_weapon_fuel()


func _notify_ui_fuel_changed() -> void:
	"""Tell UI to update ammo bar."""
	if not is_inside_tree():
		return
	var ui = get_tree().get_first_node_in_group("ui")
	if ui and ui.has_method("show_alt_weapon_fuel"):
		var is_continuous := (ammo_mode == "continuous")
		var shots_for_ui := max_ammo if ammo_mode == "clip" else 100
		ui.show_alt_weapon_fuel(weapon_id, float(max_ammo), float(ammo), shots_for_ui, is_continuous)


func can_fire_alt() -> bool:
	if ammo_mode == "clip":
		return ammo > 0 and not is_reloading
	elif ammo_mode == "continuous":
		return ammo > 0 and not is_overheated
	return false


func _update_ammo(delta: float) -> void:
	if weapon_id == "" or max_ammo <= 0:
		return
	if ammo_mode == "clip":
		_update_clip_ammo(delta)
	elif ammo_mode == "continuous":
		_update_continuous_ammo(delta)
	_notify_ui_fuel_changed()



func _update_clip_ammo(delta: float) -> void:
		# Always use gradual reload, even when empty
		if ammo <= 0 and not is_reloading:
			start_reload()
		# Auto-reload after 5 seconds if partially depleted
		if not is_reloading and ammo > 0 and ammo < max_ammo:
			time_since_last_shot += delta
			if time_since_last_shot >= 2.0:
				start_reload()
		# Gradual reload: add 1 ammo at a time based on reload_rate
		if is_reloading:
			reload_timer += delta
			var time_per_round: float = 1.0 / reload_rate
			if reload_timer >= time_per_round:
				ammo += 1
				reload_timer = 0.0
				if ammo >= max_ammo:
					ammo = max_ammo
					is_reloading = false
					time_since_last_shot = 0.0

func start_reload() -> void:
	if is_reloading:
		return
	is_reloading = true
	reload_timer = 0.0
	# Optional: play reload animation/sound here
	if sprite.has_method("play") and sprite.has_animation("reload"):
		sprite.play("reload")


func _update_continuous_ammo(delta: float) -> void:
	if is_firing_flame:
		pass
	else:
		var regen_rate: int = 20
		ammo += int(regen_rate * delta)
		if ammo >= max_ammo:
			ammo = max_ammo
		if is_overheated and ammo >= int(max_ammo * 0.25):
			is_overheated = false


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
	
	# Update ammo system
	_update_ammo(dt)


func add_ammo(_amount: int) -> void:
	# DEPRECATED - kept for compatibility, does nothing now
	pass


# --------------------------------------------------------------------
# PRIMARY FIRE
# --------------------------------------------------------------------

func handle_primary_fire(is_pressed: bool, aim_dir: Vector2) -> void:
	# 1) INPUT & CHAOS CHECKS
	if not is_pressed:
		return
	if GameState.primary_fire_disabled:
		return
	if not GameState.debug_laser_mode and fire_timer > 0.0:
		return

	# 2) DAMAGE & STEADY AIM
	var base_damage: float = GameConfig.bullet_base_damage
	var final_damage: float = base_damage * GameState.primary_damage_mult
	var player := get_tree().get_first_node_in_group("player")
	var velocity: Vector2 = Vector2.ZERO
	if player:
		if player.has_method("get_velocity"):
			velocity = player.get_velocity()
		elif "velocity" in player:
			velocity = player.velocity
	if velocity.length() < 0.1:
		final_damage *= GameState.primary_stationary_damage_mult

	# 3) CRIT SYSTEM (PRIMARY ONLY)
	if randf() < GameState.primary_crit_chance:
		final_damage *= GameState.primary_crit_mult

	# 4) PRIMARY BULLET SPAWN (no burst loop)
	var bullet = BulletScene_DEFAULT.instantiate()
	bullet.global_position = muzzle.global_position
	bullet.direction = aim_dir
	bullet.damage = roundi(final_damage)
	# Calculate bullet size multiplier from percent bonus
	var size_mult := 1.0 + (GameState.primary_bullet_size_bonus_percent / 100.0)
	bullet.scale = bullet.scale * Vector2(size_mult, size_mult)
	var base_speed := GameConfig.PRIMARY_BULLET_BASE_SPEED
	var final_speed := base_speed * GameState.primary_bullet_speed_mult
	bullet.speed = final_speed
	get_tree().current_scene.add_child(bullet)

	# If burst upgrade active, spawn second bullet slightly behind
	if GameState.has_burst_shot:
		var burst_bullet = BulletScene_DEFAULT.instantiate()
		burst_bullet.global_position = muzzle.global_position + (aim_dir * 15.0)
		burst_bullet.direction = aim_dir
		burst_bullet.damage = roundi(final_damage)
		burst_bullet.scale = burst_bullet.scale * Vector2(size_mult, size_mult)
		burst_bullet.speed = final_speed
		get_tree().current_scene.add_child(burst_bullet)

	# 6) FIRE RATE / COOLDOWN
	if GameState.debug_laser_mode:
		fire_timer = 0.0
		final_damage = 9999.0
	else:
		if GameState.fire_rate <= 0.0:
			GameState.fire_rate = GameConfig.player_fire_rate
		var fire_rate_multiplier := 1.0 + GameState.fire_rate_bonus_percent
		var cooldown = max(GameState.fire_rate / fire_rate_multiplier, 0.01)
		fire_timer = cooldown

	# 7) AUDIO
	if sfx_shoot:
		sfx_shoot.pitch_scale = 1.0
		sfx_shoot.play()


# --------------------------------------------------------------------
# ALT FIRE (SHOTGUN / SNIPER)
# --------------------------------------------------------------------

func handle_alt_fire(is_pressed: bool, aim_pos: Vector2) -> void:
	if not is_pressed:
		return

	var current_alt: int = GameState.alt_weapon

	if current_alt == GameState.AltWeaponType.NONE \
	or current_alt == GameState.AltWeaponType.TURRET:
		return

	if alt_fire_cooldown_timer > 0.0:
		return

	# Check fuel instead of ammo
	if not can_fire_alt() and not GameState.debug_infinite_ammo:
		if sfx_empty and empty_sound_cooldown <= 0.0:
			sfx_empty.play()
			empty_sound_cooldown = 0.5
		return

	var data: Dictionary = GameState.ALT_WEAPON_DATA.get(current_alt, {})
	if data.is_empty():
		return

	var base_cooldown: float = data.get("cooldown", 1.0)

	# Apply weapon-specific fire rate multipliers
	if current_alt == GameState.AltWeaponType.SHOTGUN:
		base_cooldown *= GameState.shotgun_fire_rate_mult
	elif current_alt == GameState.AltWeaponType.SNIPER:
		base_cooldown *= GameState.sniper_fire_rate_mult

	alt_fire_cooldown_timer = base_cooldown
	_fire_weapon(data, aim_pos, current_alt)


# --------------------------------------------------------------------
# GENERIC ALT FIRE (SHOTGUN / SNIPER / SHURIKEN)
# --------------------------------------------------------------------


func _fire_weapon(data: Dictionary, aim_pos: Vector2, weapon_type: int) -> void:
	# Block reload during burst/multishot
	is_firing_burst = true
	time_since_last_shot = 0.0
	# Consume ammo
	if not GameState.debug_infinite_ammo:
		ammo -= 1
		if ammo < 0:
			ammo = 0

	var bullet_scene: PackedScene = data["bullet_scene"]
	var bullet_speed: float = data["bullet_speed"]
	var pellets: int = data.get("pellets", 1)
	var spread_deg: float = data.get("spread_degrees", 0.0)
	var spread_rad: float = deg_to_rad(spread_deg)
	var damage: float = data.get("damage", 1.0)
	var recoil_strength: float = data.get("recoil", 0.0)
	var bounces: int = data.get("bounces", 0)
	var explosion_radius: float = data.get("explosion_radius", 0.0)

	# Apply weapon-specific multipliers
	if weapon_type == GameState.AltWeaponType.SHOTGUN:
		damage *= GameState.shotgun_damage_mult
	elif weapon_type == GameState.AltWeaponType.SNIPER:
		damage *= GameState.sniper_damage_mult

	var base_dir := (aim_pos - muzzle.global_position).normalized()
	var start_offset := -float(pellets - 1) / 2.0

	# Determine burst count for sniper
	var burst_count: int = 1
	if weapon_type == GameState.AltWeaponType.SNIPER:
		burst_count = GameState.sniper_burst_count

	# Fire burst shots
	for burst_idx in range(burst_count):
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
			
			# Apply shuriken chainshot upgrades
			if weapon_type == GameState.AltWeaponType.SHURIKEN:
				if "chain_count" in bullet:
					bullet.chain_count = int(GameState.shuriken_chain_count_mult - 1.0)
					bullet.chain_radius = 300.0 * GameState.shuriken_chain_radius_mult
					bullet.chain_speed_mult = GameState.shuriken_speed_chain_mult
					bullet.blade_split_chance = GameState.shuriken_blade_split_chance
			
			get_tree().current_scene.add_child(bullet)
		
		# Delay between burst shots (except last)
		if burst_idx < burst_count - 1:
			await get_tree().create_timer(0.05).timeout

	is_firing_burst = false

	# Play shoot sound with weapon-specific pitch
	if sfx_shoot:
		match weapon_type:
			GameState.AltWeaponType.SHOTGUN:
				sfx_shoot.pitch_scale = 0.85  # Slightly lower, punchier
				sfx_shoot.volume_db = 2.0     # Louder
			GameState.AltWeaponType.SNIPER:
				sfx_shoot.pitch_scale = 0.7   # Deep, powerful
				sfx_shoot.volume_db = 3.0     # Even louder
			GameState.AltWeaponType.SHURIKEN:
				sfx_shoot.pitch_scale = 1.4   # High pitched slice
				sfx_shoot.volume_db = -2.0    # Quieter, subtle
			_:
				sfx_shoot.pitch_scale = 1.0
				sfx_shoot.volume_db = 0.0
		sfx_shoot.play()

	emit_signal("recoil_requested", -base_dir, recoil_strength)
