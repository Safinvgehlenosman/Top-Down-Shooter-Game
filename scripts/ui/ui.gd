extends CanvasLayer

# New UI structure - updated node paths
@onready var hp_progress_bar: TextureProgressBar = get_node_or_null("PlayerInfo/HPFill")
@onready var hp_label: Label = get_node_or_null("PlayerInfo/HP")
@onready var ability_progress_bar: TextureProgressBar = get_node_or_null("PlayerInfo/AbilityProgressBar")
@onready var ability_label: Label = get_node_or_null("PlayerInfo/ABILITY")
@onready var ammo_label: Label = get_node_or_null("Ammo/AmmoLabel")
@onready var coin_label: Label = get_node_or_null("Coins/CoinsLabel")
@onready var level_label: Label = get_node_or_null("Level/LevelLabel")
@onready var chaos_pact_indicator: TextureRect = get_node_or_null("ChaosPact")

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
	
	# hide chaos pact indicator by default
	if chaos_pact_indicator:
		chaos_pact_indicator.visible = false


func _process(_delta: float) -> void:
	# Reduce coin animation cooldown
	if coin_animation_cooldown > 0:
		coin_animation_cooldown -= _delta
	
	# Update displays
	_update_hp_from_state()
	_update_ammo_from_state()
	_update_ability_bar()
	_update_level_label()
	_update_chaos_pact_indicator()


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
	
	# Update HP label with current/max format
	if hp_label:
		hp_label.text = "%d/%d" % [GameState.health, GameState.max_health]


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
		if ability_label:
			ability_label.visible = false
		return
	
	var data = GameState.ABILITY_DATA.get(GameState.ability, {})
	if data.is_empty():
		ability_progress_bar.visible = false
		if ability_label:
			ability_label.visible = false
		return
	
	# Get BASE cooldown
	var base_cd: float = data.get("cooldown", 0.0)
	if base_cd <= 0.0:
		ability_progress_bar.visible = false
		if ability_label:
			ability_label.visible = false
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
	
	# Update ability cooldown label
	if ability_label:
		ability_label.visible = true
		if cd_left > 0.0:
			ability_label.text = "%.1f/%.1f" % [cd_left, actual_max_cd]
		else:
			ability_label.text = "READY"


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


func _update_chaos_pact_indicator() -> void:
	"""Show/hide chaos pact indicator based on active challenge."""
	if not chaos_pact_indicator:
		return
	
	# Show if there's an active chaos challenge
	var is_active = not GameState.active_chaos_challenge.is_empty()
	var was_visible = chaos_pact_indicator.visible
	chaos_pact_indicator.visible = is_active
	
	# Debug output when state changes
	if is_active != was_visible:
		print("[UI] Chaos pact indicator: ", "ACTIVE" if is_active else "INACTIVE", " - Challenge: '", GameState.active_chaos_challenge, "'")


# --------------------------------------------------------------------
# HUB MODE (Hide in-run UI when in hub)
# --------------------------------------------------------------------

func set_in_hub(is_in_hub: bool) -> void:
	"""Toggle hub mode - hides/shows in-run UI elements."""
	# Hide in-run UI when in hub, show them during runs
	var show_ui = not is_in_hub
	
	# Use get_node_or_null to avoid errors if nodes don't exist
	var hp_bar = get_node_or_null("PlayerInfo/HPFill")
	if hp_bar:
		hp_bar.visible = show_ui
	
	var hp_container = get_node_or_null("PlayerInfo")
	if hp_container:
		hp_container.visible = show_ui
	
	var ability_bar = get_node_or_null("PlayerInfo/AbilityProgressBar")
	if ability_bar:
		ability_bar.visible = show_ui and GameState.ability != ABILITY_NONE
	
	var ammo_ui = get_node_or_null("Ammo")
	if ammo_ui:
		ammo_ui.visible = show_ui
	
	var coin_ui = get_node_or_null("Coins")
	if coin_ui:
		coin_ui.visible = show_ui
	
	var level_ui = get_node_or_null("Level")
	if level_ui:
		level_ui.visible = show_ui
	
	# Keep chaos pact indicator visible if active (even in hub)
	# It's already handled by _update_chaos_pact_indicator()
	
	print("[UI] Hub mode: ", "ENABLED" if is_in_hub else "DISABLED", " - In-run UI: ", "HIDDEN" if is_in_hub else "VISIBLE")
