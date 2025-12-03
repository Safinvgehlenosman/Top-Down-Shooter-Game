extends Node

@export_category("Player")
@export var player_move_speed: float = 200.0
@export var player_max_health: int = 50
@export var player_fire_rate: float = 0.15
@export var player_knockback_strength: float = 250.0
@export var player_knockback_duration: float = 0.15
@export var player_invincible_time: float = 0.3
@export var player_max_ammo: int = 6             # ammo stays as-is

@export_category("Bullet / Weapons")
@export var bullet_speed: float = 500.0
@export var bullet_base_damage: int = 10         # ⬅ was 1

@export_category("Slime")
@export var slime_move_speed: float = 0.0
@export var slime_max_health: int = 30           # ⬅ was 3
@export var slime_contact_damage: int = 10       # ⬅ was 1
@export var slime_heart_drop_chance: float = 0.2
@export var slime_spawn_delay: float = 1.5       # how long the slime stays as a puddle BEFORE playing spawn anim
@export var slime_spawn_anim_speed: float = 1.0  # speed multiplier for the spawn animation
@export var slime_death_cleanup: bool = false    # if true, clear puddles when leaving the room

@export_category("Pickup Magnet")
@export var pickup_magnet_range: float = 9999.0  # Always room-wide vacuum range
@export var pickup_magnet_strength: float = 500.0

# Magnet speed configuration - now using strong values as default
const PICKUP_MAGNET_SPEED_BASE := 1200.0   # Base magnet max speed (was SUPER)
const PICKUP_MAGNET_ACCEL_BASE := 2400.0   # Base acceleration (was SUPER)

# Dynamic magnet values - now always use maximum range (9999)
var current_pickup_magnet_range: float = 9999.0
var current_pickup_magnet_speed: float = PICKUP_MAGNET_SPEED_BASE
var current_pickup_magnet_accel: float = PICKUP_MAGNET_ACCEL_BASE

func _ready() -> void:
	# Initialize dynamic magnet values - always use room-wide range
	current_pickup_magnet_range = pickup_magnet_range  # Always 9999
	current_pickup_magnet_speed = PICKUP_MAGNET_SPEED_BASE
	current_pickup_magnet_accel = PICKUP_MAGNET_ACCEL_BASE

@export_category("Hit Feedback")
@export var hit_shake_strength: float = 8.0
@export var hit_shake_duration: float = 0.18
@export var hit_flash_duration: float = 0.15
@export var hit_flash_max_alpha: float = 0.15

@export_category("Shotgun Knockback")
@export var knockback_shake_strength: float = 8.0
@export var knockback_shake_duration: float = 0.18

@export_category("Alt Fire (Laser)")
@export var alt_fire_cooldown: float = 10.0
@export var alt_fire_bullet_count: int = 5
@export var alt_fire_spread_degrees: float = 12.0
@export var alt_fire_self_damage: int = 10      # ⬅ was 1
@export var alt_fire_recoil_strength: float = 400.0
@export var alt_fire_recoil_duration: float = 0.12

@export_category("Death / Game Over")
@export var death_slowmo_scale: float = 0.2
@export var death_slowmo_duration: float = 1.5

@export_category("Crate Loot")
@export var crate_coin_drop_chance: float = 0.6
@export var crate_ammo_drop_chance: float = 0.4
@export var crate_heart_drop_chance: float = 0.0  # optional, if you want hearts from crates

# -------------------------------------------------------------------
# WEAPON FUEL CONFIGURATION
# -------------------------------------------------------------------
# NOTE: Primary weapon is excluded (infinite ammo)
const WEAPON_FUEL_CONFIG := {
	"shotgun": {
		"max_fuel": 8.0,
		"shots_per_bar": 8,
		"reload_rate": 6.0,   # units per second when reloading
		"reload_delay": 0.5,   # seconds after last shot before reload starts
		"mode": "clip"         # clip-based: regen only when empty
	},
	"sniper": {
		"max_fuel": 4.0,
		"shots_per_bar": 4,
		"reload_rate": 3.0,
		"reload_delay": 0.8,
		"mode": "clip"
	},
	"grenade": {
		"max_fuel": 3.0,
		"shots_per_bar": 3,
		"reload_rate": 2.0,
		"reload_delay": 1.0,
		"mode": "clip"
	},
	"shuriken": {
		"max_fuel": 10.0,
		"shots_per_bar": 10,
		"reload_rate": 12.0,
		"reload_delay": 0.2,
		"mode": "clip"
	},
	# NOTE: Turret excluded - infinite alt-fire, no fuel system
	"flamethrower": {
		"max_fuel": 100.0,
		"drain_per_second": 25.0,  # continuous drain while firing
		"regen_per_second": 20.0,  # regen while not firing
		"overheat_threshold": 0.0,
		"mode": "continuous"       # special continuous mode
	},
}
