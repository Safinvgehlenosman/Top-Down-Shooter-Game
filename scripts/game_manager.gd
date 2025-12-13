extends Node

# ============================================================================
# B2 WAVE SYSTEM - CLEAN, TIMER-DRIVEN, RELIABLE
# ============================================================================
# Wave Count: 1 + floor(level / 3)  →  L1-2=1, L3-5=2, L6-8=3, L9-11=4, etc.
# Enemy Distribution: Total enemies divided evenly across waves
# Wave Timing: 8s - (level * 0.2s), minimum 4s between waves
# Door Spawning: ONLY when remaining_enemies reaches 0
# No kill-based triggers, no race conditions, no overspawning
# ============================================================================

# Signals
signal exit_door_spawned(door: Node2D)

# === B2 WAVE SYSTEM - CLEAN TRACKING ===
var remaining_enemies: int = 0  # Total enemies alive in this combat room
var total_waves: int = 0  # Total number of waves for this level
var current_wave: int = 0  # Which wave we're currently on (1-indexed)
var scheduled_waves: int = 0  # How many waves have been spawned so far
var door_has_spawned: bool = false  # Has exit door been spawned yet?

@export var death_screen_path: NodePath
@export var shop_path: NodePath
@export var exit_door_path: NodePath

@export_group("Chest Scenes")
@export var bronze_chest_scene: PackedScene
@export var normal_chest_scene: PackedScene
@export var gold_chest_scene: PackedScene
@export var chaos_chest_scene: PackedScene  # ⭐ Chaos chest (challenge system)

@export var ui_root_path: NodePath

@export var crate_scene: PackedScene

@export var exit_door_scene: PackedScene
@export var shop_room_scene: PackedScene  # Shop room (e.g. room_shop.tscn)
@export var hub_room_scene: PackedScene  # Hub room (e.g. hub.tscn)
@export var room_scenes: Array[PackedScene] = []

@export_group("Enemy Spawn Padding")
@export var spawn_padding_radius: float = 12.0
@export var spawn_padding_attempts: int = 6   # currently unused but kept for tuning
@export var min_spawn_distance_from_player: float = 120.0  # Distance from player (with fallback)
@export var spawn_check_radius: float = 6.0  # Radius for wall collision check

# B2 Wave timing - decreases with level for faster pacing
const WAVE_INTERVAL_BASE := 8.0  # Base seconds between waves
const WAVE_INTERVAL_PER_LEVEL := 0.2  # Reduction per level
const WAVE_INTERVAL_MIN := 4.0  # Minimum interval


# --- ENEMY SPAWN TABLE ----------------------------------------------
# IMPORTANT: enemy_scenes indices should match these roles:
# 0 = GREEN (basic melee)           -> slime.tscn
# 1 = FAST (darkgreen, chaser)      -> darkgreen_slime.tscn
# 2 = FIRE (fire DoT melee)         -> fire_slime.tscn
# 3 = POISON (cloud DoT)            -> poison_slime.tscn
# 4 = ICE (slow, tanky)             -> ice_slime.tscn
# 5 = PURPLE (basic shooter)        -> purple_slime.tscn
# 6 = GHOST (phase / special)       -> ghost_slime.tscn

const ENEMY_INDEX_GREEN  := 0
const ENEMY_INDEX_FAST   := 1
const ENEMY_INDEX_FIRE   := 2
const ENEMY_INDEX_POISON := 3
const ENEMY_INDEX_ICE    := 4
const ENEMY_INDEX_PURPLE := 5
const ENEMY_INDEX_GHOST  := 6

# --- NEW UNIFIED ENEMY SCALING SYSTEM (BALANCING) ------------------
# Design philosophy:
# - HP scales exponentially (1.6x per level) to match OP player DPS
# - Enemy count scales linearly (6 + level*1.5) for balanced difficulty
# - Speed scales mildly and is capped at 2x to keep gameplay fair
# - Damage scales gently (3% per level) and is capped at 2x
# - Difficulty comes from QUANTITY + HP, not unfair one-shots

func get_base_green_slime_hp(level: int) -> int:
	"""Smoothed exponential HP curve for balanced difficulty.
	Green slime is the baseline. Other types use multipliers of this.
	L1-10: Exponential 1.35^(level-1) - PERFECT, don't change
	L11+: Flattened curve 1.12^(level-10) from L10 baseline to prevent runaway
	L1=10, L5≈55, L6≈74, L10≈165, L15≈291, L20≈513
	"""
	if level <= 10:
		# Keep original exponential curve for levels 1-10 (perfect balance)
		var hp := int(10.0 * pow(1.35, float(level - 1)))
		return max(hp, 1)
	else:
		# Flattened curve from L10 baseline to prevent bullet sponges
		var hp_at_10 := int(10.0 * pow(1.35, 9.0))  # ≈165 HP
		var hp := int(float(hp_at_10) * pow(1.12, float(level - 10)))
		return max(hp, 1)


func get_scaled_enemy_hp_by_type(level: int, enemy_type: String) -> int:
	"""Get scaled HP for a specific enemy type using multipliers."""
	var base_hp := get_base_green_slime_hp(level)
	var multiplier := 1.0
	
	match enemy_type:
		"green", "fast":  # Green and Fast (darkgreen) use baseline
			multiplier = 1.0
		"purple":  # Shooter is slightly tankier
			multiplier = 1.3
		"fire", "ice", "poison":  # Elemental slimes are tankier
			multiplier = 1.4
		"ghost":  # Ghost is fragile but annoying
			multiplier = 0.7
		_:
			multiplier = 1.0
	
	return int(round(base_hp * multiplier))


func get_scaled_contact_damage(base_damage: float, level: int) -> float:
	"""Damage scales gently (3% per level) with a 2x hard cap.
	Danger comes from many enemies, not one-shot kills.
	"""
	var mult := pow(1.03, level - 1)
	mult = min(mult, 2.0)  # Hard cap at 2x base damage
	return base_damage * mult


func get_fast_slime_weight(level: int) -> float:
	"""Dynamic fast slime spawn weight curve for gradual introduction.
	L1-4: 0.0 (none), L5-7: 0.10 (gentle), L8-11: 0.20 (moderate), L12+: 0.30 (common).
	"""
	if level <= 4:
		return 0.0
	elif level <= 7:
		return 0.10
	elif level <= 11:
		return 0.20
	else:
		return 0.30


@export_group("Enemies")
@export var enemy_scenes: Array[PackedScene] = []
@export var enemy_weights: Array[float] = []   # runtime weights, auto-filled

# 70% crate, 30% "some enemy" by default (you can still tweak this in inspector)
@export_range(0.0, 1.0, 0.01) var enemy_chance: float = 0.3
@export_range(0.0, 1.0, 0.01) var crate_chance: float = 0.7

var current_level: int = 1

@onready var room_container: Node2D = $"../RoomContainer"

var current_room: Node2D
var current_exit_door: Node2D = null

# Spawn marker arrays (populated from groups)
var enemy_spawn_points: Array[Node2D] = []
var crate_spawn_points: Array[Node2D] = []
var door_spawn_points: Array[Node2D] = []
var player_spawn_points: Array[Node2D] = []

# Shop room tracking
var in_shop: bool = false

# Hub room tracking
var in_hub: bool = false
var run_started: bool = false

# Wave system - timer-driven waves (NOT kill-driven)

# Chest spawning - one random chest per level system
var chest_should_spawn_this_level: bool = false
var chest_has_spawned_this_level: bool = false
var chest_drop_kill_index: int = -1
var enemy_death_counter: int = 0

@export_range(0.0, 1.0, 0.05) var chest_spawn_chance: float = 0.75  # 75% chance per level

# Chaos Chest spawning (every 10 levels)
var chaos_chest_spawn_point: Node2D = null
var chaos_chest_spawned_this_cycle: bool = false
var current_level_cycle: int = 0  # Which 10-level cycle we're in

# Alpha Slime Variant spawning
var has_spawned_alpha_this_level: bool = false

var game_ui: CanvasLayer
var next_scene_path: String = ""

var shop_ui: CanvasLayer
var death_screen: CanvasLayer
var is_in_death_sequence: bool = false

var exit_door: Area2D
var door_open: bool = false

@onready var restart_button: Button = $"../UI/PauseScreen/RestartButton"
@onready var death_restart_button: Button = $"../UI/DeathScreen/RestartButton"

# 🔁 Track last used room index so we don't repeat it
var last_room_index: int = -1


# --- PROGRESSION / SPAWN CURVE TUNING -------------------------------
# These are editable in the inspector so you can tweak the curve later.

@export_group("Enemy Unlock Levels")
@export var level_unlock_green: int  = 1   # basic melee
@export var level_unlock_fast: int   = 3   # darkgreen chaser (was 4)
@export var level_unlock_purple: int = 5   # shooter (was 7)
@export var level_unlock_poison: int = 7   # DoT cloud (was 10)
@export var level_unlock_ice: int    = 9   # slow / tanky (was 13)
@export var level_unlock_fire: int   = 7   # fire melee (was 10)
@export var level_unlock_ghost: int  = 10  # late-game special (was 16)

