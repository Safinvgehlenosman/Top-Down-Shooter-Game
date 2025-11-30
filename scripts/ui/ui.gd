extends CanvasLayer

# New UI structure - updated node paths
@onready var hp_progress_bar: TextureProgressBar = get_node_or_null("PlayerInfo/HPFill")
@onready var ability_progress_bar: TextureProgressBar = get_node_or_null("PlayerInfo/AbilityProgressBar")
@onready var ammo_label: Label = get_node_or_null("Ammo/AmmoLabel")
@onready var coin_label: Label = get_node_or_null("Coins/CoinsLabel")
@onready var level_label: Label = get_node_or_null("Level/LevelLabel")

# Use GameState enums directly
const ABILITY_NONE = GameState.AbilityType.NONE
const ALT_WEAPON_NONE = GameState.AltWeaponType.NONE
const ALT_WEAPON_TURRET = GameState.AltWeaponType.TURRET

var coin_animation_cooldown: float = 0.0


func _ready() -> void:
	var gs = GameState

	# connect UI to gamestate
	gs.connect("coins_changed",  Callable(self, "_on_coins_changed"))
	gs.connect("health_changed", Callable(self, "_on_health_changed"))
	gs.connect("ammo_changed",   Callable(self, "_on_ammo_changed"))

	# initial sync
	_refresh_from_state_full()

	# hide ability bar by default
	if ability_progress_bar:
		ability_progress_bar.visible = false


func _process(_delta: float) -> void:
	# Reduce coin animation cooldown
	if coin_animation_cooldown > 0:
		coin_animation_cooldown -= _delta
	
	# Update displays
	_update_hp_from_state()
	_update_ammo_from_state()
	_update_ability_bar()
	_update_level_label()


# --------------------------------------------------------------------
# STATE REFRESH
# --------------------------------------------------------------------

func _refresh_from_state_full() -> void:
	_update_coin_label()
	_update_hp_from_state()
	_update_ammo_from_state()
	_update_level_label()
	_update_ability_bar()


func _update_coin_label() -> void:
	if not coin_label:
		return
	coin_label.text = str(GameState.coins)


func _update_hp_from_state() -> void:
	if not hp_progress_bar:
		return
	hp_progress_bar.max_value = GameState.max_health
	hp_progress_bar.value = GameState.health


func _update_ammo_from_state() -> void:
	if not ammo_label:
		return
	# Display ammo only for ammo-using alt weapons; show "-/-" for NONE or TURRET
	if GameState.alt_weapon == ALT_WEAPON_NONE or GameState.alt_weapon == ALT_WEAPON_TURRET:
		ammo_label.text = "-/-"
	else:
		ammo_label.text = "%d/%d" % [GameState.ammo, GameState.max_ammo]


func _update_level_label() -> void:
	if not level_label:
		return
	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm and "current_level" in gm:
		level_label.text = str(gm.current_level)


func _update_ability_bar() -> void:
	# Check if node exists
	if not ability_progress_bar:
		return
	
	# Hide if no ability unlocked
	if GameState.ability == ABILITY_NONE:
		ability_progress_bar.visible = false
		return
	
	var data = GameState.ABILITY_DATA.get(GameState.ability, {})
	if data.is_empty():
		ability_progress_bar.visible = false
		return
	
	# Get BASE cooldown
	var base_cd: float = data.get("cooldown", 0.0)
	if base_cd <= 0.0:
		ability_progress_bar.visible = false
		return
	
	# Apply cooldown multiplier (from upgrades)
	var multiplier: float = 1.0
	if "ability_cooldown_mult" in GameState:
		multiplier = GameState.ability_cooldown_mult
	
	# Actual cooldown after upgrades
	var actual_max_cd: float = base_cd * multiplier
	
	# Show the bar (ability is unlocked)
	ability_progress_bar.visible = true
	
	# Bar fills as cooldown recovers
	ability_progress_bar.max_value = actual_max_cd
	var cd_left: float = GameState.ability_cooldown_left
	var bar_value: float = actual_max_cd - cd_left
	ability_progress_bar.value = bar_value


# --------------------------------------------------------------------
# SIGNAL HANDLERS
# --------------------------------------------------------------------

func _on_coins_changed(new_value: int) -> void:
	if not coin_label:
		return
	var old_value = int(coin_label.text) if coin_label.text != "" else 0
	_update_coin_label()
	
	# ⭐ Animate only if coins increased AND not on cooldown
	if new_value > old_value and coin_animation_cooldown <= 0:
		_animate_coin_feedback()
		coin_animation_cooldown = 0.5  # Prevent spam for 0.5 seconds


func _on_health_changed(_new_value: int, _max_value: int) -> void:
	_update_hp_from_state()


func _on_ammo_changed(_new_value: int, _max_value: int) -> void:
	_update_ammo_from_state()


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
