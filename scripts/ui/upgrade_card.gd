extends Control

signal purchased

@onready var price_label: Label      = $PriceArea/TextureRect/PriceLabel
@onready var coin_icon: TextureRect  = $PriceArea/TextureRect/CoinIcon
@onready var icon_rect: TextureRect  = $Icon
@onready var desc_label: Label       = $Label
@onready var buy_button: Button      = $Button
@onready var color_rect: ColorRect   = $ColorRect  # ← Background for rarity color

var sfx_collect: AudioStreamPlayer = null
var background_panel: Panel = null  # Panel for rounded corners

var upgrade_id: String = ""
var base_price: int = 0
var price: int = 0
var icon: Texture2D = null
var text: String = ""
var rarity: int = 0  # ← Store rarity

const NON_SCALING_PRICE_UPGRADES := {
	"hp_refill": true,
	"ammo_refill": true,
}

# ✨ Rarity colors
const RARITY_COLORS := {
	UpgradesDB.Rarity.COMMON: Color(0.2, 0.8, 0.2, 0.3),      # Green (semi-transparent)
	UpgradesDB.Rarity.UNCOMMON: Color(0.2, 0.5, 1.0, 0.3),    # Blue
	UpgradesDB.Rarity.RARE: Color(0.7, 0.2, 1.0, 0.3),        # Purple
	UpgradesDB.Rarity.EPIC: Color(1.0, 0.85, 0.0, 0.4),       # Gold (slightly more opaque)
}

func _ready() -> void:
	if has_node("SFX_Collect"):
		sfx_collect = $SFX_Collect

	if buy_button and not buy_button.pressed.is_connected(_on_buy_pressed):
		buy_button.pressed.connect(_on_buy_pressed)
	
	# Create a Panel for rounded corners background
	if color_rect and not background_panel:
		background_panel = Panel.new()
		background_panel.z_index = -4096
		background_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		background_panel.position = Vector2.ZERO
		background_panel.size = color_rect.size
		
		# Create StyleBox for rounded corners
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.2, 0.2, 0.2, 0.3)  # Default color (will be updated in refresh)
		style.corner_radius_top_left = 10
		style.corner_radius_top_right = 10
		style.corner_radius_bottom_left = 10
		style.corner_radius_bottom_right = 10
		background_panel.add_theme_stylebox_override("panel", style)
		
		# Add panel before ColorRect (lower z-index)
		add_child(background_panel)
		move_child(background_panel, 0)
		
		# Hide the ColorRect since we're using Panel now
		color_rect.visible = false
	
	# Set pivot to center for proper rotation/scaling
	# Use actual card size (235x174 based on ColorRect/Button)
	pivot_offset = Vector2(235.0 / 2.0, 174.0 / 2.0)

	_refresh()


func setup(data: Dictionary) -> void:
	# Called by ShopUI with one of the dictionaries from UpgradesDB.get_all()
	upgrade_id = data.get("id", "")
	base_price = int(data.get("price", 0))
	# Calculate scaled price unless excluded
	if NON_SCALING_PRICE_UPGRADES.has(upgrade_id):
		price = base_price
	else:
		price = GameState.get_upgrade_price(upgrade_id, base_price)
	icon       = data.get("icon", null)
	text       = data.get("text", "")
	rarity     = data.get("rarity", UpgradesDB.Rarity.COMMON)  # ← Get rarity

	# Fallback so the card is never visually empty
	if text == "" and upgrade_id != "":
		text = upgrade_id.replace("_", " ").capitalize()

	# Update text for scaling upgrades to show actual value
	text = _get_dynamic_text()

	_refresh()


