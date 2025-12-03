extends Node

# Signals
signal exit_door_spawned(door: Node2D)

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

@export_group("Staggered Spawning")
@export var spawn_duration_initial: float = 5.0  # Time to spawn initial room enemies
@export var spawn_duration_wave_min: float = 5.0  # Minimum wave spawn duration
@export var spawn_duration_wave_max: float = 10.0  # Maximum wave spawn duration


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

@export_group("Enemies")
@export var enemy_scenes: Array[PackedScene] = []
@export var enemy_weights: Array[float] = []   # runtime weights, auto-filled

# 70% crate, 30% "some enemy" by default (you can still tweak this in inspector)
@export_range(0.0, 1.0, 0.01) var enemy_chance: float = 0.3
@export_range(0.0, 1.0, 0.01) var crate_chance: float = 0.7

var current_level: int = 1

@onready var room_container: Node2D = $"../RoomContainer"

var current_room: Node2D
var alive_enemies: int = 0
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

# Wave system - supports multiple waves
var wave_scheduled: bool = false
var wave_spawned: bool = false
var initial_enemies_defeated: bool = false
var waves_remaining: int = 0  # How many waves left to spawn
var current_wave_number: int = 0  # Which wave we're on
var waves_enemy_budget: int = 0  # Enemy budget reserved for waves

# Chest spawning
var chest_spawned: bool = false

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
@onready var death_restart_button: Button = $"../UI/DeathScreen/Content/RestartButton"

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
	randomize()

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
			print("[GameManager] Connected exit_door_spawned signal to UI")

	current_level = 1
	_update_level_ui()
	load_hub_room()


# --- ROOM LOADING HELPERS -------------------------------------------

func load_combat_room() -> void:
	"""Load a random combat room with enemies and crates."""
	in_shop = false
	in_hub = false
	
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
	alive_enemies = 0
	
	# Reset wave variables
	wave_scheduled = false
	wave_spawned = false
	initial_enemies_defeated = false
	
	# Reset chest variables
	chest_spawned = false
	
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
	await get_tree().process_frame  # Wait for door to be added to scene
	_unlock_exit_door()


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
	alive_enemies = 0
	
	# Reset wave variables
	wave_scheduled = false
	wave_spawned = false
	initial_enemies_defeated = false
	waves_remaining = 0
	current_wave_number = 0
	
	# Reset chest variables
	chest_spawned = false
	
	# Reset alpha slime tracking
	has_spawned_alpha_this_level = false
	
	# Instance hub room
	current_room = hub_room_scene.instantiate()
	room_container.add_child(current_room)
	
	# Collect spawn markers from hub room
	_collect_room_spawn_points()
	
	# Move player to hub spawn
	_move_player_to_room_spawn()
	
	# Disable player weapon in hub
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("set_weapon_enabled"):
		player.set_weapon_enabled(false)
	
	# Spawn exit door immediately and unlock it (no enemies to kill in hub)
	_spawn_exit_door()
	await get_tree().process_frame  # Wait for door to be added to scene
	_unlock_exit_door()
	
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
	alive_enemies = 0
	
	# Reset wave variables
	wave_scheduled = false
	wave_spawned = false
	initial_enemies_defeated = false
	waves_remaining = 0
	current_wave_number = 0
	
	# Reset chest variables
	chest_spawned = false
	
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
		print("[SPAWN ERROR] No current_room - cannot collect spawn points")
		return
	
	print("[SPAWN FILTER] Current room: %s" % current_room.name)
	
	# === ENEMY SPAWN FILTERING ===
	var all_enemy_markers = get_tree().get_nodes_in_group("enemy_spawn")
	print("[ENEMY SPAWN] All markers in group: %d" % all_enemy_markers.size())
	for marker in all_enemy_markers:
		if marker is Node2D and current_room.is_ancestor_of(marker):
			enemy_spawn_points.append(marker)
	print("[ENEMY SPAWN] Filtered markers in room: %d" % enemy_spawn_points.size())
	for m in enemy_spawn_points:
		print("  [ENEMY MARKER] %s at %s" % [m.name, m.global_position])
	
	# === CRATE SPAWN FILTERING ===
	var all_crate_markers = get_tree().get_nodes_in_group("crate_spawn")
	print("[CRATE SPAWN] All markers in group: %d" % all_crate_markers.size())
	for marker in all_crate_markers:
		if marker is Node2D and current_room.is_ancestor_of(marker):
			crate_spawn_points.append(marker)
	print("[CRATE SPAWN] Filtered markers in room: %d" % crate_spawn_points.size())
	for m in crate_spawn_points:
		print("  [CRATE MARKER] %s at %s" % [m.name, m.global_position])
	
	# === DOOR SPAWN FILTERING ===
	var all_door_markers = get_tree().get_nodes_in_group("door_spawn")
	print("[DOOR SPAWN] All markers in group: %d" % all_door_markers.size())
	for marker in all_door_markers:
		if marker is Node2D and current_room.is_ancestor_of(marker):
			door_spawn_points.append(marker)
	print("[DOOR SPAWN] Filtered markers in room: %d" % door_spawn_points.size())
	for m in door_spawn_points:
		print("  [DOOR MARKER] %s at %s" % [m.name, m.global_position])
	
	# === PLAYER SPAWN FILTERING ===
	var all_player_markers = get_tree().get_nodes_in_group("player_spawn")
	print("[PLAYER SPAWN] All markers in group: %d" % all_player_markers.size())
	for marker in all_player_markers:
		if marker is Node2D and current_room.is_ancestor_of(marker):
			player_spawn_points.append(marker)
	print("[PLAYER SPAWN] Filtered markers in room: %d" % player_spawn_points.size())
	for m in player_spawn_points:
		print("  [PLAYER MARKER] %s at %s" % [m.name, m.global_position])
	
	# === SUMMARY ===
	print("[SPAWN SUMMARY] Enemy: %d | Crate: %d | Door: %d | Player: %d" % 
		[enemy_spawn_points.size(), crate_spawn_points.size(), 
		 door_spawn_points.size(), player_spawn_points.size()])


func _move_player_to_room_spawn() -> void:
	var player := get_tree().get_first_node_in_group("player")
	
	print("[PLAYER SPAWN] === PLAYER SPAWN ATTEMPT ===")
	if current_room:
		print("[PLAYER SPAWN] Current room: %s" % current_room.name)
	else:
		print("[PLAYER SPAWN] Current room: null")
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
				print("[PLAYER SPAWN] Using fallback method - spawning at: %s" % spawn_point.global_position)
				player.global_position = spawn_point.global_position
			else:
				push_error("[PLAYER SPAWN] Fallback method returned null!")
		return
	
	# Use the FIRST marker (index 0) - should be the only one if filtering worked correctly
	var chosen_marker := player_spawn_points[0]
	var chosen_index := 0
	var spawn_pos := chosen_marker.global_position
	
	print("[PLAYER SPAWN] Using marker [%d]: %s at %s" % [chosen_index, chosen_marker.name, spawn_pos])
	
	# Move player
	player.global_position = spawn_pos
	print("[PLAYER SPAWN] Player moved to: %s" % player.global_position)
	
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
	
	print("---- DEBUG SPAWNPOINTS ----")
	print("[SPAWN] Total spawn_points provided:", spawn_points.size())
	for sp in spawn_points:
		print("  SP:", sp.name, "pos:", sp.global_position)
	
	var spawned_enemies: Array = []
	var candidate_positions := _get_valid_spawn_positions(spawn_points)
	
	print("[SPAWN] VALID COUNT:", candidate_positions.size())
	for c in candidate_positions:
		print("  VALID:", c)
	
	if candidate_positions.is_empty():
		print("[SPAWN] No valid positions found, aborting staggered spawn")
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
	
	var interval := duration / float(enemy_list.size())
	var pos_idx := 0
	var spawn_count := 0
	
	for enemy_scene in enemy_list:
		# Cycle through shuffled positions, wrapping around if more enemies than positions
		var pos := candidate_positions[pos_idx]
		pos_idx = (pos_idx + 1) % candidate_positions.size()
		
		# Apply safety nudge and validate
		pos = _find_safe_spawn_position(pos)
		if _is_spawn_valid(pos):
			var enemy: Node2D = enemy_scene.instantiate()
			enemy.global_position = pos
			
			if enemy.has_method("apply_level"):
				enemy.apply_level(current_level)
			
			current_room.add_child(enemy)
			alive_enemies += 1
			spawned_enemies.append(enemy)
			
			if enemy.has_signal("died"):
				enemy.died.connect(_on_enemy_died.bind(enemy))
			
			spawn_count += 1
			print("[SPAWN] Enemy spawned at: ", pos)
		
		# Wait before spawning next enemy (skip wait after last one)
		if spawn_count < enemy_list.size():
			await get_tree().create_timer(interval).timeout
	
	print("[SPAWN] Staggered spawn complete: %d enemies over %.1fs" % [spawned_enemies.size(), duration])
	
	# --- ALPHA VARIANT SPAWNING ---
	if not has_spawned_alpha_this_level and not spawned_enemies.is_empty():
		for enemy in spawned_enemies:
			if not is_instance_valid(enemy) or not enemy.has_method("make_alpha"):
				continue
			if randf() < 0.05:
				if enemy.has_method("make_alpha"):
					enemy.make_alpha()
					has_spawned_alpha_this_level = true
					break
	
	# --- MARK CHEST DROPPERS ---
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



