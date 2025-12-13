extends CanvasLayer

# New UI structure - updated node paths
@onready var hp_progress_bar: TextureProgressBar = get_node_or_null("PlayerInfo/HPFill")
@onready var hp_label: Label = get_node_or_null("PlayerInfo/HP")
@onready var ability_progress_bar: TextureProgressBar = get_node_or_null("PlayerInfo/AbilityProgressBar")
@onready var ability_label: Label = get_node_or_null("PlayerInfo/ABILITY")
@onready var ammo_container: Control = get_node_or_null("Ammo")
@onready var ammo_bar: TextureProgressBar = get_node_or_null("Ammo/Ammo")
@onready var ammo_label: Label = get_node_or_null("Ammo/AmmoLabel")
@onready var coin_label: Label = get_node_or_null("Coins/CoinsLabel")
@onready var level_label: Label = get_node_or_null("Level/LevelLabel")
@onready var chaos_pact_indicator: TextureRect = get_node_or_null("ChaosPact")
@onready var door_arrow_root: Control = $DoorArrowRoot
@onready var door_arrow: TextureRect = $DoorArrowRoot/DoorArrow

# Fuel bar configuration (assign in inspector)
@export var weapon_fuel_progress_texture: Array[Texture2D] = []

# Door arrow tracking
var exit_door: Node2D = null
var player: Node2D = null
var in_shop: bool = false

# Use GameState enums directly
const ABILITY_NONE = GameState.AbilityType.NONE
const ALT_WEAPON_NONE = GameState.AltWeaponType.NONE
const ALT_WEAPON_TURRET = GameState.AltWeaponType.TURRET

var coin_animation_cooldown: float = 0.0
var is_in_hub: bool = true  # Start as true, game_manager will set to false when entering run
var ability_bar_display_value: float = 0.0
var ability_bar_prev_max: float = 0.0
var ability_bar_smooth_speed: float = 12.0
var ability_bar_mode: String = ""


func _ready() -> void:
	# Add to 'ui' group so gun.gd can find us
	add_to_group("ui")

	# ⭐ CRITICAL: Don't process when paused (so we don't interfere with PauseScreen)
	process_mode = Node.PROCESS_MODE_PAUSABLE

	var gs = GameState

	# connect UI to gamestate
	gs.connect("coins_changed",  Callable(self, "_on_coins_changed"))
	gs.connect("health_changed", Callable(self, "_on_health_changed"))

	# initial sync
	_refresh_from_state_full()

	# hide ability bar by default
	if ability_progress_bar:
		ability_progress_bar.visible = false
		# Force smooth Range behaviour to avoid stepped visuals
		ability_progress_bar.step = 0.0
		ability_progress_bar.rounded = false

	# hide chaos pact indicator by default
	if chaos_pact_indicator:
		chaos_pact_indicator.visible = false

	# Hide door arrow by default
	if door_arrow_root:
		door_arrow_root.visible = false
		exit_door = null

	else:
		pass

	# ALWAYS start with fuel bar hidden - only show when weapon equipped in-run
	if ammo_container:
		ammo_container.visible = false

	# Connect to alt weapon changes
	GameState.alt_weapon_changed.connect(_on_alt_weapon_changed)

	# Get player reference
	player = get_tree().get_first_node_in_group("player")


func set_player(p: Node2D) -> void:
	"""Set player reference for door arrow."""
	player = p


func set_in_shop(value: bool) -> void:
	"""Update shop state and hide arrow when entering shop."""
	in_shop = value
	if in_shop:
		exit_door = null
		if door_arrow_root:
			door_arrow_root.visible = false


func clear_exit_door() -> void:
	"""Clear exit door reference and hide arrow."""
	exit_door = null
	if door_arrow_root:
		door_arrow_root.visible = false

func _on_exit_door_spawned(door: Node2D) -> void:
	"""Handle exit door spawned signal from GameManager (stores reference only)."""


	# Always store the door reference (filtering happens in _should_show_door_arrow)
	exit_door = door
	
	if is_in_hub or in_shop:
		pass

	else:
		pass

func _on_alt_weapon_changed(new_weapon: int) -> void:
	"""Handle alt weapon change to show/hide fuel bar."""
	# Always hide if NONE or TURRET
	if new_weapon == ALT_WEAPON_NONE or new_weapon == ALT_WEAPON_TURRET:
		if ammo_container:
			ammo_container.visible = false

	# Otherwise gun.gd will call show_alt_weapon_fuel() if weapon uses fuel


func _process(_delta: float) -> void:
	# Reduce coin animation cooldown
	if coin_animation_cooldown > 0:
		coin_animation_cooldown -= _delta
	
	# Update player reference if needed
	if not player or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
	
	# Update door arrow rotation
	_update_door_arrow()
	
	# Update displays
	_update_hp_from_state()
	_update_ability_bar(_delta)
	_update_level_label()
	_update_chaos_pact_indicator()


