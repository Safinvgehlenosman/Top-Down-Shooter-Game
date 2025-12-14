extends Node


# -------------------------------------------------------------------
# Upgrades_DB.gd
# - All upgrades are now defined in UPGRADE_DEFS (static GDScript data)
# - We no longer load res://data/upgrades_cleaned.csv at runtime
# - ALL_UPGRADES is built from UPGRADE_DEFS in _ensure_loaded()
# - Other systems (shop, chests, chaos, GameState) still consume upgrade dictionaries
# -------------------------------------------------------------------

enum Rarity {
    COMMON,
    UNCOMMON,
    RARE,
    EPIC,
    CHAOS,   # ⭐ Special chaos rarity for challenge upgrades
    SYNERGY  # ⭐ Special synergy rarity for combination upgrades
}

# ✅ THESE MUST MATCH GameState.AltWeaponType ENUM EXACTLY
# Verified against your game_state.gd enum order:
const ALT_WEAPON_NONE := 0
const ALT_WEAPON_SHOTGUN := 1
const ALT_WEAPON_SNIPER := 2
const ALT_WEAPON_SHURIKEN := 3
const ALT_WEAPON_TURRET := 4

const ABILITY_NONE := 0
const ABILITY_DASH := 1
const ABILITY_INVIS := 2

var ALL_UPGRADES: Array = []