# --- SIMPLE INITIAL ENEMY SPAWNING ---------------------------------

func _spawn_enemy_at(pos: Vector2, enemy_scene: PackedScene = null) -> Node2D:
	"""Spawn a single enemy at the given position."""
	if enemy_scene == null:
		enemy_scene = _pick_enemy_scene()
	
	if enemy_scene == null:
		return null
	
	var enemy: Node2D = enemy_scene.instantiate()
	enemy.global_position = pos
	
	if enemy.has_method("apply_level"):
		enemy.apply_level(current_level)
	
	current_room.add_child(enemy)
	alive_enemies += 1
	
	if enemy.has_signal("died"):
		enemy.died.connect(_on_enemy_died.bind(enemy))
	
	return enemy


func _spawn_initial_enemies(level: int) -> void:
	"""Spawn initial enemies using enemy_spawn markers (no physics validation)."""
	if in_hub:
		return
	
	var spawns := enemy_spawn_points.duplicate()
	if spawns.is_empty():
		print("[SPAWN] Room '%s' has no enemy_spawn markers" % current_room.name)
		return
	
	spawns.shuffle()
	
	var total_budget := _calculate_enemy_count_for_level(level, spawns.size())
	var initial_budget: int = clamp(int(round(total_budget * 0.35)), 1, 8)
	var initial_enemy_count: int = min(initial_budget, spawns.size())
	
	# Store waves budget
	waves_enemy_budget = max(total_budget - initial_enemy_count, 0)
	
	print("[SPAWN] Initial enemies: %d | Total budget: %d | Waves: %d | Level: %d" % 
		[initial_enemy_count, total_budget, waves_enemy_budget, level])
	
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
	
	# Handle alpha variant
	if not has_spawned_alpha_this_level and not spawned_enemies.is_empty():
		for enemy in spawned_enemies:
			if not is_instance_valid(enemy) or not enemy.has_method("make_alpha"):
				continue
			if randf() < 0.05:
				enemy.make_alpha()
				has_spawned_alpha_this_level = true
				break
	
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


