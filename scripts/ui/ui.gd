extends CanvasLayer

@onready var hp_fill: TextureProgressBar     = $HPBar/HPFill
@onready var hp_label: Label                 = $HPBar/HPLabel
@onready var ammo_label: Label               = $AmmoUI/AmmoLabel
@onready var coin_label: Label               = $CoinUI/CoinLabel

@onready var ability_bar_container: Control  = $AbilityBar
@onready var ability_bar: TextureProgressBar = $AbilityBar/AbilityFill
@onready var ability_label: Label            = $AbilityBar/AbilityLabel


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

	# hide ability bar by default
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
	_autoscale_label_deferred(coin_label)


func _on_health_changed(new_value: int, max_value: int) -> void:
	hp_fill.max_value = max_value
	hp_fill.value = new_value
	hp_label.text = "%d/%d" % [new_value, max_value]
	_autoscale_label_deferred(hp_label)


func _on_ammo_changed(new_value: int, max_value: int) -> void:
	if max_value <= 0:
		ammo_label.text = "-/-"
	else:
		ammo_label.text = "%d/%d" % [new_value, max_value]
	_autoscale_label_deferred(ammo_label)


# --------------------------------------------------------------------
# ABILITY BAR VISIBILITY + COOLDOWN
# --------------------------------------------------------------------

func _update_ability_bar() -> void:
	var gs = GameState

	# No ability equipped → hide entire bar UI
	if gs.ability == gs.ABILITY_NONE:
		ability_bar_container.visible = false
		return

	# Load runtime ability data
	var data = gs.ABILITY_DATA.get(gs.ability, {})
	if data.is_empty():
		ability_bar_container.visible = false
		return

	var max_cd: float = data.get("cooldown", 0.0)
	if max_cd <= 0.0:
		ability_bar_container.visible = false
		return

	# If we reach here → ability exists & has cooldown → show the bar
	ability_bar_container.visible = true

	# Sync bar values
	ability_bar.max_value = max_cd
	var cd_left: float = gs.ability_cooldown_left
	ability_bar.value = max_cd - cd_left

	# Optional: show "remaining / total s"
	if ability_label:
		var remaining = round(cd_left * 10.0) / 10.0
		var max_display = round(max_cd * 10.0) / 10.0
		ability_label.text = "%s / %s s" % [remaining, max_display]
		_autoscale_label_deferred(ability_label)


# --------------------------------------------------------------------
# LABEL AUTOSCALE HELPERS
# --------------------------------------------------------------------

const LABEL_MAX_FONT_SIZE := 16
const LABEL_MIN_FONT_SIZE := 8

func _autoscale_label(label: Label) -> void:
	if label == null:
		return

	# Start at max size
	var size := LABEL_MAX_FONT_SIZE
	label.add_theme_font_size_override("font_size", size)

	# Shrink until it fits or we hit min size
	while size > LABEL_MIN_FONT_SIZE and label.get_minimum_size().x > label.size.x:
		size -= 1
		label.add_theme_font_size_override("font_size", size)


func _autoscale_label_deferred(label: Label) -> void:
	# Defer so layout/size is updated before we measure
	call_deferred("_autoscale_label", label)
