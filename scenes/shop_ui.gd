extends CanvasLayer

#signal shop_closed

const ALT_WEAPON_NONE := 0
const ALT_WEAPON_SHOTGUN := 1
const ALT_WEAPON_SNIPER := 2
const ALT_WEAPON_TURRET := 3

const ABILITY_NONE := 0
const ABILITY_DASH := 1
const ABILITY_SLOWMO := 2

@onready var continue_button := $Panel/ContinueButton
@onready var cards := $Panel/Cards
@onready var coin_label := $CoinUI/CoinLabel

var upgrades := [
	{
		"id": "max_ammo_plus_1",
		"price": 0,
		"icon": preload("res://assets/Separated/bullet.png"),
		"text": "+1 Max Ammo",
		"requires_ammo_weapon": true,
	},
	{
		"id": "fire_rate_plus_10",
		"price": 0,
		"icon": preload("res://assets/Separated/singlebullet.png"),
		"text": "Shoot 5% faster"
	},

	{
		"id": "shotgun_pellet_plus_1",
		"price": 0,
		"icon": preload("res://assets/bullets/shotgunbullet.png"),
		"text": "+1 Shotgun Projectile",
		"requires_alt_weapon": ALT_WEAPON_SHOTGUN
	},

	# NEW: weapon unlocks (only show when you have no alt weapon)
	{
		"id": "unlock_shotgun",
		"price": 0,
		"icon": preload("res://assets/bullets/shotgunbullet.png"),
		"text": "Unlock Shotgun",
		"requires_alt_weapon": ALT_WEAPON_NONE
	},
	{
		"id": "unlock_sniper",
		"price": 0,
		"icon": preload("res://assets/bullets/sniperbullet.png"),
		"text": "Unlock Sniper",
		"requires_alt_weapon": ALT_WEAPON_NONE
	},
	{
		"id": "unlock_turret",
		"price": 0,
		"icon": preload("res://assets/Separated/turreticon.png"),
		"text": "Unlock Turret Backpack",
		"requires_alt_weapon": ALT_WEAPON_NONE
	},

	{
		"id": "turret_cooldown_minus_5",
		"price": 0,
		"icon": preload("res://assets/Separated/turreticon.png"), # placeholder
		"text": "Turret fires 5% faster",
		"requires_alt_weapon": ALT_WEAPON_TURRET,
	},

	{
		"id": "sniper_damage_plus_5",
		"price": 0,
		"icon": preload("res://assets/bullets/sniperbullet.png"),
		"text": "+5% Sniper Damage",
		"requires_alt_weapon": ALT_WEAPON_SNIPER,
	},

	# --- Ability unlocks ------------------------------------------------
	{
		"id": "unlock_dash",
		"price": 0,
		"icon": preload("res://assets/Separated/ammo.png"),
		"text": "Unlock Dash (Space)",
		"requires_ability": ABILITY_NONE,
	},
	{
		"id": "unlock_slowmo",
		"price": 0,
		"icon": preload("res://assets/Separated/ammo.png"),
		"text": "Unlock Bullet Time (Space)",
		"requires_ability": ABILITY_NONE,
	},
	{
		"id": "ability_cooldown_minus_10",
		"price": 0,
		"icon": preload("res://assets/Separated/ammo.png"),
		"text": "-10% Ability Cooldown",
		"requires_any_ability": true,
	},

	# Old upgrades
	{
		"id": "hp_refill",
		"price": 0,
		"icon": preload("res://assets/Separated/singleheart.png"),
		"text": "Refill HP"
	},
	{
		"id": "max_hp_plus_1",
		"price": 0,
		"icon": preload("res://assets/Separated/singleheart.png"),
		"text": "+1 Max HP"
	},
	{
		"id": "ammo_refill",
		"price": 0,
		"icon": preload("res://assets/Separated/bullet.png"),
		"text": "Refill Ammo",
		"requires_ammo_weapon": true,
	},
]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_cards()
	_update_coin_label()
	continue_button.pressed.connect(_on_continue_pressed)

func _setup_cards() -> void:
	# --- 1. Disconnect previous signals to avoid duplicates ---
	for card in cards.get_children():
		if card.purchased.is_connected(_on_card_purchased):
			card.purchased.disconnect(_on_card_purchased)

	# --- 2. Build pool of valid upgrades for this run ------------
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

		# Only connect once
		if not card.purchased.is_connected(_on_card_purchased):
			card.purchased.connect(_on_card_purchased)

func _update_coin_label() -> void:
	coin_label.text = str(GameState.coins)

func _on_card_purchased() -> void:
	# Coin amount changed → refresh label + button states
	_update_coin_label()
	for card in cards.get_children():
		if card.has_method("_update_button_state"):
			card._update_button_state()

func _on_continue_pressed() -> void:
	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm and gm.has_method("load_next_level"):
		gm.load_next_level()

# Called by GameManager when shop opens
func refresh_from_state() -> void:
	_update_coin_label()
	for card in cards.get_children():
		if card.has_method("_update_button_state"):
			card._update_button_state()