func _should_show_door_arrow() -> bool:
	"""Check if door arrow should be visible."""
	# Never show in hub or shop
	if is_in_hub or in_shop:
		return false
	
	# Must have valid player and door references
	if player == null or exit_door == null:
		return false
	
	if not is_instance_valid(player) or not is_instance_valid(exit_door):
		return false
	
	# Only show when the door is actually visible on screen
	if not exit_door.visible:
		return false
	
	# Only show when door is unlocked (check door_locked property)
	# Door is always spawned now, but locked in combat rooms until cleared
	if "door_locked" in exit_door and exit_door.door_locked:
		return false
	
	# Only show when door is open (unlocked doors should be open)
	if "door_open" in exit_door and not exit_door.door_open:
		return false
	
	# Hide when player is very close to the door (already at it)
	var distance := player.global_position.distance_to(exit_door.global_position)
	if distance < 32.0:
		return false
	
	return true


func _update_door_arrow() -> void:
	"""Update door arrow visibility and rotation."""
	if not door_arrow_root:
		return
	
	if not _should_show_door_arrow():
		door_arrow_root.visible = false
		return
	
	# Show arrow
	door_arrow_root.visible = true
	
	# Calculate direction from player to door in WORLD space
	var dir: Vector2 = exit_door.global_position - player.global_position
	if dir == Vector2.ZERO:
		return
	
	# Get angle (relative to +X axis)
	var angle := dir.angle()
	
	# Arrow sprite points UP by default, so offset by +PI/2 to point in direction
	# (UP is -Y in Godot, angle() returns 0 for +X, so UP would be -PI/2 or 3*PI/2)
	door_arrow_root.rotation = angle + PI / 2.0


# --------------------------------------------------------------------
# STATE REFRESH
# --------------------------------------------------------------------

func _refresh_from_state_full() -> void:
	_update_coin_label()
	_update_hp_from_state()
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


# --------------------------------------------------------------------
# FUEL BAR SYSTEM (replaces ammo)
# --------------------------------------------------------------------

func show_alt_weapon_fuel(weapon_id: String, max_fuel: float, current_fuel: float, shots_per_bar: int, is_continuous: bool) -> void:
	"""Configure and show fuel bar when alt weapon is equipped."""
	if not ammo_container or not ammo_bar:
		return
	
	# ONLY show if NOT in hub
	if is_in_hub:

		ammo_container.visible = false
		return

	# Show container
	ammo_container.visible = true
	
	# Texture
	var idx := _get_weapon_fuel_texture_index(weapon_id)
	if idx >= 0 and idx < weapon_fuel_progress_texture.size():
		ammo_bar.texture_progress = weapon_fuel_progress_texture[idx]
	
	# Range and step
	ammo_bar.min_value = 0.0
	ammo_bar.max_value = max_fuel  # Already includes alt_fuel_max_bonus from GameState
	if is_continuous:
		ammo_bar.step = max_fuel / 100.0
	else:
		ammo_bar.step = max_fuel / max(shots_per_bar, 1)
	
	# Value
	ammo_bar.value = clamp(current_fuel, 0.0, max_fuel)


func update_alt_weapon_fuel(current_fuel: float) -> void:
	"""Update fuel bar value every frame."""
	if ammo_bar:
		ammo_bar.value = clamp(current_fuel, ammo_bar.min_value, ammo_bar.max_value)


func hide_alt_weapon_fuel() -> void:
	"""Hide fuel bar when no alt weapon or turret equipped."""
	if ammo_container:
		ammo_container.visible = false


func _get_weapon_fuel_texture_index(weapon_id: String) -> int:
	"""Map weapon ID to texture array index."""
	match weapon_id:
		"shotgun":
			return 0
		"sniper":
			return 1
		"grenade":
			return 2
		"shuriken":
			return 3
		"flamethrower":
			return 4
		_:
			return -1


func _update_level_label() -> void:
	if not level_label:
		return
	if not is_inside_tree():
		return
	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm and "current_level" in gm:
		level_label.text = str(gm.current_level)


