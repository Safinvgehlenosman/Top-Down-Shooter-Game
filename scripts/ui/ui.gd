extends CanvasLayer

@onready var hp_fill: TextureProgressBar     = $HPBar/HPFill
@onready var hp_label: Label                 = $HPBar/HPLabel
@onready var ammo_label: Label               = $AmmoUI/AmmoLabel
@onready var coin_label: Label               = $CoinUI/CoinLabel

@onready var ability_bar_container: Control = $AbilityBar
@onready var ability_bar: TextureProgressBar = $AbilityBar/AbilityFill
@onready var ability_label: Label = $AbilityBar/AbilityLabel

const AbilityType = GameState.AbilityType


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
	if ability_bar_container:
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
	if gs.ability == AbilityType.NONE:
		if ability_bar_container:
			ability_bar_container.visible = false
		return
	
	# Load runtime ability data
	var data = gs.ABILITY_DATA.get(gs.ability, {})
	if data.is_empty():
		if ability_bar_container:
			ability_bar_container.visible = false
		return
	
	# Get BASE cooldown from ability data
	var base_cd: float = data.get("cooldown", 0.0)
	if base_cd <= 0.0:
		if ability_bar_container:
			ability_bar_container.visible = false
		return
	
	# ✅ Apply cooldown multiplier (from upgrades)
	var multiplier: float = 1.0
	if "ability_cooldown_mult" in gs:
		multiplier = gs.ability_cooldown_mult
	
	# ✅ Actual cooldown after upgrades (this is what changes with purchases!)
	var actual_max_cd: float = base_cd * multiplier
	
	# Show the bar
	if ability_bar_container:
		ability_bar_container.visible = true
	
	# ✅ CORRECT: Bar starts FULL, empties when used, fills back up
	if ability_bar:
		ability_bar.max_value = actual_max_cd
		var cd_left: float = gs.ability_cooldown_left
		# When cd_left = max → bar = 0 (empty)
		# When cd_left = 0 → bar = max (full/ready)
		var bar_value: float = actual_max_cd - cd_left
		ability_bar.value = bar_value
	
	# ✅ Show time remaining (counts down to 0)
	if ability_label:
		var remaining = round(gs.ability_cooldown_left * 10.0) / 10.0
		var max_display = round(actual_max_cd * 10.0) / 10.0
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
