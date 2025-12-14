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
@onready var icon_rect: TextureRect = get_node_or_null("VisualRoot/IconSlot/Icon") as TextureRect
@onready var icon_slot: CenterContainer = get_node_or_null("VisualRoot/IconSlot") as CenterContainer
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
var price_tween: Tween = null
var _price_has_arrow: bool = false
var is_unlock_card: bool = false
var count_as_purchase: bool = true
var adjusted_base_price: int = 0

const NON_SCALING_PRICE_UPGRADES := {"hp_refill": true, "ammo_refill": true}
const RARITY_COLORS := {
	UpgradesDB.Rarity.COMMON: Color(0.2, 0.8, 0.2, 0.8),
	UpgradesDB.Rarity.UNCOMMON: Color(0.2, 0.5, 1.0, 0.8),
	UpgradesDB.Rarity.RARE: Color(0.7, 0.2, 1.0, 0.8),
	UpgradesDB.Rarity.EPIC: Color(1.0, 0.85, 0.0, 0.85),
	UpgradesDB.Rarity.CHAOS: Color(1.0, 0.1, 0.1, 0.9),
	UpgradesDB.Rarity.SYNERGY: Color(0.0, 1.0, 1.0, 0.9),
}

# Icon resource constants (paths or resource identifiers)
const PRIMARY_GUN_ICON_TEX := "res://assets/SpriteSheet.png"
const SHOTGUN_ICON_TEX := "res://assets/bullets/shotgunbullet.png"
const SNIPER_ICON_TEX := "res://assets/bullets/sniperbullet.png"
const SHURIKEN_ICON_TEX := "res://assets/bullets/shuriken.png"
const TURRET_ICON_TEX := "res://assets/bullets/turretbullet.png"
const HEART_ICON_TEX := "res://assets/Separated/singleheart.png"
const SPEED_DASH_ICON_TEX := "res://assets/speeddashicon.png"
const INVIS_ICON_TEX := "res://assets/invisicon.png"
const DEFAULT_ICON_TEX := "res://assets/Separated/singleheart.png"

# Track missing-icon prints so we only print once per upgrade id
var _icon_missing_reported: Dictionary = {}


func _ready() -> void:
	await get_tree().process_frame
	original_position = position

	# Prefer nearest filtering for crisp UI icons
	if icon_rect:
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	
	if buy_button:
		if not buy_button.mouse_entered.is_connected(_on_hover):
			buy_button.mouse_entered.connect(_on_hover)
		if not buy_button.mouse_exited.is_connected(_on_hover_exit):
			buy_button.mouse_exited.connect(_on_hover_exit)
		if not buy_button.pressed.is_connected(_on_buy_pressed):
			buy_button.pressed.connect(_on_buy_pressed)

	if Engine.has_singleton("GameState"):
		var gs = Engine.get_singleton("GameState")
		if gs.has_signal("coins_changed"):
			gs.connect("coins_changed", Callable(self, "_on_coins_changed"))

	# Ensure slot + icon sizing and crisp filter
	if icon_slot:
		icon_slot.custom_minimum_size = Vector2(32, 32)
	if icon_rect:
		icon_rect.custom_minimum_size = Vector2(32, 32)
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _on_hover() -> void:
	var center = Vector2(1, 1)
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
	# Determine if this card represents an unlock (weapon or ability)
	is_unlock_card = false
	if str(data.get("unlock_weapon", "")).strip_edges() != "" or str(data.get("unlock_ability", "")).strip_edges() != "":
		is_unlock_card = true
	elif upgrade_id.ends_with("_unlock"):
		is_unlock_card = true
	base_price = int(data.get("price", 0))
	# Apply global half-price tweak for non-scaled items as well
	adjusted_base_price = 0
	if base_price > 0:
		adjusted_base_price = int(round(base_price * 0.5))
	# Determine price (non-scaling upgrades use adjusted base price)
	if not NON_SCALING_PRICE_UPGRADES.has(upgrade_id):
		price = GameState.get_upgrade_price(upgrade_id, base_price)
	else:
		price = adjusted_base_price
	icon = data.get("icon", null)

	# Resolve icon automatically (or respect explicit icon_path)
	_apply_icon(data)
	text = data.get("text", "")
	rarity = data.get("rarity", UpgradesDB.Rarity.COMMON)
	
	if text == "" and upgrade_id != "":
		text = upgrade_id.replace("_", " ").capitalize()
	
	text = _get_dynamic_text()
	
	if data.get("effect") == "chaos_challenge":
		is_chaos_card = true
		_create_tooltip(data)
	
	_refresh()
	# Debug: indicate unlock cards
	print("[CARD]", upgrade_id, "is_unlock=", is_unlock_card)

	# Ensure card reflects current GameState ownership without resetting visuals
	if has_method("refresh_state_from_gamestate"):
		refresh_state_from_gamestate()

	# Respect chest mode marker so chest picks don't count as purchases
	count_as_purchase = not bool(data.get("chest_mode", false))
	_apply_rarity_visuals()
	_update_price_color()

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
			# Always show just the price number
			price_label.text = str(price)
			# Centralized price color
			_update_price_color()

			# If price is above base (arrow state) and we haven't shown the flash yet, flash it
			if price > base_price:
				if not _price_has_arrow:
					flash_price_increase()
					_price_has_arrow = true
			else:
				_price_has_arrow = false
	
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