func _ensure_minimum_one_enemy() -> void:
	"""Failsafe: ensure non-hub rooms always have at least 1 enemy."""
	if in_hub or in_shop:
		return
	
	# Check if we have any enemies alive
	if alive_enemies <= 0:
		var pos: Vector2
		if not enemy_spawn_points.is_empty():
			pos = enemy_spawn_points[0].global_position
		else:
			# Fallback to room center or origin
			pos = Vector2(512, 384)  # Approximate room center
		
		_spawn_enemy_at(pos)
		print("[SPAWN FAILSAFE] Room had 0 enemies, spawned 1 basic enemy")


# --- SPAWNING ROOM CONTENT ------------------------------------------

func _spawn_room_content() -> void:
	if current_room == null:
		return
	
	chest_spawned = false
	alive_enemies = 0
	
	# Spawn crates at crate markers
	_spawn_crates_for_room()
	
	# Spawn initial enemies at enemy markers
	_spawn_initial_enemies(current_level)
	
	# Schedule waves based on level
	if current_level >= 1 and not enemy_spawn_points.is_empty():
		waves_remaining = get_wave_count()
		current_wave_number = 0
		if waves_remaining > 0:
			print("[WAVE SYSTEM] Level %d: %d waves will spawn" % [current_level, waves_remaining])
	
	# FAILSAFE: Ensure non-hub rooms always have at least 1 enemy
	_ensure_minimum_one_enemy()
	
	# Spawn exit door at door marker
	_spawn_exit_door()
	
	# In hub/shop, unlock immediately (always visible)
	# In combat rooms, unlock only when enemies are defeated
	if in_hub or in_shop or alive_enemies == 0:
		_unlock_exit_door()


# --- SPAWN COUNT CALCULATION ---------------------------------------

func _calculate_enemy_count_for_level(level: int, available_spawns: int) -> int:
	"""Calculate how many enemies to spawn based on current level and spawn ratio."""
	# Use actual spawn points available in the room
	var total_spawns = available_spawns
	
	# Calculate enemy/crate split ratio
	var enemy_ratio = _get_enemy_ratio_for_level(level)
	
	# Calculate enemy count based on ratio, then increase by +25%
	var base_enemy_count = int(total_spawns * enemy_ratio)
	var enemy_count = int(base_enemy_count * 1.25)
	
	# Clamp to reasonable values (min 3, max based on available spawns)
	enemy_count = clamp(enemy_count, 3, available_spawns)
	
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
		# Green + Fast
		if lvl >= level_unlock_green:
			enemy_weights[ENEMY_INDEX_GREEN] = weight_green
		if lvl >= level_unlock_fast and enemy_weights.size() > ENEMY_INDEX_FAST:
			enemy_weights[ENEMY_INDEX_FAST] = weight_fast * 0.7

	elif lvl < 10:
		# Green + Fast + a bit of Purple (shooter)
		if lvl >= level_unlock_green:
			enemy_weights[ENEMY_INDEX_GREEN] = weight_green
		if lvl >= level_unlock_fast and enemy_weights.size() > ENEMY_INDEX_FAST:
			enemy_weights[ENEMY_INDEX_FAST] = weight_fast
		if lvl >= level_unlock_purple and enemy_weights.size() > ENEMY_INDEX_PURPLE:
			enemy_weights[ENEMY_INDEX_PURPLE] = weight_purple * 0.5

	elif lvl < 13:
		# Add Poison + Fire, ramp Purple slightly
		if lvl >= level_unlock_green:
			enemy_weights[ENEMY_INDEX_GREEN] = weight_green * 0.8
		if lvl >= level_unlock_fast and enemy_weights.size() > ENEMY_INDEX_FAST:
			enemy_weights[ENEMY_INDEX_FAST] = weight_fast
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
			enemy_weights[ENEMY_INDEX_FAST] = weight_fast
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
			enemy_weights[ENEMY_INDEX_FAST] = weight_fast
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
	alive_enemies = max(alive_enemies - 1, 0)
	
	# Check if this enemy should drop chest
	if enemy != null and enemy.has_meta("drops_chest") and not chest_spawned:
		_spawn_chest_at_enemy_position(enemy.global_position)
		chest_spawned = true
	
	# ⭐ Check if this enemy should drop chaos chest
	if enemy != null and enemy.has_meta("drops_chaos_chest"):
		_spawn_chaos_chest_at_enemy_position(enemy.global_position)
	
	if alive_enemies == 0:
		# Check if we have more waves to spawn
		if waves_remaining > 0:
			current_wave_number += 1
			waves_remaining -= 1
			initial_enemies_defeated = true
			
			var wave_size = get_wave_enemy_count()
			print("[WAVE SYSTEM] Wave %d/%d starting with %d enemies" % [current_wave_number, get_wave_count(), wave_size])
			
			# Schedule next wave with delay
			_schedule_wave(1.5, wave_size)
			return
		
		# ⭐ ALL WAVES COMPLETE - ROOM CLEARED
		print("[GameManager] All enemies dead. Active chaos challenge: '", GameState.active_chaos_challenge, "'")
		if not GameState.active_chaos_challenge.is_empty():
			GameState.increment_chaos_challenge_progress()
		
		# QoL: Auto-break crates and collect pickups
		_on_room_cleared()
		
		# CRITICAL: Ensure door exists before unlocking
		_ensure_exit_door_exists()
		_unlock_exit_door()


