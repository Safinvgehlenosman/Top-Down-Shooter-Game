extends Node

const ALT_WEAPON_NONE := 0
const ALT_WEAPON_SHOTGUN := 1
const ALT_WEAPON_SNIPER := 2

const ALT_WEAPON_DATA := {
	ALT_WEAPON_SHOTGUN: {
		"max_ammo": 6,
		"pickup_amount": 2,
		"cooldown": 0.7,
		"spread_degrees": 15.0,
		"pellets": 3,  # can replace GameState.shotgun_pellets later
		"bullet_scene": preload("res://scenes/bullets/shotgun_bullet.tscn"),
		"bullet_speed": 900.0,
		"recoil": 300.0,
	},

	ALT_WEAPON_SNIPER: {
		"max_ammo": 4,
		"pickup_amount": 1,
		"cooldown": 1.2,
		"spread_degrees": 0.0,
		"pellets": 1,
		"bullet_scene": preload("res://scenes/bullets/sniper_bullet.tscn"),
		"bullet_speed": 1600.0,
		"recoil": 80.0,
		"pierce": true,
	},
}





var alt_weapon: int = ALT_WEAPON_NONE


signal coins_changed(new_value: int)
signal health_changed(new_value: int, max_value: int)
signal ammo_changed(new_value: int, max_value: int)
signal run_reset  # fired when a new run starts / stats reset

var coins: int = 0

var max_health: int = 0
var health: int = 0

var max_ammo: int = 0
var ammo: int = 0

var fire_rate: float = 0.0          # normal fire cooldown (seconds between shots)
var shotgun_pellets: int = 0        # how many pellets the alt-fire uses

func _ready() -> void:
	# Optional: auto-start a run when the game boots
	start_new_run()


func apply_upgrade(id: String) -> void:
	match id:

		"max_ammo_plus_1":
			max_ammo += 1
			ammo = max_ammo

		"fire_rate_plus_10":
			fire_rate = max(0.02, fire_rate * 0.95)

		"shotgun_pellet_plus_1":
			shotgun_pellets += 1

		"hp_refill":
			health = max_health

		"max_hp_plus_1":
			max_health += 1
			health = max_health

		"ammo_refill":
			ammo = max_ammo

		# 🔥 NEW WEAPON UNLOCKS
		"unlock_shotgun":
			alt_weapon = ALT_WEAPON_SHOTGUN
			var d := ALT_WEAPON_DATA[ALT_WEAPON_SHOTGUN]
			max_ammo = d["max_ammo"]
			ammo = max_ammo

		"unlock_sniper":
			alt_weapon = ALT_WEAPON_SNIPER
			var d := ALT_WEAPON_DATA[ALT_WEAPON_SNIPER]
			max_ammo = d["max_ammo"]
			ammo = max_ammo




	# 👇 NEW: after any upgrade, sync player + UI
	_sync_player_from_state()
	emit_signal("ammo_changed", ammo, max_ammo)




func start_new_run() -> void:
	# Reset health
	max_health = GameConfig.player_max_health
	health = max_health

	# Reset fire stats
	fire_rate = GameConfig.player_fire_rate
	shotgun_pellets = GameConfig.alt_fire_bullet_count

	# 🔥 Alt weapon + ammo reset
	alt_weapon = ALT_WEAPON_NONE
	max_ammo = 0
	ammo = 0

	# Coins
	coins = 0

	emit_signal("coins_changed", coins)
	emit_signal("health_changed", health, max_health)
	emit_signal("ammo_changed", ammo, max_ammo)
	emit_signal("run_reset")



func add_coins(amount: int) -> void:
	coins += amount
	emit_signal("coins_changed", coins)


func set_health(value: int) -> void:
	health = clampi(value, 0, max_health)
	emit_signal("health_changed", health, max_health)


func set_ammo(value: int) -> void:
	ammo = clampi(value, 0, max_ammo)
	emit_signal("ammo_changed", ammo, max_ammo)

func _sync_player_from_state() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("sync_from_gamestate"):
		player.sync_from_gamestate()
