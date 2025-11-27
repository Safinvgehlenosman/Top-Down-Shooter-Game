extends Node

##
##  GameState.gd
##  Global run data (HP, ammo, coins, alt weapon, flags, etc.)
##  All upgrade *definitions* now live in Upgrades_DB.gd.
##

# -------------------------------------------------------------------
# SIGNALS
# -------------------------------------------------------------------

signal health_changed(current_health: int, max_health: int)
signal coins_changed(coins: int)
signal ammo_changed(ammo: int, max_ammo: int)
signal alt_weapon_changed(new_alt_weapon: int)
signal player_invisible_changed(is_invisible: bool)

# -------------------------------------------------------------------
# ALT WEAPONS
# -------------------------------------------------------------------

enum AltWeaponType {
	NONE,
	SHOTGUN,
	SNIPER,
	FLAMETHROWER,
	GRENADE,
	SHURIKEN,
	TURRET,
}

# These preloads are only used for alt-fire bullets.
const BulletScene_SHOTGUN := preload("res://scenes/bullets/shotgun_bullet.tscn")
const BulletScene_SNIPER  := preload("res://scenes/bullets/sniper_bullet.tscn")
const BulletScene_GRENADE := preload("res://scenes/bullets/grenade_bullet.tscn")
const BulletScene_SHURIKEN := preload("res://scenes/bullets/shuriken_bullet.tscn")
const BulletScene_FLAME    := preload("res://scenes/bullets/fire_projectile.tscn")
const BulletScene_TURRET    := preload("res://scenes/bullets/turret_bullet.tscn")

# Core config for each alt weapon
const ALT_WEAPON_DATA := {
	AltWeaponType.SHOTGUN: {
		"id": "shotgun",
		"bullet_scene": BulletScene_SHOTGUN,
		"bullet_speed": 900.0,
		"pellets": 6,
		"spread_degrees": 18.0,
		"damage": 10.0,
		"recoil": 140.0,
		"ammo_cost": 1,
		"cooldown": 0.7,
		"bounces": 0,
		"explosion_radius": 0.0,
		"max_ammo": 6,           # 🔥 NEW: starting/max ammo
		"pickup_amount": 2,      # 🔥 NEW: ammo per pickup
	},

	AltWeaponType.SNIPER: {
		"id": "sniper",
		"bullet_scene": BulletScene_SNIPER,
		"bullet_speed": 1400.0,
		"pellets": 1,
		"spread_degrees": 0.0,
		"damage": 35.0,
		"recoil": 220.0,
		"ammo_cost": 1,
		"cooldown": 1.2,
		"bounces": 0,
		"explosion_radius": 0.0,
		"max_ammo": 4,           # 🔥 NEW
		"pickup_amount": 1,      # 🔥 NEW
	},

	AltWeaponType.FLAMETHROWER: {
		"id": "flamethrower",
		"bullet_scene": BulletScene_FLAME,
		"bullet_speed": 220.0,
		"pellets": 3,
		"spread_degrees": 35.0,
		"damage": 4.0,
		"recoil": 25.0,
		"ammo_cost": 1,
		"cooldown": 0.0,
		"flame_lifetime": 0.25,
		"bounces": 0,
		"explosion_radius": 0.0,
		"max_ammo": 100,         # 🔥 NEW
		"pickup_amount": 20,     # 🔥 NEW
	},

	AltWeaponType.GRENADE: {
		"id": "grenade",
		"bullet_scene": BulletScene_GRENADE,
		"bullet_speed": 500.0,
		"pellets": 1,
		"spread_degrees": 0.0,
		"damage": 40.0,
		"recoil": 90.0,
		"ammo_cost": 1,
		"cooldown": 2.2,
		"bounces": 0,
		"explosion_radius": 96.0,
		"max_ammo": 3,           # 🔥 NEW
		"pickup_amount": 1,      # 🔥 NEW
	},

	AltWeaponType.SHURIKEN: {
		"id": "shuriken",
		"bullet_scene": BulletScene_SHURIKEN,
		"bullet_speed": 950.0,
		"pellets": 1,
		"spread_degrees": 0.0,
		"damage": 12.0,
		"recoil": 60.0,
		"ammo_cost": 1,
		"cooldown": 0.45,
		"bounces": 3,
		"explosion_radius": 0.0,
		"max_ammo": 8,           # 🔥 NEW
		"pickup_amount": 3,      # 🔥 NEW
	},

	AltWeaponType.TURRET: {
	"id": "turret",
	"bullet_scene": BulletScene_TURRET,  # ← ADD THIS (or use turret-specific bullet)
	"bullet_speed": 900.0,                # ← ADD THIS
	"damage": 7.0,
	"fire_rate": 0.4,
	"range": 220.0,
	"spread_degrees": 5.0,                # ← ADD THIS (small spread)
	},
}

