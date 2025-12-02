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
		"spread_degrees": 30.0, # Fixed per-pellet separation (not total arc)
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
		"bullet_speed": 240.0,
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
	"bullet_speed": 225.0,                # ← ADD THIS (reduced by 75%)
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
	# Cast integer to enum type to avoid INT_AS_ENUM_WITHOUT_CAST
	ability = new_ability as AbilityType

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

# --- Per-line / weapon bonuses (populated by upgrades) ----
var shotgun_pellets_bonus: int = 0
var shotgun_spread_bonus_percent: float = 0.0
var shotgun_knockback_bonus_percent: float = 0.0

var sniper_damage_bonus_percent: float = 0.0
var sniper_pierce_bonus: int = 0
var sniper_charge_bonus_percent: float = 0.0

var flamethrower_lifetime_bonus_percent: float = 0.0
var flamethrower_burn_bonus_percent: float = 0.0
var flamethrower_size_bonus_percent: float = 0.0

var grenade_radius_bonus: float = 0.0
var grenade_fragments_bonus: int = 0
var grenade_damage_bonus_percent: float = 0.0

var shuriken_bounces_bonus: int = 0
var shuriken_speed_bonus_percent: float = 0.0
var shuriken_ricochet_bonus_percent: float = 0.0

var turret_fire_rate_bonus_percent: float = 0.0
var turret_range_bonus_percent: float = 0.0
var turret_bullet_speed_bonus_percent: float = 0.0

# Ability bonuses
var dash_distance_bonus_percent: float = 0.0
var bubble_duration_bonus_percent: float = 0.0
var bubble_duration_bonus_seconds: float = 0.0
var slowmo_time_bonus_seconds: float = 0.0
var invis_duration_bonus_percent: float = 0.0

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

# ⭐ Additional stat fields for CSV-based upgrades
# Primary weapon
var primary_crit_chance: float = 0.0
var primary_reload_speed_bonus: float = 0.0
var primary_ammo_capacity_bonus: int = 0

# Shotgun
var shotgun_reload_speed_bonus: float = 0.0
var shotgun_damage_reduction: float = 0.0

# Sniper
var sniper_crit_damage_bonus: float = 0.0
var sniper_accuracy_bonus: float = 0.0

# Flamethrower
var flamethrower_fuel_efficiency_bonus: float = 0.0
var flamethrower_tick_rate_bonus: float = 0.0

# Grenades
var grenades_cooldown_bonus: float = 0.0
var grenades_status_chance: float = 0.0

# Shuriken
var shuriken_return_enabled: bool = false
var shuriken_crit_chance: float = 0.0

# Turret
var turret_duration_bonus: float = 0.0
var turret_hp_bonus: float = 0.0

# Dash ability
var dash_invuln_window_bonus: float = 0.0
var dash_speed_bonus: float = 0.0
var dash_charges: int = 1

# Shield ability
var shield_hp: float = 100.0
var shield_duration: float = 3.0
var shield_cooldown_mult: float = 1.0
var shield_radius_bonus: float = 0.0
var shield_reflect_chance: float = 0.0

# Slowmo ability
var slowmo_duration: float = 1.5
var slowmo_cooldown_mult: float = 1.0
var slowmo_time_scale: float = 0.3
var slowmo_radius: float = 0.0
var slowmo_ammo_efficiency: float = 0.0