func _spawn_exit_door() -> void:
	"""Spawn exit door once when entering a room. Always spawns, lock state depends on room type."""
	print("[EXIT DOOR] === DOOR SPAWN ATTEMPT ===")
	
	if current_exit_door != null and is_instance_valid(current_exit_door) and current_exit_door.is_inside_tree():
		print("[EXIT DOOR] Door already exists and is valid in current room")
		return

	if exit_door_scene == null:
		push_error("[EXIT DOOR] No exit_door_scene assigned!")
		return
	
	if not current_room:
		push_error("[EXIT DOOR] No current_room - cannot spawn door")
		return
	
	print("[EXIT DOOR] Current room: %s" % current_room.name)
	print("[EXIT DOOR] Available door spawn markers: %d" % door_spawn_points.size())

	# Error if no spawn markers found
	if door_spawn_points.is_empty():
		push_error("[SPAWN ERROR] No door_spawn markers found in room %s" % current_room.name)
		return
	
	# Use first door marker - trust level design
	var chosen_marker := door_spawn_points[0]
	var spawn_pos := chosen_marker.global_position
	
	print("[EXIT DOOR] Using marker: %s at %s" % [chosen_marker.name, spawn_pos])

	# Instantiate and add to room
	current_exit_door = exit_door_scene.instantiate()
	current_exit_door.global_position = spawn_pos
	current_room.add_child(current_exit_door)
	
	# Determine if this is a combat room (needs to be locked initially)
	var is_combat_room := not in_hub and not in_shop
	
	# Set locked state
	if current_exit_door.has_method("set_locked"):
		current_exit_door.set_locked(is_combat_room)
	
	print("[EXIT DOOR] Door spawned at: %s (locked: %s)" % [current_exit_door.global_position, is_combat_room])
	
	# Emit signal for UI
	emit_signal("exit_door_spawned", current_exit_door)


func _ensure_exit_door_exists() -> void:
	"""CRITICAL FALLBACK: Ensure exit door exists after room clear. Prevents softlocks."""
	# If door already exists and is in tree, we're good
	if current_exit_door != null and is_instance_valid(current_exit_door) and current_exit_door.is_inside_tree():
		print("[EXIT DOOR] Door already exists and is valid")
		return
	
	# Door missing or invalid - force spawn it
	print("[EXIT DOOR] ⚠️ FALLBACK: Door missing after room clear, force spawning!")
	current_exit_door = null  # Clear invalid reference
	_spawn_exit_door()


