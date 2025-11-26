extends Node2D


enum AltWeaponType { NONE, SHOTGUN, SNIPER, TURRET }

var debug_god_mode: bool = false
var debug_infinite_ammo: bool = false
var debug_noclip: bool = false
var debug_laser_mode: bool = false
var player_invisible: bool = false


# --- ALT WEAPONS -------------------------------------------------------

const ALT_WEAPON_NONE := 0
const ALT_WEAPON_SHOTGUN := 1
const ALT_WEAPON_SNIPER := 2
const ALT_WEAPON_TURRET := 3
const ALT_WEAPON_FLAMETHROWER := 4
const ALT_WEAPON_SHURIKEN := 5
const ALT_WEAPON_GRENADE := 6

# Base, never modified
const ALT_WEAPON_BASE_DATA := {
	ALT_WEAPON_SHOTGUN: {
		"max_ammo": 6,
		"pickup_amount": 2,
		"cooldown": 0.7,
		"spread_degrees": 15.0,
		"pellets": 4,
		"bullet_scene": preload("res://scenes/bullets/shotgun_bullet.tscn"),
		"bullet_speed": 400.0,
		"recoil": 200.0,
		"damage": 10.0,   # ⬅ was 1.0
		"ammo_cost": 1,
	},
	ALT_WEAPON_SNIPER: {
		"max_ammo": 4,
		"pickup_amount": 1,
		"cooldown": 1.2,
		"spread_degrees": 0.0,
		"pellets": 1,
		"bullet_scene": preload("res://scenes/bullets/sniper_bullet.tscn"),
		"bullet_speed": 600.0,
		"recoil": 80.0,
		"damage": 20.0,   # ⬅ was 2.0
		"ammo_cost": 1,
	},
	ALT_WEAPON_TURRET: {
		"fire_interval": 0.8,
		"range": 400.0,
		"spread_degrees": 20.0,
		"bullet_scene": preload("res://scenes/bullets/turret_bullet.tscn"),
		"bullet_speed": 100.0,
		"damage": 10.0,   # ⬅ was 1.0
	},
	ALT_WEAPON_FLAMETHROWER: {
		"max_ammo": 100,          # fuel tank size
		"pickup_amount": 10,      # ammo per pickup
		"cooldown": 0.01,          # we handle “per frame” fire in Gun
		"spread_degrees": 35.0,
		"pellets": 1,
		"bullet_scene": preload("res://scenes/bullets/flamethrower_bullet.tscn"),
		"bullet_speed": 50.0,    # ⬅️ higher = longer range (was lower)
		"recoil": 0.0,
		"damage": 0,              # direct hit
		"ammo_cost": 1,
		"burn_damage": 10,        # DoT per tick (after the x10 change)
		"burn_duration": 1.5,
		"burn_interval": 0.3,
	},
		ALT_WEAPON_SHURIKEN: {
		"max_ammo": 8,
		"pickup_amount": 3,
		"cooldown": 0.5,   # seconds between throws
		"spread_degrees": 0.0,
		"pellets": 1,
		"bullet_scene": preload("res://scenes/bullets/shuriken_bullet.tscn"),
		"bullet_speed": 500.0,
		"recoil": 60.0,
		"damage": 10.0,
		"ammo_cost": 1,
		# 👇 our custom field used for bouncing
		"bounces": 2,      # base: 1 bounce
	},
		ALT_WEAPON_GRENADE: {
		"max_ammo": 4,
		"pickup_amount": 1,
		"cooldown": 0.9,
		"spread_degrees": 0.0,
		"pellets": 1,
		"bullet_scene": preload("res://scenes/bullets/grenade_bullet.tscn"),
		"bullet_speed": 260.0,
		"recoil": 220.0,
		"damage": 50.0,
		"ammo_cost": 1,
		"explosion_radius": 60.0,   # 👈 upgrade will buff this
	},



}

# Mutable runtime copy – THIS is what upgrades modify
var ALT_WEAPON_DATA: Dictionary = {}

var alt_weapon: int = ALT_WEAPON_NONE

# --- ACTIVE ABILITY ----------------------------------------------------

const ABILITY_NONE := 0
const ABILITY_DASH := 1
const ABILITY_SLOWMO := 2
const ABILITY_BUBBLE := 3
const ABILITY_INVIS := 4

