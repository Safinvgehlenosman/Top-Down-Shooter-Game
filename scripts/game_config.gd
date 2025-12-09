extends Node

@export_category("Player")
@export var player_move_speed: float = 200.0
@export var player_max_health: int = 50
@export var player_fire_rate: float = 0.15
@export var player_knockback_strength: float = 250.0
@export var player_knockback_duration: float = 0.15
@export var player_invincible_time: float = 0.3
@export var player_max_ammo: int = 6             # ammo stays as-is


# --- PRIMARY BULLET BASE SPEED ---
const PRIMARY_BULLET_BASE_SPEED := 500.0
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
		   "reload_delay": 5.0,   # seconds after last shot before reload starts
		   "mode": "clip"         # clip-based: regen only when empty
	   },
	   "sniper": {
		   "max_fuel": 4.0,
		   "shots_per_bar": 4,
		   "reload_rate": 3.0,
		   "reload_delay": 5.0,
		   "mode": "clip"
	   },
	   "grenade": {
		   "max_fuel": 3.0,
		   "shots_per_bar": 3,
		   "reload_rate": 2.0,
		   "reload_delay": 5.0,
		   "mode": "clip"
	   },
	   "shuriken": {
		   "max_fuel": 10.0,
		   "shots_per_bar": 10,
		   "reload_rate": 12.0,
		   "reload_delay": 5.0,
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

# -------------------------------------------------------------------
# EXPONENTIAL UPGRADE MULTIPLIERS
# -------------------------------------------------------------------
# All upgrades use multiplicative scaling per tier for explosive growth.
# Example: damage tier 5 = base * (1.15^5) = base * 2.01
# Centralized here for easy global tuning.
const UPGRADE_MULTIPLIERS := {
	# Weapon damage (most weapons)
	"damage": 1.15,  # 15% increase per tier
	
	# Fire rate (cooldown reduction)
	"fire_rate": 0.90,  # 10% faster per tier (cooldown *= 0.90)
	
	# Shotgun pellets
	"pellets": 1.20,  # 20% more pellets per tier
	
	# Projectile speed (bullets, shurikens, etc.)
	"projectile_speed": 1.12,  # 12% faster per tier
	
	# Flamethrower burn damage
	"burn_damage": 1.25,  # 25% more burn damage per tier
	
	# Grenade explosion radius
	"grenade_radius": 1.18,  # 18% larger radius per tier
	
	# Grenade fragment count
	"grenade_fragments": 1.20,  # 20% more fragments per tier
	
	# Shuriken bounce count
	"shuriken_bounces": 1.15,  # 15% more bounces per tier
	
	# Shuriken ricochet damage
	"shuriken_ricochet_damage": 1.20,  # 20% more damage per bounce tier
	
	# Sniper charge multiplier
	"sniper_charge": 1.30,  # 30% stronger charge per tier
	
	# Turret fire rate
	"turret_fire_rate": 0.90,  # 10% faster per tier
	
	# Turret damage
	"turret_damage": 1.15,  # 15% more damage per tier
	
	# Turret bullet speed
	"turret_bullet_speed": 1.15,  # 15% faster per tier
	
	# Turret range
	"turret_range": 1.12,  # 12% longer range per tier
	
	# Shotgun upgrades
	"shotgun_damage": 1.15,  # 15% more damage per tier
	"shotgun_fire_rate": 0.90,  # 10% faster fire rate per tier (cooldown reduction)
	"shotgun_mag": 1.20,  # 20% more ammo per tier
	
	# Sniper upgrades
	"sniper_damage": 1.20,  # 20% more damage per tier
	"sniper_fire_rate": 0.90,  # 10% faster fire rate per tier
	"sniper_mag": 1.20,  # 20% more ammo per tier
	
	# Ability duration (dash, slowmo, invis, bubble)
	"ability_duration": 1.15,  # 15% longer duration per tier
	
	# Ability cooldown reduction
	"ability_cooldown": 0.90,  # 10% faster cooldown per tier
	
	# Ability radius (slowmo, bubble)
	"ability_radius": 1.20,  # 20% larger radius per tier
	
	# Ability movement speed boost
	"ability_speed": 1.10,  # 10% faster movement per tier
}
