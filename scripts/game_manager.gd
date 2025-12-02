extends Node

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
var door_spawn_point: Node2D = null
var current_exit_door: Node2D = null
var room_spawn_points: Array[Node2D] = []

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

# Chest spawning
var chest_spawn_point: Node2D = null
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

	current_level = 1
	_update_level_ui()
	load_hub_room()


# --- ROOM LOADING HELPERS -------------------------------------------

func load_combat_room() -> void:
	"""Load a random combat room with enemies and crates."""
	in_shop = false
	in_hub = false
	_load_room_internal()


func load_shop_room() -> void:
	"""Load the shop room (no enemies, just a chest to interact with)."""
	if shop_room_scene == null:
		push_warning("No shop_room_scene assigned on GameManager")
		return
	
	in_shop = true
	in_hub = false
	
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
	door_spawn_point = null
	room_spawn_points.clear()
	
	# Reset wave variables
	wave_scheduled = false
	wave_spawned = false
	initial_enemies_defeated = false
	
	# Reset chest variables
	chest_spawn_point = null
	chest_spawned = false
	
	# Reset alpha slime tracking
	has_spawned_alpha_this_level = false
	
	# Instance shop room
	current_room = shop_room_scene.instantiate()
	room_container.add_child(current_room)
	
	# Fade music to shop track
	_crossfade_to_shop_music()
	
	# Get spawn points from shop room
	if current_room.has_method("get_spawn_points"):
		room_spawn_points = current_room.get_spawn_points()
		if not room_spawn_points.is_empty():
			# Reserve one spawn point for the exit door
			door_spawn_point = room_spawn_points.pop_back()
	
	# Move player to shop spawn
	_move_player_to_room_spawn()
	
	# Spawn exit door immediately (no enemies to kill)
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
	door_spawn_point = null
	room_spawn_points.clear()
	
	# Reset wave variables
	wave_scheduled = false
	wave_spawned = false
	initial_enemies_defeated = false
	waves_remaining = 0
	current_wave_number = 0
	
	# Reset chest variables
	chest_spawn_point = null
	chest_spawned = false
	
	# Reset alpha slime tracking
	has_spawned_alpha_this_level = false
	
	# Instance hub room
	current_room = hub_room_scene.instantiate()
	room_container.add_child(current_room)
	
	# Get spawn points from hub room
	if current_room.has_method("get_spawn_points"):
		room_spawn_points = current_room.get_spawn_points()
		print("[HUB] Found %d spawn points" % room_spawn_points.size())
		if not room_spawn_points.is_empty():
			# Reserve one spawn point for the exit door
			door_spawn_point = room_spawn_points.pop_back()
			print("[HUB] Reserved spawn point for exit door at: ", door_spawn_point.global_position)
	else:
		print("[HUB] ERROR: Room doesn't have get_spawn_points method!")
	
	# Move player to hub spawn
	_move_player_to_room_spawn()
	
	# Disable player weapon in hub
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("set_weapon_enabled"):
		player.set_weapon_enabled(false)
	
	# Spawn exit door immediately (no enemies to kill)
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
	alive_enemies = 0
	door_spawn_point = null
	room_spawn_points.clear()
	
	# Reset wave variables
	wave_scheduled = false
	wave_spawned = false
	initial_enemies_defeated = false
	waves_remaining = 0
	current_wave_number = 0
	
	# Reset chest variables
	chest_spawn_point = null
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


func _move_player_to_room_spawn() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if not player or not current_room:
		return

	if not current_room.has_method("get_player_spawn_point"):
		push_warning("Current room has no get_player_spawn_point() method")
		return

	var spawn_point: Node2D = current_room.get_player_spawn_point()
	if spawn_point:
		player.global_position = spawn_point.global_position


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
	var space_state: PhysicsDirectSpaceState2D = get_viewport().world_2d.direct_space_state

	var params := PhysicsPointQueryParameters2D.new()
	params.position = pos
	params.collide_with_areas = false  # Don't check areas (spawn points might be Area2D)
	params.collide_with_bodies = true
	params.collision_mask = 1  # Only check layer 1 (walls/environment)

	# 8 is just "max results" – we only care if it's empty or not
	var results := space_state.intersect_point(params, 8)
	
	# Debug: print what's blocking if any
	if not results.is_empty():
		for result in results:
			print("[SPAWN VALID] Collision detected with: ", result.collider.name if result.collider else "unknown")
	
	return results.is_empty()