# Invis ability
var invis_fade_speed_bonus: float = 0.0
var invis_movement_speed_bonus: float = 0.0
var invis_first_hit_bonus: float = 0.0

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

	max_ammo   = GameConfig.player_max_ammo
	set_ammo(max_ammo)  # Use setter to emit signal

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

	# reset per-line bonuses
	shotgun_spread_bonus_percent = 0.0
	shotgun_knockback_bonus_percent = 0.0

	sniper_damage_bonus_percent = 0.0
	sniper_pierce_bonus = 0
	sniper_charge_bonus_percent = 0.0

	flamethrower_lifetime_bonus_percent = 0.0
	flamethrower_burn_bonus_percent = 0.0
	flamethrower_size_bonus_percent = 0.0

	grenade_radius_bonus = 0.0
	grenade_fragments_bonus = 0
	grenade_damage_bonus_percent = 0.0

	shuriken_bounces_bonus = 0
	shuriken_speed_bonus_percent = 0.0
	shuriken_ricochet_bonus_percent = 0.0

	turret_fire_rate_bonus_percent = 0.0
	turret_range_bonus_percent = 0.0
	turret_bullet_speed_bonus_percent = 0.0

	dash_distance_bonus_percent = 0.0
	bubble_duration_bonus_percent = 0.0
	bubble_duration_bonus_seconds = 0.0
	slowmo_time_bonus_seconds = 0.0
	invis_duration_bonus_percent = 0.0

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

	# Note: keep `max_ammo` initialized from GameConfig here.
	# The HUD decides whether to show values based on `alt_weapon`.

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
	# If this alt weapon defines a max ammo, update run-time ammo pool.
	# For NONE or TURRET we want the ammo UI to show "-/-", so set to 0.
	if new_alt == AltWeaponType.NONE or new_alt == AltWeaponType.TURRET:
		max_ammo = 0
		set_ammo(0)
	elif ALT_WEAPON_DATA.has(alt_weapon) and ALT_WEAPON_DATA[alt_weapon].has("max_ammo"):
		var m := int(ALT_WEAPON_DATA[alt_weapon].get("max_ammo", GameConfig.player_max_ammo))
		max_ammo = m
		set_ammo(m)
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
	ammo_changed.emit(ammo, max_ammo)
	coins_changed.emit(coins)
	alt_weapon_changed.emit(alt_weapon)
	player_invisible_changed.emit(player_invisible)


func has_upgrade(upgrade_id: String) -> bool:
	return upgrade_id in acquired_upgrades


func _record_acquired_upgrade(upgrade_id: String) -> void:
	if not has_upgrade(upgrade_id):
		acquired_upgrades.append(upgrade_id)
		print("[GameState] Recorded acquired upgrade:", upgrade_id)


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
	print("[GameState] Upgrade '%s' purchased %d times" % [upgrade_id, current_count + 1])


