extends "res://scripts/slimes/base_slime.gd"

@export var projectile_scene: PackedScene
@export var shoot_interval: float = 2.0      # seconds between volleys
@export var shoot_range: float = 220.0       # how far it can shoot
@export var burst_count: int = 14            # pellets per volley
@export var spread_degrees: float = 80.0     # width of the cloud

# random speed range per pellet (for messy cloud)
@export var pellet_min_speed: float = 40.0
@export var pellet_max_speed: float = 90.0

var shoot_timer: float = 0.0


func _ready() -> void:
	super._ready()
	# Increase pellet speeds to match global pacing
	pellet_min_speed *= 1.2
	pellet_max_speed *= 1.2
	# tiny random offset so groups of poison slimes don’t fire in perfect sync
	shoot_timer = randf_range(0.0, shoot_interval * 0.5)


func _physics_process(delta: float) -> void:
	# 1) normal slime behaviour (movement, aggro, contact damage, etc.)
	super._physics_process(delta)

	# 2) shooting logic
	if is_dead or player == null:
		return

	shoot_timer -= delta
	if shoot_timer > 0.0:
		return

	var to_player: Vector2 = player.global_position - global_position
	if to_player.length() > shoot_range:
		return
	if not _can_see_player():
		return

	_shoot_burst(to_player.normalized())
	shoot_timer = shoot_interval


func _shoot_burst(base_dir: Vector2) -> void:
	if projectile_scene == null:
		return

	var base_angle := base_dir.angle()
	var half_spread := deg_to_rad(spread_degrees) * 0.5
	var count = max(burst_count, 1)

	for i in range(count):
		var t: float = 0.5 if count == 1 else float(i) / float(count - 1)

		var angle := base_angle - half_spread + t * (2.0 * half_spread)
		var dir := Vector2.RIGHT.rotated(angle)

		var p := projectile_scene.instantiate()
		p.global_position = global_position
		p.direction = dir

		# random speed per pellet (same as ice)
		if "speed" in p:
			p.speed = randf_range(pellet_min_speed, pellet_max_speed)

		get_tree().current_scene.add_child(p)