# Base ability data – never modified directly
const ABILITY_BASE_DATA := {
	ABILITY_DASH: {
		"id": "dash",
		"type": "dash",
		"cooldown": 5.0,
		"duration": 0.12,
		"distance": 80.0,
	},
	ABILITY_SLOWMO: {
		"id": "slowmo",
		"type": "slowmo",
		"cooldown": 15.0,
		"duration": 1.0,
		"factor": 0.3,
	},
	ABILITY_BUBBLE: {
		"id": "bubble",
		"type": "bubble",
		"cooldown": 12.0,  # tweak later
		"duration": 4.0,
		"radius": 80.0,
	},
	ABILITY_INVIS: {
		"id": "invis",
		"type": "invis",
		"cooldown": 18.0,  # tune later
		"duration": 3.5,
	},
	
}

# Mutable runtime copy – upgrades modify this
var ABILITY_DATA: Dictionary = {}

var ability: int = ABILITY_NONE
var ability_cooldown_left: float = 0.0
var ability_active_left: float = 0.0

# --- STATS & SIGNALS ---------------------------------------------------

signal coins_changed(new_value: int)
signal health_changed(new_value: int, max_value: int)
signal ammo_changed(new_value: int, max_value: int)
signal run_reset  # fired when a new run starts / stats reset

var coins: int = 0

var max_health: int = 0
var health: int = 0

var max_ammo: int = 0
var ammo: int = 0

var fire_rate: float = 0.0          # normal fire cooldown (seconds between shots)
var shotgun_pellets: int = 0        # how many pellets the alt-fire uses

func _ready() -> void:
	# Optional: auto-start a run when the game boots
	start_new_run()

func _reset_alt_weapon_data() -> void:
	ALT_WEAPON_DATA.clear()
	for key in ALT_WEAPON_BASE_DATA.keys():
		ALT_WEAPON_DATA[key] = ALT_WEAPON_BASE_DATA[key].duplicate()

func _reset_ability_data() -> void:
	ABILITY_DATA.clear()
	for key in ABILITY_BASE_DATA.keys():
		ABILITY_DATA[key] = ABILITY_BASE_DATA[key].duplicate()

# -----------------------------------------------------------------------
# UPGRADES
# -----------------------------------------------------------------------