@export_group("Enemy Base Weights")
# These are "relative" weights; the per-level logic multiplies/combines them.
@export var weight_green: float  = 1.0
@export var weight_fast: float   = 0.9
@export var weight_purple: float = 0.7
@export var weight_poison: float = 0.5
@export var weight_ice: float    = 0.4
@export var weight_fire: float   = 0.4
@export var weight_ghost: float  = 0.2


func _ready() -> void:
	# Defensive reset: ensure normal time scale on scene load
	Engine.time_scale = 1.0
	randomize()
	# initial alpha flag state (no debug)

	# Death screen
	if death_screen_path != NodePath():
		death_screen = get_node(death_screen_path)
		if death_screen:
			death_screen.visible = false

	# Shop UI
	if shop_path != NodePath():
		shop_ui = get_node(shop_path)
		if shop_ui:
			shop_ui.visible = false

	if ui_root_path != NodePath():
		game_ui = get_node(ui_root_path)
		# Connect exit door signal to UI
		if game_ui and game_ui.has_method("_on_exit_door_spawned"):
			exit_door_spawned.connect(game_ui._on_exit_door_spawned)

	current_level = 1
	_update_level_ui()
	load_hub_room()


# --- ROOM LOADING HELPERS -------------------------------------------

func load_combat_room() -> void:
	"""Load a random combat room with enemies and crates."""
	in_shop = false
	in_hub = false
	remaining_enemies = 0
	door_has_spawned = false
	
	# Disable super magnet from previous room
	_disable_super_magnet()
	
	# Clear door arrow before loading new room
	if game_ui and game_ui.has_method("clear_exit_door"):
		game_ui.clear_exit_door()
	
	# Notify UI we're not in hub/shop
	if game_ui:
		if game_ui.has_method("set_in_hub"):
			game_ui.set_in_hub(false)
		if game_ui.has_method("set_in_shop"):
			game_ui.set_in_shop(false)
	
	_load_room_internal()


func load_shop_room() -> void:
	"""Load the shop room (no enemies, just a chest to interact with)."""
	if shop_room_scene == null:
		push_warning("No shop_room_scene assigned on GameManager")
		return
	
	in_shop = true
	in_hub = false
	remaining_enemies = 0
	door_has_spawned = false

	# Prepare per-visit shop offers storage: clear any previous offers so
	# the next chest/shop interaction will generate a fresh set for this room.
	if GameState:
		GameState.current_shop_offers.clear()
		GameState.shop_offers_generated = false
	
	# Disable super magnet
	_disable_super_magnet()
	
	# Clear door arrow and notify UI
	if game_ui:
		if game_ui.has_method("clear_exit_door"):
			game_ui.clear_exit_door()
		if game_ui.has_method("set_in_shop"):
			game_ui.set_in_shop(true)
		if game_ui.has_method("set_in_hub"):
			game_ui.set_in_hub(false)
	
	# Fade out global music and fade in shop music
	_crossfade_to_shop_music()
	
	# Clear room transient objects
	_clear_room_transient_objects()
	for bullet in get_tree().get_nodes_in_group("player_bullet"):
		bullet.queue_free()
	
	# Clear previous room if there was one
	if current_room and current_room.is_inside_tree():
		current_room.queue_free()
	
	current_room = null
	current_exit_door = null
	
	# Reset alpha slime tracking
	has_spawned_alpha_this_level = false
	
	# Instance shop room
	current_room = shop_room_scene.instantiate()
	room_container.add_child(current_room)
	
	# Fade music to shop track
	_crossfade_to_shop_music()
	
	# Collect spawn markers from shop room
	_collect_room_spawn_points()
	
	# Move player to shop spawn
	_move_player_to_room_spawn()
	
	# Spawn exit door immediately and unlock it (no enemies to kill in shop)
	_spawn_exit_door()


func load_hub_room() -> void:
	"""Load the hub room (safe area before starting a run)."""
	if hub_room_scene == null:
		push_warning("No hub_room_scene assigned on GameManager")
		# Fallback to combat room if hub is missing
		load_combat_room()
		return
	
	in_hub = true
	in_shop = false
	run_started = false
	remaining_enemies = 0
	door_has_spawned = false
	
	# Disable super magnet
	_disable_super_magnet()
	
	# Clear door arrow and notify UI we're in hub
	if game_ui:
		if game_ui.has_method("clear_exit_door"):
			game_ui.clear_exit_door()
		if game_ui.has_method("set_in_hub"):
			game_ui.set_in_hub(true)
		if game_ui.has_method("set_in_shop"):
			game_ui.set_in_shop(false)
	
	# Clear room transient objects
	_clear_room_transient_objects()
	for bullet in get_tree().get_nodes_in_group("player_bullet"):
		bullet.queue_free()
	
	# Clear previous room if there was one
	if current_room and current_room.is_inside_tree():
		current_room.queue_free()
	
	current_room = null
	current_exit_door = null
	
	# Reset alpha slime tracking
	has_spawned_alpha_this_level = false
	
	# Instance hub room
	current_room = hub_room_scene.instantiate()
	room_container.add_child(current_room)
	_collect_room_spawn_points()
	
	# Move player to hub spawn
	_move_player_to_room_spawn()
	
	# Disable player weapon in hub
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("set_weapon_enabled"):
		player.set_weapon_enabled(false)
	
	# Spawn exit door immediately and unlock it (no enemies to kill in hub)
	_spawn_exit_door()
	
	# Tell UI to hide in-run elements
	if game_ui and game_ui.has_method("set_in_hub"):
		game_ui.set_in_hub(true)


func start_run_from_hub() -> void:
	"""Start the run from the hub (loads first combat room)."""
	if run_started:
		return
	
	run_started = true
	in_hub = false
	
	# Reset to level 1
	current_level = 1
	_update_level_ui()
	
	# Load first combat room with fade transition
	FadeTransition.set_black()
	get_tree().paused = false
	
	load_combat_room()
	
	# Enable player weapon when leaving hub + grant spawn invincibility
	var player := get_tree().get_first_node_in_group("player")
	if player:
		if player.has_method("set_weapon_enabled"):
			player.set_weapon_enabled(true)
		if player.has_method("grant_spawn_invincibility"):
			player.grant_spawn_invincibility(2.0)
	
	# Refresh HP UI
	var hp_ui := get_tree().get_first_node_in_group("hp_ui")
	if hp_ui and hp_ui.has_method("refresh_from_state"):
		hp_ui.refresh_from_state()
	
	# Tell UI to show in-run elements
	if game_ui and game_ui.has_method("set_in_hub"):
		game_ui.set_in_hub(false)
	
	if game_ui:
		game_ui.visible = true
	
	await get_tree().create_timer(0.2).timeout
	FadeTransition.fade_out()
	await FadeTransition.fade_out_finished


func _load_room_internal() -> void:
	"""Internal room loading logic (used by load_combat_room)."""
	_clear_room_transient_objects()
	for bullet in get_tree().get_nodes_in_group("player_bullet"):
		bullet.queue_free()
	# clear previous room if there was one
	if current_room and current_room.is_inside_tree():
		current_room.queue_free()

	current_room = null
	current_exit_door = null
	remaining_enemies = 0
	door_has_spawned = false
	
	# Reset chest variables (old system - will be replaced in _spawn_room_content)
	enemy_death_counter = 0
	chest_has_spawned_this_level = false
	
	# Reset alpha slime tracking
	has_spawned_alpha_this_level = false

	# adjust spawn weights for current_level
	_update_enemy_weights_for_level()

	var scene_for_level := _pick_room_scene_for_level(current_level)
	if scene_for_level == null:
		push_warning("No room_scenes assigned on GameManager")
		return

	current_room = scene_for_level.instantiate()
	room_container.add_child(current_room)

	# Reset per-room heart spawn counter so crates in the new room follow room-cap rules
	GameState.hearts_spawned_this_room = 0
	
	# Collect spawn markers from room
	_collect_room_spawn_points()

	_spawn_room_content()
	_move_player_to_room_spawn()


# --- LEVEL UI -------------------------------------------------------

func _update_level_ui() -> void:
	var label := get_tree().get_first_node_in_group("level_label") as Label
	if label:
		label.text = "%d" % current_level
		if _is_themed_room(current_level):
			label.modulate = Color(1, 0.2, 0.2) # Red
		else:
			label.modulate = Color(1, 1, 1) # White