# -------------------------------------------------------------------
# APPLY UPGRADE ENTRYPOINT
# All non-synergy upgrade effects are applied here.
# Keep this function limited to numeric changes of GameState or ALT_WEAPON_DATA
# -------------------------------------------------------------------
func apply_upgrade(upgrade_id: String) -> void:
	print("[GameState] Applying upgrade:", upgrade_id)

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
					print("  → Unlocked and equipped weapon: shotgun")
				"sniper":
					unlocked_sniper = true
					set_alt_weapon(AltWeaponType.SNIPER)
					print("  → Unlocked and equipped weapon: sniper")
				"flamethrower":
					unlocked_flamethrower = true
					set_alt_weapon(AltWeaponType.FLAMETHROWER)
					print("  → Unlocked and equipped weapon: flamethrower")
				"grenade":
					unlocked_grenade = true
					set_alt_weapon(AltWeaponType.GRENADE)
					print("  → Unlocked and equipped weapon: grenade")
				"shuriken":
					unlocked_shuriken = true
					set_alt_weapon(AltWeaponType.SHURIKEN)
					print("  → Unlocked and equipped weapon: shuriken")
				"turret":
					unlocked_turret = true
					set_alt_weapon(AltWeaponType.TURRET)
					print("  → Unlocked and equipped weapon: turret")
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
					print("  → Unlocked and equipped ability: dash")
				"slowmo":
					unlocked_slowmo = true
					set_ability(AbilityType.SLOWMO)
					print("  → Unlocked and equipped ability: slowmo")
				"bubble":
					unlocked_bubble = true
					set_ability(AbilityType.BUBBLE)
					print("  → Unlocked and equipped ability: bubble")
				"invis":
					unlocked_invis = true
					set_ability(AbilityType.INVIS)
					print("  → Unlocked and equipped ability: invis")
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
			set_health(min(max_health, health + inc))
			print("  → Max HP +%d, now: %d" % [inc, max_health])

		"hp_refill":
			set_health(max_health)
			print("  → HP refilled to:", max_health)

		"max_ammo":
			var inc := int(value)
			max_ammo += inc
			set_ammo(min(max_ammo, ammo + inc))
			print("  → Max Ammo +%d, now: %d" % [inc, max_ammo])

		"ammo_refill":
			set_ammo(max_ammo)
			print("  → Ammo refilled to:", max_ammo)

		"ability_cooldown":
			ability_cooldown_mult *= (1.0 + value)
			print("  → Ability cooldown mult: %.2f" % ability_cooldown_mult)

		# ==============================
		# WEAPON / ABILITY UNLOCKS (LEGACY EFFECT-BASED)
		# ==============================
		# These are the old hardcoded unlock effects
		# They set the unlock flag AND auto-equip for backwards compatibility
		"unlock_shotgun":
			unlocked_shotgun = true
			set_alt_weapon(AltWeaponType.SHOTGUN)
			print("  → Shotgun unlocked and equipped")

		"unlock_sniper":
			unlocked_sniper = true
			set_alt_weapon(AltWeaponType.SNIPER)
			print("  → Sniper unlocked and equipped")

		"unlock_turret":
			unlocked_turret = true
			set_alt_weapon(AltWeaponType.TURRET)
			print("  → Turret unlocked and equipped")

		"unlock_flamethrower":
			unlocked_flamethrower = true
			set_alt_weapon(AltWeaponType.FLAMETHROWER)
			print("  → Flamethrower unlocked and equipped")

		"unlock_shuriken":
			unlocked_shuriken = true
			set_alt_weapon(AltWeaponType.SHURIKEN)
			print("  → Shuriken unlocked and equipped")

		"unlock_grenade":
			unlocked_grenade = true
			set_alt_weapon(AltWeaponType.GRENADE)
			print("  → Grenade unlocked and equipped")

		# Ability unlocks
		"unlock_dash":
			unlocked_dash = true
			set_ability(AbilityType.DASH)
			print("  → Dash ability unlocked and equipped")

		"unlock_slowmo":
			unlocked_slowmo = true
			set_ability(AbilityType.SLOWMO)
			print("  → Slowmo ability unlocked and equipped")

		"unlock_bubble":
			unlocked_bubble = true
			set_ability(AbilityType.BUBBLE)
			print("  → Bubble ability unlocked and equipped")

		"unlock_invis":
			unlocked_invis = true
			set_ability(AbilityType.INVIS)
			print("  → Invis ability unlocked and equipped")

		# ==============================
		# PRIMARY WEAPON EFFECTS
		# ==============================
		"primary_damage":
			primary_damage_bonus += value
			primary_damage = primary_damage_base * (1.0 + primary_damage_bonus)
			print("  → Primary damage +%.1f%%, total: +%.1f%%" % [value * 100, primary_damage_bonus * 100])

		"primary_fire_rate":
			fire_rate_bonus_percent += value
			# Linear cooldown reduction: each upgrade reduces by the same absolute amount
			fire_rate = fire_rate_base - (fire_rate_base * fire_rate_bonus_percent)
			fire_rate = max(0.05, fire_rate)  # Cap at minimum cooldown
			print("  → Fire rate +%.1f%%, cooldown: %.2fs" % [value * 100, fire_rate])

		"primary_reload_speed":
			primary_reload_speed_bonus += value
			print("  → Reload speed +%.1f%%" % [value * 100])

		"primary_ammo_capacity":
			var inc := int(value)
			primary_ammo_capacity_bonus += inc
			print("  → Ammo capacity +%d" % inc)

		"primary_crit_chance":
			primary_crit_chance += value
			print("  → Crit chance +%.1f%%" % [value * 100])

		# ==============================
		# SHOTGUN EFFECTS
		# ==============================
		"shotgun_pellets":
			var inc := int(value)
			if ALT_WEAPON_DATA.has(AltWeaponType.SHOTGUN):
				ALT_WEAPON_DATA[AltWeaponType.SHOTGUN]["pellets"] += inc
				print("  → Shotgun pellets +%d, now: %d" % [inc, ALT_WEAPON_DATA[AltWeaponType.SHOTGUN]["pellets"]])

		"shotgun_spread":
			shotgun_spread_bonus_percent += value
			if ALT_WEAPON_DATA.has(AltWeaponType.SHOTGUN):
				ALT_WEAPON_DATA[AltWeaponType.SHOTGUN]["spread_degrees"] = 18.0 * (1.0 + shotgun_spread_bonus_percent)
				print("  → Shotgun spread %.1f%%, now: %.1f°" % [value * 100, ALT_WEAPON_DATA[AltWeaponType.SHOTGUN]["spread_degrees"]])

		"shotgun_knockback":
			shotgun_knockback_bonus_percent += value
			if ALT_WEAPON_DATA.has(AltWeaponType.SHOTGUN):
				ALT_WEAPON_DATA[AltWeaponType.SHOTGUN]["recoil"] = 140.0 * (1.0 + shotgun_knockback_bonus_percent)
				print("  → Shotgun knockback +%.1f%%, now: %.1f" % [value * 100, ALT_WEAPON_DATA[AltWeaponType.SHOTGUN]["recoil"]])

		"shotgun_reload_speed":
			shotgun_reload_speed_bonus += value
			print("  → Shotgun reload speed +%.1f%%" % [value * 100])

		"shotgun_damage_reduction":
			shotgun_damage_reduction += value
			print("  → Shotgun self-damage reduction +%.1f%%" % [value * 100])

		# ==============================
		# SNIPER EFFECTS
		# ==============================
		"sniper_damage":
			sniper_damage_bonus_percent += value
			if ALT_WEAPON_DATA.has(AltWeaponType.SNIPER):
				ALT_WEAPON_DATA[AltWeaponType.SNIPER]["damage"] = 35.0 * (1.0 + sniper_damage_bonus_percent + sniper_charge_bonus_percent)
				print("  → Sniper damage +%.1f%%, now: %.1f" % [value * 100, ALT_WEAPON_DATA[AltWeaponType.SNIPER]["damage"]])

		"sniper_pierce":
			var inc := int(value)
			if ALT_WEAPON_DATA.has(AltWeaponType.SNIPER):
				ALT_WEAPON_DATA[AltWeaponType.SNIPER]["bounces"] += inc
				print("  → Sniper pierce +%d, now: %d" % [inc, ALT_WEAPON_DATA[AltWeaponType.SNIPER]["bounces"]])

		"sniper_charge_speed":
			sniper_charge_bonus_percent += value
			if ALT_WEAPON_DATA.has(AltWeaponType.SNIPER):
				ALT_WEAPON_DATA[AltWeaponType.SNIPER]["damage"] = 35.0 * (1.0 + sniper_damage_bonus_percent + sniper_charge_bonus_percent)
				print("  → Sniper charge +%.1f%%, dmg: %.1f" % [value * 100, ALT_WEAPON_DATA[AltWeaponType.SNIPER]["damage"]])

		"sniper_crit_damage":
			sniper_crit_damage_bonus += value
			print("  → Sniper crit damage +%.1f%%" % [value * 100])

		"sniper_accuracy":
			sniper_accuracy_bonus += value
			print("  → Sniper accuracy +%.1f%%" % [value * 100])

		# ==============================
		# FLAMETHROWER EFFECTS
		# ==============================
		"flamethrower_burn_damage":
			flamethrower_burn_bonus_percent += value
			print("  → Flamethrower burn +%.1f%%" % [value * 100])

		"flamethrower_cone_size":
			flamethrower_size_bonus_percent += value
			if ALT_WEAPON_DATA.has(AltWeaponType.FLAMETHROWER):
				ALT_WEAPON_DATA[AltWeaponType.FLAMETHROWER]["damage"] = 4.0 * (1.0 + flamethrower_size_bonus_percent)
				print("  → Flamethrower cone +%.1f%%" % [value * 100])

		"flamethrower_duration":
			flamethrower_lifetime_bonus_percent += value
			if ALT_WEAPON_DATA.has(AltWeaponType.FLAMETHROWER):
				ALT_WEAPON_DATA[AltWeaponType.FLAMETHROWER]["flame_lifetime"] = 0.25 * (1.0 + flamethrower_lifetime_bonus_percent)
				print("  → Flamethrower duration +%.1f%%, now: %.2fs" % [value * 100, ALT_WEAPON_DATA[AltWeaponType.FLAMETHROWER]["flame_lifetime"]])

		"flamethrower_fuel_efficiency":
			flamethrower_fuel_efficiency_bonus += value
			print("  → Flamethrower fuel efficiency +%.1f%%" % [value * 100])

		"flamethrower_tick_rate":
			flamethrower_tick_rate_bonus += value
			print("  → Flamethrower tick rate +%.1f%%" % [value * 100])

		# ==============================
		# GRENADES EFFECTS
		# ==============================
		"grenades_radius":
			var inc := value
			if ALT_WEAPON_DATA.has(AltWeaponType.GRENADE):
				ALT_WEAPON_DATA[AltWeaponType.GRENADE]["explosion_radius"] += inc
				print("  → Grenade radius +%.0f, now: %.0f" % [inc, ALT_WEAPON_DATA[AltWeaponType.GRENADE]["explosion_radius"]])

		"grenades_damage":
			grenade_damage_bonus_percent += value
			if ALT_WEAPON_DATA.has(AltWeaponType.GRENADE):
				ALT_WEAPON_DATA[AltWeaponType.GRENADE]["damage"] = 40.0 * (1.0 + grenade_damage_bonus_percent)
				print("  → Grenade damage +%.1f%%, now: %.1f" % [value * 100, ALT_WEAPON_DATA[AltWeaponType.GRENADE]["damage"]])

		"grenades_cooldown":
			grenades_cooldown_bonus += value
			if ALT_WEAPON_DATA.has(AltWeaponType.GRENADE):
				ALT_WEAPON_DATA[AltWeaponType.GRENADE]["cooldown"] *= (1.0 + value)
				print("  → Grenade cooldown %.1f%%" % [value * 100])

		"grenades_frag_count":
			var inc := int(value)
			if ALT_WEAPON_DATA.has(AltWeaponType.GRENADE):
				ALT_WEAPON_DATA[AltWeaponType.GRENADE]["pellets"] += inc
				print("  → Grenade frags +%d, now: %d" % [inc, ALT_WEAPON_DATA[AltWeaponType.GRENADE]["pellets"]])

		"grenades_status_chance":
			grenades_status_chance += value
			print("  → Grenade status chance +%.1f%%" % [value * 100])

		# ==============================
		# SHURIKEN EFFECTS
		# ==============================
		"shuriken_bounce_count":
			var inc := int(value)
			if ALT_WEAPON_DATA.has(AltWeaponType.SHURIKEN):
				ALT_WEAPON_DATA[AltWeaponType.SHURIKEN]["bounces"] += inc
				print("  → Shuriken bounces +%d, now: %d" % [inc, ALT_WEAPON_DATA[AltWeaponType.SHURIKEN]["bounces"]])

		"shuriken_speed":
			shuriken_speed_bonus_percent += value
			if ALT_WEAPON_DATA.has(AltWeaponType.SHURIKEN):
				ALT_WEAPON_DATA[AltWeaponType.SHURIKEN]["bullet_speed"] = 950.0 * (1.0 + shuriken_speed_bonus_percent)
				print("  → Shuriken speed +%.1f%%, now: %.0f" % [value * 100, ALT_WEAPON_DATA[AltWeaponType.SHURIKEN]["bullet_speed"]])

		"shuriken_pierce":
			shuriken_ricochet_bonus_percent += value
			if ALT_WEAPON_DATA.has(AltWeaponType.SHURIKEN):
				ALT_WEAPON_DATA[AltWeaponType.SHURIKEN]["damage"] = 12.0 * (1.0 + shuriken_ricochet_bonus_percent)
				print("  → Shuriken pierce +%.1f%%" % [value * 100])

		"shuriken_return":
			shuriken_return_enabled = true
			print("  → Shuriken return enabled")

		"shuriken_crit_chance":
			shuriken_crit_chance += value
			print("  → Shuriken crit chance +%.1f%%" % [value * 100])

		# ==============================
		# TURRET EFFECTS
		# ==============================
		"turret_fire_rate":
			turret_fire_rate_bonus_percent += value
			if ALT_WEAPON_DATA.has(AltWeaponType.TURRET):
				ALT_WEAPON_DATA[AltWeaponType.TURRET]["fire_rate"] = 0.4 * (1.0 - turret_fire_rate_bonus_percent)
				print("  → Turret fire rate +%.1f%%, cooldown: %.2fs" % [value * 100, ALT_WEAPON_DATA[AltWeaponType.TURRET]["fire_rate"]])

		"turret_range":
			turret_range_bonus_percent += value
			if ALT_WEAPON_DATA.has(AltWeaponType.TURRET):
				ALT_WEAPON_DATA[AltWeaponType.TURRET]["range"] = 220.0 * (1.0 + turret_range_bonus_percent)
				print("  → Turret range +%.1f%%, now: %.0f" % [value * 100, ALT_WEAPON_DATA[AltWeaponType.TURRET]["range"]])

		"turret_duration":
			turret_duration_bonus += value
			print("  → Turret duration +%.1fs" % value)

		"turret_hp":
			turret_hp_bonus += value
			print("  → Turret HP +%.0f" % value)

		"turret_bullet_speed":
			turret_bullet_speed_bonus_percent += value
			if ALT_WEAPON_DATA.has(AltWeaponType.TURRET):
				ALT_WEAPON_DATA[AltWeaponType.TURRET]["bullet_speed"] = 900.0 * (1.0 + turret_bullet_speed_bonus_percent)
				print("  → Turret bullet speed +%.1f%%, now: %.0f" % [value * 100, ALT_WEAPON_DATA[AltWeaponType.TURRET]["bullet_speed"]])

		# ==============================
		# DASH ABILITY EFFECTS
		# ==============================
		"dash_distance":
			dash_distance_bonus_percent += value
			print("  → Dash distance +%.1f%%" % [value * 100])

		"dash_cooldown":
			ability_cooldown_mult *= (1.0 + value)
			print("  → Dash cooldown %.1f%%" % [value * 100])

		"dash_invuln_window":
			dash_invuln_window_bonus += value
			print("  → Dash invuln window +%.2fs" % value)

		"dash_speed":
			dash_speed_bonus += value
			print("  → Dash speed +%.1f%%" % [value * 100])

		"dash_charges":
			dash_charges += int(value)
			print("  → Dash charges now: %d" % dash_charges)

		# ==============================
		# SHIELD ABILITY EFFECTS
		# ==============================
		"shield_hp":
			shield_hp += value
			print("  → Shield HP now: %.0f" % shield_hp)

		"shield_duration":
			shield_duration += value
			print("  → Shield duration now: %.1fs" % shield_duration)

		"shield_cooldown":
			shield_cooldown_mult *= (1.0 + value)
			print("  → Shield cooldown %.1f%%" % [value * 100])

		"shield_radius":
			shield_radius_bonus += value
			print("  → Shield radius +%.1f%%" % [value * 100])

		"shield_reflect_chance":
			shield_reflect_chance += value
			print("  → Shield reflect chance +%.1f%%" % [value * 100])

		# ==============================
		# SLOWMO ABILITY EFFECTS
		# ==============================
		"slowmo_duration":
			slowmo_duration += value
			print("  → Slowmo duration now: %.1fs" % slowmo_duration)

		"slowmo_cooldown":
			slowmo_cooldown_mult *= (1.0 + value)
			print("  → Slowmo cooldown %.1f%%" % [value * 100])

		"slowmo_time_scale":
			slowmo_time_scale *= (1.0 + value)
			print("  → Slowmo time scale now: %.2f" % slowmo_time_scale)

		"slowmo_radius":
			slowmo_radius += value
			print("  → Slowmo radius now: %.0f" % slowmo_radius)

		"slowmo_ammo_efficiency":
			slowmo_ammo_efficiency += value
			print("  → Slowmo ammo efficiency +%.1f%%" % [value * 100])

		# ==============================
		# INVIS ABILITY EFFECTS
		# ==============================
		"invis_duration":
			invis_duration_bonus_percent += value
			print("  → Invis duration +%.1f%%" % [value * 100])

		"invis_cooldown":
			ability_cooldown_mult *= (1.0 + value)
			print("  → Invis cooldown %.1f%%" % [value * 100])

		"invis_fade_speed":
			invis_fade_speed_bonus += value
			print("  → Invis fade speed +%.1f%%" % [value * 100])

		"invis_movement_speed":
			invis_movement_speed_bonus += value
			print("  → Invis movement speed +%.1f%%" % [value * 100])

		"invis_first_hit_bonus":
			invis_first_hit_bonus += value
			print("  → Invis first hit bonus +%.1f%%" % [value * 100])

		# ==============================
		# SYNERGIES
		# ==============================
		"sniper_invis_synergy":
			sniper_invis_synergy_unlocked = true
			synergy_sniper_invis_unlocked = true
			has_sniper_wallpierce_synergy = true  # ⭐ NEW: Actually enable the synergy
			print("  → Sniper + Invis synergy unlocked!")

		"shield_flamethrower_synergy":
			shield_flamethrower_synergy_unlocked = true
			synergy_flamethrower_bubble_unlocked = true
			has_fireshield_synergy = true  # ⭐ NEW: Actually enable the synergy
			print("  → Shield + Flamethrower synergy unlocked!")

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
			print("  → Dash + Grenade synergy: %d grenades per dash" % grenade_count)

		# ==============================
		# NEW SYNERGY UPGRADES
		# ==============================
		"invis_shuriken_synergy":
			has_invis_shuriken_synergy = true
			print("  → Invis + Shuriken synergy: Can shoot shuriken while invisible!")

		"turret_slowmo_sprinkler_synergy":
			has_turret_slowmo_sprinkler_synergy = true
			print("  → Turret + Slowmo synergy: Turret fires 360° burst on slowmo!")

		"shotgun_dash_autofire_synergy":
			has_shotgun_dash_autofire_synergy = true
			print("  → Shotgun + Dash synergy: Auto-fire shotgun on dash end!")

		"shuriken_shield_nova_synergy":
			has_shuriken_bubble_nova_synergy = true
			print("  → Shuriken + Bubble synergy: Bubble spawns shuriken nova!")

		# ==============================
		# CHAOS CHALLENGES
		# ==============================
		"chaos_challenge":
			# Extract the actual challenge ID from the upgrade_id
			var challenge_id := upgrade_id.replace("chaos_", "")
			print("  → Starting chaos challenge:", challenge_id)
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
	
	print("[GameState] ========================================")
	print("[GameState] STARTING CHAOS CHALLENGE:", challenge_id)
	print("[GameState] ========================================")
	
	# ⭐ Apply challenge penalty immediately
	match challenge_id:
		"half_hp_double_damage":
			chaos_challenge_target = 5
			original_max_health = max_health
			max_health = int(max_health / 2.0)
			health = int(health / 2.0)
			health = max(health, 1)
			print("[GameState] Max HP halved! Survive 5 rooms for 2x damage!")
			health_changed.emit(health, max_health)
		
		# ⭐ NEW CHAOS PACT 1
		"half_speed_double_speed":
			chaos_challenge_target = 3
			original_move_speed = move_speed
			move_speed = move_speed / 2.0
			move_speed_base = move_speed  # Update base too
			print("[GameState] Move speed halved! Original:", original_move_speed, "New:", move_speed)
			print("[GameState] Survive 3 rooms to DOUBLE base move speed!")
			# ⭐ Force update player's actual speed NOW
			var player = get_tree().get_first_node_in_group("player")
			if player and player.has_method("sync_player_stats"):
				player.sync_player_stats()
				print("[GameState] Player speed synced to:", player.speed)
		
		# ⬅0 NEW CHAOS PACT 2
		"no_shop_1000_coins":
			chaos_challenge_target = 5
			coin_pickups_disabled = true
			coins = 0  # Reset coins to 0
			print("[GameState] Coin pickups DISABLED! Coins set to 0!")
			print("[GameState] Survive 5 rooms to gain 1000 coins!")
			coins_changed.emit(coins)
		
		# ⭐ NEW CHAOS PACT 3
		"no_primary_fire_triple_rate":
			chaos_challenge_target = 3
			primary_fire_disabled = true
			print("[GameState] Primary fire DISABLED!")
			print("[GameState] Survive 3 rooms to DOUBLE your fire rate!")
	
	print("[GameState] Target rooms:", chaos_challenge_target)
	print("[GameState] Challenge state after start:")
	print("[GameState] - move_speed:", move_speed)
	print("[GameState] - coin_pickups_disabled:", coin_pickups_disabled)
	print("[GameState] - primary_fire_disabled:", primary_fire_disabled)
	print("[GameState] - coins:", coins)
	print("[GameState] ========================================")


func increment_chaos_challenge_progress() -> void:
	"""Increment progress towards completing the chaos challenge."""
	if active_chaos_challenge.is_empty():
		return
	
	chaos_challenge_progress += 1
	
	print("[GameState] Chaos challenge progress: ", chaos_challenge_progress, "/", chaos_challenge_target)
	
	if chaos_challenge_progress >= chaos_challenge_target:
		_complete_chaos_challenge()


func _complete_chaos_challenge() -> void:
	"""Complete the chaos challenge and grant rewards!"""
	chaos_challenge_completed = true
	
	print("[GameState] ========================================")
	print("[GameState] COMPLETING CHAOS CHALLENGE:", active_chaos_challenge)
	print("[GameState] ========================================")
	
	# Apply reward based on challenge type
	match active_chaos_challenge:
		"half_hp_double_damage":
			max_health = original_max_health
			health = max_health
			primary_damage_base *= 2.0
			primary_damage = primary_damage_base * (1.0 + primary_damage_bonus)
			print("[GameState] Max HP restored! Damage DOUBLED!")
			health_changed.emit(health, max_health)
		
		# ⭐ NEW COMPLETION 1
		"half_speed_double_speed":
			# Double the ORIGINAL base speed (not current halved speed!)
			move_speed = original_move_speed * 2.0
			move_speed_base = move_speed  # Update base too
			print("[GameState] Move speed DOUBLED! New speed:", move_speed)
			# ⭐ Force update player's actual speed
			var player = get_tree().get_first_node_in_group("player")
			if player and player.has_method("sync_player_stats"):
				player.sync_player_stats()
				print("[GameState] Updated player's speed variable to:", player.speed)
		
		# ⬅0 NEW COMPLETION 2
		"no_shop_1000_coins":
			coin_pickups_disabled = false
			coins = 1000  # Set to 1000 directly (not +=)
			print("[GameState] Coin pickups RE-ENABLED!")
			print("[GameState] Coins set to 1000! (was:", coins - 1000, ")")
			coins_changed.emit(coins)
		
		# ⬅0 NEW COMPLETION 3
		"no_primary_fire_triple_rate":
			# ⭐ RE-ENABLE primary fire FIRST!
			primary_fire_disabled = false
			print("[GameState] ✅ PRIMARY FIRE RE-ENABLED! Flag set to: ", primary_fire_disabled)
			# THEN increase fire rate (double it)
			fire_rate_bonus_percent += 1.0  # 100% increase (double fire rate)
			fire_rate = fire_rate_base * max(0.05, 1.0 - fire_rate_bonus_percent)
			print("[GameState] Fire rate DOUBLED! New rate:", fire_rate)
	
	print("[GameState] Challenge state after completion:")
	print("[GameState] - move_speed:", move_speed)
	print("[GameState] - coin_pickups_disabled:", coin_pickups_disabled)
	print("[GameState] - primary_fire_disabled:", primary_fire_disabled)
	print("[GameState] - coins:", coins)
	print("[GameState] - fire_rate:", fire_rate)
	print("[GameState] ========================================")
	
	# Clear challenge and reset counters
	active_chaos_challenge = ""
	chaos_challenge_progress = 0
	chaos_challenge_target = 0
	
	print("[GameState] Chaos challenge cleared and counters reset")


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
	
	print("[GameState] Chaos pact pool initialized and shuffled:", chaos_pact_pool)


func get_next_chaos_pact_id() -> String:
	"""Get next chaos pact from shuffle pool, ensures no duplicates until all seen."""
	# If pool is empty, reset it
	if chaos_pact_pool.is_empty():
		print("[GameState] Chaos pool empty, reshuffling all pacts!")
		_reset_chaos_pact_pool()
	
	# Get next pact from pool
	var pact_id = chaos_pact_pool.pop_front()
	
	print("[GameState] Selected chaos pact:", pact_id)
	print("[GameState] Remaining in pool:", chaos_pact_pool.size())
	
	return pact_id