# -------------------------------------------------------------------
# STATIC UPGRADE DATA (formerly loaded from CSV)
# -------------------------------------------------------------------
const UPGRADE_DEFS: Array = [
	# REMOVED: primary_burst_shot (Twinshot Burst)
	{"id": "shotgun_unlock", "text": "Unlock Shotgun", "rarity": Rarity.COMMON, "price": 300, "category": "generic", "pool": "shop", "icon_path": "", "effect": "none", "value": 0, "requires_weapon": "none", "requires_ability": "", "enabled": true, "unlock_weapon": "shotgun", "unlock_ability": ""},
	{"id": "sniper_unlock", "text": "Unlock Sniper", "rarity": Rarity.COMMON, "price": 350, "category": "generic", "pool": "shop", "icon_path": "", "effect": "none", "value": 0, "requires_weapon": "none", "requires_ability": "", "enabled": true, "unlock_weapon": "sniper", "unlock_ability": ""},
	# flamethrower_unlock and grenade_unlock removed
	{"id": "shuriken_unlock", "text": "Unlock Shuriken", "rarity": Rarity.COMMON, "price": 300, "category": "generic", "pool": "shop", "icon_path": "", "effect": "none", "value": 0, "requires_weapon": "none", "requires_ability": "", "enabled": true, "unlock_weapon": "shuriken", "unlock_ability": ""},
	{"id": "turret_unlock", "text": "Unlock Turret", "rarity": Rarity.COMMON, "price": 350, "category": "generic", "pool": "shop", "icon_path": "", "effect": "none", "value": 0, "requires_weapon": "none", "requires_ability": "", "enabled": true, "unlock_weapon": "turret", "unlock_ability": ""},
	# Ability unlocks (explicit entries so unlock_ability is set)
	{"id": "dash_unlock", "text": "Unlock Dash", "rarity": Rarity.COMMON, "price": 250, "category": "generic", "pool": "shop", "icon_path": "", "effect": "none", "value": 0, "requires_weapon": "", "requires_ability": "", "enabled": true, "unlock_weapon": "", "unlock_ability": "dash", "stackable": false},
	{"id": "invis_unlock", "text": "Unlock Invisibility", "rarity": Rarity.COMMON, "price": 300, "category": "generic", "pool": "shop", "icon_path": "", "effect": "none", "value": 0, "requires_weapon": "", "requires_ability": "", "enabled": true, "unlock_weapon": "", "unlock_ability": "invis", "stackable": false},
	# ...existing code...
	# --- PRIMARY WEAPON UPGRADES ---
	{"id": "primary_damage_up_1", "text": "Hollow Point Rounds (+20% Primary Damage)", "rarity": Rarity.UNCOMMON, "price": 180, "category": "primary", "pool": "shop", "icon_path": "", "effect": "primary_damage", "primary_damage": 1.20, "enabled": true},
	{"id": "primary_firerate_up_1", "text": "Rapid Trigger (+20% Primary Fire Rate)", "rarity": Rarity.UNCOMMON, "price": 180, "category": "primary", "pool": "shop", "icon_path": "", "effect": "primary_fire_rate", "primary_fire_rate": 1.20, "enabled": true},
	{"id": "primary_focused_fire", "text": "Focused Fire (+40% Damage, -20% Fire Rate)", "rarity": Rarity.RARE, "price": 320, "category": "primary", "pool": "shop", "icon_path": "", "effect": "primary_focused_fire", "primary_damage_mult": 1.40, "primary_fire_rate_mult": 0.80, "enabled": true},
	{"id": "primary_hair_trigger", "text": "Hair Trigger (+40% Fire Rate, -20% Damage)", "rarity": Rarity.RARE, "price": 320, "category": "primary", "pool": "shop", "icon_path": "", "effect": "primary_hair_trigger", "primary_fire_rate_mult": 1.40, "primary_damage_mult": 0.80, "enabled": true},
	{"id": "primary_kill_shot", "text": "Kill Shot (10% Crit Chance, 2.5x Crit)", "rarity": Rarity.RARE, "price": 400, "category": "primary", "pool": "shop", "icon_path": "", "effect": "primary_crit", "primary_crit_chance_add": 0.10, "primary_crit_mult": 2.50, "enabled": true},
	{"id": "primary_weak_spotter", "text": "Weak Spotter (+5% Crit, 2x Crit)", "rarity": Rarity.RARE, "price": 350, "category": "primary", "pool": "shop", "icon_path": "", "effect": "primary_crit", "primary_crit_chance_add": 0.05, "primary_crit_mult": 2.00, "enabled": true},
	{"id": "primary_steady_aim", "text": "Steady Aim (+30% Damage While Stationary)", "rarity": Rarity.RARE, "price": 340, "category": "primary", "pool": "shop", "icon_path": "", "effect": "primary_stationary_damage", "primary_stationary_damage": 1.30, "enabled": true},
	{"id": "primary_trailing_shot", "text": "Trailing Shot (+1 Projectile)", "rarity": Rarity.EPIC, "price": 600, "category": "primary", "pool": "shop", "icon_path": "", "effect": "primary_trailing_shot", "enabled": true, "stackable": true, "description": "Fires one additional projectile that trails slightly behind your main shot. Stackable."},
	# REMOVED: primary_twinshot_burst
	# --- NEW GENERAL UPGRADES ---
	# --- NEW SHOTGUN-SPECIFIC UPGRADES ---
	{"id": "shotgun_damage_up_1", "text": "Slug Rounds (+10% Shotgun Damage)", "rarity": Rarity.UNCOMMON, "price": 220, "category": "alt", "pool": "shop", "icon_path": "", "effect": "shotgun_damage_mult", "shotgun_damage_mult": 1.10, "requires_weapon": "shotgun", "enabled": true},
	{"id": "shotgun_damage_up_2", "text": "High-Caliber Slugs (+20% Shotgun Damage)", "rarity": Rarity.RARE, "price": 380, "category": "alt", "pool": "shop", "icon_path": "", "effect": "shotgun_damage_mult", "shotgun_damage_mult": 1.20, "requires_weapon": "shotgun", "enabled": true},
	{"id": "shotgun_fire_rate_up_1", "text": "Lightened Bolt (-10% Shotgun Cooldown)", "rarity": Rarity.UNCOMMON, "price": 200, "category": "alt", "pool": "shop", "icon_path": "", "effect": "shotgun_fire_rate_mult", "shotgun_fire_rate_mult": 0.90, "requires_weapon": "shotgun", "enabled": true},
	{"id": "shotgun_fire_rate_up_2", "text": "Reinforced Bolt (-20% Shotgun Cooldown)", "rarity": Rarity.RARE, "price": 360, "category": "alt", "pool": "shop", "icon_path": "", "effect": "shotgun_fire_rate_mult", "shotgun_fire_rate_mult": 0.80, "requires_weapon": "shotgun", "enabled": true},
	{"id": "shotgun_spread_tighten", "text": "Choked Barrel (-10% Shotgun Spread)", "rarity": Rarity.UNCOMMON, "price": 210, "category": "alt", "pool": "shop", "icon_path": "", "effect": "shotgun_spread_mult", "shotgun_spread_mult": 0.90, "requires_weapon": "shotgun", "enabled": true},
	{"id": "shotgun_extra_pellet", "text": "Extra Pellet (+1 Shotgun Pellet)", "rarity": Rarity.UNCOMMON, "price": 260, "category": "alt", "pool": "shop", "icon_path": "", "effect": "shotgun_extra_pellet", "shotgun_pellets_add": 1, "stackable": true, "requires_weapon": "shotgun", "enabled": true},

	# --- NEW SHURIKEN-SPECIFIC UPGRADES ---
	{"id": "shuriken_damage_up_1", "text": "Sharp Edge (+10% Shuriken Damage)", "rarity": Rarity.COMMON, "price": 160, "category": "alt", "pool": "shop", "icon_path": "", "effect": "shuriken_damage_mult", "shuriken_damage_mult": 1.10, "requires_weapon": "shuriken", "stackable": true, "enabled": true},
	{"id": "shuriken_damage_up_2", "text": "Monofilament Edge (+20% Shuriken Damage)", "rarity": Rarity.UNCOMMON, "price": 300, "category": "alt", "pool": "shop", "icon_path": "", "effect": "shuriken_damage_mult", "shuriken_damage_mult": 1.20, "requires_weapon": "shuriken", "stackable": true, "enabled": true},
	{"id": "shuriken_firerate_up_1", "text": "Quick Spin (-10% Shuriken Cooldown)", "rarity": Rarity.COMMON, "price": 150, "category": "alt", "pool": "shop", "icon_path": "", "effect": "shuriken_fire_rate_mult", "shuriken_fire_rate_mult": 0.90, "requires_weapon": "shuriken", "stackable": true, "enabled": true},
	{"id": "shuriken_firerate_up_2", "text": "Balanced Spin (-20% Shuriken Cooldown)", "rarity": Rarity.UNCOMMON, "price": 280, "category": "alt", "pool": "shop", "icon_path": "", "effect": "shuriken_fire_rate_mult", "shuriken_fire_rate_mult": 0.80, "requires_weapon": "shuriken", "stackable": true, "enabled": true},
	{"id": "shuriken_bounce_up_1", "text": "Reinforced Edge (+1 Shuriken Bounce)", "rarity": Rarity.RARE, "price": 320, "category": "alt", "pool": "shop", "icon_path": "", "effect": "shuriken_bounce_add", "shuriken_bounce_add": 1, "requires_weapon": "shuriken", "stackable": true, "enabled": true},
	{"id": "shuriken_seeking_chain", "text": "Seeking Chain (Shuriken)", "rarity": Rarity.EPIC, "price": 650, "category": "alt", "pool": "shop", "icon_path": "res://assets/bullets/shuriken.png", "effect": "shuriken_seeking_chain", "shuriken_seek_add": 1, "requires_weapon": "shuriken", "stackable": false, "enabled": true, "description": "After hitting an enemy, shurikens seek another nearby enemy for 50% damage. One-time purchase."},
	# Rare incremental chain upgrade: requires base Seeking Chain to be owned
	{"id": "shuriken_seeking_chain_plus1", "text": "Chain Link (+1 Seeking)", "rarity": Rarity.RARE, "price": 300, "category": "alt", "pool": "shop", "icon_path": "res://assets/bullets/shuriken.png", "effect": "shuriken_seeking_chain", "shuriken_seek_add": 1, "requires_weapon": "shuriken", "requires_upgrade": "shuriken_seeking_chain", "stackable": true, "enabled": true, "description": "Requires Seeking Chain. Increases shuriken seeking chain by +1."},

	# --- NEW SNIPER-SPECIFIC UPGRADES ---
	{"id": "sniper_damage_up_1", "text": "Armor-Piercing Tip (+10% Sniper Damage)", "rarity": Rarity.COMMON, "price": 200, "category": "alt", "pool": "shop", "icon_path": "", "effect": "sniper_damage_mult", "sniper_damage_mult": 1.10, "requires_weapon": "sniper", "stackable": true, "enabled": true},
	{"id": "sniper_damage_up_2", "text": "Hollow-Point Tip (+20% Sniper Damage)", "rarity": Rarity.UNCOMMON, "price": 360, "category": "alt", "pool": "shop", "icon_path": "", "effect": "sniper_damage_mult", "sniper_damage_mult": 1.20, "requires_weapon": "sniper", "stackable": true, "enabled": true},
	{"id": "sniper_firerate_up_1", "text": "Lightened Bolt (-10% Sniper Cooldown)", "rarity": Rarity.COMMON, "price": 190, "category": "alt", "pool": "shop", "icon_path": "", "effect": "sniper_fire_rate_mult", "sniper_fire_rate_mult": 0.90, "requires_weapon": "sniper", "stackable": true, "enabled": true},
	{"id": "sniper_firerate_up_2", "text": "Reinforced Bolt (-20% Sniper Cooldown)", "rarity": Rarity.UNCOMMON, "price": 350, "category": "alt", "pool": "shop", "icon_path": "", "effect": "sniper_fire_rate_mult", "sniper_fire_rate_mult": 0.80, "requires_weapon": "sniper", "stackable": true, "enabled": true},
	{"id": "sniper_phasing_rounds", "text": "Phasing Rounds (Sniper)", "rarity": Rarity.EPIC, "price": 700, "category": "alt", "pool": "shop", "icon_path": "", "effect": "sniper_phasing_rounds", "enabled": true, "stackable": false, "requires_weapon": "sniper", "description": "Sniper shots pass through walls but deal 50% damage. Unique."},
	# --- NEW TURRET-SPECIFIC UPGRADES (FINAL SET) ---
	{"id": "turret_damage_up_1", "text": "Reinforced Rounds (+10% Turret Damage)", "rarity": Rarity.COMMON, "price": 180, "category": "alt", "pool": "shop", "icon_path": "", "effect": "turret_damage_mult", "turret_damage_mult": 1.10, "requires_weapon": "turret", "stackable": true, "enabled": true},
	{"id": "turret_damage_up_2", "text": "High-Impact Rounds (+20% Turret Damage)", "rarity": Rarity.UNCOMMON, "price": 340, "category": "alt", "pool": "shop", "icon_path": "", "effect": "turret_damage_mult", "turret_damage_mult": 1.20, "requires_weapon": "turret", "stackable": true, "enabled": true},
	{"id": "turret_firerate_up_1", "text": "Lightened Mechanism (-10% Turret Cooldown)", "rarity": Rarity.COMMON, "price": 160, "category": "alt", "pool": "shop", "icon_path": "", "effect": "turret_fire_rate_mult", "turret_fire_rate_mult": 0.90, "requires_weapon": "turret", "stackable": true, "enabled": true},
	{"id": "turret_firerate_up_2", "text": "Balanced Timing (-20% Turret Cooldown)", "rarity": Rarity.UNCOMMON, "price": 300, "category": "alt", "pool": "shop", "icon_path": "", "effect": "turret_fire_rate_mult", "turret_fire_rate_mult": 0.80, "requires_weapon": "turret", "stackable": true, "enabled": true},
	{"id": "turret_bullet_speed_up", "text": "Polished Barrels (+10% Turret Bullet Speed)", "rarity": Rarity.RARE, "price": 320, "category": "alt", "pool": "shop", "icon_path": "", "effect": "turret_bullet_speed_add", "turret_bullet_speed_add": 0.10, "requires_weapon": "turret", "stackable": true, "max_stack": 10, "enabled": true, "description": "Additive +10% bullet speed per stack. Total turret bullet speed multiplier capped at 2.0x."},
	{"id": "turret_accuracy_up", "text": "Stabilized Turret (+20% Accuracy)", "rarity": Rarity.RARE, "price": 320, "category": "alt", "pool": "shop", "icon_path": "", "effect": "turret_accuracy_mult", "turret_accuracy_mult": 0.80, "requires_weapon": "turret", "stackable": true, "max_stack": 2, "enabled": true, "description": "Reduces turret spread (improves accuracy)."},
	{"id": "turret_homing_rounds", "text": "Homing Rounds (Turret)", "rarity": Rarity.EPIC, "price": 700, "category": "alt", "pool": "shop", "icon_path": "", "effect": "turret_homing_rounds", "enabled": true, "stackable": false, "requires_weapon": "turret", "description": "Turret bullets gain subtle homing toward closest visible slimes (one-time purchase).", "turret_homing_angle_deg": 6.0, "turret_homing_turn_speed": 90.0},
	# --- DASH UPGRADES ---
	{"id": "dash_distance_up_1", "text": "Fleetfoot I (+20% Dash Distance)", "rarity": Rarity.COMMON, "price": 120, "category": "ability", "pool": "shop", "icon_path": "", "effect": "dash_distance", "enabled": true, "stackable": true, "requires_ability": "dash"},
	{"id": "dash_distance_up_2", "text": "Fleetfoot II (+40% Dash Distance)", "rarity": Rarity.UNCOMMON, "price": 240, "category": "ability", "pool": "shop", "icon_path": "", "effect": "dash_distance", "enabled": true, "stackable": true, "requires_ability": "dash"},
	{"id": "dash_cooldown_up_1", "text": "Swift Recovery I (-10% Dash Cooldown)", "rarity": Rarity.COMMON, "price": 110, "category": "ability", "pool": "shop", "icon_path": "", "effect": "dash_cooldown", "enabled": true, "stackable": true, "requires_ability": "dash"},
	{"id": "dash_cooldown_up_2", "text": "Swift Recovery II (-20% Dash Cooldown)", "rarity": Rarity.UNCOMMON, "price": 220, "category": "ability", "pool": "shop", "icon_path": "", "effect": "dash_cooldown", "enabled": true, "stackable": true, "requires_ability": "dash"},
	{"id": "dash_executioner", "text": "Executioner (On kill, reduce dash cooldown by 0.75s.)", "rarity": Rarity.RARE, "price": 380, "category": "ability", "pool": "shop", "icon_path": "", "effect": "dash_executioner", "enabled": true, "stackable": false, "requires_ability": "dash", "description": "On kill, reduce dash cooldown by 0.75s."},
	{"id": "dash_phase", "text": "Phasing Dash", "rarity": Rarity.EPIC, "price": 700, "category": "ability", "pool": "shop", "icon_path": "", "effect": "dash_phase", "enabled": true, "stackable": false, "requires_ability": "dash", "description": "Dash can phase through walls; cannot end inside walls."},
	# --- INVISIBILITY UPGRADES ---
	{"id": "invis_duration_up_1", "text": "Longer Cloak (+20% Invis Duration)", "rarity": Rarity.UNCOMMON, "price": 220, "category": "ability", "pool": "shop", "icon_path": "", "effect": "invis_duration_mult", "invis_duration_mult": 1.20, "requires_ability": "invis", "enabled": true},
	{"id": "invis_duration_up_2", "text": "Extended Cloak (+40% Invis Duration)", "rarity": Rarity.RARE, "price": 380, "category": "ability", "pool": "shop", "icon_path": "", "effect": "invis_duration_mult", "invis_duration_mult": 1.40, "requires_ability": "invis", "enabled": true},
	{"id": "invis_cooldown_up_1", "text": "Rapid Recovery I (-10% Invis Cooldown)", "rarity": Rarity.UNCOMMON, "price": 200, "category": "ability", "pool": "shop", "icon_path": "", "effect": "invis_cooldown", "enabled": true, "stackable": true, "requires_ability": "invis"},
	{"id": "invis_cooldown_up_2", "text": "Rapid Recovery II (-20% Invis Cooldown)", "rarity": Rarity.RARE, "price": 360, "category": "ability", "pool": "shop", "icon_path": "", "effect": "invis_cooldown", "enabled": true, "stackable": true, "requires_ability": "invis"},
	{"id": "invis_ambush", "text": "Ambush (Invis)", "rarity": Rarity.RARE, "price": 420, "category": "ability", "pool": "shop", "icon_path": "", "effect": "invis_ambush", "ambush_duration": 0.75, "ambush_damage_mult": 1.5, "requires_ability": "invis", "enabled": true, "stackable": false, "description": "Leaving invis grants a short damage window."},
	{"id": "invis_gunslinger", "text": "Gunslinger (Invis)", "rarity": Rarity.EPIC, "price": 700, "category": "ability", "pool": "shop", "icon_path": "", "effect": "invis_gunslinger", "requires_ability": "invis", "enabled": true, "stackable": false, "description": "Shooting does not break invis but your cloak duration is halved."},
	{"id": "general_move_speed_1", "text": "Swift Feet I (+10% Move Speed)", "rarity": Rarity.UNCOMMON, "price": 120, "category": "general", "pool": "shop", "icon_path": "", "effect": "move_speed_mult", "move_speed_mult": 1.10, "enabled": true},
	{"id": "general_move_speed_2", "text": "Swift Feet II (+20% Move Speed)", "rarity": Rarity.RARE, "price": 220, "category": "general", "pool": "shop", "icon_path": "", "effect": "move_speed_mult", "move_speed_mult": 1.20, "enabled": true},
	{"id": "general_max_hp_1", "text": "Hardened Body (+10% Max HP)", "rarity": Rarity.COMMON, "price": 100, "category": "general", "pool": "shop", "icon_path": "", "effect": "max_hp_mult", "max_hp_mult": 1.10, "enabled": true},
	# Uncommon variant: +20% Max HP
	{"id": "general_max_hp_2", "text": "Hardened Body II (+20% Max HP)", "rarity": Rarity.UNCOMMON, "price": 220, "category": "general", "pool": "shop", "icon_path": "res://assets/Separated/singleheart.png", "effect": "max_hp_mult", "max_hp_mult": 1.20, "enabled": true},
	{"id": "general_damage_reduction_1", "text": "Thick Skin (10% Damage Reduction)", "rarity": Rarity.RARE, "price": 250, "category": "general", "pool": "shop", "icon_path": "", "effect": "damage_taken_mult", "damage_taken_mult": 0.9, "enabled": true},
	# Epic damage reduction: 20% less damage taken (multiplier 0.80)
	{"id": "general_damage_reduction_2", "text": "Fortified Hide (20% Damage Reduction)", "rarity": Rarity.EPIC, "price": 650, "category": "general", "pool": "shop", "icon_path": "res://assets/Separated/singleheart.png", "effect": "damage_taken_mult", "damage_taken_mult": 0.80, "enabled": true},
	# Regen upgrades removed
]