func _get_dynamic_text() -> String:
	"""Calculate dynamic text for scaling upgrades."""
	if upgrade_id == "max_hp_plus_1":
		var purchases: int = int(GameState.upgrade_purchase_counts.get("max_hp_plus_1", 0)) + 1
		var base_increase := 10.0
		var scaled_increase := base_increase * pow(1.1, purchases - 1)
		var inc_int := int(round(scaled_increase))
		return "+" + str(inc_int) + " Max HP"
	elif upgrade_id == "max_ammo_plus_1":
		var purchases: int = int(GameState.upgrade_purchase_counts.get("max_ammo_plus_1", 0)) + 1
		
		# Use weapon's pickup_amount as base (matches pickup value)
		var base_ammo_inc := 1  # Fallback if no weapon
		if GameState.alt_weapon != GameState.AltWeaponType.NONE and GameState.ALT_WEAPON_DATA.has(GameState.alt_weapon):
			var data = GameState.ALT_WEAPON_DATA[GameState.alt_weapon]
			base_ammo_inc = data.get("pickup_amount", 1)
		
		var scaled_ammo_inc := int(pow(2, purchases - 1)) * base_ammo_inc
		return "+" + str(scaled_ammo_inc) + " Max Ammo"
	else:
		return text


func _refresh() -> void:
	if price_label:
		if price == 0:
			# Hide price for free upgrades (chest mode)
			price_label.visible = false
		else:
			price_label.visible = true
			if price > base_price:
				price_label.text = str(price) + " ↑"  # Arrow shows it scaled
				price_label.modulate = Color(1.0, 0.8, 0.2)  # Yellow = expensive
			else:
				price_label.text = str(price)
				price_label.modulate = Color(1.0, 1.0, 1.0)  # White = base price
	
	# Hide coin icon for free upgrades
	if coin_icon:
		if price == 0:
			coin_icon.visible = false
		else:
			coin_icon.visible = true

	if desc_label:
		desc_label.text = text

	if icon_rect:
		icon_rect.texture = icon

	# ✨ Set background color based on rarity
	if background_panel:
		var color = RARITY_COLORS.get(rarity, Color(0.2, 0.2, 0.2, 0.3))  # Default gray
		
		# Update the Panel's StyleBox color
		var style = background_panel.get_theme_stylebox("panel")
		if style and style is StyleBoxFlat:
			style.bg_color = color

	_update_button_state()


func _update_button_state() -> void:
	if not buy_button:
		return

	var affordable := (upgrade_id != "") and (GameState.coins >= price)

	# If upgrade is non-stackable and already owned, disable buy button
	var owned_block := false
	if upgrade_id != "":
		var u := preload("res://scripts/Upgrades_DB.gd").get_by_id(upgrade_id)
		if not u.is_empty():
			var stackable := bool(u.get("stackable", true))
			if not stackable and GameState.has_upgrade(upgrade_id):
				owned_block = true
	
	# Check if this is a weapon/ability unlock that should be blocked
	var unlock_blocked := false
	if upgrade_id.begins_with("unlock_"):
		# Weapon unlocks - block if player already has ANY weapon
		if upgrade_id in ["unlock_shotgun", "unlock_sniper", "unlock_turret", "unlock_flamethrower", "unlock_shuriken", "unlock_grenade"]:
			if GameState.alt_weapon != GameState.AltWeaponType.NONE:
				unlock_blocked = true
		
		# Ability unlocks - block if player already has ANY ability
		elif upgrade_id in ["unlock_dash", "unlock_slowmo", "unlock_bubble", "unlock_invis"]:
			if GameState.ability != GameState.AbilityType.NONE:
				unlock_blocked = true

	buy_button.disabled = not affordable or owned_block or unlock_blocked
	
	# Visual feedback: dim the card if blocked by unlock
	if unlock_blocked:
		modulate = Color(0.5, 0.5, 0.5, 0.7)  # Gray out
		if desc_label:
			desc_label.text = text + "\n[Already have one]"
	elif owned_block:
		modulate = Color(0.6, 0.6, 0.6, 0.8)  # Slightly gray
	else:
		modulate = Color(1.0, 1.0, 1.0, 1.0)  # Full color


func _on_buy_pressed() -> void:
	if upgrade_id == "" or GameState.coins < price:
		return

	# Pay (use GameState helper so signals fire)
	if not GameState.spend_coins(price):
		return

	# Record purchase for scaling unless excluded
	if not NON_SCALING_PRICE_UPGRADES.has(upgrade_id):
		GameState.record_upgrade_purchase(upgrade_id)

	# Apply the upgrade via the DB
	preload("res://scripts/Upgrades_DB.gd").apply_upgrade(upgrade_id)

	# Little feedback
	if sfx_collect:
		sfx_collect.play()

	emit_signal("purchased")
	_refresh()
