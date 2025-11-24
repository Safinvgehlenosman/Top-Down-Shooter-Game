extends CanvasLayer

@onready var hp_fill: TextureProgressBar     = $HPBar/HPFill
@onready var hp_label: Label                 = $HPBar/HPLabel
@onready var ammo_label: Label               = $AmmoUI/AmmoLabel
@onready var coin_label: Label               = $CoinUI/CoinLabel
@onready var ability_label: Label = $AbilityBar/AbilityLabel


# Ability bar wrapper (AbilityBar node itself)
@onready var ability_bar_container: Control  = $AbilityBar
@onready var ability_bar: TextureProgressBar = $AbilityBar/AbilityFill


func _ready() -> void:
	var gs = GameState

	# connect UI to gamestate
	gs.connect("coins_changed",  Callable(self, "_on_coins_changed"))
	gs.connect("health_changed", Callable(self, "_on_health_changed"))
	gs.connect("ammo_changed",   Callable(self, "_on_ammo_changed"))

	# initial sync
	_on_coins_changed(gs.coins)
	_on_health_changed(gs.health, gs.max_health)
	_on_ammo_changed(gs.ammo, gs.max_ammo)

	# hide by default
	ability_bar_container.visible = false


func _process(_delta: float) -> void:
	# Lightweight — cheap and safe
	_on_health_changed(GameState.health, GameState.max_health)
	_update_ability_bar()


# --------------------------------------------------------------------
# SIGNAL HANDLERS
# --------------------------------------------------------------------

func _on_coins_changed(new_value: int) -> void:
	coin_label.text = str(new_value)


func _on_health_changed(new_value: int, max_value: int) -> void:
	hp_fill.max_value = max_value
	hp_fill.value = new_value
	hp_label.text = "%d/%d" % [new_value, max_value]


func _on_ammo_changed(new_value: int, max_value: int) -> void:
	if max_value <= 0:
		ammo_label.text = "-/-"
	else:
		ammo_label.text = "%d/%d" % [new_value, max_value]


# --------------------------------------------------------------------
# ABILITY BAR VISIBILITY + COOLDOWN
# --------------------------------------------------------------------

func _update_ability_bar() -> void:
	var gs = GameState

	# No ability equipped → hide entire bar container
	if gs.ability == gs.ABILITY_NONE:
		ability_bar_container.visible = false
		return

	var data = gs.ABILITY_DATA.get(gs.ability, {})
	if data.is_empty():
		ability_bar_container.visible = false
		return

	var max_cd: float = data.get("cooldown", 0.0)
	if max_cd <= 0.0:
		ability_bar_container.visible = false
		return

	# Ability exists → show UI
	ability_bar_container.visible = true

	# --- BAR VALUE ---
	var cd_left: float = gs.ability_cooldown_left
	ability_bar.max_value = max_cd
	ability_bar.value = max_cd - cd_left

	# --- LABEL VALUE (rounded to 1 decimal) ---
	if ability_label:
		var remaining = round(cd_left * 10.0) / 10.0   # 1 decimal
		var max_display = round(max_cd * 10.0) / 10.0
		ability_label.text = "%s / %s s" % [remaining, max_display]
