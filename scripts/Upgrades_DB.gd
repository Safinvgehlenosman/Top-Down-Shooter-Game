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
	EPIC
}

# ✅ THESE MUST MATCH GameState.AltWeaponType ENUM EXACTLY
# Verified against your game_state.gd enum order:
const ALT_WEAPON_NONE := 0
const ALT_WEAPON_SHOTGUN := 1
const ALT_WEAPON_SNIPER := 2
const ALT_WEAPON_FLAMETHROWER := 3  # ✅ Position 3
const ALT_WEAPON_GRENADE := 4        # ✅ Position 4 (was wrong)
const ALT_WEAPON_SHURIKEN := 5       # ✅ Position 5
const ALT_WEAPON_TURRET := 6         # ✅ Position 6 (was wrong)

# ✅ THESE MUST MATCH GameState.AbilityType ENUM EXACTLY
const ABILITY_NONE := 0
const ABILITY_DASH := 1
const ABILITY_SLOWMO := 2
const ABILITY_BUBBLE := 3
const ABILITY_INVIS := 4

# -------------------------------------------------------------------
# MASTER UPGRADE LIST
# -------------------------------------------------------------------

const ALL_UPGRADES: Array = [

	# -------------------------
	# GENERAL / CORE UPGRADES
	# -------------------------
	{
		"id": "max_hp_plus_1",
		"text": "+10 Max HP",
		"price": 150,
		"rarity": Rarity.COMMON,
		"icon": preload("res://assets/Separated/singleheart.png"),
	},
	{
		"id": "hp_refill",
		"text": "Refill HP",
		"price": 50,
		"rarity": Rarity.COMMON,
		"icon": preload("res://assets/Separated/singleheart.png"),
	},
	{
		"id": "max_ammo_plus_1",
		"text": "+1 Max Ammo",
		"price": 150,
		"rarity": Rarity.COMMON,
		"icon": preload("res://assets/Separated/bullet.png"),
		"requires_ammo_weapon": true,
	},
	{
		"id": "ammo_refill",
		"text": "Refill Ammo",
		"price": 50,
		"rarity": Rarity.COMMON,
		"icon": preload("res://assets/Separated/bullet.png"),
		"requires_ammo_weapon": true,
	},
	{
		"id": "ability_cooldown_minus_10",
		"text": "-10% Ability Cooldown",
		"price": 200,
		"rarity": Rarity.UNCOMMON,
		"icon": preload("res://assets/Separated/ammo.png"),
		"requires_any_ability": true,
	},

	# -------------------------
	# PRIMARY WEAPON UPGRADES
	# -------------------------
	{
		"id": "primary_damage_plus_10",
		"text": "+10% Primary Damage",
		"price": 200,
		"rarity": Rarity.UNCOMMON,
		"icon": preload("res://assets/Separated/singlebullet.png"),
	},
	{
		"id": "primary_fire_rate_plus_10",
		"text": "+10% Primary Fire Rate",
		"price": 200,
		"rarity": Rarity.UNCOMMON,
		"icon": preload("res://assets/Separated/singlebullet.png"),
	},
	{
		"id": "primary_burst_plus_1",
		"text": "+1 Primary Shot",
		"price": 300,
		"rarity": Rarity.RARE,
		"icon": preload("res://assets/Separated/singlebullet.png"),
	},

	# -------------------------
	# ALT WEAPON UNLOCKS
	# -------------------------
	{
		"id": "unlock_shotgun",
		"text": "Unlock Shotgun",
		"price": 300,
		"rarity": Rarity.UNCOMMON,
		"icon": preload("res://assets/bullets/shotgunbullet.png"),
		"requires_alt_weapon": ALT_WEAPON_NONE,
	},
	{
		"id": "unlock_sniper",
		"text": "Unlock Sniper",
		"price": 300,
		"rarity": Rarity.UNCOMMON,
		"icon": preload("res://assets/bullets/sniperbullet.png"),
		"requires_alt_weapon": ALT_WEAPON_NONE,
	},
	{
		"id": "unlock_turret",
		"text": "Unlock Turret Backpack",
		"price": 300,
		"rarity": Rarity.UNCOMMON,
		"icon": preload("res://assets/Separated/turreticon.png"),
		"requires_alt_weapon": ALT_WEAPON_NONE,
	},
	{
		"id": "unlock_flamethrower",
		"text": "Unlock Flamethrower",
		"price": 300,
		"rarity": Rarity.UNCOMMON,
		"icon": preload("res://assets/bullets/flamethrowerbullet.png"),
		"requires_alt_weapon": ALT_WEAPON_NONE,
	},
	{
		"id": "unlock_shuriken",
		"text": "Unlock Shuriken",
		"price": 300,
		"rarity": Rarity.UNCOMMON,
		"icon": preload("res://assets/bullets/shuriken.png"),
		"requires_alt_weapon": ALT_WEAPON_NONE,
	},
	{
		"id": "unlock_grenade",
		"text": "Unlock Grenade Launcher",
		"price": 300,
		"rarity": Rarity.UNCOMMON,
		"icon": preload("res://assets/bullets/grenade.png"),
		"requires_alt_weapon": ALT_WEAPON_NONE,
	},

	# -------------------------
	# ABILITY UNLOCKS
	# -------------------------
	{
		"id": "unlock_dash",
		"text": "Unlock Dash (Space)",
		"price": 300,
		"rarity": Rarity.UNCOMMON,
		"icon": preload("res://assets/Separated/ammo.png"),
		"requires_ability": ABILITY_NONE,
	},
	{
		"id": "unlock_slowmo",
		"text": "Unlock Bullet Time (Space)",
		"price": 300,
		"rarity": Rarity.UNCOMMON,
		"icon": preload("res://assets/Separated/ammo.png"),
		"requires_ability": ABILITY_NONE,
	},
	{
		"id": "unlock_bubble",
		"text": "Unlock Shield Bubble (Space)",
		"price": 300,
		"rarity": Rarity.UNCOMMON,
		"icon": preload("res://assets/shield.png"),
		"requires_ability": ABILITY_NONE,
	},
	{
		"id": "unlock_invis",
		"text": "Unlock Invisibility Cloak (Space)",
		"price": 300,
		"rarity": Rarity.UNCOMMON,
		"icon": preload("res://assets/Separated/ammo.png"),
		"requires_ability": ABILITY_NONE,
	},
]