# -------------------------------------------------------------------
# UPGRADE LOADING (STATIC)
# -------------------------------------------------------------------
func _ensure_loaded() -> void:
	if not ALL_UPGRADES.is_empty():
		return
	ALL_UPGRADES.clear()
	for data in UPGRADE_DEFS:
		ALL_UPGRADES.append(data)
	print("[UpgradesDB] Loaded %d upgrades from static UPGRADE_DEFS" % ALL_UPGRADES.size())
# -------------------------------------------------------------------
# String normalization helper (was used for CSV, still needed for pool/category/requirements)
# -------------------------------------------------------------------
static func _normalize_string(input: String) -> String:
	return input.strip_edges().to_lower()


# -------------------------------------------------------------------
# PUBLIC API (unchanged from original)
# -------------------------------------------------------------------

func get_all() -> Array:
	_ensure_loaded()
	return ALL_UPGRADES

func get_non_chaos_upgrades() -> Array:
	_ensure_loaded()
	var filtered := []
	for upgrade in ALL_UPGRADES:
		if upgrade.get("effect") != "chaos_challenge":
			filtered.append(upgrade)
	return filtered

func get_chaos_upgrades() -> Array:
	"""Returns enabled upgrades from the chaos pool."""
	_ensure_loaded()
	var chaos_upgrades := []
	for upgrade in ALL_UPGRADES:
		# Check if enabled
		if not upgrade.get("enabled", true):
			continue
		# Prefer pool field, fallback to effect for backwards compatibility
		if upgrade.get("pool", "") == "chaos" or upgrade.get("effect") == "chaos_challenge":
			chaos_upgrades.append(upgrade)
	return chaos_upgrades

