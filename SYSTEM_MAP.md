🧠 GameState.gd (Autoload / Singleton)

What it stores (run data):

coins: int

health: int

max_health: int

ammo: int

max_ammo: int

(soon) fire_rate: float for normal shoot

(soon) shotgun_pellets: int

(soon) current_level: int (for scaling later)

What it does:

add_coins(amount)
Updates coins and emits coins_changed.

apply_upgrade(id: String)
Handles permanent run upgrades, for example:

hp_refill → health = max_health

max_hp_plus_1 → max_health += 1; health = max_health

ammo_refill → ammo = max_ammo

max_ammo_plus_1 → max_ammo += 1; ammo = max_ammo

fire_rate_plus_10 → adjust stored fire_rate

shotgun_pellet_plus_1 → increase pellet count

start_new_run() (you already have something like this)
Resets run stats when restarting.

👉 Think of GameState as: “What does the player have this run?”



🔫 Player.gd

What it stores (local copy of stats):

health, max_health

ammo, max_ammo

fire_rate

knockback stuff

aim data: aim_dir, aim_cursor_pos, aim_mode

timers: fire_timer, invincible_timer, etc.

What it does:

In _ready():

Pulls current run stats from GameState:

health = GameState.health

max_health = GameState.max_health

ammo = GameState.ammo

max_ammo = GameState.max_ammo

(later) fire_rate = GameState.fire_rate

(later) shotgun pellet count if you store it in GameState.

Initializes HP/Ammo UI.

Movement:

Reads input and sets velocity.

Applies knockback.

Calls move_and_slide().

Aim:

Handles mouse + controller aiming.

Updates aim_dir and crosshair.

Shooting:

_process_shooting(delta):

Normal shoot() respects fire_rate.

fire_laser() / shotgun uses aim_dir and pellet count.

Spawns bullets and sets their direction.

Damage / heal:

take_damage(amount):

Updates GameState.health.

Clamps with GameState.max_health (important for upgrades).

Plays VFX/SFX.

Calls die() when needed.

Coins:

add_coin() just calls GameState.add_coins(1).

👉 Player is basically: “Use the current stats + show them + handle moment-to-moment gameplay.”



🎮 GameManager.gd

What it stores:

NodePaths:

death_screen_path

shop_path

exit_door_path

ui_root_path (HUD root)

shop_ui: CanvasLayer

death_screen: CanvasLayer

game_ui: CanvasLayer/Control (HUD)

exit_door: Area2D

next_scene_path: String

door_open: bool

is_in_death_sequence: bool

What it does:

_process():

Checks if all enemies are dead → _open_exit_door().

Exit door flow:

_open_exit_door() calls exit_door.open().

on_player_reached_exit(target_scene):

sets next_scene_path

calls _open_shop() (unless final door skips shop).

Shop flow:

_open_shop():

get_tree().paused = true

Input.set_mouse_mode(MOUSE_MODE_VISIBLE)

shows shop_ui

calls shop_ui.refresh_from_state()

hides game_ui (HUD) while shopping.

load_next_level():

hides shop_ui

shows game_ui

get_tree().paused = false

Input.set_mouse_mode(MOUSE_MODE_HIDDEN)

change_scene_to_file(next_scene_path)

Pause:

_unhandled_input(event) → ESC toggles pause.

_toggle_pause():

handles get_tree().paused

shows/hides pause menu

handles mouse visible/hidden.

Death:

on_player_died() starts slow-mo and shows death screen after a timer.

👉 GameManager = “Overall game flow boss” (pause, death, doors, shop, next level).



🛒 ShopUI.gd

What it stores:

upgrades: Array[Dictionary]
Example entries:
