extends Control

signal purchased

# Rarity outline textures (set in inspector, indices match UpgradesDB.Rarity enum)
# Index 0 = COMMON, 1 = UNCOMMON, 2 = RARE, 3 = EPIC, 4 = CHAOS
@export var rarity_outline_textures: Array[Texture2D] = []
@export var rarity_outline_materials: Array[Material] = []  # Optional shader materials per rarity

# Current rarity for this card (set in inspector or via set_rarity)
@export var rarity: UpgradesDB.Rarity = UpgradesDB.Rarity.COMMON

# Visual root for scaling/animations (set in scene)
@onready var visual_root: Control = $VisualRoot

# UI references (all inside VisualRoot)
@onready var outline: TextureRect = $VisualRoot/Outline
@onready var price_label: Label = $VisualRoot/PriceArea/TextureRect/PriceLabel
@onready var coin_icon: TextureRect = $VisualRoot/PriceArea/TextureRect/CoinIcon
@onready var icon_rect: TextureRect = $VisualRoot/Icon
@onready var desc_label: Label = $VisualRoot/Label
@onready var buy_button: Button = $VisualRoot/Button

# SFX stays on root
@onready var sfx_collect: AudioStreamPlayer = $SFX_Collect

var background_panel: Panel = null  # Panel for rounded corners

var upgrade_id: String = ""
var base_price: int = 0
var price: int = 0
var icon: Texture2D = null
var text: String = ""

# Tooltip for chaos cards
var tooltip_label: Label = null
var is_chaos_card: bool = false

const NON_SCALING_PRICE_UPGRADES := {
	"hp_refill": true,
	"ammo_refill": true,
}

# ✨ Rarity colors
const RARITY_COLORS := {
	UpgradesDB.Rarity.COMMON: Color(0.2, 0.8, 0.2, 0.8),      # Green (more opaque)
	UpgradesDB.Rarity.UNCOMMON: Color(0.2, 0.5, 1.0, 0.8),    # Blue (more opaque)
	UpgradesDB.Rarity.RARE: Color(0.7, 0.2, 1.0, 0.8),        # Purple (more opaque)
	UpgradesDB.Rarity.EPIC: Color(1.0, 0.85, 0.0, 0.85),      # Gold (more opaque)
	UpgradesDB.Rarity.CHAOS: Color(1.0, 0.1, 0.1, 0.9),       # Bright red (highly opaque)
}

func _ready() -> void:
	# Get optional ColorRect from VisualRoot
	var color_rect = visual_root.get_node_or_null("ColorRect")

	if buy_button and not buy_button.pressed.is_connected(_on_buy_pressed):
		buy_button.pressed.connect(_on_buy_pressed)
		# Connect tooltip to button hover
		buy_button.mouse_entered.connect(_on_mouse_entered)
		buy_button.mouse_exited.connect(_on_mouse_exited)
	
	# Set mouse filter to PASS so we receive mouse events even when hovering over children
	mouse_filter = Control.MOUSE_FILTER_PASS
	
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
		
		# Add panel to visual_root before ColorRect (lower z-index)
		visual_root.add_child(background_panel)
		visual_root.move_child(background_panel, 0)
		
		# Hide the ColorRect since we're using Panel now
		color_rect.visible = false
	
	# IMPORTANT: Keep root card scale at Vector2.ONE always
	scale = Vector2.ONE
	
	# Wait one frame then set pivot to center of VisualRoot
	await get_tree().process_frame
	visual_root.pivot_offset = visual_root.size * 0.5
	
	# Update outline texture and material based on rarity
	_apply_rarity_visuals()

	_refresh()


func set_slot_scale(mult: float) -> void:
	"""Set the visual scale of the card without affecting layout."""
	if visual_root:
		visual_root.scale = Vector2.ONE * mult