func get_by_id(id: String) -> Dictionary:
	_ensure_loaded()
	for u in ALL_UPGRADES:
		if u.get("id", "") == id:
			return u
	return {}

func filter_by_rarity(rarity: int) -> Array:
	_ensure_loaded()
	var filtered := []
	for upgrade in ALL_UPGRADES:
		if upgrade.get("rarity") == rarity:
			filtered.append(upgrade)
	return filtered

func get_enabled() -> Array:
	"""Returns all upgrades where enabled == true."""
	_ensure_loaded()
	var filtered := []
	for upgrade in ALL_UPGRADES:
		if upgrade.get("enabled", true):
			filtered.append(upgrade)
	return filtered

func filter_by_pool(pool: String) -> Array:
	"""Returns enabled upgrades whose pool matches the given pool string (case-insensitive)."""
	_ensure_loaded()
	var normalized_pool := _normalize_string(pool)
	var filtered := []
	for upgrade in ALL_UPGRADES:
		if not upgrade.get("enabled", true):
			continue
		if upgrade.get("pool", "") == normalized_pool:
			filtered.append(upgrade)
	return filtered

func filter_by_category(category: String) -> Array:
	"""Returns enabled upgrades whose category matches the given category string (case-insensitive)."""
	_ensure_loaded()
	var normalized_category := _normalize_string(category)
	var filtered := []
	for upgrade in ALL_UPGRADES:
		if not upgrade.get("enabled", true):
			continue
		if upgrade.get("category", "") == normalized_category:
			filtered.append(upgrade)
	return filtered

