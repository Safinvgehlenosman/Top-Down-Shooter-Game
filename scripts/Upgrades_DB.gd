extends Node

##
## UpgradesDB.gd
## Central database for *all* upgrade definitions.
## ✅ FIXED: Enum indices now match GameState.AltWeaponType exactly
## ✅ FIXED: No longer tries to modify const ABILITY_DATA dictionary
##

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
const ALT_WEAPON_FLAMETHROWER := 3
const ALT_WEAPON_GRENADE := 4
const ALT_WEAPON_SHURIKEN := 5
const ALT_WEAPON_TURRET := 6

const ABILITY_NONE := 0
const ABILITY_DASH := 1
const ABILITY_SLOWMO := 2
const ABILITY_BUBBLE := 3
const ABILITY_INVIS := 4

# -------------------------------------------------------------------
# CSV-BASED UPGRADE DATABASE
# -------------------------------------------------------------------

var ALL_UPGRADES: Array = []

# Lazy-load upgrades from CSV on first access
func _ensure_loaded() -> void:
	if ALL_UPGRADES.is_empty():
		ALL_UPGRADES = _load_upgrades_from_csv("res://data/upgrades.csv")

# Parse rarity string to enum value
func _parse_rarity(rarity_str: String) -> int:
	match rarity_str.to_lower():
		"common": return Rarity.COMMON
		"uncommon": return Rarity.UNCOMMON
		"rare": return Rarity.RARE
		"epic": return Rarity.EPIC
		"chaos": return Rarity.CHAOS
		"synergy": return Rarity.SYNERGY
		_: return Rarity.COMMON

# Parse boolean string to bool
func _parse_bool(bool_str: String) -> bool:
	return bool_str.strip_edges().to_lower() == "true"

# Parse float string to float
func _parse_float(float_str: String) -> float:
	var trimmed = float_str.strip_edges()
	if trimmed.is_empty():
		return 0.0
	return float(trimmed)

# Normalize category/pool strings
func _normalize_string(input: String) -> String:
	return input.strip_edges().to_lower()

