extends CanvasLayer

#signal shop_closed

@onready var continue_button := $Panel/ContinueButton
@onready var cards := $Panel/Cards
@onready var coin_label := $CoinUI/CoinLabel

var upgrades := [
	{
		"id": "max_ammo_plus_1",
		"price": 5,
		"icon": preload("res://assets/Separated/ammo.png"),
		"text": "+1 Max Ammo"
	},
	{
		"id": "fire_rate_plus_10",
		"price": 5,
		"icon": preload("res://assets/Separated/singlebullet.png"), # or reuse ammo icon for now
		"text": "Shoot 5% faster"
	},
	{
		"id": "shotgun_pellet_plus_1",
		"price": 5,
		"icon": preload("res://assets/Separated/ammo.png"), # placeholder
		"text": "+1 Shotgun Projectile"
	},

	# keep the old ones too (they just won't show yet with only 3 cards)
	{
		"id": "hp_refill",
		"price": 3,
		"icon": preload("res://assets/Separated/singleheart.png"),
		"text": "Refill HP"
	},
	{
		"id": "max_hp_plus_1",
		"price": 5,
		"icon": preload("res://assets/Separated/singleheart.png"),
		"text": "+1 Max HP"
	},
	{
		"id": "ammo_refill",
		"price": 3,
		"icon": preload("res://assets/Separated/ammo.png"),
		"text": "Refill Ammo"
	}
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

	# --- 2. Shuffle & assign new upgrades ---
	var pool := upgrades.duplicate()
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