func _collect_room_spawn_points() -> void:
	"""Collect spawn markers ONLY from the current room (filtered by is_ancestor_of)."""
	enemy_spawn_points.clear()
	crate_spawn_points.clear()
	door_spawn_points.clear()
	player_spawn_points.clear()
	
	if not current_room:

		return

	# === ENEMY SPAWN FILTERING ===
	var all_enemy_markers = get_tree().get_nodes_in_group("enemy_spawn")
	print("[ENEMY SPAWN] All markers in group: %d" % all_enemy_markers.size())
	for marker in all_enemy_markers:
		if marker is Node2D and current_room.is_ancestor_of(marker):
			enemy_spawn_points.append(marker)
	print("[ENEMY SPAWN] Filtered markers in room: %d" % enemy_spawn_points.size())
	for m in enemy_spawn_points:
		pass

	# === CRATE SPAWN FILTERING ===
	var all_crate_markers = get_tree().get_nodes_in_group("crate_spawn")
	print("[CRATE SPAWN] All markers in group: %d" % all_crate_markers.size())
	for marker in all_crate_markers:
		if marker is Node2D and current_room.is_ancestor_of(marker):
			crate_spawn_points.append(marker)
	print("[CRATE SPAWN] Filtered markers in room: %d" % crate_spawn_points.size())
	for m in crate_spawn_points:
		pass

	# === DOOR SPAWN FILTERING ===
	var all_door_markers = get_tree().get_nodes_in_group("door_spawn")
	print("[DOOR SPAWN] All markers in group: %d" % all_door_markers.size())
	for marker in all_door_markers:
		if marker is Node2D and current_room.is_ancestor_of(marker):
			door_spawn_points.append(marker)
	print("[DOOR SPAWN] Filtered markers in room: %d" % door_spawn_points.size())
	for m in door_spawn_points:
		pass

	# === PLAYER SPAWN FILTERING ===
	var all_player_markers = get_tree().get_nodes_in_group("player_spawn")
	print("[PLAYER SPAWN] All markers in group: %d" % all_player_markers.size())
	for marker in all_player_markers:
		if marker is Node2D and current_room.is_ancestor_of(marker):
			player_spawn_points.append(marker)
	print("[PLAYER SPAWN] Filtered markers in room: %d" % player_spawn_points.size())
	for m in player_spawn_points:
		pass

	# === SUMMARY ===
	print("[SPAWN SUMMARY] Enemy: %d | Crate: %d | Door: %d | Player: %d" % 
		[enemy_spawn_points.size(), crate_spawn_points.size(), 
		 door_spawn_points.size(), player_spawn_points.size()])


func _move_player_to_room_spawn() -> void:
	var player := get_tree().get_first_node_in_group("player")

	if current_room:
		pass

	else:
		pass

	print("[PLAYER SPAWN] Player found: %s" % ("yes" if player else "no"))
	print("[PLAYER SPAWN] Available spawn markers: %d" % player_spawn_points.size())
	
	if not player or not current_room:
		push_error("[PLAYER SPAWN] Missing player or current_room - cannot spawn")
		return
	
	# Error if no spawn markers found
	if player_spawn_points.is_empty():
		push_error("[SPAWN ERROR] No player_spawn markers found in room %s" % current_room.name)
		# Try fallback method if available
		if current_room.has_method("get_player_spawn_point"):
			var spawn_point: Node2D = current_room.get_player_spawn_point()
			if spawn_point:

				player.global_position = spawn_point.global_position
			else:
				push_error("[PLAYER SPAWN] Fallback method returned null!")
		return
	
	# Use the FIRST marker (index 0) - should be the only one if filtering worked correctly
	var chosen_marker := player_spawn_points[0]
	var spawn_pos := chosen_marker.global_position

	# Move player
	player.global_position = spawn_pos

	# Update UI with player reference
	if game_ui and game_ui.has_method("set_player"):
		game_ui.set_player(player)


func _pick_room_scene_for_level(_level: int) -> PackedScene:
	if room_scenes.is_empty():
		return null

	# If there's only one room, we can't avoid repeats.
	if room_scenes.size() == 1:
		last_room_index = 0
		return room_scenes[0]

	# Pick a random index that is not the same as last_room_index
	var new_index := last_room_index
	while new_index == last_room_index:
		new_index = randi_range(0, room_scenes.size() - 1)

	last_room_index = new_index
	return room_scenes[new_index]


# --- ENEMY PICKING --------------------------------------------------

func _pick_enemy_scene() -> PackedScene:
	if enemy_scenes.is_empty():
		return null

	var total_weight: float = 0.0
	for w in enemy_weights:
		total_weight += max(w, 0.0)

	if total_weight <= 0.0:
		return null

	var r := randf() * total_weight
	var running := 0.0

	for i in range(enemy_scenes.size()):
		var w: float = 1.0
		if i < enemy_weights.size():
			w = max(enemy_weights[i], 0.0)

		running += w
		if r <= running:
			return enemy_scenes[i]

	# fallback in weird edge cases
	return enemy_scenes.back()


# --- SAFE SPAWN HELPERS ---------------------------------------------

# Physics-based check: is this position free of colliders?
# --- SAFE SPAWN HELPERS ---------------------------------------------

# Physics-based check: is this position free of colliders?
func _is_spawn_valid(pos: Vector2) -> bool:
	"""Very forgiving collision check - only blocks walls/obstacles on layer 1."""
	var space_state := get_viewport().world_2d.direct_space_state
	
	var shape := CircleShape2D.new()
	shape.radius = spawn_check_radius
	
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = Transform2D(0.0, pos)
	params.collide_with_bodies = true
	params.collide_with_areas = true
	
	# IMPORTANT: Only check layer 1 (World - walls/obstacles)
	# This prevents blocking on floors, player, enemies, etc.
	params.collision_mask = 1 << 0  # Layer 1 only (bit shift: 1 << 0 = layer 1)
	
	var results := space_state.intersect_shape(params, 8)
	return results.is_empty()


func _find_safe_spawn_position(base_pos: Vector2) -> Vector2:
	"""Slightly nudge position away from walls using small offsets."""
	if _is_spawn_valid(base_pos):
		return base_pos
	
	var offsets := [
		Vector2(8, 0), Vector2(-8, 0),
		Vector2(0, 8), Vector2(0, -8),
		Vector2(8, 8), Vector2(-8, 8),
		Vector2(8, -8), Vector2(-8, -8),
	]
	
	for off in offsets:
		var candidate: Vector2 = base_pos + off
		if _is_spawn_valid(candidate):
			return candidate
	
	# If nothing nearby is valid, return base_pos anyway
	# Caller can run _is_spawn_valid again and skip if needed
	return base_pos


func _get_valid_spawn_positions(spawn_points: Array[Node2D]) -> Array[Vector2]:
	"""Filter spawn points with fallback - never returns empty in tight rooms."""
	var collision_valid: Array[Vector2] = []
	var player := get_tree().get_first_node_in_group("player")
	
	# First pass: only collision-based validity
	for sp in spawn_points:
		var pos := sp.global_position
		pos = _find_safe_spawn_position(pos)
		if _is_spawn_valid(pos):
			collision_valid.append(pos)
	
	# If literally nothing passes the collision test, fall back to raw spawn positions
	if collision_valid.is_empty():
		for sp in spawn_points:
			collision_valid.append(sp.global_position)
		return collision_valid
	
	# Second pass: apply distance-from-player, but with fallback
	if not player:
		return collision_valid
	
	var far_enough: Array[Vector2] = []
	for pos in collision_valid:
		var dist := pos.distance_to(player.global_position)
		if dist >= 80.0:  # Reduced from 120 to 80 for better spawn distribution
			far_enough.append(pos)
	
	# If distance filter kills everything, fall back to collision-only
	if far_enough.is_empty():
		return collision_valid
	
	return far_enough


# --- STAGGERED ENEMY SPAWNING --------------------------------------

