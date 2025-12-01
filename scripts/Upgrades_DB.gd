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
	CHAOS  # ⭐ Special chaos rarity for challenge upgrades
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
		print("[UpgradesDB] CSV loaded: ", ALL_UPGRADES.size(), " upgrades")
		print("[UpgradesDB] ALL_UPGRADES size = ", ALL_UPGRADES.size())

# Parse rarity string to enum value
func _parse_rarity(rarity_str: String) -> int:
	match rarity_str.to_lower():
		"common": return Rarity.COMMON
		"uncommon": return Rarity.UNCOMMON
		"rare": return Rarity.RARE
		"epic": return Rarity.EPIC
		"chaos": return Rarity.CHAOS
		_: return Rarity.COMMON

# Load upgrades from CSV file
func _load_upgrades_from_csv(path: String) -> Array:
	var upgrades := []
	var file := FileAccess.open(path, FileAccess.READ)
	
	if not file:
		push_error("[UpgradesDB] Failed to open CSV: " + path)
		return upgrades
	
	# Read headers
	var headers := file.get_csv_line()
	
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
			
			# Parse specific fields
			match key:
				"id", "text", "effect":
					upgrade[key] = value
				"rarity":
					upgrade[key] = _parse_rarity(value)
				"price":
					upgrade[key] = int(value)
				"icon_path":
					if value != "":
						upgrade["icon"] = ResourceLoader.load(value)
		
		if not upgrade.is_empty() and upgrade.has("id"):
			print("[UpgradesDB] Loaded: ", upgrade.get("id"), " - Price: ", upgrade.get("price"))
			upgrades.append(upgrade)
	
	file.close()
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
	_ensure_loaded()
	var chaos_upgrades := []
	for upgrade in ALL_UPGRADES:
		if upgrade.get("effect") == "chaos_challenge":
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
