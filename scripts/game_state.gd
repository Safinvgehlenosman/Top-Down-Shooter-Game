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
const BulletScene_FLAME    := preload("res://scenes/bullets/flamethrower_bullet.tscn")
const BulletScene_TURRET    := preload("res://scenes/bullets/turret_bullet.tscn")

# Core config for each alt weapon
# Use `var` so runtime code can mutate per-run values when upgrades apply.
var ALT_WEAPON_DATA := {
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
	},

	AltWeaponType.GRENADE: {
		"id": "grenade",
		"bullet_scene": BulletScene_GRENADE,
		"bullet_speed": 500.0,
		"pellets": 1,
		"spread_degrees": 30.0, # Fixed per-pellet separation (not total arc)
		"damage": 40.0,
		"recoil": 90.0,
		"ammo_cost": 1,
		"cooldown": 2.2,
		"bounces": 0,
		"explosion_radius": 96.0,
	},

	AltWeaponType.SHURIKEN: {
		"id": "shuriken",
		"bullet_scene": BulletScene_SHURIKEN,
		"bullet_speed": 480.0,
		"pellets": 1,
		"spread_degrees": 0.0,
		"damage": 12.0,
		"recoil": 60.0,
		"ammo_cost": 1,
		"cooldown": 0.45,
		"bounces": 3,
		"explosion_radius": 0.0,
	},

	AltWeaponType.TURRET: {
	"id": "turret",
	"bullet_scene": BulletScene_TURRET,
	"bullet_speed": 135.0,  # Reduced to 60% of 225
	"damage": 7.0,  # Increased from 1.0
	"fire_rate": 1.2,  # Slower base fire rate (was 0.8)
	"range": 220.0,
	"spread_degrees": 10.0,  # Base inaccuracy spread
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
	# Cast integer to enum type to avoid INT_AS_ENUM_WITHOUT_CAST
	ability = new_ability as AbilityType

# -------------------------------------------------------------------
# PLAYER / RUN DATA
# -------------------------------------------------------------------

var max_health: int = 0
var health: int = 0

# --- RUNTIME STATS (MODIFIED BY UPGRADES) --------------------------
var fire_rate: float = 0.0
var shotgun_pellets: int = 0

# Movement speed
var move_speed: float = 0.0
var move_speed_base: float = 0.0
var move_speed_bonus_percent: float = 0.0

# Primary weapon stats
var primary_damage: float = 1.0         # 🔥 This is a MULTIPLIER (1.0 = 100%)
var primary_damage_base: float = 1.0
var primary_damage_bonus: float = 0.0

# Visual scaling for primary bullets (applied at spawn)
var primary_bullet_size_multiplier: float = 1.0

# Fire rate (cooldown) base + additive percent bonus (reduces cooldown)
var fire_rate_base: float = 0.0
var fire_rate_bonus_percent: float = 0.0
var primary_burst_count: int = 1
var primary_extra_burst: int = 0  # Sequential burst: +1 bullet per shot with delay (stackable)

# Piercing Rounds upgrade
var primary_pierce_mult: float = 1.0
var primary_pierce: int = 0

# Shuriken Chainshot + Blade Split upgrades
var shuriken_chain_count_mult: float = 1.0
var shuriken_chain_radius_mult: float = 1.0
var shuriken_speed_chain_mult: float = 1.0
var shuriken_blade_split_chance: float = 0.0

# Turret upgrades - accuracy and homing
var turret_accuracy_mult: float = 1.0
var turret_homing_angle_deg: float = 0.0
var turret_homing_turn_speed: float = 0.0
var turret_damage_mult: float = 1.0

# Shotgun upgrades - exponential multipliers
var shotgun_damage_mult: float = 1.0
var shotgun_fire_rate_mult: float = 1.0
var shotgun_mag_mult: float = 1.0

# Sniper upgrades - exponential multipliers
var sniper_damage_mult: float = 1.0
var sniper_fire_rate_mult: float = 1.0
var sniper_mag_mult: float = 1.0
var sniper_burst_count: int = 1

# --- Per-line / weapon bonuses (populated by upgrades) ----
var shotgun_pellets_bonus: int = 0
var shotgun_spread_bonus_percent: float = 0.0
var shotgun_knockback_bonus_percent: float = 0.0

var sniper_damage_bonus_percent: float = 0.0
var sniper_pierce_bonus: int = 0
var sniper_charge_bonus_percent: float = 0.0

var flamethrower_burn_bonus_percent: float = 1.0  # Multiplicative base

# Grenade bonuses are applied directly to ALT_WEAPON_DATA
var grenades_radius_mult: float = 1.0

# Shuriken bonuses are applied directly to ALT_WEAPON_DATA

# Turret bonuses are applied directly to ALT_WEAPON_DATA

# Ability bonuses
var dash_distance_bonus_percent: float = 1.0  # Multiplicative base

# Primary bullet size (this one can stay multiplicative as it's visual only)
var primary_bullet_size_bonus_percent: float = 0.0

# Synergy flags (data-only placeholders for later wiring)
var synergy_flamethrower_bubble_unlocked: bool = false
var synergy_grenade_dash_unlocked: bool = false
var synergy_shuriken_slowmo_unlocked: bool = false
var synergy_sniper_invis_unlocked: bool = false
var synergy_turret_bubble_unlocked: bool = false

# ⭐ CSV-based synergy flags (matches upgrades.csv effect names)
var sniper_invis_synergy_unlocked: bool = false
var shield_flamethrower_synergy_unlocked: bool = false
var dash_grenades_synergy_unlocked: bool = false

# ⭐ Synergy effect data
var dash_grenade_synergy_grenades: int = 0
var has_dash_grenade_synergy: bool = false

# ⭐ NEW SYNERGY UPGRADES
var has_invis_shuriken_synergy: bool = false
var has_sniper_wallpierce_synergy: bool = false
var has_fireshield_synergy: bool = false
var has_turret_slowmo_sprinkler_synergy: bool = false
var has_shotgun_dash_autofire_synergy: bool = false
var has_shuriken_bubble_nova_synergy: bool = false

# Shield ability
var shield_duration: float = 3.0
var shield_cooldown_mult: float = 1.0
var shield_radius_bonus: float = 1.0  # Multiplicative base

# Slowmo ability
var slowmo_duration: float = 1.5
var slowmo_cooldown_mult: float = 1.0
var slowmo_time_scale: float = 0.3
var slowmo_radius: float = 1.0  # Multiplicative base

# Invis ability (WORKING UPGRADES ONLY)
var invis_duration: float = 3.0  # Base duration from ABILITY_DATA
var invis_duration_mult: float = 1.0  # Multiplicative scaling
var invis_movement_speed_mult: float = 1.0  # Multiplicative base for movement speed

# economy
var coins: int = 0

# Bonus seconds added to the Shield Bubble ability duration by upgrades
var ability_bubble_duration_bonus: float = 0.0

# Acquired upgrades (records purchase history). Used to prevent re-offering
# non-stackable upgrades and to query ownership.
var acquired_upgrades: Array = []

# Track how many times each upgrade has been purchased this run (for price scaling)
var upgrade_purchase_counts: Dictionary = {}

# Chaos Challenge tracking (Hades-style challenge system)
var active_chaos_challenge: String = ""
var chaos_challenge_progress: int = 0
var chaos_challenge_target: int = 5  # Survive 5 rooms
var chaos_challenge_completed: bool = false
var original_max_health: int = 0  # Store original max HP before challenge
var original_move_speed: float = 0.0  # Store original move speed
var shop_disabled: bool = false  # Shops disabled flag
var primary_fire_disabled: bool = false  # Primary fire disabled flag
var coin_pickups_disabled: bool = false  # Coin pickups disabled flag

# ⭐ Chaos Pact Shuffle System
var chaos_pact_pool: Array = []  # Available chaos pacts
var chaos_pact_history: Array = []  # Already seen this cycle

# ⭐ Unlock flags for weapons and abilities
# These determine which weapons/abilities can be equipped via shop or loadout
var unlocked_shotgun: bool = false
var unlocked_sniper: bool = false
var unlocked_flamethrower: bool = false
var unlocked_grenade: bool = false
var unlocked_shuriken: bool = false
var unlocked_turret: bool = false
var unlocked_dash: bool = false
var unlocked_slowmo: bool = false
var unlocked_bubble: bool = false
var unlocked_invis: bool = false

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
	# ⭐ Initialize chaos pact pool
	_reset_chaos_pact_pool()

func start_new_run() -> void:
	# Base values come from GameConfig
	max_health = GameConfig.player_max_health
	set_health(max_health)  # Use setter to emit signal

	# Reset fire stats
	fire_rate_base = GameConfig.player_fire_rate
	fire_rate = GameConfig.player_fire_rate
	fire_rate_bonus_percent = 0.0
	shotgun_pellets = GameConfig.alt_fire_bullet_count
	shotgun_pellets_bonus = 0
	primary_damage_base = 1.0
	primary_damage_bonus = 0.0
	primary_damage = primary_damage_base * (1.0 + primary_damage_bonus)

	primary_burst_count = 1
	primary_extra_burst = 0
	
	# Reset piercing and homing
	primary_pierce_mult = 1.0
	primary_pierce = 0
	
	# Reset shuriken chainshot
	shuriken_chain_count_mult = 1.0
	shuriken_chain_radius_mult = 1.0
	shuriken_speed_chain_mult = 1.0
	shuriken_blade_split_chance = 0.0
	
	# Reset turret accuracy and homing
	turret_accuracy_mult = 1.0
	turret_homing_angle_deg = 0.0
	turret_homing_turn_speed = 0.0
	turret_damage_mult = 1.0
	
	# Reset shotgun multipliers
	shotgun_damage_mult = 1.0
	shotgun_fire_rate_mult = 1.0
	shotgun_mag_mult = 1.0
	
	# Reset sniper multipliers
	sniper_damage_mult = 1.0
	sniper_fire_rate_mult = 1.0
	sniper_mag_mult = 1.0
	sniper_burst_count = 1

	# reset per-line bonuses
	shotgun_spread_bonus_percent = 0.0
	shotgun_knockback_bonus_percent = 0.0

	sniper_damage_bonus_percent = 0.0
	sniper_pierce_bonus = 0
	sniper_charge_bonus_percent = 0.0

	flamethrower_burn_bonus_percent = 1.0  # Multiplicative base

	# Grenade bonuses reset in ALT_WEAPON_DATA
	grenades_radius_mult = 1.0

	# Shuriken bonuses reset in ALT_WEAPON_DATA

	# Turret bonuses reset in ALT_WEAPON_DATA

	dash_distance_bonus_percent = 1.0  # Multiplicative base
	invis_duration = 3.0  # Reset to base
	invis_duration_mult = 1.0
	invis_movement_speed_mult = 1.0
	invis_movement_speed_mult = 1.0  # Reset to base

	# reset synergies
	synergy_flamethrower_bubble_unlocked = false
	synergy_grenade_dash_unlocked = false
	synergy_shuriken_slowmo_unlocked = false
	synergy_sniper_invis_unlocked = false
	synergy_turret_bubble_unlocked = false

	# reset synergy effects
	dash_grenade_synergy_grenades = 0
	has_dash_grenade_synergy = false

	# ⭐ Reset all synergy upgrades
	has_invis_shuriken_synergy = false
	has_sniper_wallpierce_synergy = false
	has_fireshield_synergy = false
	has_turret_slowmo_sprinkler_synergy = false
	has_shotgun_dash_autofire_synergy = false
	has_shuriken_bubble_nova_synergy = false

	coins            = 0
	player_invisible = false
	upgrade_purchase_counts.clear()
	
	# Reset chaos challenge state
	active_chaos_challenge = ""
	chaos_challenge_progress = 0
	chaos_challenge_completed = false
	original_max_health = 0
	
	# Reset chaos challenge flags
	coin_pickups_disabled = false
	primary_fire_disabled = false

	alt_weapon       = AltWeaponType.NONE
	ability          = AbilityType.NONE
	ability_cooldown_left = 0.0
	ability_active_left = 0.0
	ability_bubble_duration_bonus = 0.0
	
	# Reset ability stat bonuses
	shield_duration = 3.0
	shield_cooldown_mult = 1.0
	shield_radius_bonus = 1.0  # Multiplicative base
	slowmo_duration = 1.5
	slowmo_cooldown_mult = 1.0
	slowmo_time_scale = 0.3
	slowmo_radius = 1.0  # Multiplicative base

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
# INVIS FLAG
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
	coins_changed.emit(coins)
	alt_weapon_changed.emit(alt_weapon)
	player_invisible_changed.emit(player_invisible)


func has_upgrade(upgrade_id: String) -> bool:
	return upgrade_id in acquired_upgrades


func _record_acquired_upgrade(upgrade_id: String) -> void:
	if not has_upgrade(upgrade_id):
		acquired_upgrades.append(upgrade_id)

func get_upgrade_price(upgrade_id: String, base_price: int) -> int:
	"""Calculate exponentially scaled price based on rarity and purchase count."""
	var times_purchased: int = upgrade_purchase_counts.get(upgrade_id, 0)
	
	# Get rarity from upgrade data
	var upgrade_data = UpgradesDB.get_by_id(upgrade_id)
	var rarity = upgrade_data.get("rarity", 0)  # Default to COMMON (0)
	
	# Rarity-based exponential multipliers
	var multiplier: float = 1.0
	match rarity:
		0:  # COMMON
			multiplier = 1.2
		1:  # UNCOMMON
			multiplier = 1.4
		2:  # RARE
			multiplier = 1.6
		3:  # EPIC
			multiplier = 1.8
	
	# Exponential scaling: base_price * (multiplier ^ times_purchased)
	var scaled_price: float = float(base_price) * pow(multiplier, float(times_purchased))
	return int(scaled_price)


func record_upgrade_purchase(upgrade_id: String) -> void:
	"""Increment purchase count for this upgrade ID."""
	var current_count: int = upgrade_purchase_counts.get(upgrade_id, 0)
	upgrade_purchase_counts[upgrade_id] = current_count + 1

# -------------------------------------------------------------------
# APPLY UPGRADE ENTRYPOINT
# All non-synergy upgrade effects are applied here.
# Keep this function limited to numeric changes of GameState or ALT_WEAPON_DATA
# -------------------------------------------------------------------
func apply_upgrade(upgrade_id: String) -> void:

	# Load upgrade from CSV database
	var upgrade := UpgradesDB.get_by_id(upgrade_id)
	if upgrade.is_empty():
		push_warning("[GameState] Unknown upgrade: %s" % upgrade_id)
		return

	# Prevent re-applying non-stackable upgrades
	var stackable := bool(upgrade.get("stackable", true))
	if not stackable and has_upgrade(upgrade_id):
		push_warning("[GameState] Upgrade already owned and not stackable: %s" % upgrade_id)
		return

	# Extract effect and value from CSV data
	var effect: String = str(upgrade.get("effect", "")).strip_edges()
	var value: float = float(upgrade.get("value", 0.0))

	# ==============================
	# PROCESS UNLOCK_WEAPON
	# ==============================
	var unlock_weapon_str: String = str(upgrade.get("unlock_weapon", "")).strip_edges()
	if unlock_weapon_str != "":
		var weapon_tokens := unlock_weapon_str.split(",")
		for token in weapon_tokens:
			var weapon_id := token.strip_edges().to_lower()
			if weapon_id == "":
				continue
			
			match weapon_id:
				"shotgun":
					unlocked_shotgun = true
					set_alt_weapon(AltWeaponType.SHOTGUN)

				"sniper":
					unlocked_sniper = true
					set_alt_weapon(AltWeaponType.SNIPER)

				"flamethrower":
					unlocked_flamethrower = true
					set_alt_weapon(AltWeaponType.FLAMETHROWER)

				"grenade":
					unlocked_grenade = true
					set_alt_weapon(AltWeaponType.GRENADE)

				"shuriken":
					unlocked_shuriken = true
					set_alt_weapon(AltWeaponType.SHURIKEN)

				"turret":
					unlocked_turret = true
					set_alt_weapon(AltWeaponType.TURRET)

				_:
					push_warning("[GameState] Unknown weapon unlock: %s" % weapon_id)

	# ==============================
	# PROCESS UNLOCK_ABILITY
	# ==============================
	var unlock_ability_str: String = str(upgrade.get("unlock_ability", "")).strip_edges()
	if unlock_ability_str != "":
		var ability_tokens := unlock_ability_str.split(",")
		for token in ability_tokens:
			var ability_id := token.strip_edges().to_lower()
			if ability_id == "":
				continue
			
			match ability_id:
				"dash":
					unlocked_dash = true
					set_ability(AbilityType.DASH)

				"slowmo":
					unlocked_slowmo = true
					set_ability(AbilityType.SLOWMO)

				"bubble":
					unlocked_bubble = true
					set_ability(AbilityType.BUBBLE)

				"invis":
					unlocked_invis = true
					set_ability(AbilityType.INVIS)

				_:
					push_warning("[GameState] Unknown ability unlock: %s" % ability_id)

	# Apply the upgrade effect
	match effect:
		# ==============================
		# CORE / GENERAL EFFECTS
		# ==============================
		"max_hp":
			var inc := int(value)
			max_health += inc
			health += inc  # Also increase current health
			emit_signal("health_changed", health, max_health)
			
			# Force update player's HealthComponent
			var player := get_tree().get_first_node_in_group("player")
			if player and player.has_node("Health"):
				var health_component = player.get_node("Health")
				if health_component:
					health_component.max_health = max_health
					health_component.health = health


		"hp_refill":
			set_health(max_health)

		"ability_cooldown":
			ability_cooldown_mult *= (1.0 + value)

		# ==============================
		# WEAPON / ABILITY UNLOCKS (LEGACY EFFECT-BASED)
		# ==============================
		# These are the old hardcoded unlock effects
		# They set the unlock flag AND auto-equip for backwards compatibility
		"unlock_shotgun":
			unlocked_shotgun = true
			set_alt_weapon(AltWeaponType.SHOTGUN)

		"unlock_sniper":
			unlocked_sniper = true
			set_alt_weapon(AltWeaponType.SNIPER)

		"unlock_turret":
			unlocked_turret = true
			set_alt_weapon(AltWeaponType.TURRET)

		"unlock_flamethrower":
			unlocked_flamethrower = true
			set_alt_weapon(AltWeaponType.FLAMETHROWER)

		"unlock_shuriken":
			unlocked_shuriken = true
			set_alt_weapon(AltWeaponType.SHURIKEN)

		"unlock_grenade":
			unlocked_grenade = true
			set_alt_weapon(AltWeaponType.GRENADE)

		# Ability unlocks
		"unlock_dash":
			unlocked_dash = true
			set_ability(AbilityType.DASH)

		"unlock_slowmo":
			unlocked_slowmo = true
			set_ability(AbilityType.SLOWMO)

		"unlock_bubble":
			unlocked_bubble = true
			set_ability(AbilityType.BUBBLE)

		"unlock_invis":
			unlocked_invis = true
			set_ability(AbilityType.INVIS)

		# ==============================
		# PRIMARY WEAPON EFFECTS
		# ==============================
		"primary_damage":
			# EXPONENTIAL SCALING: Multiply damage by constant per tier
			primary_damage *= GameConfig.UPGRADE_MULTIPLIERS["damage"]
			print("  → Primary damage ×%.2f (total now: %.2f)" % [GameConfig.UPGRADE_MULTIPLIERS["damage"], primary_damage])

		"primary_fire_rate":
			# EXPONENTIAL SCALING: Multiply cooldown by constant per tier (reduces cooldown)
			fire_rate *= GameConfig.UPGRADE_MULTIPLIERS["fire_rate"]
			fire_rate = max(0.05, fire_rate)  # Hard floor at 0.05s
			print("  → Fire rate ×%.2f (cooldown now: %.3fs)" % [GameConfig.UPGRADE_MULTIPLIERS["fire_rate"], fire_rate])

		"primary_extra_burst":
			# Stackable: adds +1 sequential bullet per upgrade
			primary_extra_burst += int(value)
			print("  → Primary extra burst +%d (total: %d)" % [int(value), primary_extra_burst])

		"primary_pierce":
			# EXPONENTIAL SCALING: Multiply pierce count by 1.20 per tier
			primary_pierce_mult *= 1.20
			primary_pierce = int(primary_pierce_mult - 1.0)
			print("  → Primary pierce ×1.20 (total pierces: %d)" % primary_pierce)

		# ==============================
		# SHOTGUN EFFECTS
		# ==============================
		"shotgun_pellets":
			# EXPONENTIAL SCALING: Multiply pellet count by constant per tier
			if ALT_WEAPON_DATA.has(AltWeaponType.SHOTGUN):
				var old_pellets: int = ALT_WEAPON_DATA[AltWeaponType.SHOTGUN]["pellets"]
				ALT_WEAPON_DATA[AltWeaponType.SHOTGUN]["pellets"] = max(1, int(round(old_pellets * GameConfig.UPGRADE_MULTIPLIERS["pellets"])))
				print("  → Shotgun pellets ×%.2f (%d → %d)" % [GameConfig.UPGRADE_MULTIPLIERS["pellets"], old_pellets, ALT_WEAPON_DATA[AltWeaponType.SHOTGUN]["pellets"]])

		"shotgun_spread":
			# EXPONENTIAL SCALING: Reduce spread multiplicatively (tighter cone)
			if ALT_WEAPON_DATA.has(AltWeaponType.SHOTGUN):
				var old_spread: float = ALT_WEAPON_DATA[AltWeaponType.SHOTGUN]["spread_degrees"]
				ALT_WEAPON_DATA[AltWeaponType.SHOTGUN]["spread_degrees"] *= 0.85  # 15% tighter per tier
				print("  → Shotgun spread ×0.85 (%.1f° → %.1f°)" % [old_spread, ALT_WEAPON_DATA[AltWeaponType.SHOTGUN]["spread_degrees"]])

		"shotgun_knockback":
			shotgun_knockback_bonus_percent += value
		
		"shotgun_damage":
			# EXPONENTIAL SCALING: Multiply damage by 1.15 per tier
			shotgun_damage_mult *= GameConfig.UPGRADE_MULTIPLIERS["shotgun_damage"]
			print("  → Shotgun damage ×%.2f (total mult: %.2f)" % [GameConfig.UPGRADE_MULTIPLIERS["shotgun_damage"], shotgun_damage_mult])
		
		"shotgun_fire_rate":
			# EXPONENTIAL SCALING: Reduce cooldown by 10% per tier
			shotgun_fire_rate_mult *= GameConfig.UPGRADE_MULTIPLIERS["shotgun_fire_rate"]
			print("  → Shotgun fire rate ×%.2f (total mult: %.2f)" % [GameConfig.UPGRADE_MULTIPLIERS["shotgun_fire_rate"], shotgun_fire_rate_mult])
		
		"shotgun_mag":
			# EXPONENTIAL SCALING: Increase magazine size by 20% per tier
			shotgun_mag_mult *= GameConfig.UPGRADE_MULTIPLIERS["shotgun_mag"]
			print("  → Shotgun mag size ×%.2f (total mult: %.2f)" % [GameConfig.UPGRADE_MULTIPLIERS["shotgun_mag"], shotgun_mag_mult])
			if ALT_WEAPON_DATA.has(AltWeaponType.SHOTGUN):
				ALT_WEAPON_DATA[AltWeaponType.SHOTGUN]["recoil"] = 140.0 * (1.0 + shotgun_knockback_bonus_percent)

		# ==============================
		# SNIPER EFFECTS
		# ==============================
		"sniper_damage":
			# EXPONENTIAL SCALING: Multiply damage by constant per tier
			if ALT_WEAPON_DATA.has(AltWeaponType.SNIPER):
				var old_damage: float = ALT_WEAPON_DATA[AltWeaponType.SNIPER]["damage"]
				ALT_WEAPON_DATA[AltWeaponType.SNIPER]["damage"] *= GameConfig.UPGRADE_MULTIPLIERS["damage"]
				print("  → Sniper damage ×%.2f (%.1f → %.1f)" % [GameConfig.UPGRADE_MULTIPLIERS["damage"], old_damage, ALT_WEAPON_DATA[AltWeaponType.SNIPER]["damage"]])

		"sniper_pierce":
			# EXPONENTIAL SCALING: Multiply pierce count by constant per tier
			if ALT_WEAPON_DATA.has(AltWeaponType.SNIPER):
				var old_bounces: int = ALT_WEAPON_DATA[AltWeaponType.SNIPER]["bounces"]
				ALT_WEAPON_DATA[AltWeaponType.SNIPER]["bounces"] = max(0, int(round((old_bounces + 1) * 1.5)) - 1)  # Exponential growth from base
				print("  → Sniper pierce +1 bounce (%d → %d)" % [old_bounces, ALT_WEAPON_DATA[AltWeaponType.SNIPER]["bounces"]])

		"sniper_charge_speed":
			# EXPONENTIAL SCALING: Multiply charge multiplier by constant per tier
			if ALT_WEAPON_DATA.has(AltWeaponType.SNIPER):
				var old_damage: float = ALT_WEAPON_DATA[AltWeaponType.SNIPER]["damage"]
				ALT_WEAPON_DATA[AltWeaponType.SNIPER]["damage"] *= GameConfig.UPGRADE_MULTIPLIERS["sniper_charge"]
				print("  → Sniper charge ×%.2f (damage: %.1f → %.1f)" % [GameConfig.UPGRADE_MULTIPLIERS["sniper_charge"], old_damage, ALT_WEAPON_DATA[AltWeaponType.SNIPER]["damage"]])
		
		"sniper_burst":
			# Stackable burst shots
			sniper_burst_count += 1
			print("  → Sniper burst +1 (total: %d shots)" % sniper_burst_count)
		
		"sniper_damage_mult":
			# EXPONENTIAL SCALING: Multiply damage by 20% per tier
			sniper_damage_mult *= GameConfig.UPGRADE_MULTIPLIERS["sniper_damage"]
			print("  → Sniper damage ×%.2f (total mult: %.2f)" % [GameConfig.UPGRADE_MULTIPLIERS["sniper_damage"], sniper_damage_mult])
		
		"sniper_fire_rate":
			# EXPONENTIAL SCALING: Reduce cooldown by 10% per tier
			sniper_fire_rate_mult *= GameConfig.UPGRADE_MULTIPLIERS["sniper_fire_rate"]
			print("  → Sniper fire rate ×%.2f (total mult: %.2f)" % [GameConfig.UPGRADE_MULTIPLIERS["sniper_fire_rate"], sniper_fire_rate_mult])
		
		"sniper_mag":
			# EXPONENTIAL SCALING: Increase magazine size by 20% per tier
			sniper_mag_mult *= GameConfig.UPGRADE_MULTIPLIERS["sniper_mag"]
			print("  → Sniper mag size ×%.2f (total mult: %.2f)" % [GameConfig.UPGRADE_MULTIPLIERS["sniper_mag"], sniper_mag_mult])

		# ==============================
		# FLAMETHROWER EFFECTS
		# ==============================
		"flamethrower_burn_damage":
			# EXPONENTIAL SCALING: Track as multiplier for burn damage
			flamethrower_burn_bonus_percent *= GameConfig.UPGRADE_MULTIPLIERS["burn_damage"]
			print("  → Flamethrower burn ×%.2f (multiplier now: %.2f)" % [GameConfig.UPGRADE_MULTIPLIERS["burn_damage"], flamethrower_burn_bonus_percent])

		"flamethrower_cone_size":
			# EXPONENTIAL SCALING: Multiply cone damage by constant per tier
			if ALT_WEAPON_DATA.has(AltWeaponType.FLAMETHROWER):
				var old_damage: float = ALT_WEAPON_DATA[AltWeaponType.FLAMETHROWER]["damage"]
				ALT_WEAPON_DATA[AltWeaponType.FLAMETHROWER]["damage"] *= 1.18  # 18% larger cone per tier
				print("  → Flamethrower cone ×1.18 (damage: %.1f → %.1f)" % [old_damage, ALT_WEAPON_DATA[AltWeaponType.FLAMETHROWER]["damage"]])

		"flamethrower_duration":
			# EXPONENTIAL SCALING: Multiply flame lifetime by constant per tier
			if ALT_WEAPON_DATA.has(AltWeaponType.FLAMETHROWER):
				var old_lifetime: float = ALT_WEAPON_DATA[AltWeaponType.FLAMETHROWER]["flame_lifetime"]
				ALT_WEAPON_DATA[AltWeaponType.FLAMETHROWER]["flame_lifetime"] *= GameConfig.UPGRADE_MULTIPLIERS["ability_duration"]
				print("  → Flamethrower duration ×%.2f (%.2fs → %.2fs)" % [GameConfig.UPGRADE_MULTIPLIERS["ability_duration"], old_lifetime, ALT_WEAPON_DATA[AltWeaponType.FLAMETHROWER]["flame_lifetime"]])

		# ==============================
		# GRENADES EFFECTS
		# ==============================
		"grenades_radius":
			# EXPONENTIAL SCALING: Multiply explosion radius by constant per tier
			grenades_radius_mult *= GameConfig.UPGRADE_MULTIPLIERS["grenade_radius"]
			if ALT_WEAPON_DATA.has(AltWeaponType.GRENADE):
				var old_radius: float = ALT_WEAPON_DATA[AltWeaponType.GRENADE]["explosion_radius"]
				ALT_WEAPON_DATA[AltWeaponType.GRENADE]["explosion_radius"] *= GameConfig.UPGRADE_MULTIPLIERS["grenade_radius"]
				print("  → Grenade radius ×%.2f (%.1f → %.1f) [multiplier now: %.2f]" % [GameConfig.UPGRADE_MULTIPLIERS["grenade_radius"], old_radius, ALT_WEAPON_DATA[AltWeaponType.GRENADE]["explosion_radius"], grenades_radius_mult])

		"grenades_damage":
			# EXPONENTIAL SCALING: Multiply damage by constant per tier
			if ALT_WEAPON_DATA.has(AltWeaponType.GRENADE):
				var old_damage: float = ALT_WEAPON_DATA[AltWeaponType.GRENADE]["damage"]
				ALT_WEAPON_DATA[AltWeaponType.GRENADE]["damage"] *= GameConfig.UPGRADE_MULTIPLIERS["damage"]
				print("  → Grenade damage ×%.2f (%.1f → %.1f)" % [GameConfig.UPGRADE_MULTIPLIERS["damage"], old_damage, ALT_WEAPON_DATA[AltWeaponType.GRENADE]["damage"]])

		"grenades_cooldown":
			# EXPONENTIAL SCALING: Multiply cooldown by constant per tier (reduces cooldown)
			if ALT_WEAPON_DATA.has(AltWeaponType.GRENADE):
				var old_cooldown: float = ALT_WEAPON_DATA[AltWeaponType.GRENADE]["cooldown"]
				ALT_WEAPON_DATA[AltWeaponType.GRENADE]["cooldown"] *= GameConfig.UPGRADE_MULTIPLIERS["fire_rate"]
				ALT_WEAPON_DATA[AltWeaponType.GRENADE]["cooldown"] = max(0.5, ALT_WEAPON_DATA[AltWeaponType.GRENADE]["cooldown"])
				print("  → Grenade cooldown ×%.2f (%.2fs → %.2fs)" % [GameConfig.UPGRADE_MULTIPLIERS["fire_rate"], old_cooldown, ALT_WEAPON_DATA[AltWeaponType.GRENADE]["cooldown"]])

		"grenades_frag_count":
			# EXPONENTIAL SCALING: Multiply fragment count by constant per tier
			if ALT_WEAPON_DATA.has(AltWeaponType.GRENADE):
				var old_pellets: int = ALT_WEAPON_DATA[AltWeaponType.GRENADE]["pellets"]
				ALT_WEAPON_DATA[AltWeaponType.GRENADE]["pellets"] = max(1, int(round(old_pellets * GameConfig.UPGRADE_MULTIPLIERS["grenade_fragments"])))
				print("  → Grenade fragments ×%.2f (%d → %d)" % [GameConfig.UPGRADE_MULTIPLIERS["grenade_fragments"], old_pellets, ALT_WEAPON_DATA[AltWeaponType.GRENADE]["pellets"]])

		# ==============================
		# SHURIKEN EFFECTS
		# ==============================
		"shuriken_bounce_count":
			# EXPONENTIAL SCALING: Multiply bounce count by constant per tier
			if ALT_WEAPON_DATA.has(AltWeaponType.SHURIKEN):
				var old_bounces: int = ALT_WEAPON_DATA[AltWeaponType.SHURIKEN]["bounces"]
				ALT_WEAPON_DATA[AltWeaponType.SHURIKEN]["bounces"] = max(1, int(round(old_bounces * GameConfig.UPGRADE_MULTIPLIERS["shuriken_bounces"])))
				print("  → Shuriken bounces ×%.2f (%d → %d)" % [GameConfig.UPGRADE_MULTIPLIERS["shuriken_bounces"], old_bounces, ALT_WEAPON_DATA[AltWeaponType.SHURIKEN]["bounces"]])

		"shuriken_chain_i":
			# COMMON: +1 chain, radius ×1.10
			shuriken_chain_count_mult += 1.0
			shuriken_chain_radius_mult *= 1.10
			print("  → Shuriken chain +1 (total: %.0f), radius ×1.10 (total: ×%.2f)" % [shuriken_chain_count_mult - 1.0, shuriken_chain_radius_mult])

		"shuriken_chain_ii":
			# UNCOMMON: +2 chains, radius ×1.20
			shuriken_chain_count_mult += 2.0
			shuriken_chain_radius_mult *= 1.20
			print("  → Shuriken chain +2 (total: %.0f), radius ×1.20 (total: ×%.2f)" % [shuriken_chain_count_mult - 1.0, shuriken_chain_radius_mult])

		"shuriken_chain_iii":
			# RARE: +4 chains, radius ×1.30, speed ×1.10
			shuriken_chain_count_mult += 4.0
			shuriken_chain_radius_mult *= 1.30
			shuriken_speed_chain_mult *= 1.10
			print("  → Shuriken chain +4 (total: %.0f), radius ×1.30 (total: ×%.2f), speed ×1.10 (total: ×%.2f)" % [shuriken_chain_count_mult - 1.0, shuriken_chain_radius_mult, shuriken_speed_chain_mult])

		"shuriken_chain_iv":
			# EPIC: infinite chains (999), radius ×1.50, speed ×1.15
			shuriken_chain_count_mult = 1000.0  # 999 chains
			shuriken_chain_radius_mult *= 1.50
			shuriken_speed_chain_mult *= 1.15
			print("  → Shuriken chain INFINITE (999), radius ×1.50 (total: ×%.2f), speed ×1.15 (total: ×%.2f)" % [shuriken_chain_radius_mult, shuriken_speed_chain_mult])

		"shuriken_blade_split":
			# EPIC: 25% chance to spawn mini-shuriken on chain
			shuriken_blade_split_chance += 0.25
			print("  → Blade Split +25%% (total: %.0f%%)" % (shuriken_blade_split_chance * 100.0))

		"shuriken_speed":
			# EXPONENTIAL SCALING: Multiply bullet speed by constant per tier
			if ALT_WEAPON_DATA.has(AltWeaponType.SHURIKEN):
				var old_speed: float = ALT_WEAPON_DATA[AltWeaponType.SHURIKEN]["bullet_speed"]
				ALT_WEAPON_DATA[AltWeaponType.SHURIKEN]["bullet_speed"] *= GameConfig.UPGRADE_MULTIPLIERS["projectile_speed"]
				print("  → Shuriken speed ×%.2f (%.1f → %.1f)" % [GameConfig.UPGRADE_MULTIPLIERS["projectile_speed"], old_speed, ALT_WEAPON_DATA[AltWeaponType.SHURIKEN]["bullet_speed"]])

		"shuriken_pierce":
			# EXPONENTIAL SCALING: Multiply ricochet damage by constant per tier
			if ALT_WEAPON_DATA.has(AltWeaponType.SHURIKEN):
				var old_damage: float = ALT_WEAPON_DATA[AltWeaponType.SHURIKEN]["damage"]
				ALT_WEAPON_DATA[AltWeaponType.SHURIKEN]["damage"] *= GameConfig.UPGRADE_MULTIPLIERS["shuriken_ricochet_damage"]
				print("  → Shuriken pierce damage ×%.2f (%.1f → %.1f)" % [GameConfig.UPGRADE_MULTIPLIERS["shuriken_ricochet_damage"], old_damage, ALT_WEAPON_DATA[AltWeaponType.SHURIKEN]["damage"]])

		# ==============================
		# TURRET EFFECTS
		# ==============================
		"turret_fire_rate":
			# EXPONENTIAL SCALING: Multiply fire rate cooldown by constant per tier
			if ALT_WEAPON_DATA.has(AltWeaponType.TURRET):
				var old_fire_rate: float = ALT_WEAPON_DATA[AltWeaponType.TURRET]["fire_rate"]
				ALT_WEAPON_DATA[AltWeaponType.TURRET]["fire_rate"] *= GameConfig.UPGRADE_MULTIPLIERS["turret_fire_rate"]
				print("  → Turret fire rate ×%.2f (%.2fs → %.2fs)" % [GameConfig.UPGRADE_MULTIPLIERS["turret_fire_rate"], old_fire_rate, ALT_WEAPON_DATA[AltWeaponType.TURRET]["fire_rate"]])

		"turret_range":
			# EXPONENTIAL SCALING: Multiply range by constant per tier
			if ALT_WEAPON_DATA.has(AltWeaponType.TURRET):
				var old_range: float = ALT_WEAPON_DATA[AltWeaponType.TURRET]["range"]
				ALT_WEAPON_DATA[AltWeaponType.TURRET]["range"] *= GameConfig.UPGRADE_MULTIPLIERS["turret_range"]
				print("  → Turret range ×%.2f (%.1f → %.1f)" % [GameConfig.UPGRADE_MULTIPLIERS["turret_range"], old_range, ALT_WEAPON_DATA[AltWeaponType.TURRET]["range"]])

		"turret_bullet_speed":
			# EXPONENTIAL SCALING: Multiply bullet speed by constant per tier
			if ALT_WEAPON_DATA.has(AltWeaponType.TURRET):
				var old_speed: float = ALT_WEAPON_DATA[AltWeaponType.TURRET]["bullet_speed"]
				ALT_WEAPON_DATA[AltWeaponType.TURRET]["bullet_speed"] *= GameConfig.UPGRADE_MULTIPLIERS["turret_bullet_speed"]
				print("  → Turret bullet speed ×%.2f (%.1f → %.1f)" % [GameConfig.UPGRADE_MULTIPLIERS["turret_bullet_speed"], old_speed, ALT_WEAPON_DATA[AltWeaponType.TURRET]["bullet_speed"]])
		
		"turret_accuracy":
			# EXPONENTIAL SCALING: Multiply accuracy by 0.85 per tier (lower = more accurate)
			turret_accuracy_mult *= 0.85
			print("  → Turret accuracy ×0.85 (spread mult: %.2f)" % turret_accuracy_mult)
		
		"turret_homing":
			# EXPONENTIAL SCALING: Increase homing cone and turn speed
			turret_homing_angle_deg += 20.0
			turret_homing_turn_speed = turret_homing_turn_speed * 1.1 + 0.5
			print("  → Turret homing angle +20° (total: %.1f°), turn speed ×1.1 +0.5 (total: %.2f)" % [turret_homing_angle_deg, turret_homing_turn_speed])
		
		"turret_damage":
			# EXPONENTIAL SCALING: Multiply damage by 1.15 per tier
			turret_damage_mult *= GameConfig.UPGRADE_MULTIPLIERS["turret_damage"]
			print("  → Turret damage ×%.2f (total mult: %.2f)" % [GameConfig.UPGRADE_MULTIPLIERS["turret_damage"], turret_damage_mult])

		# ==============================
		# DASH ABILITY EFFECTS
		# ==============================
		"dash_distance":
			# EXPONENTIAL SCALING: Multiply distance multiplier per tier
			dash_distance_bonus_percent *= GameConfig.UPGRADE_MULTIPLIERS["ability_speed"]
			print("  → Dash distance ×%.2f (multiplier now: %.2f)" % [GameConfig.UPGRADE_MULTIPLIERS["ability_speed"], dash_distance_bonus_percent])

		"dash_cooldown":
			# EXPONENTIAL SCALING: Multiply cooldown reduction per tier
			ability_cooldown_mult *= GameConfig.UPGRADE_MULTIPLIERS["ability_cooldown"]
			print("  → Dash cooldown ×%.2f (multiplier now: %.2f)" % [GameConfig.UPGRADE_MULTIPLIERS["ability_cooldown"], ability_cooldown_mult])

		# ==============================
		# SHIELD ABILITY EFFECTS========
		# SHIELD ABILITY EFFECTS
		# ==============================
		"shield_duration":
			# EXPONENTIAL SCALING: Multiply duration by constant per tier
			shield_duration *= GameConfig.UPGRADE_MULTIPLIERS["ability_duration"]
			print("  → Shield duration ×%.2f (now: %.2fs)" % [GameConfig.UPGRADE_MULTIPLIERS["ability_duration"], shield_duration])

		"shield_cooldown":
			# EXPONENTIAL SCALING: Multiply cooldown reduction per tier
			shield_cooldown_mult *= GameConfig.UPGRADE_MULTIPLIERS["ability_cooldown"]
			print("  → Shield cooldown ×%.2f (multiplier now: %.2f)" % [GameConfig.UPGRADE_MULTIPLIERS["ability_cooldown"], shield_cooldown_mult])

		"shield_radius":
			# EXPONENTIAL SCALING: Multiply radius multiplier per tier
			shield_radius_bonus *= GameConfig.UPGRADE_MULTIPLIERS["ability_radius"]
			print("  → Shield radius ×%.2f (multiplier now: %.2f)" % [GameConfig.UPGRADE_MULTIPLIERS["ability_radius"], shield_radius_bonus])

		# ==============================
		# SLOWMO ABILITY EFFECTS
		# ==============================
		"slowmo_duration":
			# EXPONENTIAL SCALING: Multiply duration by constant per tier
			slowmo_duration *= GameConfig.UPGRADE_MULTIPLIERS["ability_duration"]
			print("  → Slowmo duration ×%.2f (now: %.2fs)" % [GameConfig.UPGRADE_MULTIPLIERS["ability_duration"], slowmo_duration])

		"slowmo_cooldown":
			# EXPONENTIAL SCALING: Multiply cooldown reduction per tier
			slowmo_cooldown_mult *= GameConfig.UPGRADE_MULTIPLIERS["ability_cooldown"]
			print("  → Slowmo cooldown ×%.2f (multiplier now: %.2f)" % [GameConfig.UPGRADE_MULTIPLIERS["ability_cooldown"], slowmo_cooldown_mult])

		"slowmo_time_scale":
			# EXPONENTIAL SCALING: Multiply time scale (slower = stronger effect)
			slowmo_time_scale *= 0.90  # 10% slower per tier
			print("  → Slowmo time scale ×0.90 (now: %.2f)" % slowmo_time_scale)

		"slowmo_radius":
			# EXPONENTIAL SCALING: Multiply radius multiplier per tier
			slowmo_radius *= GameConfig.UPGRADE_MULTIPLIERS["ability_radius"]
			print("  → Slowmo radius ×%.2f (now: %.1f)" % [GameConfig.UPGRADE_MULTIPLIERS["ability_radius"], slowmo_radius])

		# ==============================
		# INVIS ABILITY EFFECTS
		# ==============================
		"invis_duration":
			# EXPONENTIAL SCALING: Multiply duration directly by constant per tier
			invis_duration_mult *= GameConfig.UPGRADE_MULTIPLIERS["ability_duration"]
			print("  → Invis duration ×%.2f (multiplier now: %.2f)" % [GameConfig.UPGRADE_MULTIPLIERS["ability_duration"], invis_duration_mult])

		"invis_movement_speed":
			# EXPONENTIAL SCALING: Multiply movement speed by constant per tier
			invis_movement_speed_mult *= GameConfig.UPGRADE_MULTIPLIERS["ability_speed"]
			print("  → Invis movement speed ×%.2f (multiplier now: %.2f)" % [GameConfig.UPGRADE_MULTIPLIERS["ability_speed"], invis_movement_speed_mult])

		# ==============================
		# SYNERGIES
		# ==============================
		"sniper_invis_synergy":
			sniper_invis_synergy_unlocked = true
			synergy_sniper_invis_unlocked = true
			has_sniper_wallpierce_synergy = true  # ⭐ NEW: Actually enable the synergy

		"shield_flamethrower_synergy":
			shield_flamethrower_synergy_unlocked = true
			synergy_flamethrower_bubble_unlocked = true
			has_fireshield_synergy = true  # ⭐ NEW: Actually enable the synergy

		"dash_grenades_synergy":
			dash_grenades_synergy_unlocked = true
			synergy_grenade_dash_unlocked = true
			# ⭐ NEW: Actually enable the synergy with default grenade count
			var grenade_count := int(value) if value > 0 else 3  # Default to 3 grenades
			dash_grenade_synergy_grenades = grenade_count
			has_dash_grenade_synergy = true
			print("  → Dash + Grenades synergy unlocked! (%d grenades per dash)" % grenade_count)

		"dash_grenade_synergy":
			var grenade_count := int(value)
			dash_grenade_synergy_grenades = grenade_count
			has_dash_grenade_synergy = (grenade_count > 0)

		# ==============================
		# NEW SYNERGY UPGRADES
		# ==============================
		"invis_shuriken_synergy":
			has_invis_shuriken_synergy = true

		"turret_slowmo_sprinkler_synergy":
			has_turret_slowmo_sprinkler_synergy = true

		"shotgun_dash_autofire_synergy":
			has_shotgun_dash_autofire_synergy = true

		"shuriken_shield_nova_synergy":
			has_shuriken_bubble_nova_synergy = true

		# ==============================
		# CHAOS CHALLENGES
		# ==============================
		"chaos_challenge":
			# Extract the actual challenge ID from the upgrade_id
			var challenge_id := upgrade_id.replace("chaos_", "")

			start_chaos_challenge(challenge_id)

		_:
			push_warning("[GameState] Unhandled upgrade effect: '%s' (id: %s)" % [effect, upgrade_id])

	# After changing numbers, broadcast signals so UI and systems can refresh
	# Record acquisition (used to prevent re-offering non-stackables)
	_record_acquired_upgrade(upgrade_id)

	_emit_all_signals()


# -------------------------------------------------------------------
# UNLOCK SYSTEM HELPERS
# -------------------------------------------------------------------

func is_weapon_unlocked(weapon_type: int) -> bool:
	"""Check if a weapon type is unlocked."""
	match weapon_type:
		AltWeaponType.SHOTGUN: return unlocked_shotgun
		AltWeaponType.SNIPER: return unlocked_sniper
		AltWeaponType.FLAMETHROWER: return unlocked_flamethrower
		AltWeaponType.GRENADE: return unlocked_grenade
		AltWeaponType.SHURIKEN: return unlocked_shuriken
		AltWeaponType.TURRET: return unlocked_turret
		AltWeaponType.NONE: return true  # NONE is always available
		_: return false

func is_ability_unlocked(ability_type: int) -> bool:
	"""Check if an ability type is unlocked."""
	match ability_type:
		AbilityType.DASH: return unlocked_dash
		AbilityType.SLOWMO: return unlocked_slowmo
		AbilityType.BUBBLE: return unlocked_bubble
		AbilityType.INVIS: return unlocked_invis
		AbilityType.NONE: return true  # NONE is always available
		_: return false

func get_unlocked_weapons() -> Array:
	"""Returns an array of weapon type enums that are currently unlocked."""
	var unlocked := []
	if unlocked_shotgun: unlocked.append(AltWeaponType.SHOTGUN)
	if unlocked_sniper: unlocked.append(AltWeaponType.SNIPER)
	if unlocked_flamethrower: unlocked.append(AltWeaponType.FLAMETHROWER)
	if unlocked_grenade: unlocked.append(AltWeaponType.GRENADE)
	if unlocked_shuriken: unlocked.append(AltWeaponType.SHURIKEN)
	if unlocked_turret: unlocked.append(AltWeaponType.TURRET)
	return unlocked

func get_unlocked_abilities() -> Array:
	"""Returns an array of ability type enums that are currently unlocked."""
	var unlocked := []
	if unlocked_dash: unlocked.append(AbilityType.DASH)
	if unlocked_slowmo: unlocked.append(AbilityType.SLOWMO)
	if unlocked_bubble: unlocked.append(AbilityType.BUBBLE)
	if unlocked_invis: unlocked.append(AbilityType.INVIS)
	return unlocked

# -------------------------------------------------------------------
# CHAOS CHALLENGE SYSTEM (Hades-style challenges)
# -------------------------------------------------------------------

func start_chaos_challenge(challenge_id: String) -> void:
	"""Start a chaos challenge with immediate penalty."""
	active_chaos_challenge = challenge_id
	chaos_challenge_progress = 0
	chaos_challenge_completed = false


	# ⭐ Apply challenge penalty immediately
	match challenge_id:
		"half_hp_double_damage":
			chaos_challenge_target = 5
			original_max_health = max_health
			max_health = int(max_health / 2.0)
			health = int(health / 2.0)
			health = max(health, 1)

			health_changed.emit(health, max_health)
		
		# ⭐ NEW CHAOS PACT 1
		"half_speed_double_speed":
			chaos_challenge_target = 3
			original_move_speed = move_speed
			move_speed = move_speed / 2.0
			move_speed_base = move_speed  # Update base too


			# ⭐ Force update player's actual speed NOW
			var player = get_tree().get_first_node_in_group("player")
			if player and player.has_method("sync_player_stats"):
				player.sync_player_stats()

		# ⬅0 NEW CHAOS PACT 2
		"no_shop_1000_coins":
			chaos_challenge_target = 5
			coin_pickups_disabled = true
			coins = 0  # Reset coins to 0


			coins_changed.emit(coins)
		
		# ⭐ NEW CHAOS PACT 3
		"no_primary_fire_triple_rate":
			chaos_challenge_target = 3
			primary_fire_disabled = true


func increment_chaos_challenge_progress() -> void:
	"""Increment progress towards completing the chaos challenge."""
	if active_chaos_challenge.is_empty():
		return
	
	chaos_challenge_progress += 1

	if chaos_challenge_progress >= chaos_challenge_target:
		_complete_chaos_challenge()


func _complete_chaos_challenge() -> void:
	"""Complete the chaos challenge and grant rewards!"""
	chaos_challenge_completed = true


	# Apply reward based on challenge type
	match active_chaos_challenge:
		"half_hp_double_damage":
			max_health = original_max_health
			health = max_health
			primary_damage_base *= 2.0
			primary_damage = primary_damage_base * (1.0 + primary_damage_bonus)

			health_changed.emit(health, max_health)
		
		# ⭐ NEW COMPLETION 1
		"half_speed_double_speed":
			# Double the ORIGINAL base speed (not current halved speed!)
			move_speed = original_move_speed * 2.0
			move_speed_base = move_speed  # Update base too

			# ⭐ Force update player's actual speed
			var player = get_tree().get_first_node_in_group("player")
			if player and player.has_method("sync_player_stats"):
				player.sync_player_stats()

		# ⬅0 NEW COMPLETION 2
		"no_shop_1000_coins":
			coin_pickups_disabled = false
			coins = 1000  # Set to 1000 directly (not +=)

			print("[GameState] Coins set to 1000! (was:", coins - 1000, ")")
			coins_changed.emit(coins)
		
		# ⬅0 NEW COMPLETION 3
		"no_primary_fire_triple_rate":
			# ⭐ RE-ENABLE primary fire FIRST!
			primary_fire_disabled = false

			# THEN increase fire rate (double it)
			fire_rate_bonus_percent += 1.0  # 100% increase (double fire rate)
			fire_rate = fire_rate_base * max(0.05, 1.0 - fire_rate_bonus_percent)


	# Clear challenge and reset counters
	active_chaos_challenge = ""
	chaos_challenge_progress = 0
	chaos_challenge_target = 0

# -------------------------------------------------------------------
# CHAOS PACT SHUFFLE SYSTEM
# -------------------------------------------------------------------

func _reset_chaos_pact_pool() -> void:
	"""Initialize and shuffle the chaos pact pool."""
	chaos_pact_pool = [
		"half_hp_double_damage",
		"half_speed_double_speed",
		"no_shop_1000_coins",
		"no_primary_fire_triple_rate"
	]
	chaos_pact_pool.shuffle()

func get_next_chaos_pact_id() -> String:
	"""Get next chaos pact from shuffle pool, ensures no duplicates until all seen."""
	# If pool is empty, reset it
	if chaos_pact_pool.is_empty():

		_reset_chaos_pact_pool()
	
	# Get next pact from pool
	var pact_id = chaos_pact_pool.pop_front()

	print("[GameState] Remaining in pool:", chaos_pact_pool.size())
	
	return pact_id

# -------------------------------------------------------------------
# DPS LOGGING (FOR EXPONENTIAL SCALING ANALYSIS)
# -------------------------------------------------------------------

var last_combat_dps: float = 0.0  # Store last calculated DPS for logging

func log_current_dps(level: int) -> void:
	"""Log current DPS stats for exponential curve analysis.
	Call this after level completion, after major upgrades, or periodically during combat."""
	
	# Try to find DPS dummy in scene if available
	var dps_dummy = get_tree().get_first_node_in_group("dps_dummy")
	if dps_dummy and dps_dummy.has_method("get_current_dps"):
		last_combat_dps = dps_dummy.get_current_dps()
		print("[DPS DEBUG] Level %d | Measured DPS=%.2f" % [level, last_combat_dps])
	else:
		# Calculate theoretical DPS from stats if no dummy available
		var theoretical_dps = _calculate_theoretical_dps()
		last_combat_dps = theoretical_dps
		print("[DPS DEBUG] Level %d | Theoretical DPS=%.2f (primary_damage=%.2f, fire_rate=%.3fs)" % [level, theoretical_dps, primary_damage, fire_rate])

func _calculate_theoretical_dps() -> float:
	"""Calculate theoretical DPS from current stats (primary weapon only)."""
	if fire_rate <= 0.0:
		return 0.0
	
	var base_bullet_damage = GameConfig.bullet_base_damage * primary_damage
	var shots_per_second = 1.0 / fire_rate
	return base_bullet_damage * shots_per_second * primary_burst_count