func _update_ability_bar(_delta: float = 0.0) -> void:
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

	# Ensure we have a reasonable delta for smoothing (avoid snapping when _delta==0)
	var dt: float = _delta
	if dt <= 0.0:
		dt = 1.0 / 60.0

	# If Invis ability is currently active, show remaining active duration
	var new_mode: String = "hidden"
	if GameState.ability == GameState.AbilityType.INVIS and GameState.ability_active_left > 0.0:
		var invis_data = GameState.ABILITY_DATA.get(GameState.AbilityType.INVIS, {})
		var duration: float = invis_data.get("duration", 0.0)
		# Configure bar to represent remaining active time (drains to 0)
		ability_progress_bar.visible = true
		ability_progress_bar.max_value = duration
		# Compute target value and mode
		var target_value: float = GameState.ability_active_left
		new_mode = "invis_active"
		# If mode changed, snap once and record max
		if new_mode != ability_bar_mode:
			ability_bar_mode = new_mode
			ability_bar_display_value = target_value
			ability_bar_prev_max = ability_progress_bar.max_value
		# If max changed significantly, clamp display value to new range
		if not is_equal_approx(ability_progress_bar.max_value, ability_bar_prev_max) and ability_bar_prev_max > 0.0:
			ability_bar_display_value = clamp(ability_bar_display_value, 0.0, ability_progress_bar.max_value)
		ability_bar_prev_max = ability_progress_bar.max_value
		# Smooth toward target using stable dt (avoids snap when _delta==0)
		var alpha := 1.0 - exp(-ability_bar_smooth_speed * dt)
		ability_bar_display_value = lerp(ability_bar_display_value, target_value, alpha)
		ability_progress_bar.value = clamp(ability_bar_display_value, 0.0, ability_progress_bar.max_value)
		# Ensure our visual value overrides any other writers this frame by setting deferred
		call_deferred("_set_ability_bar_value_deferred", ability_bar_display_value)
		if ability_label:
			ability_label.visible = true
			ability_label.text = "%.1f s" % [GameState.ability_active_left]
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
	# Compute target and mode
	var cd_left: float = GameState.ability_cooldown_left
	var bar_value: float = actual_max_cd - cd_left
	var target_value_cd: float = bar_value
	new_mode = "cooldown"
	# If mode changed, snap display to target to avoid clunk, record max
	if new_mode != ability_bar_mode:
		ability_bar_mode = new_mode
		ability_bar_display_value = target_value_cd
		ability_bar_prev_max = ability_progress_bar.max_value
	# If max changed significantly, clamp display value
	if not is_equal_approx(ability_progress_bar.max_value, ability_bar_prev_max) and ability_bar_prev_max > 0.0:
		ability_bar_display_value = clamp(ability_bar_display_value, 0.0, ability_progress_bar.max_value)
	ability_bar_prev_max = ability_progress_bar.max_value
	# Smooth toward cooldown target using stable dt
	var alpha_cd := 1.0 - exp(-ability_bar_smooth_speed * dt)
	ability_bar_display_value = lerp(ability_bar_display_value, target_value_cd, alpha_cd)
	ability_progress_bar.value = clamp(ability_bar_display_value, 0.0, ability_progress_bar.max_value)
	# Also defer set to avoid being overwritten by other UI scripts in the same frame
	call_deferred("_set_ability_bar_value_deferred", ability_bar_display_value)
	
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
		pass


func _set_ability_bar_value_deferred(val: float) -> void:
	if ability_progress_bar:
		ability_progress_bar.value = clamp(val, 0.0, ability_progress_bar.max_value)

# --------------------------------------------------------------------
# HUB MODE (Hide in-run UI when in hub)
# --------------------------------------------------------------------

func set_in_hub(is_in_hub_mode: bool) -> void:
	print("=== UI set_in_hub() ===")
	print("is_in_hub_mode: ", is_in_hub_mode)
	is_in_hub = is_in_hub_mode

	# Clear door arrow when entering hub
	if is_in_hub:
		print("Clearing exit_door and hiding door_arrow_root")
		exit_door = null
		if door_arrow_root:
			door_arrow_root.visible = false

	# FORCE hide ammo container when entering hub
	if is_in_hub_mode and ammo_container:
		print("Hiding ammo_container")
		ammo_container.visible = false

	# Hide in-run UI when in hub, show them during runs
	var show_ui = not is_in_hub_mode
	print("show_ui: ", show_ui)
	var hp_bar = get_node_or_null("PlayerInfo/HPFill")
	if hp_bar:
		hp_bar.visible = show_ui
		print("  - HPFill visible: ", hp_bar.visible)

	var hp_container = get_node_or_null("PlayerInfo")
	if hp_container:
		hp_container.visible = show_ui
		print("  - PlayerInfo visible: ", hp_container.visible)

	var ability_bar = get_node_or_null("PlayerInfo/AbilityProgressBar")
	if ability_bar:
		ability_bar.visible = show_ui and GameState.ability != ABILITY_NONE
		print("  - AbilityProgressBar visible: ", ability_bar.visible)

	var ammo_ui = get_node_or_null("UI/Ammo")
	if ammo_ui:
		ammo_ui.visible = show_ui
		print("  - UI/Ammo visible: ", ammo_ui.visible)

	var coin_ui = get_node_or_null("Coins")
	if coin_ui:
		coin_ui.visible = show_ui
		print("  - Coins visible: ", coin_ui.visible)

	var level_ui = get_node_or_null("Level")
	if level_ui:
		level_ui.visible = show_ui
		print("  - Level visible: ", level_ui.visible)

	# Keep chaos pact indicator visible if active (even in hub)
	# It's already handled by _update_chaos_pact_indicator()
