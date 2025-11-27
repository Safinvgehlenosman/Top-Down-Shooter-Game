extends Node

@export var death_screen_path: NodePath
@export var shop_path: NodePath
@export var exit_door_path: NodePath
@export var chest_scene: PackedScene      # not really used now, but ok to leave
@export var ui_root_path: NodePath

@export var crate_scene: PackedScene

@export var exit_door_scene: PackedScene
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

# Chest spawning
var chest_spawn_point: Node2D = null
var chest_spawned: bool = false
var chest_instance: Area2D = null
var chest_should_spawn_this_level: bool = false  # Rolled once per level

@export_range(0.0, 1.0, 0.05) var chest_spawn_chance: float = 0.75  # 75% chance per level

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
@export var level_unlock_fast: int   = 4   # darkgreen chaser
@export var level_unlock_purple: int = 7   # shooter
@export var level_unlock_poison: int = 10  # DoT cloud
@export var level_unlock_ice: int    = 13  # slow / tanky
@export var level_unlock_fire: int   = 10  # fire melee (mid-game)
@export var level_unlock_ghost: int  = 16  # late-game special

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
	_load_room()


# --- LEVEL UI -------------------------------------------------------

func _update_level_ui() -> void:
	var label := get_tree().get_first_node_in_group("level_label") as Label
	if label:
		label.text = "%d" % current_level


# --- ROOM / LEVEL LOADING -------------------------------------------

func _load_room() -> void:
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
	
	# Reset chest variables
	chest_spawn_point = null
	chest_spawned = false
	chest_instance = null
	
	# Roll chest spawn chance for this level (75% by default)
	chest_should_spawn_this_level = randf() < chest_spawn_chance

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
	params.collide_with_areas = true
	params.collide_with_bodies = true

	# 8 is just "max results" – we only care if it's empty or not
	var results := space_state.intersect_point(params, 8)
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

	room_spawn_points.shuffle()

	# reserve one spawn for the door
	door_spawn_point = room_spawn_points.pop_back()
	
	# reserve one spawn for the chest
	if room_spawn_points.size() > 0:
		chest_spawn_point = room_spawn_points.pop_back()
	else:
		chest_spawn_point = null
	
	chest_spawned = false
	chest_instance = null

	alive_enemies = 0

	for spawn in room_spawn_points:
		var r := randf()

		# --- ENEMY ---------------------------------------------------
		if r < enemy_chance:
			var enemy_scene := _pick_enemy_scene()
			if enemy_scene:
				# find a safe position near the spawn marker
				var desired_pos := spawn.global_position
				var safe_pos := _find_safe_spawn_position(desired_pos)

				# if we STILL can't get a valid position, skip this spawn
				if not _is_spawn_valid(safe_pos):
					continue

				var enemy := enemy_scene.instantiate()
				enemy.global_position = safe_pos

				# Find which index this enemy came from (for apply_level logic)
				var _enemy_index := enemy_scenes.find(enemy_scene)

				# scale stats by current level if the enemy supports it,
				# (ghost can still ignore this in its own script if needed)
				if enemy.has_method("apply_level"):
					enemy.apply_level(current_level)

				current_room.add_child(enemy)
				alive_enemies += 1

				if enemy.has_signal("died"):
					enemy.died.connect(_on_enemy_died)
			continue

		# --- CRATE ---------------------------------------------------
		if r < enemy_chance + crate_chance and crate_scene:
			var crate := crate_scene.instantiate()
			crate.global_position = spawn.global_position
			current_room.add_child(crate)
			continue

		# --- NOTHING -------------------------------------------------
		pass

	if alive_enemies == 0:
		_spawn_exit_door()


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

func _on_enemy_died() -> void:
	alive_enemies = max(alive_enemies - 1, 0)
	
	# Chest spawn logic (only if level rolled for chest)
	if chest_should_spawn_this_level and not chest_spawned and chest_spawn_point != null:
		# 30% chance to spawn chest on each enemy death
		if randf() < 0.3:
			_spawn_chest()
	
	if alive_enemies == 0:
		# Guarantee chest spawn if level rolled for it and not spawned yet
		if chest_should_spawn_this_level and not chest_spawned:
			_spawn_chest()
		_spawn_exit_door()


func _spawn_exit_door() -> void:
	if current_exit_door != null:
		return # already spawned

	if exit_door_scene == null:
		push_warning("No exit_door_scene assigned")
		return

	# Failsafe: if door_spawn_point is somehow null, pick one now.
	if door_spawn_point == null:
		var candidates: Array[Node2D] = room_spawn_points
		if candidates.is_empty() and current_room and current_room.has_method("get_spawn_points"):
			candidates = current_room.get_spawn_points()

		if candidates.is_empty():
			push_warning("Tried to spawn door but room has no spawn points at all")
			return

		candidates.shuffle()
		door_spawn_point = candidates[0]

	current_exit_door = exit_door_scene.instantiate()
	current_exit_door.global_position = door_spawn_point.global_position
	current_room.add_child(current_exit_door)

	if current_exit_door.has_method("open"):
		current_exit_door.open()


func _spawn_chest() -> void:
	"""Spawn a chest at the reserved chest spawn point."""
	# Guard checks
	if chest_scene == null:
		return
	
	if chest_spawn_point == null:
		return
	
	if chest_spawned:
		return  # Already spawned
	
	# Instantiate and position chest
	chest_instance = chest_scene.instantiate()
	chest_instance.global_position = chest_spawn_point.global_position
	current_room.add_child(chest_instance)
	
	# Mark as spawned
	chest_spawned = true
	print("[GameManager] Chest spawned at", chest_spawn_point.global_position)

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

	_open_shop()


# --- SHOP / LEVEL PROGRESSION --------------------------------------

func _open_shop() -> void:
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if shop_ui:
		shop_ui.visible = true
		if shop_ui.has_method("open_as_shop"):
			shop_ui.open_as_shop()
		elif shop_ui.has_method("refresh_from_state"):
			shop_ui._setup_cards()
			shop_ui.refresh_from_state()

	if game_ui:
		game_ui.visible = false        # hide HUD while in shop


func load_next_level() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

	if shop_ui:
		shop_ui.visible = false

	get_tree().paused = false

	# increase level, then reroll a room
	current_level += 1
	_update_level_ui()
	_load_room()

	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("grant_spawn_invincibility"):
		player.grant_spawn_invincibility(0.7) # tweak value

	# refresh HP UI
	var hp_ui := get_tree().get_first_node_in_group("hp_ui")
	if hp_ui and hp_ui.has_method("refresh_from_state"):
		hp_ui.refresh_from_state()

	if game_ui:
		game_ui.visible = true         # show HUD again


func restart_run() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false

	# reset run data
	GameState.start_new_run()

	# go back to level 1 (or start screen if you prefer)
	current_level = 1
	_update_level_ui()
	_load_room()


func debug_set_level(level: int) -> void:
	# Clamp to at least level 1
	level = max(1, level)

	current_level = level
	_update_level_ui()
	_load_room()

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
