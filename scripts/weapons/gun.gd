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
# FUEL SYSTEM (for all alt weapons, primary excluded)
# -------------------------------------------------------------------
var weapon_id: String = ""
var fuel: float = 0.0
var max_fuel: float = 0.0
var fuel_reload_rate: float = 0.0
var fuel_reload_delay: float = 0.0
var fuel_drain_per_shot: float = 1.0
var fuel_drain_per_second: float = 0.0  # for flamethrower
var fuel_regen_per_second: float = 0.0  # for flamethrower
var fuel_mode: String = "clip"          # "clip" or "continuous"
var shots_per_bar: int = 0              # for UI display (clip mode)
var reload_timer: float = 0.0
var is_reloading: bool = false
var is_overheated: bool = false  # for flamethrower
var is_firing_flame: bool = false  # track flamethrower firing state


func _ready() -> void:
	# Connect to weapon changes
	GameState.alt_weapon_changed.connect(_on_alt_weapon_changed)
	_initialize_fuel_for_weapon()


func _on_alt_weapon_changed(_new_weapon: int) -> void:
	"""Reinitialize fuel when weapon changes."""
	_initialize_fuel_for_weapon()


func init_from_state() -> void:
	fire_rate = GameState.fire_rate
	_initialize_fuel_for_weapon()


func _initialize_fuel_for_weapon() -> void:
	"""Initialize fuel system based on current alt weapon."""
	var current_alt: int = GameState.alt_weapon
	
	# Hide UI for NONE or TURRET
	if current_alt == GameState.AltWeaponType.NONE or current_alt == GameState.AltWeaponType.TURRET:
		weapon_id = ""
		fuel = 0.0
		max_fuel = 0.0
		# Hide fuel bar (deferred to ensure UI exists)
		call_deferred("_hide_fuel_ui")
		return
	
	var data: Dictionary = GameState.ALT_WEAPON_DATA.get(current_alt, {})
	weapon_id = data.get("id", "")
	
	if weapon_id == "" or not GameConfig.WEAPON_FUEL_CONFIG.has(weapon_id):
		fuel = 0.0
		max_fuel = 0.0
		# Hide fuel bar (deferred to ensure UI exists)
		call_deferred("_hide_fuel_ui")
		return
	
	var config: Dictionary = GameConfig.WEAPON_FUEL_CONFIG[weapon_id]
	fuel_mode = config.get("mode", "clip")
	max_fuel = config.get("max_fuel", 10.0)
	fuel_reload_delay = config.get("reload_delay", 0.5)
	
	if fuel_mode == "clip":
		fuel_reload_rate = config.get("reload_rate", 5.0)
		shots_per_bar = config.get("shots_per_bar", 10)
		fuel_drain_per_shot = max_fuel / float(shots_per_bar)
		fuel = max_fuel  # Start with full fuel
		is_reloading = false
		reload_timer = 0.0
	elif fuel_mode == "continuous":
		shots_per_bar = 0  # Not used for continuous mode
		fuel_drain_per_second = config.get("drain_per_second", 25.0)
		fuel_regen_per_second = config.get("regen_per_second", 20.0)
		fuel = max_fuel  # Start with full fuel
		is_overheated = false
	
	# Notify UI
	_notify_ui_fuel_changed()


func _hide_fuel_ui() -> void:
	"""Helper to hide fuel UI (called deferred)."""
	if not is_inside_tree():
		return
	var ui = get_tree().get_first_node_in_group("ui")
	if ui and ui.has_method("hide_alt_weapon_fuel"):
		ui.hide_alt_weapon_fuel()


func _notify_ui_fuel_changed() -> void:
	"""Tell UI to update fuel bar."""
	if not is_inside_tree():
		return
	var ui = get_tree().get_first_node_in_group("ui")
	if ui and ui.has_method("show_alt_weapon_fuel"):
		var is_continuous := (fuel_mode == "continuous")
		ui.show_alt_weapon_fuel(weapon_id, max_fuel, fuel, shots_per_bar, is_continuous)


