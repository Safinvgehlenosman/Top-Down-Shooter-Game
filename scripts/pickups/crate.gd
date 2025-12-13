extends Area2D

@export var CoinScene: PackedScene
@export var HeartScene: PackedScene  # optional

@export var hit_flash_time: float = 0.1
var hit_flash_timer: float = 0.0
var base_modulate: Color

var destroyed: bool = false
var is_room_clear_break: bool = false

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D          # Area2D hitbox
@onready var blocker_shape: CollisionShape2D = $Blocker/CollisionShape2D  # solid collider
@onready var health_component: Node = $Health

const COINS_PER_EXTRA_HEART: int = 1
const HEART_HEAL_MIN: int = 10  # minimum heal per heart pickup (use min to compute budget)
const MAX_HEARTS_PER_ROOM: int = 1
const MAX_HEARTS_PER_ROOM_LOW_HP: int = 2


func force_break() -> void:
	"""Force break the crate (called on room clear)."""
	if destroyed:
		return

	# Mark this break as coming from a room-clear so loot logic can allow hearts
	is_room_clear_break = true
	# Trigger death through health component
	if health_component and health_component.has_method("kill"):
		health_component.kill()
	else:
		# Fallback: directly call die handler
		_on_health_died()


func _ready() -> void:
	add_to_group("crate")
	
	if animated_sprite:
		animated_sprite.play("idle")
		base_modulate = animated_sprite.modulate

	# --- Wire up HealthComponent for crates ---
	if health_component:
		# Crate does NOT use GameState HP
		health_component.use_gamestate = false

		# Make sure it starts with at least 1 HP
		if health_component.max_health <= 0:
			health_component.max_health = 1
		if health_component.health <= 0:
			health_component.health = health_component.max_health

		# No i-frames for crates
		health_component.invincible_time = 0.0

		health_component.connect("damaged", Callable(self, "_on_health_damaged"))
		health_component.connect("died",    Callable(self, "_on_health_died"))


func _process(delta: float) -> void:
	_update_hit_feedback(delta)


func _update_hit_feedback(delta: float) -> void:
	if hit_flash_timer > 0.0:
		hit_flash_timer -= delta
		if hit_flash_timer <= 0.0 and animated_sprite:
			animated_sprite.modulate = base_modulate


# --------------------------------------------------------------------
# LOOT + BREAK
# --------------------------------------------------------------------

func _spawn_loot() -> void:
	# Dynamic pickup spawn based on player needs
	var hp_percent := 1.0
	
	# Calculate HP percentage from GameState
	if GameState.max_health > 0:
		hp_percent = float(GameState.health) / float(GameState.max_health)
	
	# ⭐ Check if chaos challenge is active (no HP upgrades allowed)
	var chaos_active := not GameState.active_chaos_challenge.is_empty()
	
	# LOOT PRIORITY:
	# 1. During chaos challenge → always coins
	# 2. Player missing HP → hearts (but NOT if at full HP)
	# 3. Player at full HP → coins only
	
	# Recompute global heart budget only if not yet computed or depleted
	if GameState.hearts_remaining_budget <= 0 and GameState.health < GameState.max_health:
		GameState.recompute_hearts_budget(HEART_HEAL_MIN)

	# Debug: show pre-roll state
	print("[CRATE DBG] GameState.health=%d max=%d missing=%d hp_percent=%.3f hearts_budget=%d" % [GameState.health, GameState.max_health, max(0, GameState.max_health - GameState.health), hp_percent, GameState.hearts_remaining_budget])

	# Determine rolled results from existing logic (preserve current roll behavior)
	var rolled_hearts: int = 0
	var rolled_coins: int = 0

	if chaos_active:
		rolled_coins = 1
	elif hp_percent < 1.0 and HeartScene:
		rolled_hearts = 1
	else:
		rolled_coins = 1

	# --- SAFETY GUARD: Crates must NEVER drop hearts during normal breaks.
	# Hearts are only granted by end-of-room / end-of-level systems elsewhere.
	# Convert any rolled hearts into coins to preserve probability mass, but
	# allow hearts when this crate was broken due to a room-clear (force_break()).
	if rolled_hearts > 0 and not is_room_clear_break:
		rolled_coins += rolled_hearts * COINS_PER_EXTRA_HEART
		rolled_hearts = 0

	# --- Per-room and missing-HP gating:
	var missing_hp := int(max(0, int(GameState.max_health - GameState.health)))

	# If player missing less than a single heart heal, convert any rolled hearts into coins
	if missing_hp < HEART_HEAL_MIN and rolled_hearts > 0:
		rolled_coins += rolled_hearts * COINS_PER_EXTRA_HEART
		rolled_hearts = 0

	# Determine room-allowed maximum hearts (default 1; allow 2 when low HP and missing >= 2 * HEART_HEAL_MIN)
	var room_allowed_max: int = MAX_HEARTS_PER_ROOM
	if hp_percent <= 0.5 and missing_hp >= (HEART_HEAL_MIN * 2):
		room_allowed_max = MAX_HEARTS_PER_ROOM_LOW_HP

	# Respect hearts already spawned in this room (do not mutate original roll yet)
	var room_remaining = max(0, room_allowed_max - int(GameState.hearts_spawned_this_room))

	# Convert excess hearts into coins using the global heart budget.
	# Pass `room_remaining` so conversion can request at most that many hearts from the global budget.
	var converted := _convert_excess_hearts_to_coins(rolled_hearts, rolled_coins, room_remaining)
	var hearts_to_spawn: int = int(converted.get("hearts", 0))
	var coins_to_spawn: int = int(converted.get("coins", 0))

	# Increment per-room counter for any hearts that will actually spawn
	if hearts_to_spawn > 0:
		GameState.hearts_spawned_this_room += hearts_to_spawn

	# Debug: final spawn decision
	print("[CRATE DBG] rolled_hearts=%d rolled_coins=%d -> hearts_to_spawn=%d coins_to_spawn=%d hearts_remaining_after=%d" % [rolled_hearts, rolled_coins, hearts_to_spawn, coins_to_spawn, GameState.hearts_remaining_budget])

	# Spawn hearts
	for i in range(hearts_to_spawn):
		if HeartScene:
			var heart := HeartScene.instantiate()
			heart.global_position = global_position
			get_tree().current_scene.add_child(heart)

	# Spawn coins
	for i in range(coins_to_spawn):
		if CoinScene:
			var coin := CoinScene.instantiate()
			coin.global_position = global_position
			get_tree().current_scene.add_child(coin)


func _break_and_despawn() -> void:
	# disable both the Area2D hitbox and the solid collider
	if collision:
		collision.disabled = true
	if blocker_shape:
		blocker_shape.disabled = true

	# flash red + start timer
	if animated_sprite:
		animated_sprite.modulate = Color(1, 0.4, 0.4, 1)
	hit_flash_timer = hit_flash_time

	# scale pop
	scale = Vector2(1.6, 1.6)
	await get_tree().create_timer(0.2).timeout

	# shrink a bit before death
	scale = Vector2(1.4, 1.4)
	await get_tree().create_timer(0.2).timeout

	_spawn_loot()
	queue_free()


# --------------------------------------------------------------------
# DAMAGE FLOW
# --------------------------------------------------------------------

func take_damage(amount: int) -> void:
	if destroyed:
		return

	if health_component and health_component.has_method("take_damage"):
		health_component.take_damage(amount)


func _on_area_entered(area: Area2D) -> void:
	if destroyed:
		return

	if area.is_in_group("bullet"):
		# Bullet hits crate → crate takes 1 damage
		area.queue_free()
		take_damage(1)


func _on_health_damaged(_amount: int) -> void:
	# simple red flash
	if animated_sprite:
		animated_sprite.modulate = Color(1, 0.4, 0.4, 1)
	hit_flash_timer = hit_flash_time


func _on_health_died() -> void:
	if destroyed:
		return
	destroyed = true

	# Play break SFX once
	if has_node("SFX_Break"):
		$SFX_Break.play()

	# Do the break animation + loot
	call_deferred("_break_and_despawn")


func _estimate_heart_heal_amount() -> int:
	# Try to obtain heal amount from HeartScene if available
	if not HeartScene:
		return 0
	var inst = HeartScene.instantiate()
	var heal: int = 0
	if inst == null:
		return 0

	# Add the temporary instance into the current scene so its methods using get_tree() work.
	var parent = null
	if get_tree() != null:
		parent = get_tree().current_scene

	if parent != null:
		parent.add_child(inst)
		if inst.has_method("_get_hp_value_for_level"):
			heal = int(inst._get_hp_value_for_level())
		# Remove temporary instance
		if inst.is_inside_tree():
			inst.queue_free()

	return heal


func _convert_excess_hearts_to_coins(rolled_hearts: int, rolled_coins: int, room_remaining: int) -> Dictionary:
	# Convert extra hearts into coins using both the per-room allowance and the global GameState heart budget
	var missing_hp: int = int(max(0, int(GameState.max_health - GameState.health)))
	var heart_heal_min: int = int(HEART_HEAL_MIN)

	# Debug: pre-conversion state
	print("[CRATE DBG CONV] health=%d max=%d missing_hp=%d rolled_hearts=%d rolled_coins=%d heart_heal_min=%d hearts_budget_before=%d room_remaining=%d" % [GameState.health, GameState.max_health, missing_hp, rolled_hearts, rolled_coins, heart_heal_min, GameState.hearts_remaining_budget, room_remaining])

	# Request at most `room_remaining` hearts from the global budget to avoid over-consuming it
	var request_count := int(min(rolled_hearts, room_remaining))
	var hearts_allowed := GameState.consume_heart_budget(request_count)

	# Any rolled hearts that weren't allowed (either due to room cap or budget) become coins
	var extra_hearts = max(0, rolled_hearts - hearts_allowed)
	var coins_to_spawn = int(rolled_coins) + (extra_hearts * int(COINS_PER_EXTRA_HEART))

	# Debug: after consumption
	print("[CRATE DBG CONV] request=%d hearts_allowed=%d extra_hearts=%d coins_to_spawn=%d hearts_budget_after=%d" % [request_count, hearts_allowed, extra_hearts, coins_to_spawn, GameState.hearts_remaining_budget])

	return {"hearts": hearts_allowed, "coins": coins_to_spawn}