func flash_price_increase() -> void:
	"""Call this when price increases to show yellow flash with arrow."""
	if not price_label or price <= base_price:
		return
	# Kill any running price tween
	if price_tween and price_tween.is_running():
		price_tween.kill()

	# Show yellow with arrow immediately on the label (only the label flashes)
	price_label.text = str(price) + " ↑"
	var flash_color := Color(1.0, 0.8, 0.2)
	price_label.modulate = flash_color
	# Mark flashing so other updates don't override the flash
	price_label.set_meta("price_flash_active", true)

	# Wait a short moment then restore final color/text on the label
	var final_color: Color = Color.WHITE if GameState.coins >= price else Color(1.0, 0.3, 0.3)
	await get_tree().create_timer(0.35).timeout
	if price_label:
		price_label.modulate = final_color
		price_label.text = str(price)
		# Ensure final state is computed from authoritative logic
		_update_price_color()
		price_label.set_meta("price_flash_active", false)


func flash_purchase() -> void:
	# Flash yellow briefly on successful purchase, then recalc final color.
	if not price_label:
		return
	# Kill any running price tween
	if price_tween and price_tween.is_running():
		price_tween.kill()

	price_label.set_meta("price_flash_active", true)
	price_label.text = str(price)
	price_label.modulate = Color(1.0, 0.8, 0.2)
	await get_tree().create_timer(0.35).timeout
	if price_label:
		price_label.text = str(price)
		price_label.set_meta("price_flash_active", false)
		_update_price_color()

func _update_button_state() -> void:
	if not buy_button:
		return

	var affordable := (upgrade_id != "") and (GameState.coins >= price)
	var owned_block := false
	var unlock_blocked := false
	var stackable := true

	if upgrade_id != "":
		var u := UpgradesDB.get_by_id(upgrade_id)
		if not u.is_empty():
			stackable = bool(u.get("stackable", true))
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

	# Preserve permanent greys for unlocks/owned non-stackable items
	if unlock_blocked:
		modulate = Color(0.5, 0.5, 0.5, 0.7)
		if desc_label:
			desc_label.text = text + "\n[Already have one]"
	elif owned_block:
		# Owned non-unlock upgrades get a subtle grey but not the permanent unlock style
		if not is_unlock_card:
			modulate = Color(1, 1, 1, 1)
		else:
			modulate = Color(0.6, 0.6, 0.6, 0.8)
	else:
		modulate = Color.WHITE

	# Price color controlled centrally
	if price_label:
		_update_price_color()

func _on_buy_pressed() -> void:
	if upgrade_id == "" or GameState.coins < price:
		return
	
	var old_price = price
	
	if not GameState.spend_coins(price):
		return
	
	if not NON_SCALING_PRICE_UPGRADES.has(upgrade_id):
		if count_as_purchase:
			GameState.record_upgrade_purchase(upgrade_id)
	
	UpgradesDB.apply_upgrade(upgrade_id)
	
	if sfx_collect:
		sfx_collect.play()
	
	emit_signal("purchased")
	
	# Recalculate price after purchase
	if not NON_SCALING_PRICE_UPGRADES.has(upgrade_id):
		price = GameState.get_upgrade_price(upgrade_id, base_price)
	else:
		price = adjusted_base_price
	
	# Flash to indicate successful purchase (deterministic behavior)
	flash_purchase()

	# Immediately update this card's visuals; only lock/grey permanently for unlock cards
	if is_unlock_card:
		if buy_button:
			buy_button.disabled = true
		modulate = Color(0.6, 0.6, 0.6, 0.8)
		if desc_label:
			desc_label.text = text + "\n[Purchased]"
	else:
		# Non-unlock: disable button if now owned/non-stackable, but don't change modulate permanently
		if buy_button:
			buy_button.disabled = true
		# leave modulate as-is; refresh to reflect price/affordability
		_refresh()

	print("[CARD PURCHASED]", upgrade_id, "is_unlock=", is_unlock_card)

	# Check upgrade data for unlocks and queue hints immediately
	var up := UpgradesDB.get_by_id(upgrade_id)
	if up.size() > 0:
		var uw := str(up.get("unlock_weapon", "")).strip_edges()
		var ua := str(up.get("unlock_ability", "")).strip_edges()
		var hint_node := _get_hint_popup()
		if hint_node == null:
			# Nothing to do if no hint system available
			return
		if not hint_node.has_method("queue_hint"):
			print("[HINT][upgrade_card] ERROR: HintPopup has no queue_hint() method")
			return
		if ua != "":
			hint_node.call_deferred("queue_hint", "ABILITY UNLOCKED", "Press SPACE to use it")
			print("[HINT][upgrade_card] queued ability hint")
		if uw != "":
			var instr := "New weapon unlocked"
			match uw:
				"sniper", "shotgun", "shuriken":
					instr = "Press RMB to shoot"
				"turret":
					instr = "Turret shoots automatically"
				_:
					instr = "New weapon unlocked"
			hint_node.call_deferred("queue_hint", "ALT WEAPON UNLOCKED", instr)
			print("[HINT][upgrade_card] queued weapon hint type=", uw)

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