func can_fire_alt() -> bool:
	"""Check if alt weapon has enough fuel to fire."""
	if fuel_mode == "clip":
		return fuel >= fuel_drain_per_shot and not is_reloading
	elif fuel_mode == "continuous":
		return fuel > 0.0 and not is_overheated
	return false


func _update_fuel(delta: float) -> void:
	"""Update fuel regeneration/reload logic."""
	if weapon_id == "" or max_fuel <= 0.0:
		return
	
	if fuel_mode == "clip":
		_update_clip_fuel(delta)
	elif fuel_mode == "continuous":
		_update_continuous_fuel(delta)
	
	# Notify UI every frame
	var ui = get_tree().get_first_node_in_group("ui")
	if ui and ui.has_method("update_alt_weapon_fuel"):
		ui.update_alt_weapon_fuel(fuel)


func _update_clip_fuel(delta: float) -> void:
	"""Reload logic for clip-based weapons."""
	if fuel <= 0.0:
		is_reloading = true
	
	if is_reloading:
		reload_timer += delta
		if reload_timer >= fuel_reload_delay:
			fuel += fuel_reload_rate * delta
			if fuel >= max_fuel:
				fuel = max_fuel
				is_reloading = false
				reload_timer = 0.0


func _update_continuous_fuel(delta: float) -> void:
	"""Regen logic for continuous weapons (flamethrower)."""
	if is_firing_flame:
		# Fuel is drained in handle_alt_fire for flamethrower
		pass
	else:
		# Regenerate when not firing
		fuel += fuel_regen_per_second * delta
		if fuel >= max_fuel:
			fuel = max_fuel
		# Clear overheat when fuel regenerates enough
		if is_overheated and fuel >= max_fuel * 0.25:
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
	
	# Update fuel system
	_update_fuel(dt)


func add_ammo(_amount: int) -> void:
	# DEPRECATED - kept for compatibility, does nothing now
	pass


# --------------------------------------------------------------------
# PRIMARY FIRE
# --------------------------------------------------------------------

func handle_primary_fire(is_pressed: bool, aim_dir: Vector2) -> void:
	if not is_pressed:
		return
	
	# ⬅0 Check if primary fire is disabled by chaos challenge
	if GameState.primary_fire_disabled:
		# Debug: Only print occasionally to avoid spam
		if Engine.get_process_frames() % 60 == 0:
			pass

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

	for i in range(burst):
		var angle := (start_offset + i) * spread_rad
		var dir := aim_dir.rotated(angle)

		var bullet := BulletScene_DEFAULT.instantiate()
		bullet.global_position = muzzle.global_position
		bullet.direction = dir
		bullet.damage = roundi(final_damage)  # Round instead of truncate
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
		is_firing_flame = false  # Release flamethrower
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

	# Check fuel instead of ammo
	if not can_fire_alt() and not GameState.debug_infinite_ammo:
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
	# Check fuel for continuous mode
	if not can_fire_alt() and not GameState.debug_infinite_ammo:
		is_firing_flame = false
		if sfx_empty and empty_sound_cooldown <= 0.0:
			sfx_empty.play()
			empty_sound_cooldown = 0.5
		return
	
	is_firing_flame = true  # Mark as firing

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

	# Drain fuel for continuous mode
	if not GameState.debug_infinite_ammo:
		var drain = fuel_drain_per_second * get_process_delta_time()
		fuel -= drain
		if fuel <= 0.0:
			fuel = 0.0
			is_overheated = true
			is_firing_flame = false

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
	# Consume fuel instead of ammo
	if not GameState.debug_infinite_ammo:
		fuel -= fuel_drain_per_shot
		if fuel < 0.0:
			fuel = 0.0

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
		
		# Apply shuriken chainshot upgrades
		if weapon_type == GameState.AltWeaponType.SHURIKEN:
			if "chain_count" in bullet:
				bullet.chain_count = int(GameState.shuriken_chain_count_mult - 1.0)
				bullet.chain_radius = 300.0 * GameState.shuriken_chain_radius_mult
				bullet.chain_speed_mult = GameState.shuriken_speed_chain_mult
				bullet.blade_split_chance = GameState.shuriken_blade_split_chance
		
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