func apply_upgrade(id: String) -> void:
	match id:
		# --- Weapon-specific upgrades -----------------------------------
		"sniper_damage_plus_5":
			if ALT_WEAPON_DATA.has(ALT_WEAPON_SNIPER):
				var d = ALT_WEAPON_DATA[ALT_WEAPON_SNIPER]
				var current = d.get("damage", 10.0)
				d["damage"] = current * 1.05

		"max_ammo_plus_1":
			max_ammo += 1
			ammo = max_ammo

		"turret_cooldown_minus_5":
			if ALT_WEAPON_DATA.has(ALT_WEAPON_TURRET):
				var d = ALT_WEAPON_DATA[ALT_WEAPON_TURRET]
				var current = d.get("fire_interval", 0.8)
				# 5% faster = 95% of old interval, clamp to avoid 0
				d["fire_interval"] = max(0.05, current * 0.95)

		"fire_rate_plus_10":
			# Ensure initialized
			if fire_rate <= 0.0:
				fire_rate = GameConfig.player_fire_rate

			# Reduce current cooldown by 5% (shoot faster)
			fire_rate = max(0.05, fire_rate * 0.95)

		"shotgun_pellet_plus_1":
			if ALT_WEAPON_DATA.has(ALT_WEAPON_SHOTGUN):
				var d = ALT_WEAPON_DATA[ALT_WEAPON_SHOTGUN]
				var current = d.get("pellets", 1)
				d["pellets"] = current + 1

		# --- Health / ammo ----------------------------------------------
		"hp_refill":
			health = max_health

		"max_hp_plus_1":
			max_health += 10   # ⬅ was 1, now fits the "+10 Max HP" card
			health = max_health

		"ammo_refill":
			ammo = max_ammo

		# --- Alt weapon unlocks ----------------------------------------
		"unlock_shotgun":
			alt_weapon = ALT_WEAPON_SHOTGUN
			if ALT_WEAPON_DATA.has(ALT_WEAPON_SHOTGUN):
				var sd = ALT_WEAPON_DATA[ALT_WEAPON_SHOTGUN]
				max_ammo = sd.get("max_ammo", 0)
				ammo = max_ammo

		"unlock_sniper":
			alt_weapon = ALT_WEAPON_SNIPER
			if ALT_WEAPON_DATA.has(ALT_WEAPON_SNIPER):
				var nd = ALT_WEAPON_DATA[ALT_WEAPON_SNIPER]
				max_ammo = nd.get("max_ammo", 0)
				ammo = max_ammo

		"unlock_turret":
			alt_weapon = ALT_WEAPON_TURRET
			if ALT_WEAPON_DATA.has(ALT_WEAPON_TURRET):
				var td = ALT_WEAPON_DATA[ALT_WEAPON_TURRET]
				max_ammo = td.get("max_ammo", 0)
				ammo = max_ammo

		"unlock_flamethrower":
			alt_weapon = ALT_WEAPON_FLAMETHROWER
			if ALT_WEAPON_DATA.has(ALT_WEAPON_FLAMETHROWER):
				var fd = ALT_WEAPON_DATA[ALT_WEAPON_FLAMETHROWER]
				max_ammo = fd.get("max_ammo", 0)
				ammo = max_ammo
				
		"unlock_shuriken":
			alt_weapon = ALT_WEAPON_SHURIKEN
			if ALT_WEAPON_DATA.has(ALT_WEAPON_SHURIKEN):
				var d = ALT_WEAPON_DATA[ALT_WEAPON_SHURIKEN]
				max_ammo = d.get("max_ammo", 0)
				ammo = max_ammo
				
		"unlock_grenade":
			alt_weapon = ALT_WEAPON_GRENADE
			if ALT_WEAPON_DATA.has(ALT_WEAPON_GRENADE):
				var gd = ALT_WEAPON_DATA[ALT_WEAPON_GRENADE]
				max_ammo = gd.get("max_ammo", 0)
				ammo = max_ammo

		"grenade_radius_plus_20":
			if ALT_WEAPON_DATA.has(ALT_WEAPON_GRENADE):
				var gd = ALT_WEAPON_DATA[ALT_WEAPON_GRENADE]
				var current = gd.get("explosion_radius", 60.0)
				gd["explosion_radius"] = current + 20.0


				
		"flame_range_plus_20":
			if ALT_WEAPON_DATA.has(ALT_WEAPON_FLAMETHROWER):
				var d = ALT_WEAPON_DATA[ALT_WEAPON_FLAMETHROWER]
				var current_speed = d.get("bullet_speed", 320.0)
				# 20% more range = 20% more speed
				d["bullet_speed"] = current_speed * 1.2
				
		"shuriken_bounce_plus_1":
			if ALT_WEAPON_DATA.has(ALT_WEAPON_SHURIKEN):
				var d = ALT_WEAPON_DATA[ALT_WEAPON_SHURIKEN]
				var current = d.get("bounces", 1)
				d["bounces"] = current + 1




		# --- Ability unlocks -------------------------------------------
		"unlock_dash":
			ability = ABILITY_DASH

		"unlock_slowmo":
			ability = ABILITY_SLOWMO
			
		"unlock_bubble":
			ability = ABILITY_BUBBLE
			
		"unlock_invis":
			ability = ABILITY_INVIS

		# --- Ability generic cooldown reduction ------------------------
		"ability_cooldown_minus_10":
			if ability != ABILITY_NONE and ABILITY_DATA.has(ability):
				var ad = ABILITY_DATA[ability]
				var cd = ad.get("cooldown", 1.0)
				ad["cooldown"] = max(0.1, cd * 0.9)

	# After any upgrade, sync player + UI
	_sync_player_from_state()
	emit_signal("ammo_changed", ammo, max_ammo)

# -----------------------------------------------------------------------
# RUN RESET
# -----------------------------------------------------------------------

func start_new_run() -> void:
	_reset_alt_weapon_data()
	_reset_ability_data()

	# Reset health
	max_health = GameConfig.player_max_health
	health = max_health

	# Reset fire stats
	fire_rate = GameConfig.player_fire_rate
	shotgun_pellets = GameConfig.alt_fire_bullet_count

	# Alt weapon + ammo reset
	alt_weapon = ALT_WEAPON_NONE
	max_ammo = 0
	ammo = 0
	
	# Ability reset
	ability = ABILITY_NONE
	ability_cooldown_left = 0.0
	ability_active_left = 0.0
	player_invisible = false


	# Coins
	coins = 0

	emit_signal("coins_changed", coins)
	emit_signal("health_changed", health, max_health)
  
	emit_signal("ammo_changed", ammo, max_ammo)
	emit_signal("run_reset")

# -----------------------------------------------------------------------
# COINS / STATS HELPERS
# -----------------------------------------------------------------------

func add_coins(amount: int) -> void:
	coins += amount
	emit_signal("coins_changed", coins)

func set_health(value: int) -> void:
	health = clampi(value, 0, max_health)
	emit_signal("health_changed", health, max_health)

func set_ammo(value: int) -> void:
	ammo = clampi(value, 0, max_ammo)
	emit_signal("ammo_changed", ammo, max_ammo)

# -----------------------------------------------------------------------
# PLAYER SYNC
# -----------------------------------------------------------------------

func _sync_player_from_state() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("sync_from_gamestate"):
		player.sync_from_gamestate()