# Try to nudge the spawn away from walls using a few offsets.
# Returns either a safe position near base_pos, or base_pos as fallback.
func _find_safe_spawn_position(base_pos: Vector2) -> Vector2:
	# if original is already fine, keep it
	if _is_spawn_valid(base_pos):
		return base_pos

	var r := spawn_padding_radius

	var offsets := [
		Vector2(0, 0),
		Vector2(r, 0),
		Vector2(-r, 0),
		Vector2(0, r),
		Vector2(0, -r),
		Vector2(r, r),
		Vector2(-r, r),
		Vector2(r, -r),
		Vector2(-r, -r),
	]

	for off in offsets:
		var p: Vector2 = base_pos + off
		if _is_spawn_valid(p):
			return p

	return base_pos



# --- SPAWNING ROOM CONTENT ------------------------------------------

func _spawn_room_content() -> void:
	if current_room == null:
		return

	if not current_room.has_method("get_spawn_points"):
		push_warning("Current room has no get_spawn_points() method")
		return

	room_spawn_points = current_room.get_spawn_points()
	if room_spawn_points.is_empty():
		push_warning("Room '%s' has no spawn points" % current_room.name)
		return

	print("[SPAWN] Room has %d total spawn points before reserving door spawn" % room_spawn_points.size())
	room_spawn_points.shuffle()

	# reserve one spawn for the door
	door_spawn_point = room_spawn_points.pop_back()
	print("[SPAWN] Reserved door spawn, %d spawn points remaining for entities" % room_spawn_points.size())
	
	# Determine if chest should spawn this level (75% chance)
	var should_spawn_chest: bool = randf() < chest_spawn_chance
	
	# Determine if chaos chest should spawn this level (if flagged)
	# ⭐ Don't spawn if all chaos upgrades have been purchased
	var all_chaos_purchased := _are_all_chaos_upgrades_purchased()
	var should_spawn_chaos_chest: bool = chaos_chest_spawned_this_cycle and GameState.active_chaos_challenge.is_empty() and not all_chaos_purchased
	
	chest_spawned = false

	alive_enemies = 0

	var themed_room := _is_themed_room(current_level)
	var themed_slimes := _get_themed_room_slimes(current_level)

	# Calculate how many enemies and crates to spawn based on level
	var enemy_count := 0
	var crate_count := 0
	
	# Get actual available spawn points (minus door spawn)
	var available_spawns = room_spawn_points.size()
	
	if themed_room:
		# Themed rooms: spawn many enemies, no crates
		enemy_count = _calculate_enemy_count_for_level(current_level, available_spawns)
		crate_count = 0
	else:
		# Normal rooms: balanced mix of enemies and crates
		enemy_count = _calculate_enemy_count_for_level(current_level, available_spawns)
		crate_count = _calculate_crate_count_for_level(current_level, available_spawns)
	
	# Make sure we don't exceed available spawn points
	var total_entities = enemy_count + crate_count
	if total_entities > room_spawn_points.size():
		# Prioritize enemies over crates
		crate_count = max(0, room_spawn_points.size() - enemy_count)
	
	# Shuffle spawn points for randomness
	room_spawn_points.shuffle()
	
	var spawn_index = 0
	
	# --- SPAWN ENEMIES ---
	var spawned_enemies: Array = []  # Track spawned enemies
	
	for i in range(enemy_count):
		if spawn_index >= room_spawn_points.size():
			break
		
		var spawn = room_spawn_points[spawn_index]
		var enemy_scene: PackedScene = null
		
		if themed_room and themed_slimes.size() > 0:
			# Pick themed enemy
			enemy_scene = themed_slimes[randi() % themed_slimes.size()]
		else:
			# Pick normal enemy based on weights
			enemy_scene = _pick_enemy_scene()
		
		if enemy_scene:
			var desired_pos: Vector2 = spawn.global_position
			var safe_pos := _find_safe_spawn_position(desired_pos)
			
			# Just use the position - _find_safe_spawn_position already tried to find a safe spot
			# If it couldn't, spawning anyway is better than skipping
			var enemy := enemy_scene.instantiate()
			enemy.global_position = safe_pos
			
			if enemy.has_method("apply_level"):
				enemy.apply_level(current_level)
			
			current_room.add_child(enemy)
			alive_enemies += 1
			spawned_enemies.append(enemy)  # Track this enemy
			
			if enemy.has_signal("died"):
				enemy.died.connect(_on_enemy_died.bind(enemy))
			
			spawn_index += 1
	
	# --- ALPHA VARIANT SPAWNING ---
	# After all enemies are spawned, try to make one an alpha (5% fixed chance, max one per level)
	if not has_spawned_alpha_this_level and not spawned_enemies.is_empty():
		for enemy in spawned_enemies:
			# Check if this enemy is a slime (has make_alpha method)
			if not enemy.has_method("make_alpha"):
				continue
			
			# Roll 5% chance (FIXED, not level-scaled)
			if randf() < 0.05:
				if enemy.has_method("make_alpha"):
					enemy.make_alpha()
					has_spawned_alpha_this_level = true
					break  # Only one alpha per level
	
	# --- MARK RANDOM ENEMIES AS CHEST DROPPERS ---
	# After spawning all enemies, mark random ones to drop chests
	
	# ⭐ FIX: Chaos chest should spawn first to avoid overlapping with normal chest
	if should_spawn_chaos_chest and not spawned_enemies.is_empty():
		spawned_enemies.shuffle()
		var chaos_dropper = spawned_enemies[0]
		chaos_dropper.set_meta("drops_chaos_chest", true)
	
	if should_spawn_chest and not spawned_enemies.is_empty():
		spawned_enemies.shuffle()
		var chest_dropper = spawned_enemies[0]
		# ⭐ Ensure chaos chest and normal chest don't spawn from same enemy
		if chest_dropper.has_meta("drops_chaos_chest"):
			if spawned_enemies.size() > 1:
				chest_dropper = spawned_enemies[1]
			else:
				# Only one enemy - skip normal chest
				chest_dropper = null
		
		if chest_dropper:
			chest_dropper.set_meta("drops_chest", true)
	
	# --- SPAWN CRATES ---
	if not themed_room and crate_scene:
		for i in range(crate_count):
			if spawn_index >= room_spawn_points.size():
				break
			
			var spawn = room_spawn_points[spawn_index]
			var crate := crate_scene.instantiate()
			crate.global_position = spawn.global_position
			current_room.add_child(crate)
			
			spawn_index += 1
	
	# Schedule multiple waves based on level
	if current_level >= 1 and not room_spawn_points.is_empty():
		waves_remaining = get_wave_count()
		current_wave_number = 0
		if waves_remaining > 0:
			print("[WAVE SYSTEM] Level %d: %d waves will spawn" % [current_level, waves_remaining])
	
	if alive_enemies == 0:
		_spawn_exit_door()


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
		
		# ⭐ Progress chaos challenge if active
		print("[GameManager] All enemies dead. Active chaos challenge: '", GameState.active_chaos_challenge, "'")
		if not GameState.active_chaos_challenge.is_empty():
			GameState.increment_chaos_challenge_progress()
		
		_spawn_exit_door()


