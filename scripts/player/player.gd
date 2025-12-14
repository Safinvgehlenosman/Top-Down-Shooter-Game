extends CharacterBody2D

const BulletScene_DEFAULT := preload("res://scenes/bullets/bullet.tscn")
const BulletScene_SHOTGUN := preload("res://scenes/bullets/shotgun_bullet.tscn")
const BulletScene_SNIPER  := preload("res://scenes/bullets/sniper_bullet.tscn")
const DashGhostScene := preload("res://scenes/dash_ghost.tscn")

# Fixed turret & muzzle positions (brute-force 2-state).
# Replace the Vector2(0, 0) defaults with inspector values:
# TURRET_POS_RIGHT := Vector2(<X>, <Y>)
# TURRET_POS_LEFT  := TURRET_POS_RIGHT + Vector2(8, 0)
const TURRET_POS_RIGHT := Vector2(-5, -5)
const TURRET_POS_LEFT  := TURRET_POS_RIGHT + Vector2(15, 0)

# Muzzle local positions (barrel tip). Replace placeholders:
# MUZZLE_POS_RIGHT := Vector2(<MX>, <MY>)
# MUZZLE_POS_LEFT  := Vector2(<MLX>, <MLY>)
const MUZZLE_POS_RIGHT := Vector2(0, 0)
const MUZZLE_POS_LEFT  := Vector2(0, 0)

var dash_ghost_interval: float = 0.03
var dash_ghost_timer: float = 0.0

@onready var gun: Node = $Gun
@onready var health_component: Node = $Health
@onready var ability_component: Node = $Ability
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var visual: Node2D = $AnimatedSprite2D
@onready var muzzle: Marker2D = $Gun/Muzzle

@onready var turret_node: Node2D = null

# Runtime stats (filled from GameConfig / GameState in _ready)
var speed: float
var max_health: int
var knockback_strength: float
var knockback_duration: float
var invincible_time: float
var alt_weapon: int = GameState.AltWeaponType.NONE


# State
var health: int = 0


# Knockback
var knockback: Vector2 = Vector2.ZERO
var knockback_timer: float = 0.0

# Invincibility
var invincible_timer: float = 0.0

var is_dead: bool = false
var weapon_enabled: bool = true  # Disabled in hub

# Visual sway state (affects visuals only)
var base_visual_pos: Vector2 = Vector2.ZERO
var base_visual_rot: float = 0.0
var walk_time: float = 0.0
var gun_sprite: Node = null
var base_gun_pos: Vector2 = Vector2.ZERO
var backpack_sprite: Node = null
var base_backpack_pos: Vector2 = Vector2.ZERO
@export var turret_back_offset: Vector2 = Vector2(-10, -6)
@export var turret_left_extra_offset: Vector2 = Vector2(800000000, 0)
var base_turret_pos: Vector2 = Vector2.ZERO

# --- AIM / INPUT MODE ------------------------------------------------

const AIM_DEADZONE: float = 0.25
const AIM_CURSOR_SPEED: float = 800.0  # tweak speed of controller cursor
const AIM_SMOOTH: float = 10.0  # higher = snappier, lower = floatier


enum AimMode { MOUSE, CONTROLLER }
var aim_mode: AimMode = AimMode.MOUSE

var aim_dir: Vector2 = Vector2.RIGHT

# one shared cursor for mouse + controller
var aim_cursor_pos: Vector2 = Vector2.ZERO
var last_mouse_pos: Vector2 = Vector2.ZERO
# Track last facing to print once when it changes
var _prev_facing_left = null
var _last_facing_left: bool = false

func grant_spawn_invincibility(duration: float) -> void:
	if health_component and health_component.has_method("grant_spawn_invincibility"):
		health_component.grant_spawn_invincibility(duration)

# --------------------------------------------------------------------
# READY
# --------------------------------------------------------------------

func _ready() -> void:
	# Design defaults from GameConfig
	speed              = GameConfig.player_move_speed
	knockback_strength = GameConfig.player_knockback_strength
	knockback_duration = GameConfig.player_knockback_duration
	invincible_time    = GameConfig.player_invincible_time
	
	# gun.init_from_state() removed (function does not exist)
	gun.connect("recoil_requested", _on_gun_recoil_requested)

	# --- HealthComponent wiring ---
	if health_component:
		# Player-specific config for the generic Health component
		health_component.invincible_time = GameConfig.player_invincible_time

		health_component.connect("damaged", Callable(self, "_on_health_damaged"))
		health_component.connect("healed",  Callable(self, "_on_health_healed"))
		health_component.connect("died",    Callable(self, "_on_health_died"))

	# --- AbilityComponent wiring (optional sync) ---
	if ability_component and ability_component.has_method("sync_from_gamestate"):
		ability_component.sync_from_gamestate()
	
	# --- Listen for alt weapon changes ---
	GameState.alt_weapon_changed.connect(func(_new_weapon): sync_from_gamestate())

	var design_max_health: int = GameConfig.player_max_health

	var _design_max_ammo: int   = GameConfig.player_max_ammo
	var design_fire_rate: float = GameConfig.player_fire_rate
	var design_pellets: int    = GameConfig.alt_fire_bullet_count

	# --- Sync with GameState (current run data) ---

	# Initialize GameState once (first run)
	if GameState.max_health == 0:
		GameState.max_health = design_max_health
		GameState.health     = design_max_health

	if GameState.fire_rate <= 0.0:
		GameState.fire_rate = design_fire_rate
	
	if GameState.move_speed <= 0.0:
		GameState.move_speed_base = GameConfig.player_move_speed
		GameState.move_speed = GameState.move_speed_base

	if GameState.shotgun_pellets <= 0:
		GameState.shotgun_pellets = design_pellets

	# Local copies from current run (+ push into HealthComponent)
	sync_from_gamestate()
	alt_weapon = GameState.alt_weapon

	# Aim setup
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	aim_cursor_pos = get_global_mouse_position()
	last_mouse_pos = get_viewport().get_mouse_position()

	# Listen for invisibility changes so we can react immediately (ability may update GameState after player physics)
	if GameState != null and GameState.has_signal("player_invisible_changed"):
		GameState.player_invisible_changed.connect(Callable(self, "_on_player_invis_changed"))

	# Record visual base transform (visual is the AnimatedSprite2D by default)
	if visual:
		base_visual_pos = visual.position
		base_visual_rot = visual.rotation

	# Record gun base pos and find the gun sprite child (do not assume specific child name)
	if gun:
		base_gun_pos = gun.position
		for c in gun.get_children():
			if c is Sprite2D or c is AnimatedSprite2D:
				gun_sprite = c
				break

	# Try to find a backpack sprite under the visual node so we can mirror it
	if visual:
		for c in visual.get_children():
			if c is Sprite2D or c is AnimatedSprite2D:
				var lname := c.name.to_lower()
				if lname.contains("back") or lname.contains("pack"):
					backpack_sprite = c
					break

		# Record backpack base local pos if we found one
		if backpack_sprite:
			base_backpack_pos = backpack_sprite.position

	# If backpack exists under the Turret node (scene has Backpack as a child of Turret), pick that up too
	if has_node("Turret"):
		var tnode := $Turret
		# Keep a direct reference for faster updates
		turret_node = tnode
		# Record turret base local pos so we can apply visual sway offsets
		if turret_node:
			base_turret_pos = turret_node.position
		if tnode and tnode.has_node("Backpack"):
			backpack_sprite = tnode.get_node("Backpack")
			if backpack_sprite:
				base_backpack_pos = backpack_sprite.position


# --------------------------------------------------------------------
# PROCESS
# --------------------------------------------------------------------

