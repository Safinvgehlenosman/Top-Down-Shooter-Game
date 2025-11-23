extends Node2D

@onready var head: Node2D = $TurretHead
@onready var muzzle: Marker2D = $TurretHead/Muzzle

var fire_interval: float = 0.8
var range: float = 400.0
var spread_rad: float = deg_to_rad(20.0)
var bullet_scene: PackedScene = null
var bullet_speed: float = 900.0
var damage: int = 1

var fire_timer: float = 0.0


# Called from Player.sync_from_gamestate()
func configure(data: Dictionary) -> void:
	fire_interval = data.get("fire_interval", fire_interval)
	range        = data.get("range", range)

	# get degrees from data, convert once to radians
	var spread_deg: float = data.get("spread_degrees", 20.0)
	spread_rad = deg_to_rad(spread_deg)

	bullet_scene = data.get("bullet_scene", bullet_scene)
	bullet_speed = data.get("bullet_speed", bullet_speed)
	damage       = data.get("damage", damage)


func _process(delta: float) -> void:
	if bullet_scene == null:
		return

	fire_timer -= delta

	var target := _find_target()
	if target == null:
		return

	# Aim at enemy
	head.look_at(target.global_position)
	head.rotation += deg_to_rad(180)


	# Auto fire
	if fire_timer <= 0.0:
		_fire_at(target)
		fire_timer = fire_interval


func _find_target() -> Node2D:
	var best: Node2D = null
	var best_dist: float = range

	# your slimes live in the "enemy" group
	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is Node2D):
			continue

		var d: float = global_position.distance_to(e.global_position)
		if d < best_dist:
			best_dist = d
			best = e

	return best


func _fire_at(target: Node2D) -> void:
	var dir := (target.global_position - muzzle.global_position).normalized()

	# add inaccuracy
	if spread_rad > 0.0:
		dir = dir.rotated(randf_range(-spread_rad, spread_rad))

	var bullet = bullet_scene.instantiate()
	bullet.global_position = muzzle.global_position
	bullet.direction = dir
	bullet.speed = bullet_speed
	bullet.damage = damage

	get_tree().current_scene.add_child(bullet)
