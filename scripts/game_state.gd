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



func start_new_run() -> void:
	# Pull defaults from GameConfig (same place your Player uses)
	max_health = GameConfig.player_max_health
	health = max_health

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