func _process(delta: float) -> void:
	_update_crosshair()

	# --- Walk sway (visuals only) ---
	if visual:
		# facing used to mirror gun/pivot correctly
		var mouse_pos: Vector2 = get_global_mouse_position()
		var facing_left: bool = mouse_pos.x < global_position.x

		var speed_val: float = velocity.length()
		var max_speed: float = 1.0
		if GameState != null:
			max_speed = max(0.0001, GameState.move_speed)
		var t: float = clamp(speed_val / max_speed, 0.0, 1.0)

		if t > 0.0:
			walk_time += delta * lerp(6.0, 10.0, t)
		else:
			# decay walk_time back to 0 when idle
			walk_time = lerp(walk_time, 0.0, clamp(delta * 6.0, 0.0, 1.0))

		var side: float = sin(walk_time) * lerp(0.0, 2.5, t)
		var bob: float = abs(cos(walk_time)) * lerp(0.0, 1.5, t)
		var rot: float = sin(walk_time) * deg_to_rad(lerp(0.0, 3.0, t))

		var target_pos: Vector2 = base_visual_pos + Vector2(side, -bob)
		var target_rot: float = base_visual_rot + rot

		# Smoothly interpolate visuals towards target (returns to neutral when idle)
		visual.position = visual.position.lerp(target_pos, clamp(delta * 10.0, 0.0, 1.0))
		visual.rotation = lerp_angle(visual.rotation, target_rot, clamp(delta * 10.0, 0.0, 1.0))

		# --- Gun sway (synced with body sway, visuals only) ---
		if gun:
			# smaller amplitude so gun sway is subtle compared to body
			var gun_side_mult: float = 0.6
			var gun_bob_mult: float = 0.5
			var gun_scale_mult: float = lerp(0.0, 0.03, t) # tiny scale pulse

			# Mirror base gun X depending on facing (keep gun on correct side)
			var mirror_base_x: float = -abs(base_gun_pos.x) if facing_left else abs(base_gun_pos.x)

			var gun_target_pos: Vector2 = Vector2(mirror_base_x + side * gun_side_mult, base_gun_pos.y - bob * gun_bob_mult)
			# Smoothly move gun local position toward target
			gun.position = gun.position.lerp(gun_target_pos, clamp(delta * 10.0, 0.0, 1.0))

			# Tiny scale pulse synced to step; return to Vector2.ONE when idle
			var desired_scale: Vector2 = Vector2.ONE + Vector2(gun_scale_mult, gun_scale_mult)
			if gun_sprite == null:
				# If gun node itself is a Sprite2D/AnimatedSprite2D it may have scale
				gun.scale = gun.scale.lerp(desired_scale, clamp(delta * 8.0, 0.0, 1.0))
			else:
				gun_sprite.scale = gun_sprite.scale.lerp(desired_scale, clamp(delta * 8.0, 0.0, 1.0))

		# --- Turret: fixed positions per facing (no sway) ---
		# Centralized turret attachment update (runs every frame while turret exists)
		_update_turret_attachment()


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Regeneration removed

	_update_timers(delta)
	_process_movement(delta)
	_update_aim_direction(delta)
	_process_aim(delta)
			# centralized turret update function defined below
			# (keeps turret local transform in sync even if turret is spawned later)
			# function implementation below
	_update_turret_attachment()
	gun.update_timers(delta)

	var is_shooting := Input.is_action_pressed("shoot")
	var is_alt_fire := Input.is_action_pressed("alt_fire")

	# Shooting allowed when weapon is enabled. Shooting while invisible will
	# break invisibility (handled in gun logic) except for Gunslinger upgrade.
	if weapon_enabled:
		gun.handle_primary_fire(is_shooting, aim_dir)
		gun.handle_alt_fire(is_alt_fire, aim_cursor_pos)

	# Update animation and facing based on current velocity and mouse position
	_update_animation_and_facing()

	# Also ensure turret attachment is kept in sync while turret exists
	_update_turret_attachment()


func _on_gun_recoil_requested(dir: Vector2, strength: float) -> void:
	knockback = dir * strength
	knockback_timer = knockback_duration

# --------------------------------------------------------------------
# TIMERS
# --------------------------------------------------------------------

func _update_timers(delta: float) -> void:
	# NOTE: invincibility is now handled inside HealthComponent

	if knockback_timer > 0.0:
		knockback_timer -= delta
	else:
		knockback = Vector2.ZERO

# --------------------------------------------------------------------
# MOVEMENT & AIM
# --------------------------------------------------------------------

func _process_movement(_delta: float) -> void:
	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input_dir.y = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")

	if input_dir != Vector2.ZERO:
		input_dir = input_dir.normalized()

	# ⭐ Always read current speed from GameState (for chaos challenges)
	var current_speed: float = GameState.move_speed

	# Ask HealthComponent how slowed we are (1.0 = normal)
	var slow_factor: float = 1.0
	if health_component and health_component.has_method("get_move_slow_factor"):
		slow_factor = health_component.get_move_slow_factor()

	# Ask AbilityComponent if a dash is active
	if ability_component and ability_component.has_method("get_dash_velocity"):
		var dash_velocity: Vector2 = ability_component.get_dash_velocity()
		if dash_velocity != Vector2.ZERO:
			# Dash ignores slow (nice counterplay). Remove if you want frozen dashes too.
			velocity = dash_velocity
		else:
			velocity = input_dir * current_speed * slow_factor
	else:
		velocity = input_dir * current_speed * slow_factor

	# Apply knockback on top of input movement
	if knockback_timer > 0.0:
		velocity += knockback

	move_and_slide()