func _spawn_enemies_over_time(enemy_list: Array, spawn_points: Array[Node2D], duration: float, is_initial_spawn: bool = false) -> void:
	"""Spawn enemies gradually over time with proper distribution."""
	if enemy_list.is_empty():
		return

	print("[SPAWN] Total spawn_points provided:", spawn_points.size())
	for sp in spawn_points:
		pass

	var spawned_enemies: Array = []
	var candidate_positions := _get_valid_spawn_positions(spawn_points)
	
	print("[SPAWN] VALID COUNT:", candidate_positions.size())
	for c in candidate_positions:
		pass

	if candidate_positions.is_empty():

		return
	
	# FOR INITIAL SPAWN: Cap enemy count to valid positions (no stacking)
	# FOR WAVES: Allow expansion to reuse positions (they spawn over time)
	var wanted := enemy_list.size()
	if is_initial_spawn:
		# Initial spawn: NEVER duplicate positions, cap to available spots
		if wanted > candidate_positions.size():
			print("[SPAWN] Initial spawn capped: wanted %d, only %d valid positions available" % [wanted, candidate_positions.size()])
			wanted = candidate_positions.size()
			# Trim enemy list to match available positions
			enemy_list = enemy_list.slice(0, wanted)
	else:
		# Waves: Expand list if needed (enemies spawn over time so less stacking)
		if candidate_positions.size() < wanted:
			print("[SPAWN] Expanding spawn positions: have %d, need %d" % [candidate_positions.size(), wanted])
			var expanded: Array[Vector2] = []
			while expanded.size() < wanted:
				for pos in candidate_positions:
					expanded.append(pos)
					if expanded.size() >= wanted:
						break
			candidate_positions = expanded
			print("[SPAWN] Expanded to:", candidate_positions.size(), "positions")
	
	# Shuffle positions to spread enemies around
	candidate_positions.shuffle()
	
	# Adjust spawn duration based on level (faster spawns at higher levels)
	var level_adjusted_duration: float = clamp(duration - (current_level * 0.3), 2.0, duration)
	var interval: float = level_adjusted_duration / float(enemy_list.size())
	var pos_idx := 0
	var spawn_count := 0
	
	print("[SPAWN TIMING] Level %d: duration %.1fs → adjusted %.1fs, interval %.2fs" % [current_level, duration, level_adjusted_duration, interval])
	
	for enemy_scene in enemy_list:
		# Cycle through shuffled positions, wrapping around if more enemies than positions
		var pos := candidate_positions[pos_idx]
		pos_idx = (pos_idx + 1) % candidate_positions.size()
		
		# Apply safety nudge and validate
		pos = _find_safe_spawn_position(pos)
		if _is_spawn_valid(pos):
			var enemy: Node2D = enemy_scene.instantiate()
			enemy.global_position = pos
			
			# Determine enemy type for HP multiplier
			var enemy_type := _get_enemy_type_from_scene(enemy_scene)
			
			# Apply new unified HP scaling
			var health_comp = enemy.get_node_or_null("Health")
			if health_comp:
				var scaled_hp := get_scaled_enemy_hp_by_type(current_level, enemy_type)
				health_comp.max_health = scaled_hp
				health_comp.health = scaled_hp
			
			# Apply damage scaling
			if "contact_damage" in enemy:
				var base_damage := float(enemy.contact_damage)
				enemy.contact_damage = int(round(get_scaled_contact_damage(base_damage, current_level)))
			
			# Level behaviors (NOT HP/damage, already handled above)
			if enemy.has_method("apply_level_behaviors"):
				enemy.apply_level_behaviors(current_level)
			elif enemy.has_method("apply_level"):
				enemy.apply_level(current_level)
			
			current_room.add_child(enemy)
			spawned_enemies.append(enemy)
			
			if enemy.has_signal("died"):
				enemy.died.connect(_on_enemy_died.bind(enemy))
			
			spawn_count += 1

		# Wait before spawning next enemy (skip wait after last one)
		if spawn_count < enemy_list.size():
			await get_tree().create_timer(interval).timeout
	
	print("[SPAWN] Staggered spawn complete: %d enemies over %.1fs" % [spawned_enemies.size(), duration])
	
	# Alpha variant spawning handled elsewhere; no debug roll here
	
	# --- CHAOS CHEST DROPPER MARKING ---
	# Only mark chaos chest droppers (normal chests use kill-index system)
	var should_spawn_chaos := chaos_chest_spawned_this_cycle and GameState.active_chaos_challenge.is_empty()
	
	if should_spawn_chaos and not spawned_enemies.is_empty():
		spawned_enemies.shuffle()
		if is_instance_valid(spawned_enemies[0]):
			spawned_enemies[0].set_meta("drops_chaos_chest", true)


# --- SIMPLE INITIAL ENEMY SPAWNING ---------------------------------

func _spawn_enemy_at(pos: Vector2, enemy_scene: PackedScene = null) -> Node2D:
	"""Spawn a single enemy at the given position."""
	if enemy_scene == null:
		enemy_scene = _pick_enemy_scene()
	
	if enemy_scene == null:
		return null
	
	var enemy: Node2D = enemy_scene.instantiate()
	enemy.global_position = pos
	
	# Determine enemy type for HP multiplier (parse from scene name)
	var enemy_type := _get_enemy_type_from_scene(enemy_scene)
	
	# Apply new unified HP scaling
	var health_comp = enemy.get_node_or_null("Health")
	if health_comp:
		var scaled_hp := get_scaled_enemy_hp_by_type(current_level, enemy_type)
		health_comp.max_health = scaled_hp
		health_comp.health = scaled_hp
		print("[SCALING DEBUG] Spawned %s (type=%s) at level %d with HP=%d" % [enemy.name, enemy_type, current_level, scaled_hp])
	
	# Apply damage scaling if enemy has contact_damage
	if "contact_damage" in enemy:
		var base_damage := float(enemy.contact_damage)
		enemy.contact_damage = int(round(get_scaled_contact_damage(base_damage, current_level)))
	
	# Level application for slime-specific behaviors (NOT for HP/damage, those are handled above)
	if enemy.has_method("apply_level_behaviors"):
		enemy.apply_level_behaviors(current_level)
	elif enemy.has_method("apply_level"):
		# Fallback for old method, but HP/damage already set above
		enemy.apply_level(current_level)
	
	current_room.add_child(enemy)
	
	if enemy.has_signal("died"):
		enemy.died.connect(_on_enemy_died.bind(enemy))

	# Alpha application for single-spawn path removed (handled in wave/initial spawn logic)
	
	return enemy


func _spawn_initial_enemies(level: int) -> void:
	"""Spawn initial enemies using enemy_spawn markers (no physics validation)."""
	if in_hub:
		return
	
	var spawns := enemy_spawn_points.duplicate()
	if spawns.is_empty():

		return
	
	spawns.shuffle()
	
	var total_budget := _calculate_enemy_count_for_level(level, spawns.size())
	# 35% for initial spawn, no hard cap - let high levels spawn more up front
	var initial_budget: int = max(int(round(total_budget * 0.35)), 1)
	var initial_enemy_count: int = min(initial_budget, spawns.size())
	
	# SET REMAINING_ENEMIES TO TOTAL BUDGET (all enemies for this room)
	remaining_enemies = total_budget
	print("[ROOM] ========================================")
	print("[ROOM] Level %d: Total enemies = %d" % [level, total_budget])
	print("[ROOM] Initial spawn = %d, Wave budget = %d" % [initial_enemy_count, total_budget - initial_enemy_count])
	print("[ROOM] Remaining enemies set to: %d" % remaining_enemies)
	print("[ROOM] ========================================")

	var themed_room := _is_themed_room(level)
	var themed_slimes := _get_themed_room_slimes(level)
	var spawned_enemies: Array = []
	
	# Spawn one enemy per marker (no validation)
	for i in range(initial_enemy_count):
		var spawn_node: Node2D = spawns[i]
		var pos: Vector2 = spawn_node.global_position
		var enemy_scene: PackedScene = null
		
		if themed_room and themed_slimes.size() > 0:
			enemy_scene = themed_slimes[randi() % themed_slimes.size()]
		else:
			enemy_scene = _pick_enemy_scene()
		
		var enemy := _spawn_enemy_at(pos, enemy_scene)
		if enemy:
			spawned_enemies.append(enemy)
	
	# Alpha handling removed from initial spawn (alpha selection centralized elsewhere)
	
	# Handle chest droppers
	var should_spawn_chaos := chaos_chest_spawned_this_cycle and GameState.active_chaos_challenge.is_empty()
	var should_spawn_normal := randf() < chest_spawn_chance
	
	if should_spawn_chaos and not spawned_enemies.is_empty():
		spawned_enemies.shuffle()
		if is_instance_valid(spawned_enemies[0]):
			spawned_enemies[0].set_meta("drops_chaos_chest", true)
	
	if should_spawn_normal and not spawned_enemies.is_empty():
		spawned_enemies.shuffle()
		var chest_dropper = spawned_enemies[0]
		if is_instance_valid(chest_dropper):
			if chest_dropper.has_meta("drops_chaos_chest"):
				if spawned_enemies.size() > 1:
					chest_dropper = spawned_enemies[1]
				else:
					chest_dropper = null
			if chest_dropper and is_instance_valid(chest_dropper):
				chest_dropper.set_meta("drops_chest", true)


func _spawn_crates_for_room() -> void:
	"""Spawn crates at crate_spawn markers."""
	if not crate_scene:
		return
	
	if crate_spawn_points.is_empty():
		return
	
	for spawn_node in crate_spawn_points:
		var crate := crate_scene.instantiate()
		current_room.add_child(crate)
		crate.global_position = spawn_node.global_position
	
	print("[SPAWN] Crates: %d" % crate_spawn_points.size())




# --- SPAWNING ROOM CONTENT ------------------------------------------