func _on_room_cleared() -> void:
	"""Called when all enemies and waves are defeated. Auto-breaks crates and collects pickups."""
	print("[ROOM CLEAR] Room cleared! Auto-breaking crates and collecting pickups...")
	_auto_break_all_crates()
	
	# Wait a short moment for crates to drop their loot before enabling super magnet
	await get_tree().create_timer(0.3).timeout
	
	# Enable super magnet to auto-collect all pickups
	_enable_super_magnet()
	
	# Unlock and open the door
	if current_exit_door and is_instance_valid(current_exit_door) and current_exit_door.is_inside_tree():
		if current_exit_door.has_method("unlock_and_open"):
			current_exit_door.unlock_and_open()
			print("[EXIT DOOR] Door unlocked via unlock_and_open()")
		else:
			print("[EXIT DOOR] WARNING: unlock_and_open() method not found, using fallback")
			_unlock_exit_door()
	else:
		push_error("[EXIT DOOR] Room cleared but no door exists, spawning failsafe door.")
		_spawn_exit_door()
		await get_tree().process_frame
		if current_exit_door and current_exit_door.has_method("unlock_and_open"):
			current_exit_door.unlock_and_open()


func _enable_super_magnet() -> void:
	"""Enable super magnet to attract all pickups in the room."""
	# Set magnet radius to cover entire room
	GameConfig.current_pickup_magnet_range = 9999.0
	# Set super magnet speed and acceleration for fast collection
	GameConfig.current_pickup_magnet_speed = GameConfig.PICKUP_MAGNET_SPEED_SUPER
	GameConfig.current_pickup_magnet_accel = GameConfig.PICKUP_MAGNET_ACCEL_SUPER
	
	# Log pickup count for debugging
	var pickups: Array = []
	pickups += get_tree().get_nodes_in_group("pickup_coin")
	pickups += get_tree().get_nodes_in_group("pickup_heart")
	pickups += get_tree().get_nodes_in_group("pickup_ammo")
	print("[AUTO COLLECT] Super magnet enabled - collecting %d pickups" % pickups.size())


func _disable_super_magnet() -> void:
	"""Disable super magnet and restore normal magnet radius."""
	GameConfig.current_pickup_magnet_range = GameConfig.pickup_magnet_range
	GameConfig.current_pickup_magnet_speed = GameConfig.PICKUP_MAGNET_SPEED_NORMAL
	GameConfig.current_pickup_magnet_accel = GameConfig.PICKUP_MAGNET_ACCEL_NORMAL
	print("[AUTO COLLECT] Super magnet disabled")


func _auto_break_all_crates() -> void:
	"""Auto-break all crates in the current room when all enemies are defeated."""
	if not current_room:
		return
	
	var crates := _get_room_nodes_in_group("crate")
	print("[AUTO BREAK] Breaking ", crates.size(), " crates")
	
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


func _unlock_exit_door() -> void:
	"""Unlock and open the exit door after all enemies are defeated."""
	if current_exit_door == null:
		print("[EXIT DOOR] Cannot unlock - door not spawned yet")
		return
	
	# Check if still in scene tree before awaiting
	if not is_inside_tree():
		return
	
	# Wait one frame to ensure door's _ready() has run
	await get_tree().process_frame
	
	# Check again after await in case node was removed
	if not is_inside_tree() or current_exit_door == null:
		return
	
	# Call unlock_and_open() method
	if current_exit_door.has_method("unlock_and_open"):
		# Don't play sound in hub or shop
		if in_hub or in_shop:
			current_exit_door.unlock_and_open(false)
		else:
			current_exit_door.unlock_and_open()
		print("[EXIT DOOR] Door unlocked and opened")
	else:
		# Fallback to old open() method
		if current_exit_door.has_method("open"):
			if in_hub or in_shop:
				current_exit_door.open(false)
			else:
				current_exit_door.open()
			print("[EXIT DOOR] Door opened (fallback)")