# choose input mode & update aim_dir
func _update_aim_direction(delta: float) -> void:
	var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	var mouse_pos := get_global_mouse_position()

	# 1) Controller input → move virtual cursor
	if stick.length() >= AIM_DEADZONE:
		aim_mode = AimMode.CONTROLLER
		stick = stick.normalized()

		var target_pos: Vector2 = aim_cursor_pos + stick * AIM_CURSOR_SPEED * delta
		var t: float = clamp(AIM_SMOOTH * delta, 0.0, 1.0)

		aim_cursor_pos = aim_cursor_pos.lerp(target_pos, t)

	# 2) Mouse movement → override cursor
	else:
		if mouse_pos.distance_to(last_mouse_pos) > 0.5:
			aim_mode = AimMode.MOUSE
			aim_cursor_pos = mouse_pos
			last_mouse_pos = mouse_pos

	# 3) Keep cursor inside viewport
	var vp := get_viewport()
	aim_cursor_pos.x = clamp(aim_cursor_pos.x, 0.0, vp.size.x)
	aim_cursor_pos.y = clamp(aim_cursor_pos.y, 0.0, vp.size.y)

	# 4) Aim direction: from player to cursor
	var vec := aim_cursor_pos - global_position
	if vec.length() > 0.001:
		aim_dir = vec.normalized()
	else:
		aim_dir = Vector2.RIGHT

func _process_aim(delta: float) -> void:
	# Facing based on mouse position (not movement). Mirror gun so it stays on correct side.
	var mouse_pos: Vector2 = get_global_mouse_position()
	var facing_left: bool = mouse_pos.x < global_position.x

	animated_sprite.flip_h = facing_left

	# Rotate gun to face the mouse and mirror its local X offset so it visually sticks
	if has_node("Gun"):
		var aim_vec: Vector2 = mouse_pos - global_position
		if aim_vec.length() > 0.001:
			gun.rotation = aim_vec.angle()

		# Flip gun art if present. Use vertical flip as a reasonable default for top-down art.
		if gun_sprite:
			if gun_sprite is Sprite2D or gun_sprite is AnimatedSprite2D:
				gun_sprite.flip_v = facing_left

		# Also flip backpack art if present so it stays visually correct
		if backpack_sprite:
			if backpack_sprite is Sprite2D or backpack_sprite is AnimatedSprite2D:
				backpack_sprite.flip_v = facing_left

		# Mirror backpack local position so it sits on correct side of the body
		if backpack_sprite:
			var speed_val: float = velocity.length()
			var max_speed: float = 1.0
			if GameState != null:
				max_speed = max(0.0001, GameState.move_speed)
			var t: float = clamp(speed_val / max_speed, 0.0, 1.0)
			var walk_time_local := walk_time
			var side: float = sin(walk_time_local) * lerp(0.0, 2.5, t)
			var bob: float = abs(cos(walk_time_local)) * lerp(0.0, 1.5, t)
			var mirror_base_x_b: float = -abs(base_backpack_pos.x) if facing_left else abs(base_backpack_pos.x)
			var backpack_target: Vector2 = Vector2(mirror_base_x_b + side * 0.3, base_backpack_pos.y - bob * 0.2)
			backpack_sprite.position = backpack_sprite.position.lerp(backpack_target, clamp(delta * 10.0, 0.0, 1.0))

			# Turret attachment handled centrally by _update_turret_attachment()

		# Flip & rotate entire Turret node so it sits on the correct side
		# NOTE: Turret visual transforms (flip/rotation) are handled only on the Backpack sprite.
		# Do not change Turret node scale/rotation here.


func _on_player_invis_changed(is_invisible: bool) -> void:
	# Called when GameState's invis flag changes; refresh animation immediately
	# Debug suppressed
	# print("[ANIM-SIGNAL] player_invisible_changed ->", is_invisible)
	_update_animation_and_facing()

# Crosshair follows shared cursor (mouse + controller)
func _update_crosshair() -> void:
	var crosshair := get_tree().get_first_node_in_group("crosshair")
	if crosshair == null:
		return

	crosshair.global_position = aim_cursor_pos


func _update_animation() -> void:
	# Switch between 'idle' and 'move' based on actual velocity magnitude.
	# Do not restart the animation if it's already playing.
	if not animated_sprite:
		return

	var speed_val: float = velocity.length()
	var desired_anim: String = "move" if speed_val > 1.0 else "idle"

	if animated_sprite.animation != desired_anim:
		animated_sprite.play(desired_anim)

	# Optional horizontal flipping based on movement direction
	if velocity.x > 0.1:
		animated_sprite.flip_h = false
	elif velocity.x < -0.1:
		animated_sprite.flip_h = true
