extends CanvasLayer

#signal shop_closed

const ALT_WEAPON_NONE := 0
const ALT_WEAPON_SHOTGUN := 1
const ALT_WEAPON_SNIPER := 2
const ALT_WEAPON_TURRET := 3
const ALT_WEAPON_FLAMETHROWER := 4

const ABILITY_NONE := 0
const ABILITY_DASH := 1
const ABILITY_SLOWMO := 2

@onready var continue_button       := $Panel/ContinueButton
@onready var cards                 := $Panel/Cards
@onready var coin_label: Label     =  $CoinUI/CoinLabel

@onready var hp_fill: TextureProgressBar = $HPBar/HPFill
@onready var hp_label: Label             = $HPBar/HPLabel

@onready var ammo_label: Label           = $AmmoUI/AmmoLabel
@onready var level_label: Label          = $LevelUI/LevelLabel

@onready var ability_bar_container: Control      = $AbilityBar
@onready var ability_bar: TextureProgressBar     = $AbilityBar/AbilityFill
@onready var ability_label: Label                = $AbilityBar/AbilityLabel


var upgrades := [
	{
		"id": "max_ammo_plus_1",
		"price": 10,
		"icon": preload("res://assets/Separated/bullet.png"),
		"text": "+1 Max Ammo",
		"requires_ammo_weapon": true,
	},
	{
		"id": "fire_rate_plus_10",
		"price": 10,
		"icon": preload("res://assets/Separated/singlebullet.png"),
		"text": "Shoot 5% faster"
	},

	{
		"id": "shotgun_pellet_plus_1",
		"price": 10,
		"icon": preload("res://assets/bullets/shotgunbullet.png"),
		"text": "+1 Shotgun Projectile",
		"requires_alt_weapon": ALT_WEAPON_SHOTGUN
	},

	# NEW: weapon unlocks (only show when you have no alt weapon)
	{
		"id": "unlock_shotgun",
		"price": 15,
		"icon": preload("res://assets/bullets/shotgunbullet.png"),
		"text": "Unlock Shotgun",
		"requires_alt_weapon": ALT_WEAPON_NONE
	},
	{
		"id": "unlock_sniper",
		"price": 15,
		"icon": preload("res://assets/bullets/sniperbullet.png"),
		"text": "Unlock Sniper",
		"requires_alt_weapon": ALT_WEAPON_NONE
	},
  
	{
		"id": "unlock_turret",
		"price": 15,
		"icon": preload("res://assets/Separated/turreticon.png"),
		"text": "Unlock Turret Backpack",
		"requires_alt_weapon": ALT_WEAPON_NONE
	},
	{
		"id": "unlock_flamethrower",
		"price": 15,
		"icon": preload("res://assets/bullets/flamethrowerbullet.png"), # TODO: flame icon
		"text": "Unlock Flamethrower",
		"requires_alt_weapon": ALT_WEAPON_NONE
	},
	{
		"id": "flame_range_plus_20",
		"price": 10,
		"icon": preload("res://assets/bullets/flamethrowerbullet.png"), # use whatever icon you want
		"text": "+20% Flame Range",
		"requires_alt_weapon": ALT_WEAPON_FLAMETHROWER,
	},

	
	{
		"id": "turret_cooldown_minus_5",
		"price": 10,
		"icon": preload("res://assets/Separated/turreticon.png"), # placeholder
		"text": "Turret fires 5% faster",
		"requires_alt_weapon": ALT_WEAPON_TURRET,
	},
	{
		"id": "sniper_damage_plus_5",
		"price": 10,
		"icon": preload("res://assets/bullets/sniperbullet.png"),
		"text": "+5% Sniper Damage",
		"requires_alt_weapon": ALT_WEAPON_SNIPER,
	},

	# --- Ability unlocks ------------------------------------------------
	{
		"id": "unlock_dash",
		"price": 15,
		"icon": preload("res://assets/Separated/ammo.png"),
		"text": "Unlock Dash (Space)",
		"requires_ability": ABILITY_NONE,
	},
	{
		"id": "unlock_slowmo",
		"price": 15,
		"icon": preload("res://assets/Separated/ammo.png"),
		"text": "Unlock Bullet Time (Space)",
		"requires_ability": ABILITY_NONE,
	},
	{
		"id": "ability_cooldown_minus_10",
		"price": 10,
		"icon": preload("res://assets/Separated/ammo.png"),
		"text": "-10% Ability Cooldown",
		"requires_any_ability": true,
	},

	# Old upgrades
	{
		"id": "hp_refill",
		"price": 3,
		"icon": preload("res://assets/Separated/singleheart.png"),
		"text": "Refill HP"
	},
	{
		"id": "max_hp_plus_1",
		"price": 15,
		"icon": preload("res://assets/Separated/singleheart.png"),
		"text": "+10 Max HP"   # ⬅ scaled text to match +10 effect
	},
	{
		"id": "ammo_refill",
		"price": 3,
		"icon": preload("res://assets/Separated/bullet.png"),
		"text": "Refill Ammo",
		"requires_ammo_weapon": true,
	},
]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ability_bar_container.visible = false

	_setup_cards()
	_refresh_from_state_full()

	continue_button.pressed.connect(_on_continue_pressed)