func _spawn_chest_at_enemy_position(position: Vector2) -> void:
	"""Spawn a weighted random chest at the enemy's death position. In themed rooms, always spawn gold chest."""
	var chest_scene: PackedScene = null
	if _is_themed_room(current_level):
		chest_scene = gold_chest_scene
	else:
		# Weighted random chest selection
		# Bronze: 50%, Normal: 35%, Gold: 15%
		var chest_roll := randf()
		if chest_roll < 0.50:  # 50% bronze
			chest_scene = bronze_chest_scene
		elif chest_roll < 0.85:  # 35% normal (0.50 + 0.35)
			chest_scene = normal_chest_scene
		else:  # 15% gold
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

func _process(_delta: float) -> void:
	pass


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
			print("[GameManager] Shops are disabled by chaos challenge!")
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

	Engine.time_scale = 0.0

	if death_screen:
		death_screen.visible = true
		if death_restart_button:
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

func get_wave_enemy_count() -> int:
	"""Calculate wave size based on current level with aggressive scaling."""
	if current_level < 1:
		return 0
	
	# Base wave size (30% larger than before)
	var base_size: int
	
	if current_level <= 5:
		# Level 1-5: baseline +30% (4-8 enemies, was 3-6)
		base_size = randi_range(4, 8)
	elif current_level <= 10:
		# Level 6-10: baseline × 1.75 (5-11 enemies)
		base_size = randi_range(5, 11)
	elif current_level <= 20:
		# Level 11-20: baseline × 2.25 (7-14 enemies)
		base_size = randi_range(7, 14)
	else:
		# Level 20+: baseline × 3.0 (12-24 enemies)
		base_size = randi_range(12, 24)
	
	print("[WAVE SIZE] Level %d wave size: %d enemies" % [current_level, base_size])
	return base_size


func get_wave_count() -> int:
	"""Calculate how many waves should spawn based on current level."""
	if current_level < 1:
		return 0
	elif current_level <= 4:
		# Level 1-4: 1 wave
		return 1
	elif current_level <= 9:
		# Level 5-9: 2 waves minimum
		return 2
	else:
		# Level 10+: 3 waves
		return 3


func _schedule_wave(delay: float, count: int) -> void:
	"""Schedule a wave to spawn after a delay."""
	if wave_scheduled:
		return  # Already scheduled
	
	wave_scheduled = true
	wave_spawned = false
	
	print("[WAVE] Scheduled wave of %d enemies in %.1f seconds" % [count, delay])
	
	# Wait for delay, then spawn the wave
	await get_tree().create_timer(delay).timeout
	
	# Only spawn if initial enemies are actually defeated
	if initial_enemies_defeated:
		_spawn_wave(count)


func _spawn_wave(count: int) -> void:
	"""Spawn a wave of enemies using existing spawn points and logic."""
	if wave_spawned:
		return  # Already spawned
	
	wave_spawned = true
	
	if enemy_spawn_points.is_empty():
		print("[WAVE] No enemy spawn points available for wave!")
		return
	
	print("[WAVE] Preparing wave of %d enemies!" % count)
	
	# Get available spawn points (use enemy spawn markers)
	var available_spawns := enemy_spawn_points.duplicate()
	if available_spawns.is_empty():
		print("[WAVE] No enemy spawn markers available!")
		return
	
	# Prepare enemy list
	var themed_room := _is_themed_room(current_level)
	var themed_slimes := _get_themed_room_slimes(current_level)
	var enemy_list: Array = []
	
	for i in range(count):
		var enemy_scene: PackedScene = null
		
		if themed_room and themed_slimes.size() > 0:
			enemy_scene = themed_slimes[randi() % themed_slimes.size()]
		else:
			enemy_scene = _pick_enemy_scene()
		
		if enemy_scene:
			enemy_list.append(enemy_scene)
	
	enemy_list.shuffle()
	
	# Pick random duration for this wave
	var wave_duration := randf_range(spawn_duration_wave_min, spawn_duration_wave_max)
	
	# Start staggered wave spawning
	if not enemy_list.is_empty():
		_spawn_enemies_over_time(enemy_list, available_spawns, wave_duration, false)  # false = not initial, allow expansion


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
		print("[MUSIC] No shop music found in room")
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