func _spawn_room_content() -> void:
	if current_room == null:
		return
	
	# Detect room type from room script
	var room_type := "combat"  # Default
	if current_room.has_method("get") and "room_type" in current_room:
		room_type = current_room.room_type
	print("[ROOM] Room type detected: %s" % room_type)
	
	# Handle non-combat rooms (shop/hub) - spawn door immediately and skip combat logic
	if room_type in ["shop", "hub"]:
		print("[DOOR] Non-combat room (%s) → spawning door immediately." % room_type)
		_spawn_crates_for_room()  # Crates may exist in hub/shop
		_spawn_exit_door()
		return  # Skip all combat logic below
	
	# === COMBAT ROOM LOGIC ONLY ===
	# Spawn crates at crate markers
	_spawn_crates_for_room()
	
	# B2 Wave System Initialization
	var total_enemies := get_base_enemy_count(current_level)
	remaining_enemies = total_enemies
	total_waves = get_wave_count(current_level)
	current_wave = 0
	scheduled_waves = 0
	
	# Initialize chest system for this level
	enemy_death_counter = 0
	chest_has_spawned_this_level = false
	
	# 75% chance this level gets a chest at all
	chest_should_spawn_this_level = randf() < chest_spawn_chance
	
	if chest_should_spawn_this_level and remaining_enemies > 0:
		chest_drop_kill_index = randi_range(1, remaining_enemies)
		print("[CHEST] Level %d: chest will drop on kill #%d (total enemies=%d)" % [
			current_level,
			chest_drop_kill_index,
			remaining_enemies,
		])
	else:
		chest_drop_kill_index = -1
		print("[CHEST] Level %d: no chest this level (roll failed or no enemies)." % current_level)
	
	# Debug logs for difficulty verification
	var base_hp := get_base_green_slime_hp(current_level)
	var wave_delay := _calculate_wave_interval()
	var fast_weight := get_fast_slime_weight(current_level)
	print("[SCALING] Level %d → HP curve updated: base HP = %d" % [current_level, base_hp])
	print("[SCALING] Level %d → Waves = %d, Wave Delay = %.1fs" % [current_level, total_waves, wave_delay])
	print("[SCALING] Level %d → Fast Slime Weight = %.2f" % [current_level, fast_weight])
	print("[WAVES] Level %d → waves=%d, enemies=%d total" % [current_level, total_waves, total_enemies])
	
	# Spawn first wave immediately
	_spawn_next_wave()
	
	# DO NOT SPAWN EXIT DOOR HERE - it spawns when all enemies die (combat rooms only)


# --- SPAWN COUNT CALCULATION ---------------------------------------

func get_base_enemy_count(level: int) -> int:
	"""Base enemy count formula: more enemies for horde pressure.
	L1-10: Linear growth (6 + level*1.5)
	L11+: Capped at 20 enemies max to prevent overwhelming floods.
	"""
	var count := int(round(6.0 + level * 1.5))
	if level > 10:
		count = min(count, 20)  # Hard cap at 20 enemies for L11+
	return count


func _calculate_enemy_count_for_level(level: int, _available_spawns: int) -> int:
	"""Calculate how many enemies to spawn based on current level.
	New formula: 6 + level * 1.5 for balanced difficulty.
	L1=8, L5=14, L6=15, L10=21, L20=36
	
	NOTE: Crates are placed manually in editor, so we don't reduce enemy count.
	The enemy_ratio system is obsolete for this new scaling.
	"""
	var base_wave_size := get_base_enemy_count(level)
	
	# Use the base count directly - NO reduction via enemy_ratio
	# (enemy_ratio was for old crate/enemy distribution, now crates are manual)
	var enemy_count: int = base_wave_size
	
	print("[SCALING DEBUG] Level %d → enemy_count=%d (formula: 6 + level*1.5)" % [level, enemy_count])
	
	return enemy_count


func _calculate_crate_count_for_level(level: int, available_spawns: int) -> int:
	"""Calculate how many crates to spawn based on current level and spawn ratio."""
	# Use actual spawn points available
	var total_spawns = available_spawns
	
	# Calculate crate ratio (inverse of enemy ratio)
	var enemy_ratio = _get_enemy_ratio_for_level(level)
	var crate_ratio = 1.0 - enemy_ratio
	
	# Calculate crate count based on ratio
	var crate_count = int(total_spawns * crate_ratio)
	
	# Clamp to reasonable values (min 1, max based on remaining spawns)
	crate_count = clamp(crate_count, 1, available_spawns)
	
	return crate_count


func _get_enemy_ratio_for_level(level: int) -> float:
	"""Get the enemy spawn ratio for a given level. Aggressively transitions from 50% to 90%."""
	# New curve:
	# Level 1: 50% enemies
	# Level 5: 60% enemies  
	# Level 10: 75% enemies
	# Level 20+: 90% enemies (hard cap)
	
	if level >= 20:
		return 0.9
	
	if level <= 1:
		return 0.5
	
	# Piecewise linear interpolation
	if level <= 5:
		# 1→5: 50% → 60%
		var progress = float(level - 1) / 4.0
		return 0.5 + (progress * 0.1)
	elif level <= 10:
		# 5→10: 60% → 75%
		var progress = float(level - 5) / 5.0
		return 0.6 + (progress * 0.15)
	else:
		# 10→20: 75% → 90%
		var progress = float(level - 10) / 10.0
		return 0.75 + (progress * 0.15)


func _get_enemy_type_from_scene(scene: PackedScene) -> String:
	"""Determine enemy type from scene resource path for HP multiplier."""
	if scene == null:
		return "green"
	
	var path := scene.resource_path.to_lower()
	
	if "darkgreen" in path or "fast" in path:
		return "fast"
	elif "purple" in path:
		return "purple"
	elif "fire" in path:
		return "fire"
	elif "ice" in path:
		return "ice"
	elif "poison" in path:
		return "poison"
	elif "ghost" in path:
		return "ghost"
	else:
		return "green"  # Default to green slime


# --- ENEMY WEIGHT SCALING / PROGRESSION -----------------------------

func _update_enemy_weights_for_level() -> void:
	if enemy_scenes.is_empty():
		return

	# Make sure weights array is big enough
	if enemy_weights.size() < enemy_scenes.size():
		enemy_weights.resize(enemy_scenes.size())

	# Reset all weights to 0 by default
	for i in range(enemy_weights.size()):
		enemy_weights[i] = 0.0

	var lvl := current_level

	# --- Enemy spawn curve by level range ---
	#  1–3   : Green only (learning)
	#  4–6   : Green + Fast
	#  7–9   : Add Purple (shooter)
	# 10–12  : Add Poison + Fire
	# 13–15  : Add Ice
	# 16–20  : Add Ghost (rare)
	# 21+    : Full mix, slightly more dangerous composition

	if lvl < 4:
		if lvl >= level_unlock_green:
			enemy_weights[ENEMY_INDEX_GREEN] = weight_green

	elif lvl < 7:
		# Green + Fast (gentle fast-slime introduction)
		if lvl >= level_unlock_green:
			enemy_weights[ENEMY_INDEX_GREEN] = weight_green
		if lvl >= level_unlock_fast and enemy_weights.size() > ENEMY_INDEX_FAST:
			var fast_weight := get_fast_slime_weight(lvl)
			enemy_weights[ENEMY_INDEX_FAST] = fast_weight

	elif lvl < 10:
		# Green + Fast + a bit of Purple (shooter)
		if lvl >= level_unlock_green:
			enemy_weights[ENEMY_INDEX_GREEN] = weight_green
		if lvl >= level_unlock_fast and enemy_weights.size() > ENEMY_INDEX_FAST:
			var fast_weight := get_fast_slime_weight(lvl)
			enemy_weights[ENEMY_INDEX_FAST] = fast_weight
		if lvl >= level_unlock_purple and enemy_weights.size() > ENEMY_INDEX_PURPLE:
			enemy_weights[ENEMY_INDEX_PURPLE] = weight_purple * 0.5

	elif lvl < 13:
		# Add Poison + Fire, ramp Purple slightly
		if lvl >= level_unlock_green:
			enemy_weights[ENEMY_INDEX_GREEN] = weight_green * 0.8
		if lvl >= level_unlock_fast and enemy_weights.size() > ENEMY_INDEX_FAST:
			var fast_weight := get_fast_slime_weight(lvl)
			enemy_weights[ENEMY_INDEX_FAST] = fast_weight
		if lvl >= level_unlock_purple and enemy_weights.size() > ENEMY_INDEX_PURPLE:
			enemy_weights[ENEMY_INDEX_PURPLE] = weight_purple * 0.8
		if lvl >= level_unlock_poison and enemy_weights.size() > ENEMY_INDEX_POISON:
			enemy_weights[ENEMY_INDEX_POISON] = weight_poison * 0.7
		if lvl >= level_unlock_fire and enemy_weights.size() > ENEMY_INDEX_FIRE:
			enemy_weights[ENEMY_INDEX_FIRE] = weight_fire * 0.6

	elif lvl < 16:
		# Add Ice (tanky support)
		if lvl >= level_unlock_green:
			enemy_weights[ENEMY_INDEX_GREEN] = weight_green * 0.6
		if lvl >= level_unlock_fast and enemy_weights.size() > ENEMY_INDEX_FAST:
			var fast_weight := get_fast_slime_weight(lvl)
			enemy_weights[ENEMY_INDEX_FAST] = fast_weight
		if lvl >= level_unlock_purple and enemy_weights.size() > ENEMY_INDEX_PURPLE:
			enemy_weights[ENEMY_INDEX_PURPLE] = weight_purple
		if lvl >= level_unlock_poison and enemy_weights.size() > ENEMY_INDEX_POISON:
			enemy_weights[ENEMY_INDEX_POISON] = weight_poison * 0.8
		if lvl >= level_unlock_fire and enemy_weights.size() > ENEMY_INDEX_FIRE:
			enemy_weights[ENEMY_INDEX_FIRE] = weight_fire * 0.7
		if lvl >= level_unlock_ice and enemy_weights.size() > ENEMY_INDEX_ICE:
			enemy_weights[ENEMY_INDEX_ICE] = weight_ice * 0.7

	elif lvl < 21:
		# Add Ghost (rare), mid/late mix
		if lvl >= level_unlock_green:
			enemy_weights[ENEMY_INDEX_GREEN] = weight_green * 0.5
		if lvl >= level_unlock_fast and enemy_weights.size() > ENEMY_INDEX_FAST:
			var fast_weight := get_fast_slime_weight(lvl)
			enemy_weights[ENEMY_INDEX_FAST] = fast_weight
		if lvl >= level_unlock_purple and enemy_weights.size() > ENEMY_INDEX_PURPLE:
			enemy_weights[ENEMY_INDEX_PURPLE] = weight_purple
		if lvl >= level_unlock_poison and enemy_weights.size() > ENEMY_INDEX_POISON:
			enemy_weights[ENEMY_INDEX_POISON] = weight_poison
		if lvl >= level_unlock_fire and enemy_weights.size() > ENEMY_INDEX_FIRE:
			enemy_weights[ENEMY_INDEX_FIRE] = weight_fire
		if lvl >= level_unlock_ice and enemy_weights.size() > ENEMY_INDEX_ICE:
			enemy_weights[ENEMY_INDEX_ICE] = weight_ice
		if lvl >= level_unlock_ghost and enemy_weights.size() > ENEMY_INDEX_GHOST:
			enemy_weights[ENEMY_INDEX_GHOST] = weight_ghost * 0.4

	else:
		# 21+ : Full chaos mix – slightly more elites / ranged / control
		if lvl >= level_unlock_fast and enemy_weights.size() > ENEMY_INDEX_FAST:
			var fast_weight := get_fast_slime_weight(lvl)
			enemy_weights[ENEMY_INDEX_FAST] = fast_weight
		if lvl >= level_unlock_green:
			enemy_weights[ENEMY_INDEX_GREEN] = weight_green * 0.4
		if lvl >= level_unlock_fast and enemy_weights.size() > ENEMY_INDEX_FAST:
			enemy_weights[ENEMY_INDEX_FAST] = weight_fast * 1.1
		if lvl >= level_unlock_purple and enemy_weights.size() > ENEMY_INDEX_PURPLE:
			enemy_weights[ENEMY_INDEX_PURPLE] = weight_purple * 1.2
		if lvl >= level_unlock_poison and enemy_weights.size() > ENEMY_INDEX_POISON:
			enemy_weights[ENEMY_INDEX_POISON] = weight_poison
		if lvl >= level_unlock_fire and enemy_weights.size() > ENEMY_INDEX_FIRE:
			enemy_weights[ENEMY_INDEX_FIRE] = weight_fire
		if lvl >= level_unlock_ice and enemy_weights.size() > ENEMY_INDEX_ICE:
			enemy_weights[ENEMY_INDEX_ICE] = weight_ice * 1.1
		if lvl >= level_unlock_ghost and enemy_weights.size() > ENEMY_INDEX_GHOST:
			enemy_weights[ENEMY_INDEX_GHOST] = weight_ghost * 0.6