func is_upgrade_available_for_loadout(upgrade: Dictionary, equipped_weapon: String, equipped_ability: String) -> bool:
	"""Check if an upgrade is available based on enabled status and requirements."""
	if not upgrade.get("enabled", true):
		return false
	
	# For synergies, check if player has the required weapon/ability UNLOCKED (not just equipped)
	var requires_weapon: String = upgrade.get("requires_weapon", "")
	if requires_weapon != "":
		# "none" means this upgrade only appears when NO weapon is equipped
		if requires_weapon == "none":
			if equipped_weapon != "":
				return false
		else:
			# Check if this is a synergy - if so, check unlocked weapons instead of equipped
			if upgrade.get("rarity", Rarity.COMMON) == Rarity.SYNERGY:
				var unlocked_weapons = GameState.get_unlocked_weapons()
				var has_required_weapon = false
				for weapon_type in unlocked_weapons:
					var weapon_name = _get_weapon_name_from_type(weapon_type)
					if _normalize_string(requires_weapon) == _normalize_string(weapon_name):
						has_required_weapon = true
						break
				if not has_required_weapon:
					return false
			else:
				# Non-synergy: check equipped weapon
				if _normalize_string(requires_weapon) != _normalize_string(equipped_weapon):
					return false
	
	var requires_ability: String = upgrade.get("requires_ability", "")
	if requires_ability != "":
		# "none" means this upgrade only appears when NO ability is equipped
		if requires_ability == "none":
			if equipped_ability != "":
				return false
		else:
			# Check if this is a synergy - if so, check unlocked abilities instead of equipped
			if upgrade.get("rarity", Rarity.COMMON) == Rarity.SYNERGY:
				var unlocked_abilities = GameState.get_unlocked_abilities()
				var has_required_ability = false
				for ability_type in unlocked_abilities:
					var ability_name = _get_ability_name_from_type(ability_type)
					var normalized_required = _normalize_string(requires_ability)
					var normalized_ability = _normalize_string(ability_name)
					if normalized_required == normalized_ability:
						has_required_ability = true
						break
				if not has_required_ability:
					return false
			else:
				# Non-synergy: check equipped ability
				if _normalize_string(requires_ability) != _normalize_string(equipped_ability):
					return false
	
	return true

