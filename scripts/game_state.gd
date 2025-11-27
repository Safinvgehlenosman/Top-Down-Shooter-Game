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

# Synergy flags (data-only placeholders for later wiring)
var synergy_flamethrower_bubble_unlocked: bool = false
var synergy_grenade_dash_unlocked: bool = false
var synergy_shuriken_slowmo_unlocked: bool = false
var synergy_sniper_invis_unlocked: bool = false
var synergy_turret_bubble_unlocked: bool = false

# economy
var coins: int = 0

# Bonus seconds added to the Shield Bubble ability duration by upgrades
var ability_bubble_duration_bonus: float = 0.0

# Acquired upgrades (records purchase history). Used to prevent re-offering
# non-stackable upgrades and to query ownership.
var acquired_upgrades: Array = []

# Track how many times each upgrade has been purchased this run (for price scaling)
var upgrade_purchase_counts: Dictionary = {}


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

	coins            = 0
	player_invisible = false
	upgrade_purchase_counts.clear()

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


func has_upgrade(upgrade_id: String) -> bool:
	return upgrade_id in acquired_upgrades


func _record_acquired_upgrade(upgrade_id: String) -> void:
	if not has_upgrade(upgrade_id):
		acquired_upgrades.append(upgrade_id)
		print("[GameState] Recorded acquired upgrade:", upgrade_id)


func get_upgrade_price(upgrade_id: String, base_price: int) -> int:
	"""Calculate scaled price based on how many times this upgrade has been purchased."""
	var times_purchased: int = upgrade_purchase_counts.get(upgrade_id, 0)
	var scaled_price: float = float(base_price) * (1.0 + 0.2 * float(times_purchased))
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

	# Prevent re-applying non-stackable upgrades
	var u := preload("res://scripts/Upgrades_DB.gd").get_by_id(upgrade_id)
	if not u.is_empty():
		var stackable := bool(u.get("stackable", true))
		if not stackable and has_upgrade(upgrade_id):
			push_warning("[GameState] Upgrade already owned and not stackable: %s" % upgrade_id)
			return

	match upgrade_id:
		# GENERAL / CORE
		"max_hp_plus_1":
			# Scaled max HP increase: base 10, each repeat multiplies by 1.5
			var purchases: int = int(upgrade_purchase_counts.get("max_hp_plus_1", 1))
			var base_increase := 10.0
			var scaled_increase := base_increase * pow(1.5, purchases - 1)
			var inc_int := int(round(scaled_increase))
			max_health += inc_int
			# Heal by same amount (do not exceed new max)
			set_health(min(max_health, health + inc_int))
			print("  → Max HP increase applied:", inc_int, "(purchase #", purchases, ")")
			print("  → Max HP now:", max_health)

		"hp_refill":
			set_health(max_health)
			print("  → HP refilled to:", max_health)

		"max_ammo_plus_1":
			# Scaled max ammo increase: base 1, doubles each purchase (1,2,4,8,...)
			var purchases_ammo: int = int(upgrade_purchase_counts.get("max_ammo_plus_1", 1))
			var base_ammo_inc := 1
			var scaled_ammo_inc := int(pow(2, purchases_ammo - 1)) * base_ammo_inc
			max_ammo += scaled_ammo_inc
			set_ammo(min(max_ammo, ammo + scaled_ammo_inc))
			print("  → Max Ammo increase applied:", scaled_ammo_inc, "(purchase #", purchases_ammo, ")")
			print("  → Max Ammo now:", max_ammo)

		"ammo_refill":
			set_ammo(max_ammo)
			print("  → Ammo refilled to:", max_ammo)

		"ability_cooldown_minus_10":
			ability_cooldown_mult *= 0.9
			var reduction_percent = int((1.0 - ability_cooldown_mult) * 100)
			print("  → Ability cooldown multiplier:", ability_cooldown_mult)
			print("  → Total reduction:", reduction_percent, "%")

		# PRIMARY

		# UNLOCKS (shop buys should call these)
		"unlock_shotgun":
			set_alt_weapon(AltWeaponType.SHOTGUN)
			print("  → Shotgun unlocked")

		"unlock_sniper":
			set_alt_weapon(AltWeaponType.SNIPER)
			print("  → Sniper unlocked")

		"unlock_turret":
			set_alt_weapon(AltWeaponType.TURRET)
			print("  → Turret unlocked")

		"unlock_flamethrower":
			set_alt_weapon(AltWeaponType.FLAMETHROWER)
			print("  → Flamethrower unlocked")

		"unlock_shuriken":
			set_alt_weapon(AltWeaponType.SHURIKEN)
			print("  → Shuriken unlocked")

		"unlock_grenade":
			set_alt_weapon(AltWeaponType.GRENADE)
			print("  → Grenade unlocked")

		# Ability unlocks
		"unlock_dash":
			set_ability(AbilityType.DASH)
			print("  → Dash ability unlocked")

		"unlock_slowmo":
			set_ability(AbilityType.SLOWMO)
			print("  → Slowmo ability unlocked")

		"unlock_bubble":
			set_ability(AbilityType.BUBBLE)
			print("  → Bubble ability unlocked")

		"unlock_invis":
			set_ability(AbilityType.INVIS)
			print("  → Invis ability unlocked")

		"primary_damage_common":
			primary_damage_bonus += 0.05
			primary_damage = primary_damage_base * (1.0 + primary_damage_bonus)
			print("  → Primary damage bonus:", primary_damage_bonus)

		"primary_damage_uncommon":
			primary_damage_bonus += 0.10
			primary_damage = primary_damage_base * (1.0 + primary_damage_bonus)
			print("  → Primary damage bonus:", primary_damage_bonus)

		"primary_damage_rare":
			primary_damage_bonus += 0.15
			primary_damage = primary_damage_base * (1.0 + primary_damage_bonus)
			print("  → Primary damage bonus:", primary_damage_bonus)

		"primary_fire_rate_uncommon":
			fire_rate_bonus_percent += 0.05
			fire_rate = fire_rate_base * max(0.05, 1.0 - fire_rate_bonus_percent)
			print("  → Fire rate (cooldown) now:", fire_rate)

		"primary_fire_rate_rare":
			fire_rate_bonus_percent += 0.10
			fire_rate = fire_rate_base * max(0.05, 1.0 - fire_rate_bonus_percent)
			print("  → Fire rate (cooldown) now:", fire_rate)

		"primary_bullet_size_rare":
			# Increase primary bullet visual size at spawn
			primary_bullet_size_multiplier *= 1.25
			print("  → Primary bullet size multiplier now:", primary_bullet_size_multiplier)

		"primary_bullet_size_epic":
			# Larger increase for epic
			primary_bullet_size_multiplier *= 1.5
			print("  → Primary bullet size multiplier now:", primary_bullet_size_multiplier)

		# PRIMARY burst shot (existing id)
		"primary_burst_plus_1":
			primary_burst_count += 1
			print("  → Primary burst count now:", primary_burst_count)

		# ALT WEAPON TWEAKS (modify ALT_WEAPON_DATA where sensible)
		"shotgun_pellets_common":
			if ALT_WEAPON_DATA.has(AltWeaponType.SHOTGUN) and ALT_WEAPON_DATA[AltWeaponType.SHOTGUN].has("pellets"):
				ALT_WEAPON_DATA[AltWeaponType.SHOTGUN]["pellets"] = int(ALT_WEAPON_DATA[AltWeaponType.SHOTGUN].get("pellets", 0) + 1)
			print("  → Shotgun pellets:", ALT_WEAPON_DATA[AltWeaponType.SHOTGUN].get("pellets"))

		"shotgun_pellets_uncommon":
			if ALT_WEAPON_DATA.has(AltWeaponType.SHOTGUN) and ALT_WEAPON_DATA[AltWeaponType.SHOTGUN].has("pellets"):
				ALT_WEAPON_DATA[AltWeaponType.SHOTGUN]["pellets"] = int(ALT_WEAPON_DATA[AltWeaponType.SHOTGUN].get("pellets", 0) + 2)
			print("  → Shotgun pellets:", ALT_WEAPON_DATA[AltWeaponType.SHOTGUN].get("pellets"))

		"shotgun_pellets_rare":
			if ALT_WEAPON_DATA.has(AltWeaponType.SHOTGUN) and ALT_WEAPON_DATA[AltWeaponType.SHOTGUN].has("pellets"):
				ALT_WEAPON_DATA[AltWeaponType.SHOTGUN]["pellets"] = int(ALT_WEAPON_DATA[AltWeaponType.SHOTGUN].get("pellets", 0) + 3)
			print("  → Shotgun pellets:", ALT_WEAPON_DATA[AltWeaponType.SHOTGUN].get("pellets"))

		"shotgun_spread_uncommon":
			if ALT_WEAPON_DATA.has(AltWeaponType.SHOTGUN) and ALT_WEAPON_DATA[AltWeaponType.SHOTGUN].has("spread_degrees"):
				ALT_WEAPON_DATA[AltWeaponType.SHOTGUN]["spread_degrees"] = float(ALT_WEAPON_DATA[AltWeaponType.SHOTGUN].get("spread_degrees", 0.0) * 0.95)
			print("  → Shotgun spread now:", ALT_WEAPON_DATA[AltWeaponType.SHOTGUN].get("spread_degrees"))

		"shotgun_spread_rare":
			if ALT_WEAPON_DATA.has(AltWeaponType.SHOTGUN) and ALT_WEAPON_DATA[AltWeaponType.SHOTGUN].has("spread_degrees"):
				ALT_WEAPON_DATA[AltWeaponType.SHOTGUN]["spread_degrees"] = float(ALT_WEAPON_DATA[AltWeaponType.SHOTGUN].get("spread_degrees", 0.0) * 0.90)
			print("  → Shotgun spread now:", ALT_WEAPON_DATA[AltWeaponType.SHOTGUN].get("spread_degrees"))

		"shotgun_knockback_rare":
			if ALT_WEAPON_DATA.has(AltWeaponType.SHOTGUN) and ALT_WEAPON_DATA[AltWeaponType.SHOTGUN].has("recoil"):
				ALT_WEAPON_DATA[AltWeaponType.SHOTGUN]["recoil"] = float(ALT_WEAPON_DATA[AltWeaponType.SHOTGUN].get("recoil", 0.0) * 1.10)
			print("  → Shotgun recoil now:", ALT_WEAPON_DATA[AltWeaponType.SHOTGUN].get("recoil"))

		"shotgun_knockback_epic":
			if ALT_WEAPON_DATA.has(AltWeaponType.SHOTGUN) and ALT_WEAPON_DATA[AltWeaponType.SHOTGUN].has("recoil"):
				ALT_WEAPON_DATA[AltWeaponType.SHOTGUN]["recoil"] = float(ALT_WEAPON_DATA[AltWeaponType.SHOTGUN].get("recoil", 0.0) * 1.20)
			print("  → Shotgun recoil now:", ALT_WEAPON_DATA[AltWeaponType.SHOTGUN].get("recoil"))

		# SNIPER
		"sniper_damage_common":
			if ALT_WEAPON_DATA.has(AltWeaponType.SNIPER) and ALT_WEAPON_DATA[AltWeaponType.SNIPER].has("damage"):
				ALT_WEAPON_DATA[AltWeaponType.SNIPER]["damage"] = float(ALT_WEAPON_DATA[AltWeaponType.SNIPER].get("damage", 0.0) * 1.10)
			print("  → Sniper damage now:", ALT_WEAPON_DATA[AltWeaponType.SNIPER].get("damage"))

		"sniper_damage_uncommon":
			if ALT_WEAPON_DATA.has(AltWeaponType.SNIPER) and ALT_WEAPON_DATA[AltWeaponType.SNIPER].has("damage"):
				ALT_WEAPON_DATA[AltWeaponType.SNIPER]["damage"] = float(ALT_WEAPON_DATA[AltWeaponType.SNIPER].get("damage", 0.0) * 1.20)
			print("  → Sniper damage now:", ALT_WEAPON_DATA[AltWeaponType.SNIPER].get("damage"))

		"sniper_damage_rare":
			if ALT_WEAPON_DATA.has(AltWeaponType.SNIPER) and ALT_WEAPON_DATA[AltWeaponType.SNIPER].has("damage"):
				ALT_WEAPON_DATA[AltWeaponType.SNIPER]["damage"] = float(ALT_WEAPON_DATA[AltWeaponType.SNIPER].get("damage", 0.0) * 1.30)
			print("  → Sniper damage now:", ALT_WEAPON_DATA[AltWeaponType.SNIPER].get("damage"))

		"sniper_pierce_uncommon":
			if ALT_WEAPON_DATA.has(AltWeaponType.SNIPER):
				ALT_WEAPON_DATA[AltWeaponType.SNIPER]["bounces"] = int(ALT_WEAPON_DATA[AltWeaponType.SNIPER].get("bounces", 0) + 1)
			print("  → Sniper pierce now:", ALT_WEAPON_DATA[AltWeaponType.SNIPER].get("bounces"))

		"sniper_pierce_rare":
			if ALT_WEAPON_DATA.has(AltWeaponType.SNIPER):
				ALT_WEAPON_DATA[AltWeaponType.SNIPER]["bounces"] = int(ALT_WEAPON_DATA[AltWeaponType.SNIPER].get("bounces", 0) + 2)
			print("  → Sniper pierce now:", ALT_WEAPON_DATA[AltWeaponType.SNIPER].get("bounces"))

		"sniper_charge_rare":
			if ALT_WEAPON_DATA.has(AltWeaponType.SNIPER) and ALT_WEAPON_DATA[AltWeaponType.SNIPER].has("damage"):
				ALT_WEAPON_DATA[AltWeaponType.SNIPER]["damage"] = float(ALT_WEAPON_DATA[AltWeaponType.SNIPER].get("damage", 0.0) * 1.15)
			print("  → Sniper charge damage bonus applied (data-only)")

		"sniper_charge_epic":
			if ALT_WEAPON_DATA.has(AltWeaponType.SNIPER) and ALT_WEAPON_DATA[AltWeaponType.SNIPER].has("damage"):
				ALT_WEAPON_DATA[AltWeaponType.SNIPER]["damage"] = float(ALT_WEAPON_DATA[AltWeaponType.SNIPER].get("damage", 0.0) * 1.30)
			print("  → Sniper charge epic applied (data-only)")

		# FLAMETHROWER
		"flame_lifetime_common":
			if ALT_WEAPON_DATA.has(AltWeaponType.FLAMETHROWER) and ALT_WEAPON_DATA[AltWeaponType.FLAMETHROWER].has("flame_lifetime"):
				ALT_WEAPON_DATA[AltWeaponType.FLAMETHROWER]["flame_lifetime"] = float(ALT_WEAPON_DATA[AltWeaponType.FLAMETHROWER].get("flame_lifetime", 0.0) * 1.10)
			print("  → Flame lifetime now:", ALT_WEAPON_DATA[AltWeaponType.FLAMETHROWER].get("flame_lifetime"))

		"flame_lifetime_uncommon":
			if ALT_WEAPON_DATA.has(AltWeaponType.FLAMETHROWER) and ALT_WEAPON_DATA[AltWeaponType.FLAMETHROWER].has("flame_lifetime"):
				ALT_WEAPON_DATA[AltWeaponType.FLAMETHROWER]["flame_lifetime"] = float(ALT_WEAPON_DATA[AltWeaponType.FLAMETHROWER].get("flame_lifetime", 0.0) * 1.20)
			print("  → Flame lifetime now:", ALT_WEAPON_DATA[AltWeaponType.FLAMETHROWER].get("flame_lifetime"))

		"flame_lifetime_rare":
			if ALT_WEAPON_DATA.has(AltWeaponType.FLAMETHROWER) and ALT_WEAPON_DATA[AltWeaponType.FLAMETHROWER].has("flame_lifetime"):
				ALT_WEAPON_DATA[AltWeaponType.FLAMETHROWER]["flame_lifetime"] = float(ALT_WEAPON_DATA[AltWeaponType.FLAMETHROWER].get("flame_lifetime", 0.0) * 1.30)
			print("  → Flame lifetime now:", ALT_WEAPON_DATA[AltWeaponType.FLAMETHROWER].get("flame_lifetime"))

		"flame_burn_uncommon":
			print("  → Flamethrower burn damage increase (data-only)")

		"flame_burn_rare":
			print("  → Flamethrower burn damage rare (data-only)")

		"flame_size_rare":
			if ALT_WEAPON_DATA.has(AltWeaponType.FLAMETHROWER) and ALT_WEAPON_DATA[AltWeaponType.FLAMETHROWER].has("damage"):
				ALT_WEAPON_DATA[AltWeaponType.FLAMETHROWER]["damage"] = float(ALT_WEAPON_DATA[AltWeaponType.FLAMETHROWER].get("damage", 0.0) * 1.10)
			print("  → Flame size / damage proxy applied")

		"flame_size_epic":
			if ALT_WEAPON_DATA.has(AltWeaponType.FLAMETHROWER) and ALT_WEAPON_DATA[AltWeaponType.FLAMETHROWER].has("damage"):
				ALT_WEAPON_DATA[AltWeaponType.FLAMETHROWER]["damage"] = float(ALT_WEAPON_DATA[AltWeaponType.FLAMETHROWER].get("damage", 0.0) * 1.20)
			print("  → Flame size epic applied")

		# GRENADE
		"grenade_radius_common":
			if ALT_WEAPON_DATA.has(AltWeaponType.GRENADE) and ALT_WEAPON_DATA[AltWeaponType.GRENADE].has("explosion_radius"):
				ALT_WEAPON_DATA[AltWeaponType.GRENADE]["explosion_radius"] = float(ALT_WEAPON_DATA[AltWeaponType.GRENADE].get("explosion_radius", 0.0) + 10.0)
			print("  → Grenade radius now:", ALT_WEAPON_DATA[AltWeaponType.GRENADE].get("explosion_radius"))

		"grenade_radius_uncommon":
			if ALT_WEAPON_DATA.has(AltWeaponType.GRENADE) and ALT_WEAPON_DATA[AltWeaponType.GRENADE].has("explosion_radius"):
				ALT_WEAPON_DATA[AltWeaponType.GRENADE]["explosion_radius"] = float(ALT_WEAPON_DATA[AltWeaponType.GRENADE].get("explosion_radius", 0.0) + 20.0)
			print("  → Grenade radius now:", ALT_WEAPON_DATA[AltWeaponType.GRENADE].get("explosion_radius"))

		"grenade_radius_rare":
			if ALT_WEAPON_DATA.has(AltWeaponType.GRENADE) and ALT_WEAPON_DATA[AltWeaponType.GRENADE].has("explosion_radius"):
				ALT_WEAPON_DATA[AltWeaponType.GRENADE]["explosion_radius"] = float(ALT_WEAPON_DATA[AltWeaponType.GRENADE].get("explosion_radius", 0.0) + 30.0)
			print("  → Grenade radius now:", ALT_WEAPON_DATA[AltWeaponType.GRENADE].get("explosion_radius"))

		"grenade_fragments_uncommon":
			# Behave like shotgun pellet upgrade: add +1 simultaneous grenade
			if ALT_WEAPON_DATA.has(AltWeaponType.GRENADE) and ALT_WEAPON_DATA[AltWeaponType.GRENADE].has("pellets"):
				ALT_WEAPON_DATA[AltWeaponType.GRENADE]["pellets"] = int(ALT_WEAPON_DATA[AltWeaponType.GRENADE].get("pellets", 1) + 1)
			print("  → Grenade pellets now:", ALT_WEAPON_DATA[AltWeaponType.GRENADE].get("pellets"))
			# Fixed spread remains constant – no recompute

		"grenade_fragments_rare":
			# Behave like shotgun pellet upgrade: add +2 simultaneous grenades
			if ALT_WEAPON_DATA.has(AltWeaponType.GRENADE) and ALT_WEAPON_DATA[AltWeaponType.GRENADE].has("pellets"):
				ALT_WEAPON_DATA[AltWeaponType.GRENADE]["pellets"] = int(ALT_WEAPON_DATA[AltWeaponType.GRENADE].get("pellets", 1) + 2)
			print("  → Grenade pellets now:", ALT_WEAPON_DATA[AltWeaponType.GRENADE].get("pellets"))
			# Fixed spread remains constant – no recompute

		"grenade_damage_rare":
			if ALT_WEAPON_DATA.has(AltWeaponType.GRENADE) and ALT_WEAPON_DATA[AltWeaponType.GRENADE].has("damage"):
				ALT_WEAPON_DATA[AltWeaponType.GRENADE]["damage"] = float(ALT_WEAPON_DATA[AltWeaponType.GRENADE].get("damage", 0.0) * 1.10)
			print("  → Grenade damage:", ALT_WEAPON_DATA[AltWeaponType.GRENADE].get("damage"))

		"grenade_damage_epic":
			if ALT_WEAPON_DATA.has(AltWeaponType.GRENADE) and ALT_WEAPON_DATA[AltWeaponType.GRENADE].has("damage"):
				ALT_WEAPON_DATA[AltWeaponType.GRENADE]["damage"] = float(ALT_WEAPON_DATA[AltWeaponType.GRENADE].get("damage", 0.0) * 1.20)
			print("  → Grenade damage epic:", ALT_WEAPON_DATA[AltWeaponType.GRENADE].get("damage"))

		# SHURIKEN
		"shuriken_bounces_common":
			if ALT_WEAPON_DATA.has(AltWeaponType.SHURIKEN):
				ALT_WEAPON_DATA[AltWeaponType.SHURIKEN]["bounces"] = int(ALT_WEAPON_DATA[AltWeaponType.SHURIKEN].get("bounces", 0) + 1)
			print("  → Shuriken bounces:", ALT_WEAPON_DATA[AltWeaponType.SHURIKEN].get("bounces"))

		"shuriken_bounces_uncommon":
			if ALT_WEAPON_DATA.has(AltWeaponType.SHURIKEN):
				ALT_WEAPON_DATA[AltWeaponType.SHURIKEN]["bounces"] = int(ALT_WEAPON_DATA[AltWeaponType.SHURIKEN].get("bounces", 0) + 2)
			print("  → Shuriken bounces:", ALT_WEAPON_DATA[AltWeaponType.SHURIKEN].get("bounces"))

		"shuriken_bounces_rare":
			if ALT_WEAPON_DATA.has(AltWeaponType.SHURIKEN):
				ALT_WEAPON_DATA[AltWeaponType.SHURIKEN]["bounces"] = int(ALT_WEAPON_DATA[AltWeaponType.SHURIKEN].get("bounces", 0) + 3)
			print("  → Shuriken bounces:", ALT_WEAPON_DATA[AltWeaponType.SHURIKEN].get("bounces"))

		"shuriken_speed_uncommon":
			if ALT_WEAPON_DATA.has(AltWeaponType.SHURIKEN) and ALT_WEAPON_DATA[AltWeaponType.SHURIKEN].has("bullet_speed"):
				ALT_WEAPON_DATA[AltWeaponType.SHURIKEN]["bullet_speed"] = float(ALT_WEAPON_DATA[AltWeaponType.SHURIKEN].get("bullet_speed", 0.0) * 1.10)
			print("  → Shuriken speed:", ALT_WEAPON_DATA[AltWeaponType.SHURIKEN].get("bullet_speed"))

		"shuriken_speed_rare":
			if ALT_WEAPON_DATA.has(AltWeaponType.SHURIKEN) and ALT_WEAPON_DATA[AltWeaponType.SHURIKEN].has("bullet_speed"):
				ALT_WEAPON_DATA[AltWeaponType.SHURIKEN]["bullet_speed"] = float(ALT_WEAPON_DATA[AltWeaponType.SHURIKEN].get("bullet_speed", 0.0) * 1.20)
			print("  → Shuriken speed:", ALT_WEAPON_DATA[AltWeaponType.SHURIKEN].get("bullet_speed"))

		"shuriken_ricochet_rare":
			if ALT_WEAPON_DATA.has(AltWeaponType.SHURIKEN) and ALT_WEAPON_DATA[AltWeaponType.SHURIKEN].has("damage"):
				ALT_WEAPON_DATA[AltWeaponType.SHURIKEN]["damage"] = float(ALT_WEAPON_DATA[AltWeaponType.SHURIKEN].get("damage", 0.0) * 1.10)
			print("  → Shuriken ricochet damage:", ALT_WEAPON_DATA[AltWeaponType.SHURIKEN].get("damage"))

		"shuriken_ricochet_epic":
			if ALT_WEAPON_DATA.has(AltWeaponType.SHURIKEN) and ALT_WEAPON_DATA[AltWeaponType.SHURIKEN].has("damage"):
				ALT_WEAPON_DATA[AltWeaponType.SHURIKEN]["damage"] = float(ALT_WEAPON_DATA[AltWeaponType.SHURIKEN].get("damage", 0.0) * 1.20)
			print("  → Shuriken ricochet damage epic:", ALT_WEAPON_DATA[AltWeaponType.SHURIKEN].get("damage"))

		# TURRET
		"turret_fire_rate_common":
			if ALT_WEAPON_DATA.has(AltWeaponType.TURRET) and ALT_WEAPON_DATA[AltWeaponType.TURRET].has("fire_rate"):
				ALT_WEAPON_DATA[AltWeaponType.TURRET]["fire_rate"] = float(ALT_WEAPON_DATA[AltWeaponType.TURRET].get("fire_rate", 0.4) * 0.95)
			print("  → Turret fire rate:", ALT_WEAPON_DATA[AltWeaponType.TURRET].get("fire_rate"))

		"turret_fire_rate_uncommon":
			if ALT_WEAPON_DATA.has(AltWeaponType.TURRET) and ALT_WEAPON_DATA[AltWeaponType.TURRET].has("fire_rate"):
				ALT_WEAPON_DATA[AltWeaponType.TURRET]["fire_rate"] = float(ALT_WEAPON_DATA[AltWeaponType.TURRET].get("fire_rate", 0.4) * 0.90)
			print("  → Turret fire rate:", ALT_WEAPON_DATA[AltWeaponType.TURRET].get("fire_rate"))

		"turret_fire_rate_rare":
			if ALT_WEAPON_DATA.has(AltWeaponType.TURRET) and ALT_WEAPON_DATA[AltWeaponType.TURRET].has("fire_rate"):
				ALT_WEAPON_DATA[AltWeaponType.TURRET]["fire_rate"] = float(ALT_WEAPON_DATA[AltWeaponType.TURRET].get("fire_rate", 0.4) * 0.85)
			print("  → Turret fire rate:", ALT_WEAPON_DATA[AltWeaponType.TURRET].get("fire_rate"))

		"turret_range_uncommon":
			if ALT_WEAPON_DATA.has(AltWeaponType.TURRET) and ALT_WEAPON_DATA[AltWeaponType.TURRET].has("range"):
				ALT_WEAPON_DATA[AltWeaponType.TURRET]["range"] = float(ALT_WEAPON_DATA[AltWeaponType.TURRET].get("range", 220.0) * 1.05)
			print("  → Turret range:", ALT_WEAPON_DATA[AltWeaponType.TURRET].get("range"))

		"turret_range_rare":
			if ALT_WEAPON_DATA.has(AltWeaponType.TURRET) and ALT_WEAPON_DATA[AltWeaponType.TURRET].has("range"):
				ALT_WEAPON_DATA[AltWeaponType.TURRET]["range"] = float(ALT_WEAPON_DATA[AltWeaponType.TURRET].get("range", 220.0) * 1.10)
			print("  → Turret range:", ALT_WEAPON_DATA[AltWeaponType.TURRET].get("range"))

		"turret_bullet_speed_rare":
			if ALT_WEAPON_DATA.has(AltWeaponType.TURRET) and ALT_WEAPON_DATA[AltWeaponType.TURRET].has("bullet_speed"):
				ALT_WEAPON_DATA[AltWeaponType.TURRET]["bullet_speed"] = float(ALT_WEAPON_DATA[AltWeaponType.TURRET].get("bullet_speed", 900.0) * 1.10)
			print("  → Turret bullet speed:", ALT_WEAPON_DATA[AltWeaponType.TURRET].get("bullet_speed"))

		"turret_bullet_speed_epic":
			if ALT_WEAPON_DATA.has(AltWeaponType.TURRET) and ALT_WEAPON_DATA[AltWeaponType.TURRET].has("bullet_speed"):
				ALT_WEAPON_DATA[AltWeaponType.TURRET]["bullet_speed"] = float(ALT_WEAPON_DATA[AltWeaponType.TURRET].get("bullet_speed", 900.0) * 1.20)
			print("  → Turret bullet speed epic:", ALT_WEAPON_DATA[AltWeaponType.TURRET].get("bullet_speed"))

		# ABILITIES
		"dash_distance_common":
			dash_distance_bonus_percent += 0.10
			print("  → Dash distance bonus:", dash_distance_bonus_percent)

		"dash_distance_uncommon":
			dash_distance_bonus_percent += 0.20
			print("  → Dash distance bonus:", dash_distance_bonus_percent)

		"dash_distance_rare":
			dash_distance_bonus_percent += 0.30
			print("  → Dash distance bonus:", dash_distance_bonus_percent)

		"dash_distance_epic":
			dash_distance_bonus_percent += 0.50
			print("  → Dash distance bonus:", dash_distance_bonus_percent)

		"bubble_duration_common":
			bubble_duration_bonus_percent += 0.05
			print("  → Bubble duration multiplier now:", bubble_duration_bonus_percent)

		"bubble_duration_uncommon":
			bubble_duration_bonus_percent += 0.10
			print("  → Bubble duration multiplier now:", bubble_duration_bonus_percent)

		"bubble_duration_rare":
			bubble_duration_bonus_percent += 0.20
			print("  → Bubble duration multiplier now:", bubble_duration_bonus_percent)

		"bubble_duration_epic":
			bubble_duration_bonus_percent += 0.30
			print("  → Bubble duration multiplier now:", bubble_duration_bonus_percent)

		"bubble_duration_plus_0_5":
			bubble_duration_bonus_seconds += 0.5
			print("  → Bubble duration flat bonus now:", bubble_duration_bonus_seconds)

		"bubble_duration_plus_1":
			bubble_duration_bonus_seconds += 1.0
			print("  → Bubble duration flat bonus now:", bubble_duration_bonus_seconds)

		"bubble_duration_plus_2":
			bubble_duration_bonus_seconds += 2.0
			print("  → Bubble duration flat bonus now:", bubble_duration_bonus_seconds)

		"slowmo_time_common":
			slowmo_time_bonus_seconds += 0.1
			print("  → Slowmo time bonus sec:", slowmo_time_bonus_seconds)

		"slowmo_time_uncommon":
			slowmo_time_bonus_seconds += 0.2
			print("  → Slowmo time bonus sec:", slowmo_time_bonus_seconds)

		"slowmo_time_rare":
			slowmo_time_bonus_seconds += 0.4
			print("  → Slowmo time bonus sec:", slowmo_time_bonus_seconds)

		"slowmo_time_epic":
			slowmo_time_bonus_seconds += 1.0
			print("  → Slowmo time bonus sec:", slowmo_time_bonus_seconds)

		"invis_duration_common":
			invis_duration_bonus_percent += 0.05
			print("  → Invisibility duration bonus:", invis_duration_bonus_percent)

		"invis_duration_uncommon":
			invis_duration_bonus_percent += 0.10
			print("  → Invisibility duration bonus:", invis_duration_bonus_percent)

		"invis_duration_rare":
			invis_duration_bonus_percent += 0.20
			print("  → Invisibility duration bonus:", invis_duration_bonus_percent)

		"invis_duration_epic":
			invis_duration_bonus_percent += 0.30
			print("  → Invisibility duration bonus:", invis_duration_bonus_percent)

		# SYNERGIES (data-only flags)
		"synergy_flamethrower_bubble_burning_shield":
			synergy_flamethrower_bubble_unlocked = true
			# TODO: Implement burning shield behavior in gameplay code

		"synergy_grenade_dash_explosive_trail":
			synergy_grenade_dash_unlocked = true
			# TODO: Implement explosive dash trail in gameplay code

		"synergy_shuriken_slowmo_infinite_bounces":
			synergy_shuriken_slowmo_unlocked = true
			# TODO: Implement infinite bounces during slowmo in gameplay code

		"synergy_sniper_invis_assassins_shot":
			synergy_sniper_invis_unlocked = true
			# TODO: Implement assassins shot on invisibility break

		"synergy_turret_bubble_shielded_turret":
			synergy_turret_bubble_unlocked = true
			# TODO: Implement shielded turret while bubble is active

		_:
			push_warning("[GameState] No handler for upgrade_id: %s" % upgrade_id)

	# After changing numbers, broadcast signals so UI and systems can refresh
	# Record acquisition (used to prevent re-offering non-stackables)
	_record_acquired_upgrade(upgrade_id)

	_emit_all_signals()
