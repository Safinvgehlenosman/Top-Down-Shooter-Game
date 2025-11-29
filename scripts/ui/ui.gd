extends CanvasLayer

@onready var hp_fill: TextureProgressBar     = $HPBar/HPFill
@onready var hp_label: Label                 = $HPBar/HPLabel
@onready var ammo_label: Label               = $AmmoUI/AmmoLabel
@onready var coin_label: Label               = $CoinUI/CoinLabel

@onready var ability_bar_container: Control = $AbilityBar
@onready var ability_bar: TextureProgressBar = $AbilityBar/AbilityFill
@onready var ability_label: Label = $AbilityBar/AbilityLabel

const AbilityType = GameState.AbilityType

var coin_animation_cooldown: float = 0.0


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
	# Reduce coin animation cooldown
	if coin_animation_cooldown > 0:
		coin_animation_cooldown -= _delta
	
	# Lightweight — cheap and safe
	_on_health_changed(GameState.health, GameState.max_health)
	_update_ability_bar()


# --------------------------------------------------------------------
# SIGNAL HANDLERS
# --------------------------------------------------------------------

func _on_coins_changed(new_value: int) -> void:
	var old_value = int(coin_label.text) if coin_label.text != "" else 0
	coin_label.text = str(new_value)
	_autoscale_label_deferred(coin_label)
	
	# ⭐ Animate only if coins increased AND not on cooldown
	if new_value > old_value and coin_animation_cooldown <= 0:
		_animate_coin_feedback()
		coin_animation_cooldown = 0.5  # Prevent spam for 0.5 seconds


func _on_health_changed(new_value: int, max_value: int) -> void:
	hp_fill.max_value = max_value
	hp_fill.value = new_value
	hp_label.text = "%d/%d" % [new_value, max_value]
	_autoscale_label_deferred(hp_label)


func _on_ammo_changed(new_value: int, max_value: int) -> void:
	# Show "-/-" when no alt weapon or when it's the turret (which doesn't use player ammo)
	if GameState.alt_weapon == GameState.AltWeaponType.NONE or GameState.alt_weapon == GameState.AltWeaponType.TURRET:
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


# --------------------------------------------------------------------
# COIN COLLECTION FEEDBACK
# --------------------------------------------------------------------

func _animate_coin_feedback() -> void:
	if not coin_label:
		return
	
	# Kill any existing tween
	if coin_label.has_meta("coin_tween"):
		var old_tween = coin_label.get_meta("coin_tween")
		if old_tween and old_tween is Tween:
			old_tween.kill()
	
	# Create simple color flash tween
	var tween := create_tween()
	coin_label.set_meta("coin_tween", tween)
	
	# Flash to bright gold
	tween.tween_property(coin_label, "modulate", Color(1.0, 0.85, 0.0), 0.1)
	
	# Back to white
	tween.tween_property(coin_label, "modulate", Color.WHITE, 0.2)