# -------------------------------------------------------------------
# CARD SETUP
# -------------------------------------------------------------------

func _setup_cards() -> void:
	# Disconnect old signals so we don't double-connect
	for card in cards.get_children():
		if card.purchased.is_connected(_on_card_purchased):
			card.purchased.disconnect(_on_card_purchased)

	var pool: Array = []

	for u in upgrades:
		# Exact weapon requirement
		if u.has("requires_alt_weapon") and u["requires_alt_weapon"] != GameState.alt_weapon:
			continue

		# Generic "needs ammo-using weapon" requirement
		if u.get("requires_ammo_weapon", false):
			if GameState.alt_weapon == ALT_WEAPON_NONE or GameState.alt_weapon == ALT_WEAPON_TURRET:
				continue

		# Ability must be NONE
		if u.has("requires_ability") and GameState.ability != u["requires_ability"]:
			continue

		# Any ability required
		if u.get("requires_any_ability", false) and GameState.ability == ABILITY_NONE:
			continue

		pool.append(u)

	pool.shuffle()

	var count: int = min(cards.get_child_count(), pool.size())

	for i in range(count):
		var card = cards.get_child(i)
		var data = pool[i]

		card.setup(data)

		if not card.purchased.is_connected(_on_card_purchased):
			card.purchased.connect(_on_card_purchased)


# -------------------------------------------------------------------
# UI REFRESH HELPERS
# -------------------------------------------------------------------

func _refresh_from_state_full() -> void:
	_update_coin_label()
	_update_hp_from_state()
	_update_ammo_from_state()
	_update_level_label()
	_update_ability_bar()
	_update_card_button_states()


func _update_coin_label() -> void:
	coin_label.text = str(GameState.coins)


func _update_hp_from_state() -> void:
	var gs = GameState
	hp_fill.max_value = gs.max_health
	hp_fill.value = gs.health
	hp_label.text = "%d/%d" % [gs.health, gs.max_health]


func _update_ammo_from_state() -> void:
	var gs = GameState
	if gs.max_ammo <= 0:
		ammo_label.text = "-/-"
	else:
		ammo_label.text = "%d/%d" % [gs.ammo, gs.max_ammo]


func _update_level_label() -> void:
	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm:
		level_label.text = str(gm.current_level)


func _update_card_button_states() -> void:
	for card in cards.get_children():
		if card.has_method("_update_button_state"):
			card._update_button_state()


# --- Ability bar (same logic as main HUD) ---------------------------

func _update_ability_bar() -> void:
	var gs = GameState

	# No ability equipped → hide bar
	if gs.ability == ABILITY_NONE:
		ability_bar_container.visible = false
		return

	var data = gs.ABILITY_DATA.get(gs.ability, {})
	if data.is_empty():
		ability_bar_container.visible = false
		return

	var max_cd: float = data.get("cooldown", 0.0)
	if max_cd <= 0.0:
		ability_bar_container.visible = false
		return

	ability_bar_container.visible = true

	var cd_left: float = gs.ability_cooldown_left
	ability_bar.max_value = max_cd
	ability_bar.value = max_cd - cd_left

	# Show "remaining / total s"
	if ability_label:
		var remaining = round(cd_left * 10.0) / 10.0
		var max_display = round(max_cd * 10.0) / 10.0
		ability_label.text = "%s / %s s" % [remaining, max_display]


# -------------------------------------------------------------------
# SIGNALS
# -------------------------------------------------------------------

func _on_card_purchased() -> void:
	# Some upgrade changed stats → refresh everything visible in the shop
	_refresh_from_state_full()


func _on_continue_pressed() -> void:
	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm and gm.has_method("load_next_level"):
		gm.load_next_level()


# Called by GameManager when shop opens
func refresh_from_state() -> void:
	_refresh_from_state_full()