# --- ENEMY DEATH / DOOR SPAWN --------------------------------------

func _on_enemy_died(enemy: Node2D = null) -> void:
	"""B2: Simple enemy death handler - decrements counter and spawns door when all dead."""
	remaining_enemies -= 1
	print("[ROOM] Enemy died, remaining=%d" % remaining_enemies)
	
	# Track total kills in this room
	enemy_death_counter += 1
	
	# Check chest drop based on kill index
	if chest_should_spawn_this_level \
			and not chest_has_spawned_this_level \
			and enemy_death_counter == chest_drop_kill_index:
		var chest_type := _choose_random_chest_type()
		_spawn_chest_at_enemy_position(enemy.global_position, chest_type)
		chest_has_spawned_this_level = true
		print("[CHEST] Dropped %s chest on kill #%d at %s" % [
			str(chest_type),
			enemy_death_counter,
			str(enemy.global_position),
		])
	
	# Check if this enemy should drop chaos chest
	if enemy != null and enemy.has_meta("drops_chaos_chest"):
		_spawn_chaos_chest_at_enemy_position(enemy.global_position)
	
	# B2: When all enemies are dead, break crates and spawn the exit door
	if remaining_enemies == 0:
		# If we were previously in a shop, clear the per-visit shop offers cache
		var _was_in_shop := in_shop
		in_shop = false
		if _was_in_shop and GameState and GameState.has_method("clear_shop_offers"):
			GameState.clear_shop_offers()
		# Break crates and spawn the exit door for this room
		_break_all_crates_in_room()
		_spawn_exit_door()

	# Dash Executioner: refund dash cooldown on kill if enabled
	if GameState.dash_executioner_enabled and GameState.ability == GameState.AbilityType.DASH:
		var before_cd := GameState.ability_cooldown_left
		if before_cd > 0.0:
			GameState.ability_cooldown_left = max(0.0, before_cd - 0.75)
			print("[DASH EXEC] refund applied: %.2f -> %.2f" % [before_cd, GameState.ability_cooldown_left])








func _spawn_exit_door() -> void:
	"""B2: Spawn the exit door (simple, clean, unlocked)."""
	if door_has_spawned:
		return  # Already spawned
	
	if exit_door_scene == null:
		push_error("[DOOR] No exit_door_scene assigned!")
		return
	
	if not current_room:
		push_error("[DOOR] No current_room - cannot spawn door")
		return
	
	if door_spawn_points.is_empty():
		push_error("[DOOR] No spawn markers found!")
		return
	
	var marker = door_spawn_points.pick_random()
	var door = exit_door_scene.instantiate()
	door.global_position = marker.global_position
	current_room.add_child(door)
	current_exit_door = door
	door_has_spawned = true
	
	# Wait for door's _ready() to finish before unlocking
	await get_tree().process_frame
	
	# Door is always unlocked when spawned
	if door.has_method("unlock_and_open"):
		door.unlock_and_open()
	
	print("[DOOR] Exit door spawned at: %s" % marker.global_position)
	
	# Emit signal for UI
	emit_signal("exit_door_spawned", door)





func _on_level_cleared() -> void:
	"""DEPRECATED - No longer used. Room clear logic moved to _check_room_cleared().
	This function used budget-based logic which was too fragile.
	Kept for reference only - can be removed in future cleanup."""
	pass
	# OLD BUDGET-BASED LOGIC (NO LONGER USED):
	# - Checked budget_complete AND all_waves_scheduled
	# - Had hard safety guard for enemy count
	# - Called _auto_break_crates, _enable_super_magnet, _unlock_and_open_exit_door
	# NOW: _check_room_cleared() handles all this based on actual enemy count only


func _enable_super_magnet() -> void:
	"""Trigger auto-collect phase (magnet range already 9999 by default)."""
	# Magnet radius is always 9999 now - no need to change it
	# This function just logs the auto-collect phase for debugging
	
	# Log pickup count for debugging
	var pickups: Array = []
	pickups += get_tree().get_nodes_in_group("pickup_coin")
	pickups += get_tree().get_nodes_in_group("pickup_heart")
	pickups += get_tree().get_nodes_in_group("pickup_ammo")
	print("[AUTO COLLECT] Room-wide collection triggered (magnet range already 9999) - collecting %d pickups" % pickups.size())


func _disable_super_magnet() -> void:
	"""End auto-collect phase (magnet range stays at 9999 always)."""
	# Magnet radius stays at 9999 - no changes needed
	# This function kept for future behavior or logging if needed
	print("[AUTO COLLECT] Auto-collect phase ended (magnet range stays 9999)")

func _break_all_crates_in_room() -> void:
	"""Break all crates in the current combat room when all enemies are defeated."""
	if not current_room:
		return
	
	# Only break crates in combat rooms
	var room_type := "combat"
	if current_room.has_method("get") and "room_type" in current_room:
		room_type = current_room.room_type
	
	if room_type in ["shop", "hub"]:
		return  # Don't break crates in shop/hub
	
	var crates := _get_room_nodes_in_group("crate")
	print("[AUTO BREAK] Breaking %d crates" % crates.size())
	
	for crate in crates:
		if crate.has_method("force_break"):
			crate.force_break()
		elif crate.has_method("take_damage"):
			# Fallback: deal massive damage to break it
			crate.take_damage(9999)


func _get_room_nodes_in_group(group_name: String) -> Array:
	"""Get all nodes in a group that are children of the current room."""
	var result: Array = []
	if not current_room:
		return result
	
	for node in get_tree().get_nodes_in_group(group_name):
		if current_room.is_ancestor_of(node):
			result.append(node)
	
	return result


func _choose_random_chest_type() -> String:
	"""Choose a random chest type with weighted probability.
	Bronze: 50%, Normal: 35%, Gold: 15%
	"""
	var r := randf()
	if r < 0.5:
		return "bronze"
	elif r < 0.85:
		return "normal"
	else:
		return "gold"


