extends Area2D

@export var initial_speed: float = 80.0
@export var friction: float = 200.0

@export var jump_force: float = 60.0      # how high the coin hops
@export var fall_gravity: float = 200.0   # how fast it falls back down

var velocity: Vector2 = Vector2.ZERO
var z_height: float = 0.0
var z_velocity: float = 0.0
var has_landed: bool = false
var is_collected: bool = false   # <-- new

@onready var sprite: Node2D = $AnimatedSprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var sfx_land: AudioStreamPlayer2D = $SFX_Spawn
@onready var sfx_pickup: AudioStreamPlayer2D = $SFX_Collect
@onready var light: PointLight2D = $PointLight2D   # <-- new


func _ready() -> void:
	print("COIN CONFIG → range:", GameConfig.pickup_magnet_range,
		" strength:", GameConfig.pickup_magnet_strength)


func launch() -> void:
	# random horizontal direction for the hop
	var angle: float = randf_range(-PI, PI)
	velocity = Vector2(cos(angle), sin(angle)) * initial_speed

	# vertical fake jump
	z_velocity = jump_force


func _physics_process(delta: float) -> void:
	# After pickup: no more movement / magnet / light drifting
	if is_collected:
		return

	# Magnet attraction (use global GameConfig values directly)
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player:
		var dist: float = global_position.distance_to(player.global_position)
		if dist < GameConfig.pickup_magnet_range:
			var dir: Vector2 = (player.global_position - global_position).normalized()
			global_position += dir * GameConfig.pickup_magnet_strength * delta
			return  # skip normal bounce movement when magnetizing

	# move horizontally
	global_position += velocity * delta
	velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	# fake vertical jump
	z_velocity -= fall_gravity * delta
	z_height += z_velocity * delta

	# coin hits "ground"
	if z_height < 0.0:
		z_height = 0.0

		if not has_landed:
			has_landed = true
			if sfx_land:
				sfx_land.play()

	# visual offset for jump
	sprite.position.y = -z_height


func _on_body_entered(body: Node2D) -> void:
	if is_collected:
		return

	if body.is_in_group("player"):
		is_collected = true

		GameState.add_coins(1)

		# disable interaction & hide while sound plays
		if collision:
			collision.set_deferred("disabled", true)
		if sprite:
			sprite.visible = false
		if light:
			light.visible = false  # <-- kill the light instantly

		if sfx_pickup:
			sfx_pickup.play()
			await sfx_pickup.finished

		queue_free()