func _get_hint_popup() -> Node:
	var root := get_tree().get_root()
	var hint := root.get_node_or_null("Level1/UI/HintPopup")
	if hint == null:
		hint = root.find_node("HintPopup", true, false)
	if hint != null:
		print("[HINT][upgrade_card] HintPopup found at: ", hint.get_path())
	else:
		print("[HINT][upgrade_card] ERROR: HintPopup not found")
	return hint

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


func _load_tex_safe(path: String) -> Texture2D:
	if not path or str(path).strip_edges() == "":
		return null
	# ResourceLoader.exists accepts a path string
	if not ResourceLoader.exists(path):
		return null
	var res = load(path)
	if res and res is Texture2D:
		return res
	# Not a texture
	return null


func _get_icon_texture(u: Dictionary) -> Texture2D:
	# Respect explicit icon_path if present
	var override_path := str(u.get("icon_path", "")).strip_edges()
	if override_path != "":
		var otex := _load_tex_safe(override_path)
		if otex:
			return otex

	# Weapon unlock/requirement mapping (bullets/projectiles)
	var req_weapon := str(u.get("requires_weapon", "")).strip_edges()
	var uw := str(u.get("unlock_weapon", "")).strip_edges()
	var weapon_key := uw if uw != "" else req_weapon
	if weapon_key != "":
		match weapon_key:
			"shotgun": return _load_tex_safe(SHOTGUN_ICON_TEX)
			"sniper": return _load_tex_safe(SNIPER_ICON_TEX)
			"shuriken": return _load_tex_safe(SHURIKEN_ICON_TEX)
			"turret": return _load_tex_safe(TURRET_ICON_TEX)

	# Invis-related
	var ua := str(u.get("unlock_ability", "")).strip_edges()
	var ra := str(u.get("requires_ability", "")).strip_edges()
	var id := str(u.get("id", ""))
	if ua == "invis" or ra == "invis" or id.find("invis") >= 0:
		return _load_tex_safe(INVIS_ICON_TEX)

	# Speed/dash-related
	if id.find("move_speed") >= 0 or id.find("dash") >= 0 or ua == "dash" or ra == "dash":
		return _load_tex_safe(SPEED_DASH_ICON_TEX)

	# Primary category -> gun sprite (use player gun atlas region)
	var category := str(u.get("category", ""))
	if category == "primary":
		var atlas := _load_tex_safe(PRIMARY_GUN_ICON_TEX)
		if atlas:
			var at := AtlasTexture.new()
			at.atlas = atlas
			# region matches player.tscn region_rect = Rect2(8, 104, 16, 16)
			at.region = Rect2(8, 104, 16, 16)
			return at

	# HP/defensive
	if category == "general":
		if id.find("max_hp") >= 0 or id.find("damage_reduction") >= 0 or id == "max_hp_plus_1":
			return _load_tex_safe(HEART_ICON_TEX)

	# Fallback default
	return _load_tex_safe(DEFAULT_ICON_TEX)


func _get_icon_scale(u: Dictionary, tex: Texture2D) -> float:
	# Visual multipliers to normalize perceived size (tweakable)
	const SCALE_HEART := 1.0
	const SCALE_BULLET := 1.8
	const SCALE_PRIMARY := 2.0
	const SCALE_SPEED := 1.4
	const SCALE_INVIS := 1.4

	var id := str(u.get("id", ""))
	var category := str(u.get("category", ""))
	var uw := str(u.get("unlock_weapon", "")).strip_edges()
	var reqw := str(u.get("requires_weapon", "")).strip_edges()
	var weapon_key := uw if uw != "" else reqw

	# Heart / HP
	if category == "general" and (id.find("max_hp") >= 0 or id.find("damage_reduction") >= 0 or id == "max_hp_plus_1"):
		return SCALE_HEART

	# Weapon bullets
	if weapon_key != "":
		match weapon_key:
			"shotgun", "sniper", "shuriken", "turret":
				return SCALE_BULLET

	# Primary gun
	if category == "primary":
		return SCALE_PRIMARY

	# Speed / dash
	if id.find("move_speed") >= 0 or id.find("dash") >= 0 or str(u.get("unlock_ability", "")) == "dash" or str(u.get("requires_ability", "")) == "dash":
		return SCALE_SPEED

	# Invis
	if id.find("invis") >= 0 or str(u.get("unlock_ability", "")) == "invis" or str(u.get("requires_ability", "")) == "invis":
		return SCALE_INVIS

	# Default
	return 1.0