# Helper functions to convert enum types to lowercase names
func _get_weapon_name_from_type(weapon_type: int) -> String:
	match weapon_type:
		1: return "shotgun"  # ALT_WEAPON_SHOTGUN
		2: return "sniper"
		3: return "shuriken"
		4: return "turret"
		_: return ""

func _get_ability_name_from_type(ability_type: int) -> String:
	match ability_type:
		1: return "dash"  # ABILITY_DASH
		2: return "invis"
		_: return ""

# -------------------------------------------------------------------
# UPGRADE APPLICATION LOGIC
# -------------------------------------------------------------------

func apply_upgrade(upgrade_id: String) -> void:

	if Engine.has_singleton("GameState"):
		GameState.apply_upgrade(upgrade_id)
	else:
		if typeof(GameState) != TYPE_NIL and GameState.has_method("apply_upgrade"):
			GameState.apply_upgrade(upgrade_id)
	
	_sync_player_after_upgrade()

func _sync_player_after_upgrade() -> void:
	var tree = Engine.get_main_loop() as SceneTree
	if not tree:
		return
	
	var player = tree.get_first_node_in_group("player")
	if player and player.has_method("sync_from_gamestate"):
		player.sync_from_gamestate()

	var _gun_node = null
	if player and player.has_node("Gun"):
		_gun_node = player.get_node("Gun")
	
	# Removed call to gun_node.init_from_state() (function does not exist)
