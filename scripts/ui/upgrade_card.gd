extends Control

signal purchased

@export var hover_scale: float = 1.05
@export var hover_tween_duration: float = 0.10
@export var rarity_outline_textures: Array[Texture2D] = []
@export var rarity_outline_materials: Array[Material] = []
@export var rarity: UpgradesDB.Rarity = UpgradesDB.Rarity.COMMON

@onready var visual_root: Control = $VisualRoot
@onready var outline: TextureRect = $VisualRoot/Outline
@onready var price_label: Label = $VisualRoot/PriceArea/TextureRect/PriceLabel
@onready var coin_icon: TextureRect = $VisualRoot/PriceArea/TextureRect/CoinIcon
@onready var icon_rect: TextureRect = $VisualRoot/Icon
@onready var desc_label: Label = $VisualRoot/Label
@onready var buy_button: Button = $VisualRoot/Button
@onready var sfx_collect: AudioStreamPlayer = $SFX_Collect

var upgrade_id: String = ""
var base_price: int = 0
var price: int = 0
var icon: Texture2D = null
var text: String = ""
var original_position: Vector2 = Vector2.ZERO
var tooltip_label: Label = null
var is_chaos_card: bool = false
var background_panel: Panel = null

const NON_SCALING_PRICE_UPGRADES := {"hp_refill": true, "ammo_refill": true}
const RARITY_COLORS := {
	UpgradesDB.Rarity.COMMON: Color(0.2, 0.8, 0.2, 0.8),
	UpgradesDB.Rarity.UNCOMMON: Color(0.2, 0.5, 1.0, 0.8),
	UpgradesDB.Rarity.RARE: Color(0.7, 0.2, 1.0, 0.8),
	UpgradesDB.Rarity.EPIC: Color(1.0, 0.85, 0.0, 0.85),
	UpgradesDB.Rarity.CHAOS: Color(1.0, 0.1, 0.1, 0.9),
	UpgradesDB.Rarity.SYNERGY: Color(0.0, 1.0, 1.0, 0.9),
}

func _ready() -> void:
	await get_tree().process_frame
	original_position = position
	
	if buy_button:
		if not buy_button.mouse_entered.is_connected(_on_hover):
			buy_button.mouse_entered.connect(_on_hover)
		if not buy_button.mouse_exited.is_connected(_on_hover_exit):
			buy_button.mouse_exited.connect(_on_hover_exit)
		if not buy_button.pressed.is_connected(_on_buy_pressed):
			buy_button.pressed.connect(_on_buy_pressed)

func _on_hover() -> void:
	var center = Vector2(1, 1)  # Adjusted Y from 117.5 to 125
	var offset = center * (hover_scale - 1.0)
	
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK).set_parallel(true)
	tween.tween_property(self, "scale", Vector2(hover_scale, hover_scale), hover_tween_duration)
	tween.tween_property(self, "position", original_position - offset, hover_tween_duration)

func _on_hover_exit() -> void:
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK).set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE, hover_tween_duration)
	tween.tween_property(self, "position", original_position, hover_tween_duration)

func setup(data: Dictionary) -> void:
	modulate = Color.WHITE
	rotation = 0.0
	visible = true
	
	var old_tooltip = get_node_or_null("TooltipLabel")
	if old_tooltip:
		old_tooltip.queue_free()
	
	is_chaos_card = false
	
	upgrade_id = data.get("id", "")
	base_price = int(data.get("price", 0))
	price = GameState.get_upgrade_price(upgrade_id, base_price) if not NON_SCALING_PRICE_UPGRADES.has(upgrade_id) else base_price
	icon = data.get("icon", null)
	text = data.get("text", "")
	rarity = data.get("rarity", UpgradesDB.Rarity.COMMON)
	
	if text == "" and upgrade_id != "":
		text = upgrade_id.replace("_", " ").capitalize()
	
	text = _get_dynamic_text()
	
	if data.get("effect") == "chaos_challenge":
		is_chaos_card = true
		_create_tooltip(data)
	
	_refresh()
	_apply_rarity_visuals()

func _get_dynamic_text() -> String:
	if upgrade_id == "max_hp_plus_1":
		var purchases: int = int(GameState.upgrade_purchase_counts.get("max_hp_plus_1", 0)) + 1
		var base_increase := 10.0
		var scaled_increase := base_increase * pow(1.1, purchases - 1)
		var inc_int := int(round(scaled_increase))
		return "+" + str(inc_int) + " Max HP"
	elif upgrade_id == "max_ammo_plus_1":
		var purchases: int = int(GameState.upgrade_purchase_counts.get("max_ammo_plus_1", 0)) + 1
		var base_ammo_inc := 1
		if GameState.alt_weapon != GameState.AltWeaponType.NONE and GameState.ALT_WEAPON_DATA.has(GameState.alt_weapon):
			var data = GameState.ALT_WEAPON_DATA[GameState.alt_weapon]
			base_ammo_inc = data.get("pickup_amount", 1)
		var scaled_ammo_inc := int(pow(2, purchases - 1)) * base_ammo_inc
		return "+" + str(scaled_ammo_inc) + " Max Ammo"
	else:
		return text

