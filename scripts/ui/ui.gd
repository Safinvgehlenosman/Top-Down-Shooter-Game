extends CanvasLayer  # or Control if that's what you use

@onready var hp_fill: TextureProgressBar     = $HPBar/HPFill
@onready var hp_label: Label                 = $HPBar/HPLabel
@onready var ammo_label: Label               = $AmmoUI/AmmoLabel
@onready var coin_label: Label               = $CoinUI/CoinLabel
@onready var ability_bar: TextureProgressBar = $AbilityBar/AbilityFill


func _ready() -> void:
	# Connect UI directly to GameState
	var gs = GameState

	gs.connect("coins_changed",  Callable(self, "_on_coins_changed"))
	gs.connect("health_changed", Callable(self, "_on_health_changed"))
	gs.connect("ammo_changed",   Callable(self, "_on_ammo_changed"))

	# Initial sync so UI is correct when level loads
	_on_coins_changed(gs.coins)
	_on_health_changed(gs.health, gs.max_health)
	_on_ammo_changed(gs.ammo, gs.max_ammo)


func _process(_delta: float) -> void:
	# Hard-sync HP every frame (cheap + reliable)
	_on_health_changed(GameState.health, GameState.max_health)
	_update_ability_bar()



# --------------------------------------------------------------------
# SIGNAL HANDLERS FROM GAMESTATE
# --------------------------------------------------------------------

func _on_coins_changed(new_value: int) -> void:
	if coin_label:
		coin_label.text = str(new_value)


func _on_health_changed(new_value: int, max_value: int) -> void:
	if hp_fill:
		hp_fill.max_value = max_value
		hp_fill.value = new_value

	if hp_label:
		hp_label.text = "%d/%d" % [new_value, max_value]


func _on_ammo_changed(new_value: int, max_value: int) -> void:
	if ammo_label:
		if max_value <= 0:
			ammo_label.text = "-/-"
		else:
			ammo_label.text = "%d/%d" % [new_value, max_value]


# --------------------------------------------------------------------
# ABILITY BAR (now also GameState-only)
# --------------------------------------------------------------------

func _update_ability_bar() -> void:
	# No ability equipped
	if GameState.ability == GameState.ABILITY_NONE:
		ability_bar.visible = false
		return

	# Load runtime ability stats
	var data: Dictionary = GameState.ABILITY_DATA.get(GameState.ability, {})
	if data.is_empty():
		ability_bar.visible = false
		return

	var max_cd: float = data.get("cooldown", 0.0)
	if max_cd <= 0.0:
		ability_bar.visible = false
		return
	
	ability_bar.visible = true
	ability_bar.max_value = max_cd

	# Cooldown time left is kept in GameState by AbilityComponent
	var cd_left: float = GameState.ability_cooldown_left

	# Fill bar as cooldown refills
	ability_bar.value = max_cd - cd_left