func _spawn_exit_door() -> void:
	print("[EXIT DOOR] Attempting to spawn exit door...")
	
	if current_exit_door != null:
		print("[EXIT DOOR] Door already spawned, skipping")
		return # already spawned

	if exit_door_scene == null:
		push_warning("[EXIT DOOR] No exit_door_scene assigned!")
		return
	
	print("[EXIT DOOR] Exit door scene found: ", exit_door_scene)

	# Failsafe: if door_spawn_point is somehow null, pick one now.
	if door_spawn_point == null:
		print("[EXIT DOOR] door_spawn_point is null, trying to find one...")
		var candidates: Array[Node2D] = room_spawn_points
		if candidates.is_empty() and current_room and current_room.has_method("get_spawn_points"):
			candidates = current_room.get_spawn_points()

		if candidates.is_empty():
			push_warning("[EXIT DOOR] Tried to spawn door but room has no spawn points at all")
			return

		candidates.shuffle()
		door_spawn_point = candidates[0]
		print("[EXIT DOOR] Found spawn point: ", door_spawn_point.global_position)
	else:
		print("[EXIT DOOR] Using reserved spawn point: ", door_spawn_point.global_position)

	current_exit_door = exit_door_scene.instantiate()
	current_exit_door.global_position = door_spawn_point.global_position
	
	current_room.add_child(current_exit_door)
	
	print("[EXIT DOOR] Door spawned successfully at: ", current_exit_door.global_position)

	# Call open() deferred to ensure it happens after _ready() sets visible = false
	if current_exit_door.has_method("open"):
		# Don't play sound in hub or shop
		if in_hub or in_shop:
			current_exit_door.call_deferred("open", false)
		else:
			current_exit_door.call_deferred("open")
		print("[EXIT DOOR] Door open() called (deferred)")


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
	# Determine which 10-level cycle we're in (0 = levels 1-10, 1 = levels 11-20, etc.)
	var new_cycle = int(float(current_level - 1) / 10.0)
	
	# If we've entered a new cycle, reset the flag
	if new_cycle > current_level_cycle:
		current_level_cycle = new_cycle
		chaos_chest_spawned_this_cycle = false
	
	# If chaos chest already spawned this cycle, skip
	if chaos_chest_spawned_this_cycle:
		return
	
	# Calculate spawn chance based on levels remaining in cycle
	# This guarantees exactly one chaos chest per 10-level cycle
	var cycle_progress = (current_level - 1) % 10  # 0-9
	var levels_remaining_in_cycle = 10 - cycle_progress
	var spawn_chance = 1.0 / float(levels_remaining_in_cycle)
	
	if randf() < spawn_chance:
		chaos_chest_spawned_this_cycle = true
		# Flag is set; actual spawn happens in _spawn_room_content()


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
	
	# Clear spawn point
	chaos_chest_spawn_point = null


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
	"""Calculate wave size based on current level with size scaling."""
	if current_level < 1:
		return 0
	
	# Base wave size
	var base_size: int
	
	if current_level <= 5:
		# Level 1-5: baseline (3-6 enemies)
		base_size = randi_range(3, 6)
	elif current_level <= 10:
		# Level 6-10: +50% more (5-9 enemies)
		base_size = randi_range(5, 9)
	elif current_level <= 20:
		# Level 11-20: +100% more (6-12 enemies)
		base_size = randi_range(6, 12)
	else:
		# Level 20+: +200% more (9-18 enemies)
		base_size = randi_range(9, 18)
	
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
	
	if room_spawn_points.is_empty():
		print("[WAVE] No spawn points available for wave!")
		return
	
	var themed_room := _is_themed_room(current_level)
	var themed_slimes := _get_themed_room_slimes(current_level)
	
	print("[WAVE] Spawning wave of %d enemies!" % count)
	
	# Shuffle spawn points for randomness
	room_spawn_points.shuffle()
	
	var spawned_count = 0
	for i in range(count):
		# Use available spawn points (cycle if needed)
		if room_spawn_points.is_empty():
			break
		
		var spawn = room_spawn_points[i % room_spawn_points.size()]
		var enemy_scene: PackedScene = null
		
		if themed_room and themed_slimes.size() > 0:
			# Pick themed enemy
			enemy_scene = themed_slimes[randi() % themed_slimes.size()]
		else:
			# Pick normal enemy based on weights
			enemy_scene = _pick_enemy_scene()
		
		if enemy_scene:
			var desired_pos: Vector2 = spawn.global_position
			var safe_pos := _find_safe_spawn_position(desired_pos)
			
			var enemy := enemy_scene.instantiate()
			enemy.global_position = safe_pos
			
			if enemy.has_method("apply_level"):
				enemy.apply_level(current_level)
			
			current_room.add_child(enemy)
			alive_enemies += 1
			spawned_count += 1
			
			if enemy.has_signal("died"):
				enemy.died.connect(_on_enemy_died.bind(enemy))
	
	print("[WAVE] Wave complete! Spawned %d/%d enemies" % [spawned_count, count])


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