# -------------------------------------------------------------------
# HELPERS
# -------------------------------------------------------------------

static func get_all() -> Array:
	return ALL_UPGRADES


static func get_by_id(id: String) -> Dictionary:
	for u in ALL_UPGRADES:
		if u.get("id", "") == id:
			return u
	return {}


# -------------------------------------------------------------------
# 🔥 UPGRADE APPLICATION LOGIC (FIXED)
# -------------------------------------------------------------------

static func apply_upgrade(upgrade_id: String) -> void:
	print("[UpgradesDB] Applying upgrade:", upgrade_id)

	match upgrade_id:
		# -------------------------
		# GENERAL / CORE UPGRADES
		# -------------------------
		"max_hp_plus_1":
			GameState.max_health += 10
			GameState.set_health(GameState.health + 10)
			print("  → Max HP now:", GameState.max_health)

		"hp_refill":
			GameState.set_health(GameState.max_health)
			print("  → HP refilled to:", GameState.max_health)

		"max_ammo_plus_1":
			GameState.max_ammo += 1
			GameState.set_ammo(GameState.ammo + 1)
			print("  → Max Ammo now:", GameState.max_ammo)

		"ammo_refill":
			GameState.set_ammo(GameState.max_ammo)
			print("  → Ammo refilled to:", GameState.max_ammo)

		"ability_cooldown_minus_10":
	# Reduce cooldown by 10% (stacks multiplicatively)
			GameState.ability_cooldown_mult *= 0.9
	
			var reduction_percent = int((1.0 - GameState.ability_cooldown_mult) * 100)
			print("  → Ability cooldown multiplier:", GameState.ability_cooldown_mult)
			print("  → Total reduction:", reduction_percent, "%")

		# -------------------------
		# PRIMARY WEAPON UPGRADES
		# -------------------------
		"primary_damage_plus_10":
			GameState.primary_damage *= 1.1
			print("  → Primary damage now:", GameState.primary_damage)

		"primary_fire_rate_plus_10":
			GameState.fire_rate *= 0.9
			print("  → Primary fire rate now:", GameState.fire_rate)

		"primary_burst_plus_1":
			GameState.primary_burst_count += 1
			print("  → Primary burst count now:", GameState.primary_burst_count)

		# -------------------------
		# ALT WEAPON UNLOCKS (✅ FIXED INDICES)
		# -------------------------
		"unlock_shotgun":
			GameState.set_alt_weapon(GameState.AltWeaponType.SHOTGUN)  # = 1
			GameState.max_ammo = 6
			GameState.set_ammo(6)
			print("  → Shotgun unlocked! (AltWeaponType = 1)")

		"unlock_sniper":
			GameState.set_alt_weapon(GameState.AltWeaponType.SNIPER)  # = 2
			GameState.max_ammo = 4
			GameState.set_ammo(4)
			print("  → Sniper unlocked! (AltWeaponType = 2)")

		"unlock_flamethrower":
			GameState.set_alt_weapon(GameState.AltWeaponType.FLAMETHROWER)  # = 3
			GameState.max_ammo = 100
			GameState.set_ammo(100)
			print("  → Flamethrower unlocked! (AltWeaponType = 3)")

		"unlock_grenade":
			GameState.set_alt_weapon(GameState.AltWeaponType.GRENADE)  # = 4 ✅
			GameState.max_ammo = 3
			GameState.set_ammo(3)
			print("  → Grenade Launcher unlocked! (AltWeaponType = 4)")

		"unlock_shuriken":
			GameState.set_alt_weapon(GameState.AltWeaponType.SHURIKEN)  # = 5
			GameState.max_ammo = 8
			GameState.set_ammo(8)
			print("  → Shuriken unlocked! (AltWeaponType = 5)")

		"unlock_turret":
			GameState.set_alt_weapon(GameState.AltWeaponType.TURRET)  # = 6 ✅
			GameState.max_ammo = 0
			GameState.set_ammo(0)
			print("  → Turret unlocked! (AltWeaponType = 6)")

		# -------------------------
		# ABILITY UNLOCKS
		# -------------------------
		"unlock_dash":
			GameState.set_ability(GameState.AbilityType.DASH)
			print("  → Dash unlocked!")

		"unlock_slowmo":
			GameState.set_ability(GameState.AbilityType.SLOWMO)
			print("  → Bullet Time unlocked!")

		"unlock_bubble":
			GameState.set_ability(GameState.AbilityType.BUBBLE)
			print("  → Shield Bubble unlocked!")

		"unlock_invis":
			GameState.set_ability(GameState.AbilityType.INVIS)
			print("  → Invisibility Cloak unlocked!")

		_:
			push_warning("[UpgradesDB] No handler for upgrade_id: %s" % upgrade_id)

	_sync_player_after_upgrade()


# -------------------------------------------------------------------
# PLAYER SYNC HELPER
# -------------------------------------------------------------------

static func _sync_player_after_upgrade() -> void:
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