func _update_animation_and_facing() -> void:
	# Switch between idle/move and invis variants based on velocity and invisibility.
	# Play only when the animation actually changes. Facing is driven by mouse X.
	if not animated_sprite:
		return

	var speed_val: float = velocity.length()

	# Determine invisibility from existing project state:
	# Prefer explicit GameState.player_invisible, but also consider ability timers
	var is_invis_active: bool = false
	if GameState != null:
		# explicit flag (preferred)
		if GameState.player_invisible:
			is_invis_active = true
		# fallback: ability type + active timer (covers cases where flag isn't set)
		elif GameState.ability == GameState.AbilityType.INVIS and GameState.ability_active_left > 0.0:
			is_invis_active = true
				# Diagnostic: GameState invisibility info suppressed to reduce log spam

	# Pick desired animation name
	var desired_anim: String
	if is_invis_active:
		desired_anim = "invis_move" if speed_val > 1.0 else "invis_idle"
	else:
		desired_anim = "move" if speed_val > 1.0 else "idle"

	# Safe fallbacks: if invis animations missing, fall back to non-invis variants
	var frames = animated_sprite.sprite_frames
	if frames:
		# Suppress frequent animation diagnostics to reduce log spam
		# print("[ANIM] speed=", speed_val, " invis=", is_invis_active, " desired=", desired_anim, " has_frames=", frames != null, " has_anim=", frames.has_animation(desired_anim), " current=", animated_sprite.animation)
		if not frames.has_animation(desired_anim):
			if is_invis_active:
				var fallback := "move" if speed_val > 1.0 else "idle"
				if frames.has_animation(fallback):
					desired_anim = fallback
				else:
					# No valid animation found; preserve current
					desired_anim = animated_sprite.animation
			else:
				# For non-invis, ensure at least 'idle' exists
				if frames.has_animation("idle"):
					desired_anim = "idle"
				else:
					desired_anim = animated_sprite.animation

	if desired_anim != animated_sprite.animation and desired_anim != "":
		# Suppressed animation switching log
		# print("[ANIM] switching to ", desired_anim)
		animated_sprite.play(desired_anim)

	# Facing is handled in _process_aim() (mouse-based flip)
# --------------------------------------------------------------------
# FEEDBACK (HIT / HEAL)
# --------------------------------------------------------------------

func _play_hit_feedback() -> void:
	# Camera shake
	var cam := get_tree().get_first_node_in_group("camera")
	if cam and cam.has_method("shake"):
		cam.shake(GameConfig.hit_shake_strength, GameConfig.hit_shake_duration)

	# Red screen flash
	var flash := get_tree().get_first_node_in_group("screen_flash")
	if flash and flash.has_method("flash"):
		flash.flash()

func _play_heal_feedback() -> void:
	# Green screen flash (no shake)
	var flash := get_tree().get_first_node_in_group("screen_flash_heal")
	if flash and flash.has_method("flash"):
		flash.flash()

# --------------------------------------------------------------------
# HEALTH & DAMAGE
# --------------------------------------------------------------------

func take_damage(amount: int) -> void:
	# God mode only for the player, not for every HealthComponent user
	if amount > 0 and GameState.debug_god_mode:
		return

	# Wrapper so enemies can still call player.take_damage(amount)
	if health_component and health_component.has_method("take_damage"):
		health_component.take_damage(amount)


func _on_health_damaged(_amount: int) -> void:
	# Sync GameState from component
	if health_component:
		GameState.set_health(health_component.health)

	# Play hurt SFX + camera/screen feedback
	if has_node("SFX_Hurt"):
		$SFX_Hurt.play()
	_play_hit_feedback()
	# UI is updated via GameState.health_changed -> ui.gd


func _on_health_healed(_amount: int) -> void:
	if health_component:
		GameState.set_health(health_component.health)

	_play_heal_feedback()
	# UI is updated via GameState.health_changed -> ui.gd


func _on_health_died() -> void:
	# Make sure GameState HP is 0
	GameState.set_health(0)

	# Mark player as dead so _physics_process stops
	is_dead = true
	die()


func add_coin() -> void:
	GameState.add_coins(1)

func apply_knockback(from_position: Vector2) -> void:
	var dir := (global_position - from_position).normalized()
	knockback = dir * knockback_strength
	knockback_timer = knockback_duration


