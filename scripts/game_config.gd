extends Node

@export_category("Player")
@export var player_move_speed: float = 200.0
@export var player_max_health: int = 50
@export var player_fire_rate: float = 0.15
@export var player_knockback_strength: float = 250.0
@export var player_knockback_duration: float = 0.15
@export var player_invincible_time: float = 0.3
@export var player_max_ammo: int = 6             # ammo stays as-is

@export_category("Bullet / Weapons")
@export var bullet_speed: float = 500.0
@export var bullet_base_damage: int = 10         # ⬅ was 1

@export_category("Slime")
@export var slime_move_speed: float = 0.0
@export var slime_max_health: int = 30           # ⬅ was 3
@export var slime_contact_damage: int = 10       # ⬅ was 1
@export var slime_heart_drop_chance: float = 0.2

@export_category("Pickup Magnet")
@export var pickup_magnet_range: float = 160.0
@export var pickup_magnet_strength: float = 500.0

@export_category("Hit Feedback")
@export var hit_shake_strength: float = 8.0
@export var hit_shake_duration: float = 0.18
@export var hit_flash_duration: float = 0.15
@export var hit_flash_max_alpha: float = 0.15

@export_category("Shotgun Knockback")
@export var knockback_shake_strength: float = 8.0
@export var knockback_shake_duration: float = 0.18

@export_category("Alt Fire (Laser)")
@export var alt_fire_cooldown: float = 10.0
@export var alt_fire_bullet_count: int = 5
@export var alt_fire_spread_degrees: float = 12.0
@export var alt_fire_self_damage: int = 10      # ⬅ was 1
@export var alt_fire_recoil_strength: float = 400.0
@export var alt_fire_recoil_duration: float = 0.12

@export_category("Death / Game Over")
@export var death_slowmo_scale: float = 0.2
@export var death_slowmo_duration: float = 1.5

@export_category("Crate Loot")
@export var crate_coin_drop_chance: float = 0.6
@export var crate_ammo_drop_chance: float = 0.4
@export var crate_heart_drop_chance: float = 0.0  # optional, if you want hearts from crates