func _apply_icon(u: Dictionary) -> void:
	# One central place to decide which icon to show for an upgrade card.
	if icon_rect == null:
		push_warning("Icon node not found (expected VisualRoot/IconSlot/Icon)")
		return
	# Resolve texture via helper that centralizes mapping rules
	var tex := _get_icon_texture(u)
	var id := str(u.get("id", ""))
	var category := str(u.get("category", ""))
	if tex:
		icon_rect.texture = tex
		# enforce nearest filter + layout rules
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# visual normalization scale
		var mult := _get_icon_scale(u, tex)
		icon_rect.scale = Vector2(mult, mult)
		icon_rect.visible = true
		icon = tex
		return

	# nothing resolved: clear and print once
	icon = null
	icon_rect.texture = null
	icon_rect.visible = false
	if not _icon_missing_reported.has(id):
		print("[ICON] missing icon for id=", id)
		_icon_missing_reported[id] = true

func set_rarity(new_rarity: UpgradesDB.Rarity) -> void:
	rarity = new_rarity
	_apply_rarity_visuals()

func _update_price_color():
	if not price_label:
		return
	# If a flash is active, don't override the color
	if price_label.has_meta("price_flash_active") and price_label.get_meta("price_flash_active"):
		return
	# Determine ownership / caps
	var owned := false
	var stackable := true
	var maxed := false
	if upgrade_id != "":
		owned = GameState.has_upgrade(upgrade_id)
		var u := UpgradesDB.get_by_id(upgrade_id)
		if not u.is_empty():
			stackable = bool(u.get("stackable", true))
			if u.has("max_stack"):
				var purchases := int(GameState.upgrade_purchase_counts.get(upgrade_id, 0))
				maxed = purchases >= int(u.get("max_stack", 0))

	# If permanently owned/non-stackable or maxed, price label should be gray
	if (owned and not stackable) or maxed or (is_unlock_card and owned):
		price_label.modulate = Color(0.6, 0.6, 0.6, 1.0)
		return

	# Affordability: red if cannot afford, white otherwise
	if GameState.coins < price:
		price_label.modulate = Color(1.0, 0.2, 0.2, 1.0)
	else:
		price_label.modulate = Color(1.0, 1.0, 1.0, 1.0)

func _on_coins_changed():
	_update_price_color()


func refresh_state_from_gamestate() -> void:
	"""Update only the button/disabled/modulate state based on GameState ownership.
	Does not reset text, icon, or rarity visuals."""
	if upgrade_id == "":
		return

	var owned := GameState.has_upgrade(upgrade_id)
	var stackable := bool(UpgradesDB.get_by_id(upgrade_id).get("stackable", true))

	if is_unlock_card:
		# If this is an unlock card and owned, permanently grey and disable
		if owned:
			if buy_button:
				buy_button.disabled = true
			modulate = Color(0.6, 0.6, 0.6, 0.8)
			if desc_label and not desc_label.text.find("[Purchased]") >= 0:
				desc_label.text = desc_label.text + "\n[Purchased]"
			return
		else:
			# Not yet owned: ensure normal visuals
			if buy_button:
				buy_button.disabled = not (GameState.coins >= price)
			modulate = Color.WHITE
			return

	# Non-unlock cards: reflect ownership by disabling if non-stackable, but do not change modulate permanently
	if owned and not stackable:
		# Single-use epic upgrades should grey out like unlocks; other non-stackable remain white
		if rarity == UpgradesDB.Rarity.EPIC:
			if buy_button:
				buy_button.disabled = true
			modulate = Color(0.6, 0.6, 0.6, 0.8)
			if desc_label and not desc_label.text.find("[Purchased]") >= 0:
				desc_label.text = desc_label.text + "\n[Purchased]"
			return
		else:
			if buy_button:
				buy_button.disabled = true
			# keep visuals white for non-epic single-use items
			modulate = Color.WHITE
			if desc_label and not desc_label.text.find("[Purchased]") >= 0:
				desc_label.text = desc_label.text + "\n[Purchased]"
			return

	# Default: update affordability
	if buy_button:
		var affordable := GameState.coins >= price
		buy_button.disabled = not affordable
	# do not change modulate

	# Ensure price label reflects final computed state
	_update_price_color()