func die() -> void:
	is_dead = true

	# Disable gun logic so it stops rotating/aiming
	if has_node("Gun"):
		gun.process_mode = Node.PROCESS_MODE_DISABLED

	# Hide crosshair
	var crosshair := get_tree().get_first_node_in_group("crosshair")
	if crosshair:
		crosshair.visible = false

	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm and gm.has_method("on_player_died"):
		gm.on_player_died()

	# Show DeathScreen UI if present (reads final values from GameState)
	var ds := get_tree().current_scene.get_node_or_null("DeathScreen")
	if ds and ds.has_method("show_death_screen"):
		ds.show_death_screen()

# --------------------------------------------------------------------
# UI BARS
# --------------------------------------------------------------------

func sync_from_gamestate() -> void:
	# Core stats from GameState
	max_health = GameState.max_health
	health     = GameState.health
	
	# Apply move speed from GameState
	speed = GameState.move_speed

	# Push into generic HealthComponent
	if health_component:
		health_component.max_health = max_health
		health_component.health     = health

	# Also tell AbilityComponent to resync (e.g. after unlocks)
	if ability_component and ability_component.has_method("sync_from_gamestate"):
		ability_component.sync_from_gamestate()

	# 🔥 ALSO SYNC ALT WEAPON
	alt_weapon = GameState.alt_weapon  # 0–3

	# Turret visual + config
	if has_node("Turret"):
		var turret = $Turret

		if alt_weapon == GameState.AltWeaponType.TURRET:
			turret.visible = true

			var data: Dictionary = GameState.ALT_WEAPON_DATA.get(GameState.alt_weapon, {})
			if not data.is_empty() and turret.has_method("configure"):
				turret.configure(data)
				# Ensure attachment transforms apply immediately after configure/spawn
				_update_turret_attachment()
		else:
			turret.visible = false


# --------------------------------------------------------------------
# HUB MODE - Disable/Enable Weapon
# --------------------------------------------------------------------

func set_weapon_enabled(enabled: bool) -> void:
	"""Enable or disable the player's weapon (used in hub)."""
	weapon_enabled = enabled
	if gun:
		gun.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
		gun.visible = enabled
	
	# Also hide/show crosshair
	var crosshair := get_tree().get_first_node_in_group("crosshair")
	if crosshair:
		crosshair.visible = enabled
	
	# Hide turret in hub
	if has_node("Turret"):
		var turret = $Turret
		if not enabled:
			turret.visible = false


# --------------------------------------------------------------------
# Turret attachment helper
# --------------------------------------------------------------------
func _update_turret_attachment() -> void:
	# Ensure turret_node reference is valid (turret may be instanced later)
	if turret_node == null or not is_instance_valid(turret_node):
		if has_node("Turret"):
			turret_node = $Turret
		else:
			return

	var tnode: Node = turret_node
	if tnode == null:
		return

	# Resolve backpack and muzzle lazily (they live under TurretHead/VisualRoot)
	var t_backpack := tnode.get_node_or_null("TurretHead/VisualRoot/Backpack")
	var t_muzzle := tnode.get_node_or_null("TurretHead/VisualRoot/Muzzle")

	# IMPORTANT: derive facing from the same thing that flips the player sprite
	var facing_left: bool = false
	if animated_sprite != null:
		facing_left = animated_sprite.flip_h
	else:
		# fallback to direct node lookup
		if has_node("AnimatedSprite2D"):
			facing_left = $AnimatedSprite2D.flip_h

	# Hardcoded two-state placement
	if facing_left:
		# LEFT state (use inspector constant)
		tnode.position = TURRET_POS_LEFT
	else:
		# RIGHT state (canonical)
		tnode.position = TURRET_POS_RIGHT

	# Debug-protection: in debug builds verify no other code overwrites turret position
	if OS.is_debug_build():
		var _expected_pos: Vector2 = tnode.position
		# Wait one frame and then verify the position is unchanged
		await get_tree().process_frame
		if is_instance_valid(tnode) and tnode.position != _expected_pos:
			print("[TURRET PROTECT] turret.position was overwritten! expected=", _expected_pos, " got=", tnode.position)
			print_stack()

	# One-time debug print only when facing changes
	if facing_left != _last_facing_left:
		print("[TURRET ATTACH] facing_left=", facing_left, " turret_pos=", tnode.position, " backpack_exists=", (t_backpack != null))
		_last_facing_left = facing_left