# Load upgrades from CSV file
func _load_upgrades_from_csv(path: String) -> Array:
	var upgrades := []
	var file := FileAccess.open(path, FileAccess.READ)
	
	if not file:
		push_error("[UpgradesDB] Failed to open CSV: " + path)
		return upgrades
	
	# Read headers
	var headers := file.get_csv_line()
	var enabled_count := 0
	
	# Read each row
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() < headers.size():
			continue
		
		# Skip empty rows
		if row.size() == 0 or (row.size() == 1 and row[0].strip_edges() == ""):
			continue
		
		var upgrade := {}
		
		# Map CSV columns to Dictionary
		for i in range(headers.size()):
			var key := headers[i].strip_edges()
			var value := row[i].strip_edges()
			
			# Parse specific fields based on CSV schema
			match key:
				"id":
					upgrade["id"] = value
				"text":
					upgrade["text"] = value
				"rarity":
					upgrade["rarity"] = _parse_rarity(value)
				"price":
					upgrade["price"] = int(value) if value != "" else 0
				"category":
					upgrade["category"] = _normalize_string(value)
				"pool":
					upgrade["pool"] = _normalize_string(value)
				"icon_path":
					if value != "":
						upgrade["icon"] = ResourceLoader.load(value)
					else:
						upgrade["icon"] = null
				"effect":
					upgrade["effect"] = value
				"value":
					upgrade["value"] = _parse_float(value)
				"requires_weapon":
					upgrade["requires_weapon"] = _normalize_string(value)
				"requires_ability":
					upgrade["requires_ability"] = _normalize_string(value)
				"enabled":
					upgrade["enabled"] = _parse_bool(value)
				"unlock_weapon":
					upgrade["unlock_weapon"] = value
				"unlock_ability":
					upgrade["unlock_ability"] = value
		
		# Skip rows with empty id or text
		if not upgrade.has("id") or upgrade["id"] == "":
			continue
		if not upgrade.has("text") or upgrade["text"] == "":
			continue
		
		# Ensure all expected keys exist with defaults
		if not upgrade.has("enabled"):
			upgrade["enabled"] = true
		if not upgrade.has("category"):
			upgrade["category"] = ""
		if not upgrade.has("pool"):
			upgrade["pool"] = ""
		if not upgrade.has("value"):
			upgrade["value"] = 0.0
		if not upgrade.has("requires_weapon"):
			upgrade["requires_weapon"] = ""
		if not upgrade.has("requires_ability"):
			upgrade["requires_ability"] = ""
		if not upgrade.has("effect"):
			upgrade["effect"] = ""
		if not upgrade.has("unlock_weapon"):
			upgrade["unlock_weapon"] = ""
		if not upgrade.has("unlock_ability"):
			upgrade["unlock_ability"] = ""
		
		# ⭐ SYNERGIES are NOT stackable - remove from pool after purchase
		if upgrade.get("rarity", 0) == Rarity.SYNERGY:
			upgrade["stackable"] = false
		else:
			# Default: most upgrades are stackable
			if not upgrade.has("stackable"):
				upgrade["stackable"] = true
		
		if upgrade["enabled"]:
			enabled_count += 1
		
		# Debug print for each upgrade
		var rarity_str := ""
		match upgrade.get("rarity", 0):
			Rarity.COMMON: rarity_str = "common"
			Rarity.UNCOMMON: rarity_str = "uncommon"
			Rarity.RARE: rarity_str = "rare"
			Rarity.EPIC: rarity_str = "epic"
			Rarity.CHAOS: rarity_str = "chaos"
			Rarity.SYNERGY: rarity_str = "synergy"
		
		print("[UpgradesDB] Loaded upgrade: %s (rarity=%s, price=%d, pool=%s, category=%s, enabled=%s)" % [
			upgrade["id"],
			rarity_str,
			upgrade["price"],
			upgrade.get("pool", ""),
			upgrade.get("category", ""),
			str(upgrade["enabled"])
		])
		
		upgrades.append(upgrade)
	
	file.close()
	
	# Summary print
	print("[UpgradesDB] CSV loaded %d upgrades (enabled: %d)" % [upgrades.size(), enabled_count])
	
	return upgrades

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
		# Handle 'shield' as alias for 'bubble'
		if requires_ability == "shield":
			requires_ability = "bubble"
		
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
					
					# Handle "shield" alias for "bubble"
					if normalized_required == "shield":
						normalized_required = "bubble"
					
					if normalized_required == normalized_ability:
						has_required_ability = true
						break
				if not has_required_ability:
					return false
			else:
				# Non-synergy: check equipped ability
				if _normalize_string(requires_ability) != _normalize_string(equipped_ability):
					return false
				return false
	
	return true

# Helper functions to convert enum types to lowercase names
func _get_weapon_name_from_type(weapon_type: int) -> String:
	match weapon_type:
		1: return "shotgun"  # ALT_WEAPON_SHOTGUN
		2: return "sniper"
		3: return "flamethrower"
		4: return "grenade"
		5: return "shuriken"
		6: return "turret"
		_: return ""

func _get_ability_name_from_type(ability_type: int) -> String:
	match ability_type:
		1: return "dash"  # ABILITY_DASH
		2: return "slowmo"
		3: return "bubble"
		4: return "invis"
		_: return ""

# -------------------------------------------------------------------
# UPGRADE APPLICATION LOGIC
# -------------------------------------------------------------------

func apply_upgrade(upgrade_id: String) -> void:
	print("[UpgradesDB] Applying upgrade:", upgrade_id)
	
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
		print("[UpgradesDB] Player synced after upgrade")
	
	var gun_node = null
	if player and player.has_node("Gun"):
		gun_node = player.get_node("Gun")
	
	if gun_node and gun_node.has_method("init_from_state"):
		gun_node.init_from_state()
		print("[UpgradesDB] Gun synced after upgrade")