func _refresh() -> void:
	if price_label:
		price_label.visible = (price > 0)
		if price > 0:
			if price > base_price:
				price_label.text = str(price) + " ↑"
				price_label.modulate = Color(1.0, 0.8, 0.2)
			else:
				price_label.text = str(price)
				price_label.modulate = Color.WHITE
	
	if coin_icon:
		coin_icon.visible = (price > 0)
	
	if desc_label:
		desc_label.text = text
	
	if icon_rect:
		icon_rect.texture = icon
	
	if background_panel:
		var color = RARITY_COLORS.get(rarity, Color(0.2, 0.2, 0.2, 0.3))
		var style = background_panel.get_theme_stylebox("panel")
		if style and style is StyleBoxFlat:
			style.bg_color = color
	
	_update_button_state()

func _update_button_state() -> void:
	if not buy_button:
		return
	
	var affordable := (upgrade_id != "") and (GameState.coins >= price)
	var owned_block := false
	var unlock_blocked := false
	
	if upgrade_id != "":
		var u := UpgradesDB.get_by_id(upgrade_id)
		if not u.is_empty():
			var stackable := bool(u.get("stackable", true))
			if not stackable and GameState.has_upgrade(upgrade_id):
				owned_block = true
	
	if upgrade_id.begins_with("unlock_"):
		if upgrade_id in ["unlock_shotgun", "unlock_sniper", "unlock_turret", "unlock_shuriken"]:
			if GameState.alt_weapon != GameState.AltWeaponType.NONE:
				unlock_blocked = true
		elif upgrade_id in ["unlock_dash", "unlock_invis"]:
			if GameState.ability != GameState.AbilityType.NONE:
				unlock_blocked = true
	
	buy_button.disabled = not affordable or owned_block or unlock_blocked
	
	if unlock_blocked:
		modulate = Color(0.5, 0.5, 0.5, 0.7)
		if desc_label:
			desc_label.text = text + "\n[Already have one]"
	elif owned_block:
		modulate = Color(0.6, 0.6, 0.6, 0.8)
	else:
		modulate = Color.WHITE

func _on_buy_pressed() -> void:
	if upgrade_id == "" or GameState.coins < price:
		return
	
	if not GameState.spend_coins(price):
		return
	
	if not NON_SCALING_PRICE_UPGRADES.has(upgrade_id):
		GameState.record_upgrade_purchase(upgrade_id)
	
	UpgradesDB.apply_upgrade(upgrade_id)
	
	if sfx_collect:
		sfx_collect.play()
	
	emit_signal("purchased")
	_refresh()

func _create_tooltip(upgrade: Dictionary) -> void:
	tooltip_label = Label.new()
	tooltip_label.name = "TooltipLabel"
	tooltip_label.z_index = 1000
	
	var challenge_id = upgrade.get("value", "")
	match challenge_id:
		"half_hp_double_damage":
			tooltip_label.text = "Survive 5 rooms with half HP.\nComplete to DOUBLE your damage!"
	
	tooltip_label.add_theme_font_size_override("font_size", 14)
	tooltip_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.8))
	tooltip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	tooltip_label.custom_minimum_size = Vector2(200, 0)
	
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.1, 0.1, 0.1, 0.95)
	style_box.border_color = Color(0.8, 0.2, 0.2)
	style_box.border_width_left = 2
	style_box.border_width_right = 2
	style_box.border_width_top = 2
	style_box.border_width_bottom = 2
	style_box.corner_radius_top_left = 4
	style_box.corner_radius_top_right = 4
	style_box.corner_radius_bottom_left = 4
	style_box.corner_radius_bottom_right = 4
	style_box.content_margin_left = 8
	style_box.content_margin_right = 8
	style_box.content_margin_top = 8
	style_box.content_margin_bottom = 8
	
	tooltip_label.add_theme_stylebox_override("normal", style_box)
	tooltip_label.position = Vector2(10, -70)
	tooltip_label.visible = false
	visual_root.add_child(tooltip_label)

func _on_mouse_entered() -> void:
	if is_chaos_card and tooltip_label:
		tooltip_label.visible = true

func _on_mouse_exited() -> void:
	if is_chaos_card and tooltip_label:
		tooltip_label.visible = false

func _apply_rarity_visuals() -> void:
	if not outline:
		return
	
	var idx := int(rarity)
	
	if idx < rarity_outline_textures.size() and rarity_outline_textures[idx]:
		outline.texture = rarity_outline_textures[idx]
	
	if idx < rarity_outline_materials.size() and rarity_outline_materials[idx]:
		outline.material = rarity_outline_materials[idx]
	else:
		outline.material = null

func set_rarity(new_rarity: UpgradesDB.Rarity) -> void:
	rarity = new_rarity
	_apply_rarity_visuals()
