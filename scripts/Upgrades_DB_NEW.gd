extends Node

##
## UpgradesDB.gd
## Central database for *all* upgrade definitions.
## ✅ Now loads from CSV: res://data/upgrades.csv
##

enum Rarity {
	COMMON,
	UNCOMMON,
	RARE,
	EPIC,
	CHAOS  # ⭐ Special chaos rarity for challenge upgrades
}

# ✅ THESE MUST MATCH GameState.AltWeaponType ENUM EXACTLY
const ALT_WEAPON_NONE := 0
const ALT_WEAPON_SHOTGUN := 1
const ALT_WEAPON_SNIPER := 2
const ALT_WEAPON_FLAMETHROWER := 3
const ALT_WEAPON_GRENADE := 4
const ALT_WEAPON_SHURIKEN := 5
const ALT_WEAPON_TURRET := 6

# ✅ THESE MUST MATCH GameState.AbilityType ENUM EXACTLY
const ABILITY_NONE := 0
const ABILITY_DASH := 1
const ABILITY_SLOWMO := 2
const ABILITY_BUBBLE := 3
const ABILITY_INVIS := 4

# -------------------------------------------------------------------
# MASTER UPGRADE LIST - NOW LOADED FROM CSV
# -------------------------------------------------------------------

var ALL_UPGRADES: Array = _load_upgrades_from_csv("res://data/upgrades.csv")

# -------------------------------------------------------------------
# CSV LOADING HELPERS
# -------------------------------------------------------------------

static func _parse_rarity(rarity_str: String) -> int:
	"""Convert rarity string to enum value."""
	match rarity_str.to_lower().strip_edges():
		"common":
			return Rarity.COMMON
		"uncommon":
			return Rarity.UNCOMMON
		"rare":
			return Rarity.RARE
		"epic":
			return Rarity.EPIC
		"chaos":
			return Rarity.CHAOS
		_:
			push_warning("Unknown rarity: " + rarity_str + ", defaulting to COMMON")
			return Rarity.COMMON


static func _parse_bool(value_str: String) -> bool:
	"""Parse boolean value from string."""
	var cleaned = value_str.to_lower().strip_edges()
	return cleaned == "true" or cleaned == "1" or cleaned == "yes"


static func _parse_int_const(value_str: String) -> int:
	"""Parse weapon/ability constants from string."""
	match value_str.to_upper().strip_edges():
		"ALT_WEAPON_SHOTGUN":
			return ALT_WEAPON_SHOTGUN
		"ALT_WEAPON_SNIPER":
			return ALT_WEAPON_SNIPER
		"ALT_WEAPON_FLAMETHROWER":
			return ALT_WEAPON_FLAMETHROWER
		"ALT_WEAPON_GRENADE":
			return ALT_WEAPON_GRENADE
		"ALT_WEAPON_SHURIKEN":
			return ALT_WEAPON_SHURIKEN
		"ALT_WEAPON_TURRET":
			return ALT_WEAPON_TURRET
		"ABILITY_DASH":
			return ABILITY_DASH
		"ABILITY_SLOWMO":
			return ABILITY_SLOWMO
		"ABILITY_BUBBLE":
			return ABILITY_BUBBLE
		"ABILITY_INVIS":
			return ABILITY_INVIS
		_:
			return -1


static func _build_upgrade_from_row(row: Dictionary) -> Dictionary:
	"""Build an upgrade dictionary from a CSV row."""
	var upgrade := {}
	
	# Required fields
	upgrade["id"] = row.get("id", "").strip_edges()
	upgrade["text"] = row.get("text", "").strip_edges()
	upgrade["price"] = int(row.get("price", "0"))
	upgrade["rarity"] = _parse_rarity(row.get("rarity", "common"))
	
	# Optional: icon
	var icon_path = row.get("icon_path", "").strip_edges()
	if icon_path != "" and ResourceLoader.exists(icon_path):
		upgrade["icon"] = load(icon_path)
	else:
		upgrade["icon"] = null
	
	# Optional: description
	if row.has("description") and row["description"].strip_edges() != "":
		upgrade["description"] = row["description"].strip_edges()
	
	# Optional: effect
	if row.has("effect") and row["effect"].strip_edges() != "":
		upgrade["effect"] = row["effect"].strip_edges()
	
	# Optional: value (for effects)
	if row.has("value") and row["value"].strip_edges() != "":
		upgrade["value"] = row["value"].strip_edges()
	
	# Optional: line_id
	if row.has("line_id") and row["line_id"].strip_edges() != "":
		upgrade["line_id"] = row["line_id"].strip_edges()
	
	# Optional: increment (as float)
	if row.has("increment") and row["increment"].strip_edges() != "":
		upgrade["increment"] = float(row["increment"])
	
	# Optional: stackable
	if row.has("stackable") and row["stackable"].strip_edges() != "":
		upgrade["stackable"] = _parse_bool(row["stackable"])
	
	# Optional: requires_alt_weapon
	if row.has("requires_alt_weapon") and row["requires_alt_weapon"].strip_edges() != "":
		var weapon_val = _parse_int_const(row["requires_alt_weapon"])
		if weapon_val >= 0:
			upgrade["requires_alt_weapon"] = weapon_val
	
	# Optional: requires_ability
	if row.has("requires_ability") and row["requires_ability"].strip_edges() != "":
		var ability_val = _parse_int_const(row["requires_ability"])
		if ability_val >= 0:
			upgrade["requires_ability"] = ability_val
	
	# Optional: requires_any_ability
	if row.has("requires_any_ability") and row["requires_any_ability"].strip_edges() != "":
		upgrade["requires_any_ability"] = _parse_bool(row["requires_any_ability"])
	
	# Optional: requires_ammo_weapon
	if row.has("requires_ammo_weapon") and row["requires_ammo_weapon"].strip_edges() != "":
		upgrade["requires_ammo_weapon"] = _parse_bool(row["requires_ammo_weapon"])
	
	# Optional: tags (comma-separated)
	if row.has("tags") and row["tags"].strip_edges() != "":
		var tags_str = row["tags"].strip_edges()
		upgrade["tags"] = tags_str.split(",", false)
		# Clean each tag
		for i in range(upgrade["tags"].size()):
			upgrade["tags"][i] = upgrade["tags"][i].strip_edges()
	
	return upgrade


