extends Node

##
## UpgradesDB.gd
## Central database for *all* upgrade definitions.
## GameState only knows how to APPLY an upgrade by id.
## ShopUI only asks this DB what upgrades exist.
##

enum Rarity {
	COMMON,
	UNCOMMON,
	RARE,
	EPIC
}

# 🔁 Keep these in sync with GameState / ShopUI
const ALT_WEAPON_NONE := 0
const ALT_WEAPON_SHOTGUN := 1
const ALT_WEAPON_SNIPER := 2
const ALT_WEAPON_TURRET := 3
const ALT_WEAPON_FLAMETHROWER := 4
const ALT_WEAPON_SHURIKEN := 5
const ALT_WEAPON_GRENADE := 6

const ABILITY_NONE := 0
const ABILITY_DASH := 1
const ABILITY_SLOWMO := 2
const ABILITY_BUBBLE := 3
const ABILITY_INVIS := 4

# -------------------------------------------------------------------
# MASTER UPGRADE LIST
# -------------------------------------------------------------------
# Each entry:
# {
#   "id": String,
#   "text": String,           # label on card
#   "price": int,             # in coins
#   "rarity": Rarity,
#   "icon": Texture2D,
#   # optional requirement fields:
#   "requires_alt_weapon": int,
#   "requires_ammo_weapon": bool,
#   "requires_ability": int,
#   "requires_any_ability": bool,
# }
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
