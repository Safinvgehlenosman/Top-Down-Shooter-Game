extends Control

signal purchased

@export var upgrade_id: String = ""
@export var price: int = 0
@export var icon: Texture2D
@export var description: String = ""

@onready var sfx_collect: AudioStreamPlayer = $Button/SFX_Collect
@onready var price_label: Label = $PriceArea/TextureRect/PriceLabel
@onready var icon_rect: TextureRect = $Icon
@onready var desc_label: Label = $Label
@onready var buy_button: Button = $Button

func _ready() -> void:
	_refresh()
	buy_button.pressed.connect(_on_buy_pressed)

# Called from ShopUI to configure this card
func setup(data: Dictionary) -> void:
	upgrade_id = data.get("id", "")
	price = data.get("price", 0)
	icon = data.get("icon", null)
	description = data.get("text", "")
	_refresh()

func _refresh() -> void:
	if price_label:
		price_label.text = str(price)
	if icon_rect:
		icon_rect.texture = icon
	if desc_label:
		desc_label.text = description
	_update_button_state()

func _update_button_state() -> void:
	if buy_button:
		buy_button.disabled = GameState.coins < price

func _on_buy_pressed() -> void:
	if GameState.coins < price:
		return

	GameState.coins -= price
	GameState.apply_upgrade(upgrade_id)

	emit_signal("purchased")
	_refresh()
	sfx_collect.play()
