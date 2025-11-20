extends Area2D

@export var CoinScene: PackedScene
@export var AmmoScene: PackedScene
@export var HeartScene: PackedScene  # optional

@export var hit_flash_time: float = 0.1
var hit_flash_timer: float = 0.0
var base_modulate: Color

var destroyed: bool = false

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	if animated_sprite:
		animated_sprite.play("idle")  # your idle crate frame
	base_modulate = animated_sprite.modulate   # <--- add this

func _process(delta: float) -> void:
	_update_hit_feedback(delta)



func _update_hit_feedback(delta: float) -> void:
	# sprite flash
	if hit_flash_timer > 0.0:
		hit_flash_timer -= delta
		if hit_flash_timer <= 0.0:
			animated_sprite.modulate = base_modulate


func _spawn_loot() -> void:
	var roll := randf()

	var coin_chance := GameConfig.crate_coin_drop_chance
	var ammo_chance := GameConfig.crate_ammo_drop_chance
	var heart_chance := GameConfig.crate_heart_drop_chance

	# total chance covered by all drops
	var total := coin_chance + ammo_chance + heart_chance

	if total <= 0.0:
		return  # nothing can drop, bail early

	# normalize roll within [0, total)
	roll *= total

	if roll < ammo_chance:
		if AmmoScene:
			var ammo := AmmoScene.instantiate()
			ammo.global_position = global_position
			get_tree().current_scene.add_child(ammo)
	elif roll < ammo_chance + coin_chance:
		if CoinScene:
			var coin := CoinScene.instantiate()
			coin.global_position = global_position
			get_tree().current_scene.add_child(coin)
	else:
		if HeartScene:
			var heart := HeartScene.instantiate()
			heart.global_position = global_position
			get_tree().current_scene.add_child(heart)


func _break_and_despawn() -> void:
	if collision:
		collision.disabled = true

	# flash red + start timer
	animated_sprite.modulate = Color(1, 0.4, 0.4, 1)
	hit_flash_timer = hit_flash_time

	# scale pop
	scale = Vector2(1.6, 1.6)
	await get_tree().create_timer(0.4).timeout

	# shrink a bit before death
	scale = Vector2(1.4, 1.4)
	await get_tree().create_timer(0.4).timeout

	_spawn_loot()
	queue_free()



func _on_area_entered(area: Area2D) -> void:
	if destroyed:
		return

	if area.is_in_group("bullet"):
		destroyed = true
		$SFX_Break.play()

		# optional: remove bullet on impact
		area.queue_free()

		call_deferred("_break_and_despawn")