# Current alt weapon for this run
var alt_weapon: int = AltWeaponType.NONE

# -------------------------------------------------------------------
# ABILITIES
# -------------------------------------------------------------------

enum AbilityType { NONE, DASH, SLOWMO, BUBBLE, INVIS }

var ability: AbilityType = AbilityType.NONE
var ability_cooldown_left: float = 0.0
var ability_active_left: float = 0.0
var ability_cooldown_mult: float = 1.0

const ABILITY_DATA := {
	AbilityType.DASH: {
		"type": "dash",
		"duration": 0.12,
		"distance": 220.0,
		"cooldown": 5.0,
	},
	AbilityType.SLOWMO: {
		"type": "slowmo",
		"duration": 3.0,
		"cooldown": 30.0,
		"factor": 0.3,
	},
	AbilityType.BUBBLE: {
		"type": "bubble",
		"duration": 3.0,
		"cooldown": 12.0,
	},
	AbilityType.INVIS: {
		"type": "invis",
		"duration": 3.0,
		"cooldown": 18.0,
	},
}

func set_ability(new_ability: int) -> void:
	ability = new_ability

# -------------------------------------------------------------------
# PLAYER / RUN DATA
# -------------------------------------------------------------------

var max_health: int = 0
var health: int = 0

var max_ammo: int = 0
var ammo: int = 0

# --- RUNTIME STATS (MODIFIED BY UPGRADES) --------------------------
var fire_rate: float = 0.0
var shotgun_pellets: int = 0

# Primary weapon stats
var primary_damage: float = 1.0         # 🔥 This is a MULTIPLIER (1.0 = 100%)
var primary_burst_count: int = 1

# economy
var coins: int = 0

# flags
var player_invisible: bool = false

# debug flags
var debug_laser_mode: bool = false
var debug_infinite_ammo: bool = false
var debug_god_mode: bool = false
var debug_noclip: bool = false

# -------------------------------------------------------------------
# LIFECYCLE
# -------------------------------------------------------------------

func _ready() -> void:
	start_new_run()

func start_new_run() -> void:
	# Base values come from GameConfig
	max_health = GameConfig.player_max_health
	health     = max_health

	max_ammo   = GameConfig.player_max_ammo
	ammo       = max_ammo

	# Reset fire stats
	fire_rate = GameConfig.player_fire_rate
	shotgun_pellets = GameConfig.alt_fire_bullet_count
	primary_damage = 1.0
	primary_burst_count = 1

	coins            = 0
	player_invisible = false

	alt_weapon       = AltWeaponType.NONE
	ability          = AbilityType.NONE
	ability_cooldown_left = 0.0
	ability_active_left = 0.0

	debug_laser_mode     = false
	debug_infinite_ammo  = false
	debug_god_mode       = false
	debug_noclip         = false

	_emit_all_signals()

# -------------------------------------------------------------------
# HEALTH
# -------------------------------------------------------------------

func set_health(value: int) -> void:
	health = clamp(value, 0, max_health)
	health_changed.emit(health, max_health)

func change_health(delta: int) -> void:
	set_health(health + delta)

# -------------------------------------------------------------------
# AMMO
# -------------------------------------------------------------------

func set_ammo(value: int) -> void:
	ammo = clamp(value, 0, max_ammo)
	ammo_changed.emit(ammo, max_ammo)

func add_ammo(delta: int) -> void:
	set_ammo(ammo + delta)

# -------------------------------------------------------------------
# COINS
# -------------------------------------------------------------------

func add_coins(delta: int) -> void:
	coins = max(coins + delta, 0)
	coins_changed.emit(coins)

func can_afford(cost: int) -> bool:
	return coins >= cost

func spend_coins(cost: int) -> bool:
	if coins < cost:
		return false
	coins -= cost
	coins_changed.emit(coins)
	return true

# -------------------------------------------------------------------
# ALT WEAPON
# -------------------------------------------------------------------

func set_alt_weapon(new_alt: int) -> void:
	if new_alt == alt_weapon:
		return
	alt_weapon = new_alt
	alt_weapon_changed.emit(alt_weapon)

# -------------------------------------------------------------------
# INVISIBILITY FLAG
# -------------------------------------------------------------------

func set_player_invisible(is_invisible: bool) -> void:
	if player_invisible == is_invisible:
		return
	player_invisible = is_invisible
	player_invisible_changed.emit(player_invisible)

# -------------------------------------------------------------------
# INTERNAL HELPERS
# -------------------------------------------------------------------

func _emit_all_signals() -> void:
	health_changed.emit(health, max_health)
	ammo_changed.emit(ammo, max_ammo)
	coins_changed.emit(coins)
	alt_weapon_changed.emit(alt_weapon)
	player_invisible_changed.emit(player_invisible)
