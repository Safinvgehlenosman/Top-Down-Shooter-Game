extends Node

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
		"hp_refill":
			health = max_health

		"max_hp_plus_1":
			max_health += 1
			health = max_health

		"ammo_refill":
			ammo = max_ammo

		"max_ammo_plus_1":
			max_ammo += 1
			ammo = max_ammo

		"fire_rate_plus_10":
			# 10% faster → 10% shorter cooldown
			if fire_rate > 0.0:
				fire_rate *= 0.9

		"shotgun_pellet_plus_1":
			shotgun_pellets += 1

		_:
			print("Unknown upgrade id:", id)

	# 👇 NEW: after any upgrade, sync player + UI
	_sync_player_from_state()





func start_new_run() -> void:
	# Pull defaults from GameConfig (same place your Player uses)
	max_health = GameConfig.player_max_health
	health = max_health
	
	fire_rate = GameConfig.player_fire_rate
	shotgun_pellets = GameConfig.alt_fire_bullet_count

	max_ammo = GameConfig.player_max_ammo
	ammo = max_ammo

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