static func _load_upgrades_from_csv(path: String) -> Array:
	"""Load upgrades from a CSV file."""
	var upgrades := []
	
	if not FileAccess.file_exists(path):
		push_error("CSV file not found: " + path)
		return upgrades
	
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open CSV file: " + path)
		return upgrades
	
	# Read header line
	var header_line = file.get_line().strip_edges()
	if header_line == "":
		push_error("CSV file is empty: " + path)
		file.close()
		return upgrades
	
	var headers = header_line.split(",", false)
	# Clean headers
	for i in range(headers.size()):
		headers[i] = headers[i].strip_edges()
	
	# Read data lines
	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		
		# Skip empty lines
		if line == "":
			continue
		
		# Skip comment lines
		if line.begins_with("#"):
			continue
		
		# Split by comma
		var values = line.split(",", false)
		
		# Skip malformed lines (must have at least id, text, rarity, price)
		if values.size() < 4:
			continue
		
		# Build row dictionary
		var row := {}
		for i in range(min(headers.size(), values.size())):
			row[headers[i]] = values[i]
		
		# Build upgrade from row
		var upgrade = _build_upgrade_from_row(row)
		
		# Only add if id is not empty
		if upgrade.get("id", "") != "":
			upgrades.append(upgrade)
	
	file.close()
	
	print("[UpgradesDB] Loaded ", upgrades.size(), " upgrades from CSV: ", path)
	return upgrades


# -------------------------------------------------------------------
# HELPERS (UNCHANGED)
# -------------------------------------------------------------------

static func get_all() -> Array:
	return ALL_UPGRADES


static func get_non_chaos_upgrades() -> Array:
	"""Get all upgrades except chaos challenge upgrades (for normal shops/chests)."""
	var filtered := []
	
	for upgrade in ALL_UPGRADES:
		# Skip chaos upgrades
		if upgrade.get("effect") == "chaos_challenge":
			continue
		
		filtered.append(upgrade)
	
	return filtered


static func get_chaos_upgrades() -> Array:
	"""Get all chaos challenge upgrades."""
	var chaos_upgrades := []
	
	for upgrade in ALL_UPGRADES:
		if upgrade.get("effect") == "chaos_challenge":
			chaos_upgrades.append(upgrade)
	
	return chaos_upgrades


static func get_by_id(id: String) -> Dictionary:
	for u in ALL_UPGRADES:
		if u.get("id", "") == id:
			return u
	return {}


# -------------------------------------------------------------------
# 🔥 UPGRADE APPLICATION LOGIC (UNCHANGED)
# -------------------------------------------------------------------

static func apply_upgrade(upgrade_id: String) -> void:

	# Delegate to GameState which now owns upgrade application logic
	if Engine.has_singleton("GameState"):
		GameState.apply_upgrade(upgrade_id)
	else:
		# Fallback: try direct call (older setups)
		if typeof(GameState) != TYPE_NIL and GameState.has_method("apply_upgrade"):
			GameState.apply_upgrade(upgrade_id)

	_sync_player_after_upgrade()


# -------------------------------------------------------------------
# PLAYER SYNC HELPER (UNCHANGED)
# -------------------------------------------------------------------

static func _sync_player_after_upgrade() -> void:
	var tree = Engine.get_main_loop() as SceneTree
	if not tree:
		return

	var player = tree.get_first_node_in_group("player")
	if player and player.has_method("sync_from_gamestate"):
		player.sync_from_gamestate()

	var gun_node = null
	if player and player.has_node("Gun"):
		gun_node = player.get_node("Gun")
	
	if gun_node and gun_node.has_method("init_from_state"):
		gun_node.init_from_state()