func _spawn_chest_at_enemy_position(position: Vector2, chest_type: String = "") -> void:
	"""Spawn a chest at the enemy's death position. In themed rooms, always spawn gold chest."""
	print("[CHEST] Spawning chest at position: ", position)
	var chest_scene: PackedScene = null
	
	# Use provided chest type, or default to gold in themed rooms
	if _is_themed_room(current_level):
		chest_scene = gold_chest_scene
	elif chest_type == "bronze":
		chest_scene = bronze_chest_scene
	elif chest_type == "normal":
		chest_scene = normal_chest_scene
	elif chest_type == "gold":
		chest_scene = gold_chest_scene
	else:
		# Fallback: use weighted random selection
		var chest_roll := randf()
		if chest_roll < 0.50:
			chest_scene = bronze_chest_scene
		elif chest_roll < 0.85:
			chest_scene = normal_chest_scene
		else:
			chest_scene = gold_chest_scene

	# Fallback to normal if specific scene is missing
	if chest_scene == null:
		if normal_chest_scene != null:
			chest_scene = normal_chest_scene
		elif bronze_chest_scene != null:
			chest_scene = bronze_chest_scene
		elif gold_chest_scene != null:
			chest_scene = gold_chest_scene
		else:
			push_warning("[GameManager] No chest scenes assigned!")
			return

	var chest := chest_scene.instantiate()
	chest.global_position = position
	current_room.add_child(chest)

# CHEST SPAWNING LOGIC:
# 
# Add variables at top with other spawn variables:
# - chest_spawn_point: Node2D = null (reserved spawn for chest)
# - chest_spawned: bool = false
# - chest_instance: Node2D = null
# 
# In _spawn_room_content():
# - Reserve TWO spawn points: one for door (existing), one for chest (new)
# - Pop chest_spawn_point from room_spawn_points after door_spawn_point
# - Set chest_spawned to false
# - Reset chest_instance to null
# 
# Modify _on_enemy_died():
# - After decrementing alive_enemies
# - If chest not spawned yet AND chest_spawn_point exists
# - Roll random chance (e.g., 30% per enemy death) to spawn chest
# - If random succeeds, call _spawn_chest()
# - If alive_enemies reaches 0, guarantee spawn chest if not spawned yet
# 
# Add new function: _spawn_chest()
# - Check if chest_scene is null, return if so
# - Check if chest_spawn_point is null, return if so
# - Check if chest_spawned is true, return if so (prevent duplicate)
# - Instantiate chest_scene
# - Set position to chest_spawn_point.global_position
# - Add as child to current_room
# - Set chest_spawned to true
# - Store reference in chest_instance variable
# 
# In _load_room():
# - Reset chest_spawned to false
# - Reset chest_instance to null
# - Reset chest_spawn_point to null









func _open_exit_door() -> void:
	if door_open:
		return
	door_open = true
	if exit_door and exit_door.has_method("open"):
		exit_door.open()


# Called by the exit door when the player reaches it
func on_player_reached_exit() -> void:
	if is_in_death_sequence:
		return

	if in_hub:
		# Using the door in the hub starts the run
		start_run_from_hub()
	elif in_shop:
		# Leaving the shop: go to a new combat room and increase the level
		# Fade music back to global
		_crossfade_to_global_music()

		# Clear the per-visit shop offers cache when actually leaving the shop room.
		# This ensures the next shop room generates a fresh set of offers.
		if GameState and GameState.has_method("clear_shop_offers"):
			GameState.clear_shop_offers()
		
		current_level += 1
		_update_level_ui()
		_check_chaos_chest_spawn()  # ⭐ Check for chaos chest spawn
		
		# Load combat room with fade transition
		FadeTransition.set_black()
		get_tree().paused = false
		
		load_combat_room()
		
		# Grant spawn invincibility
		var player := get_tree().get_first_node_in_group("player")
		if player and player.has_method("grant_spawn_invincibility"):
			player.grant_spawn_invincibility(2.0)
		
		# Refresh HP UI
		var hp_ui := get_tree().get_first_node_in_group("hp_ui")
		if hp_ui and hp_ui.has_method("refresh_from_state"):
			hp_ui.refresh_from_state()
		
		if game_ui:
			game_ui.visible = true
		
		await get_tree().create_timer(0.2).timeout
		FadeTransition.fade_out()
		await FadeTransition.fade_out_finished
	else:
		# Leaving a combat room: go to the shop room (STAY on the same level)
		FadeTransition.set_black()
		get_tree().paused = false
		
		load_shop_room()
		
		# Move player and refresh UI
		var player := get_tree().get_first_node_in_group("player")
		if player and player.has_method("grant_spawn_invincibility"):
			player.grant_spawn_invincibility(1.0)
		
		if game_ui:
			game_ui.visible = true
		
		await get_tree().create_timer(0.2).timeout
		FadeTransition.fade_out()
		await FadeTransition.fade_out_finished


# --- SHOP UI (called from shop room chest) -------------------------

func _open_shop() -> void:
	"""Opens the shop UI. Called by the chest in the shop room."""
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if shop_ui:
		# ⬅0 Check if shops are disabled by chaos challenge
		if GameState.shop_disabled:
			pass
			# TODO: Show message to player
			return
		
		shop_ui.visible = true
		if shop_ui.has_method("open_as_shop"):
			shop_ui.open_as_shop()
		elif shop_ui.has_method("refresh_from_state"):
			shop_ui._setup_cards()
			shop_ui.refresh_from_state()

	if game_ui:
			game_ui.visible = false        # hide HUD while in shop


func open_shop_from_chest() -> void:
	"""Public method for chest to call to open shop UI."""
	_open_shop()


# --- LEVEL PROGRESSION ---------------------------------------------
func load_next_level() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

	if shop_ui:
		shop_ui.visible = false

	# Skip fade transition if in shop room (chest interaction, not level transition)
	if not in_shop:
		# Make sure fade is at full black
		FadeTransition.set_black()
	
	# UNPAUSE FIRST so we can do work
	get_tree().paused = false
	
	# Note: Level increment handled by on_player_reached_exit when leaving shop
	# This method is now primarily for closing shop UI and continuing
	
	# Refresh HP UI
	var hp_ui := get_tree().get_first_node_in_group("hp_ui")
	if hp_ui and hp_ui.has_method("refresh_from_state"):
		hp_ui.refresh_from_state()

	if game_ui:
		game_ui.visible = true
	
	# Skip fade if in shop (just close UI, player is already in shop room)
	if in_shop:
		return
	
	# Small delay to ensure everything is positioned
	await get_tree().create_timer(0.2).timeout
	
	# NOW start fade out from black (player is already in position)
	FadeTransition.fade_out()
	
	# Wait for fade to finish
	await FadeTransition.fade_out_finished


func restart_run() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false

	# reset run data
	GameState.start_new_run()

	# go back to hub
	current_level = 1
	_update_level_ui()
	load_hub_room()


func debug_set_level(level: int) -> void:
	# Clamp to at least level 1
	level = max(1, level)

	current_level = level
	_update_level_ui()
	load_combat_room()

	# Same optional spawn invincibility as load_next_level
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("grant_spawn_invincibility"):
		player.grant_spawn_invincibility(0.7)

	# Refresh HP UI
	var hp_ui := get_tree().get_first_node_in_group("hp_ui")
	if hp_ui and hp_ui.has_method("refresh_from_state"):
		hp_ui.refresh_from_state()

	if game_ui:
		game_ui.visible = true


# --- PAUSE ----------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"): # Esc
		# 🔥 NEW: ignore Esc while shop is open
		if shop_ui and shop_ui.visible:
			return

		_toggle_pause()


func _toggle_pause() -> void:
	get_tree().paused = !get_tree().paused

	var pause_menu := get_tree().get_first_node_in_group("pause")
	if pause_menu:
		pause_menu.visible = get_tree().paused

		if get_tree().paused:
			var first_button := pause_menu.get_node("RestartButton")
			if first_button:
				first_button.grab_focus()

	# Show mouse when paused, hide mouse when unpaused
	if get_tree().paused:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)


# --- DEATH SEQUENCE -------------------------------------------------

func on_player_died() -> void:
	if is_in_death_sequence:
		return

	is_in_death_sequence = true

	# Slow motion
	Engine.time_scale = GameConfig.death_slowmo_scale

	# Start a one-shot timer for the slowmo duration
	var t := get_tree().create_timer(GameConfig.death_slowmo_duration)
	_show_death_screen_after_timer(t)


func _show_death_screen_after_timer(timer: SceneTreeTimer) -> void:
	await timer.timeout

	# Reset time scale
	Engine.time_scale = 1.0  # ← RESET TO NORMAL!

	# Pause the tree instead
	get_tree().paused = true  # ← USE PAUSE, NOT TIMESCALE!

	if death_screen:
		death_screen.visible = true
		if death_screen.has_method("show_death_screen"):
			death_screen.show_death_screen()  # ← Call the proper method!
		elif death_restart_button:
			death_restart_button.grab_focus()

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _clear_room_transient_objects() -> void:
	# Everything that should NOT persist between rooms
	var nodes := get_tree().get_nodes_in_group("room_cleanup")
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()


# --- CHAOS CHEST SPAWN LOGIC ---------------------------------------