func set_hovered(is_hovered: bool) -> void:
	"""Scale the visual root on hover without affecting card layout."""
	if not visual_root:
		return
	
	# Kill existing tween
	var existing_tween = get_meta("hover_tween", null)
	if existing_tween and existing_tween is Tween:
		existing_tween.kill()
	
	var tween = create_tween()
	set_meta("hover_tween", tween)
	
	if is_hovered:
		tween.tween_property(visual_root, "scale", Vector2(1.05, 1.05), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		tween.tween_property(visual_root, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func setup(data: Dictionary) -> void:
	# Called by ShopUI with one of the dictionaries from UpgradesDB.get_all()
	
	# ========== COMPREHENSIVE VISUAL STATE RESET ==========
	# Reset EVERYTHING to ensure no leftover state from previous use
	
	# Color & opacity - FULL reset
	modulate = Color(1.0, 1.0, 1.0, 1.0)  # Explicit full white, full opacity
	self_modulate = Color(1.0, 1.0, 1.0, 1.0)  # Also reset self_modulate
	
	# Transform - don't touch scale (shop_ui manages this for card positioning)
	rotation = 0.0
	
	# Visibility & interaction
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Z-index
	z_index = 0
	
	# Remove old tooltip if exists
	var old_tooltip = get_node_or_null("TooltipLabel")
	if old_tooltip:
		old_tooltip.queue_free()
	
	is_chaos_card = false
	
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
	
	# Check if this is a chaos upgrade and create tooltip
	if data.get("effect") == "chaos_challenge":
		is_chaos_card = true
		_create_tooltip(data)

	_refresh()
	
	# Update outline texture and material to match rarity
	_apply_rarity_visuals()


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

	# Play purchase sound effect
	if sfx_collect:
		print("Playing SFX_Collect - Stream: ", sfx_collect.stream, " Playing: ", sfx_collect.playing)
		sfx_collect.play()
		print("After play() - Playing: ", sfx_collect.playing)
	else:
		print("ERROR: sfx_collect is null!")

	# ⭐ NOTE: Do NOT touch scale here - shop_ui manages card scales for layout
	# Only emit signal and refresh this card's state
	emit_signal("purchased")
	_refresh()


func _create_tooltip(upgrade: Dictionary) -> void:
	"""Create tooltip for chaos upgrades."""
	# Create tooltip label
	tooltip_label = Label.new()
	tooltip_label.name = "TooltipLabel"
	tooltip_label.z_index = 1000  # Above everything
	
	# Set tooltip text based on challenge
	var challenge_id = upgrade.get("value", "")
	
	match challenge_id:
		"half_hp_double_damage":
			tooltip_label.text = "Survive 5 rooms with half HP.\nComplete to DOUBLE your damage!"
	
	# Style the tooltip
	tooltip_label.add_theme_font_size_override("font_size", 14)
	tooltip_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.8))
	tooltip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	tooltip_label.custom_minimum_size = Vector2(200, 0)
	
	# Add background
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.1, 0.1, 0.1, 0.95)
	style_box.border_color = Color(0.8, 0.2, 0.2)  # Red border
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
	
	# Position tooltip (above card) - RELATIVE positioning
	tooltip_label.position = Vector2(10, -70)
	
	# Start hidden
	tooltip_label.visible = false
	
	# Add to VisualRoot so it scales with the card
	visual_root.add_child(tooltip_label)


func _on_mouse_entered() -> void:
	"""Show tooltip when mouse enters."""
	if is_chaos_card and tooltip_label:
		tooltip_label.visible = true


func _on_mouse_exited() -> void:
	"""Hide tooltip when mouse exits."""
	if is_chaos_card and tooltip_label:
		tooltip_label.visible = false


func _apply_rarity_visuals() -> void:
	"""Apply both texture and material based on current rarity."""
	if not outline:
		return
	
	var idx := int(rarity)
	
	# Apply texture from array
	if idx < rarity_outline_textures.size() and rarity_outline_textures[idx]:
		outline.texture = rarity_outline_textures[idx]
	
	# Apply optional shader material per rarity
	if idx < rarity_outline_materials.size() and rarity_outline_materials[idx]:
		outline.material = rarity_outline_materials[idx]
	else:
		outline.material = null


func set_rarity(new_rarity: UpgradesDB.Rarity) -> void:
	"""Update the rarity and immediately refresh visuals (texture + material)."""
	rarity = new_rarity
	_apply_rarity_visuals()