func _check_chaos_chest_spawn() -> void:
	"""Check if we should spawn a chaos chest this cycle (every 10 levels)."""
	# ⚠️ DISABLED: Chaos chests temporarily disabled for testing
	return
	
	## Unreachable code below - kept for reference when re-enabling
	#var new_cycle = int(float(current_level - 1) / 10.0)
	#if new_cycle > current_level_cycle:
	#	current_level_cycle = new_cycle
	#	chaos_chest_spawned_this_cycle = false
	#if chaos_chest_spawned_this_cycle:
	#	return
	#var cycle_progress = (current_level - 1) % 10
	#var levels_remaining_in_cycle = 10 - cycle_progress
	#var spawn_chance = 1.0 / float(levels_remaining_in_cycle)
	#if randf() < spawn_chance:
	#	chaos_chest_spawned_this_cycle = true


func _spawn_chaos_chest_at_enemy_position(position: Vector2) -> void:
	"""Spawn the chaos chest at the enemy's death position."""
	if chaos_chest_scene == null:
		push_warning("[GameManager] No chaos_chest_scene assigned!")
		return
	
	var chaos_chest := chaos_chest_scene.instantiate()
	chaos_chest.global_position = position
	
	# Connect signal to handle chaos chest opening
	if chaos_chest.has_signal("chaos_chest_opened"):
		chaos_chest.chaos_chest_opened.connect(_on_chaos_chest_opened)
	
	current_room.add_child(chaos_chest)


func _are_all_chaos_upgrades_purchased() -> bool:
	"""Check if all chaos upgrades have been purchased by the player."""
	# Get all chaos upgrades from the database
	var all_upgrades = UpgradesDB.get_chaos_upgrades()
	
	if all_upgrades.is_empty():
		return true  # No chaos upgrades exist, treat as "all purchased"
	
	# Check if player has purchased all chaos upgrades
	for chaos_upgrade in all_upgrades:
		var upgrade_id: String = chaos_upgrade.get("id", "")
		if not GameState.has_upgrade(upgrade_id):
			return false  # Found one that hasn't been purchased
	
	return true  # All chaos upgrades have been purchased


func _on_chaos_chest_opened(chaos_upgrade: Dictionary) -> void:
	"""Handle chaos chest interaction - show upgrade via shop UI"""
	if not shop_ui:
		push_error("[GameManager] No shop_ui reference!")
		return
	
	# Show the chaos upgrade using existing shop UI system
	shop_ui.visible = true
	if shop_ui.has_method("open_as_chest_with_loot"):
		# Use the chest loot display method with only the chaos upgrade
		shop_ui.open_as_chest_with_loot([chaos_upgrade])
	else:
		push_error("[GameManager] shop_ui doesn't have open_as_chest_with_loot method!")


# --- WAVE SYSTEM ---------------------------------------------------

# --- B2 WAVE SYSTEM ------------------------------------------------

func get_wave_count(level: int) -> int:
	"""Smoothed wave progression to reduce early-game spikes.
	L1-4=1 wave, L5-7=2 waves, L8-10=3 waves, L11-20=3 waves, L21+=4 waves (max).
	This is the ONLY place this formula exists.
	"""
	if level <= 4:
		return 1
	elif level <= 7:
		return 2
	elif level <= 20:
		return 3
	else:
		return 4  # Hard cap at 4 waves


func _calculate_wave_interval() -> float:
	"""Calculate wave spawn interval based on level (gets faster as you progress).
	L1-10: Smooth linear compression (8.0 → 7.0s)
	L11+: Continued gentle compression from 7.0s with 5.8s floor.
	L1=8.0s, L5=7.5s, L10=7.0s, L12=6.8s, L20=6.0s, min=5.8s.
	"""
	if current_level <= 10:
		# Keep original curve for L1-10 (perfect balance)
		var delay := 8.0 - float(current_level) * 0.1
		return max(delay, 7.0)
	else:
		# Continue compression from L10 baseline with higher floor
		var delay := 7.0 - float(current_level - 10) * 0.1
		return max(delay, 5.8)


func _spawn_next_wave() -> void:
	"""Spawn the next wave and schedule the following one if needed."""
	if current_wave >= total_waves:
		return  # No more waves to spawn
	
	current_wave += 1
	scheduled_waves += 1
	
	# Calculate enemies for this wave
	var total_enemies := get_base_enemy_count(current_level)
	var enemies_per_wave := int(floor(float(total_enemies) / float(total_waves)))
	
	# Last wave gets any remainder
	var wave_enemy_count := enemies_per_wave
	if current_wave == total_waves:
		wave_enemy_count = total_enemies - (enemies_per_wave * (total_waves - 1))
	
	print("[WAVES] Wave %d/%d spawning %d enemies" % [current_wave, total_waves, wave_enemy_count])
	
	# Spawn the wave
	_spawn_wave(wave_enemy_count)
	
	# Schedule next wave if not the last
	if current_wave < total_waves:
		var interval := _calculate_wave_interval()
		get_tree().create_timer(interval).timeout.connect(_spawn_next_wave)


func _spawn_wave(count: int) -> void:
	"""Spawn exactly 'count' enemies at available spawn points."""
	if enemy_spawn_points.is_empty():
		print("[SPAWN ERROR] No enemy spawn points for wave!")
		return
	
	var available_spawns := enemy_spawn_points.duplicate()
	available_spawns.shuffle()
	
	# Determine if themed room
	var themed_room := _is_themed_room(current_level)
	var themed_slimes := _get_themed_room_slimes(current_level)
	
	# Spawn enemies immediately (B2: no staggered spawning)
	for i in range(count):
		var spawn_marker: Node2D = available_spawns[i % available_spawns.size()]
		var enemy_scene: PackedScene = null
		
		if themed_room and themed_slimes.size() > 0:
			enemy_scene = themed_slimes[randi() % themed_slimes.size()]
		else:
			enemy_scene = _pick_enemy_scene()
		
		if enemy_scene:
			_spawn_enemy_at(spawn_marker.global_position, enemy_scene)


# --- THEMED ROOM CONFIGURATION ---
@export_group("Themed Rooms")
@export var themed_room_interval: int = 5
@export var first_themed_room_level: int = 10

@export_subgroup("Themed Room 1 (Level 10)")
@export var themed_room_1_slimes: Array[PackedScene] = []
@export_subgroup("Themed Room 2 (Level 15)")
@export var themed_room_2_slimes: Array[PackedScene] = []
@export_subgroup("Themed Room 3 (Level 20)")
@export var themed_room_3_slimes: Array[PackedScene] = []
@export_subgroup("Themed Room 4 (Level 25)")
@export var themed_room_4_slimes: Array[PackedScene] = []
@export_subgroup("Themed Room 5 (Level 30)")
@export var themed_room_5_slimes: Array[PackedScene] = []

func _is_themed_room(level: int) -> bool:
	if level < first_themed_room_level:
		return false
	return (level - first_themed_room_level) % themed_room_interval == 0

func _get_themed_room_slimes(level: int) -> Array[PackedScene]:
	if not _is_themed_room(level):
		return []
	var themed_room_index = int(float(level - first_themed_room_level) / float(themed_room_interval))
	match themed_room_index:
		0:
			return themed_room_1_slimes
		1:
			return themed_room_2_slimes
		2:
			return themed_room_3_slimes
		3:
			return themed_room_4_slimes
		4:
			return themed_room_5_slimes
		_:
			return themed_room_5_slimes if themed_room_5_slimes.size() > 0 else []


# --- MUSIC CROSSFADE ------------------------------------------------

func _crossfade_to_shop_music() -> void:
	"""Fade out global music and fade in shop music."""
	var global_music = GlobalAudioStreamPlayer
	var shop_music = current_room.get_node_or_null("AudioStreamPlayer") if current_room else null
	
	if not shop_music:

		return
	
	# Stop shop music if it's already playing (prevent double-play)
	if shop_music.playing:
		shop_music.stop()
	
	# Set shop music to ALWAYS process (ignore pause)
	shop_music.process_mode = Node.PROCESS_MODE_ALWAYS
	
	var fade_duration = 1.0  # Reduced from 1.5 to 1.0 second
	
	# Fade out global music first
	var global_tween = create_tween()
	global_tween.tween_property(global_music, "volume_db", -80, fade_duration)
	global_tween.tween_callback(func(): global_music.stream_paused = true)
	
	# Wait for fade out to finish, then start shop music at full volume
	await global_tween.finished
	shop_music.volume_db = 0
	shop_music.play()


func _crossfade_to_global_music() -> void:
	"""Fade out shop music and fade in global music."""
	var global_music = GlobalAudioStreamPlayer
	var shop_music = current_room.get_node_or_null("AudioStreamPlayer") if current_room else null
	
	# Resume global music if paused
	if global_music.stream_paused:
		global_music.stream_paused = false
	
	var fade_duration = 1.5
	
	# Fade in global music
	var global_tween = create_tween()
	global_tween.tween_property(global_music, "volume_db", 0, fade_duration)
	
	# Fade out shop music if it exists and is valid
	if shop_music and is_instance_valid(shop_music) and shop_music.playing:
		var shop_tween = create_tween()
		shop_tween.tween_property(shop_music, "volume_db", -80, fade_duration)
		# Store reference before callback to avoid freed object access
		var music_ref = shop_music
		shop_tween.tween_callback(func(): 
			if is_instance_valid(music_ref):
				music_ref.stop()
		)
