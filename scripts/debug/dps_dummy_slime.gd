extends CharacterBody2D

const DPS_WINDOW := 2.0  # Calculate DPS over last 2 seconds

@onready var health_component: Node = $Health
@onready var dps_label: Label = $Label

var damage_events: Array = []  # Array of {amount: float, time: float}
var current_dps: float = 0.0
var print_timer: float = 0.0  # Timer for periodic DPS prints


func _ready() -> void:
	# Add to enemy group so bullets can hit us
	add_to_group("enemy")
	
	# Set up health component with very high HP
	if health_component:
		health_component.max_health = 999999
		health_component.health = 999999
		health_component.use_gamestate = false
		health_component.invincible_time = 0.0
		
		# Disable damage number spawning for the dummy
		health_component.set_meta("skip_damage_numbers", true)
		
		# Connect to damage signal
		health_component.damaged.connect(_on_damaged)
		health_component.died.connect(_on_died)
	
	# Initialize label
	if dps_label:
		dps_label.text = "DPS: 0"


func take_damage(amount: int) -> void:
	"""Called by bullets when they hit - forward to HealthComponent"""
	if health_component and health_component.has_method("take_damage"):
		health_component.take_damage(amount)


func _process(delta: float) -> void:
	var current_time := Time.get_ticks_msec() / 1000.0
	
	# Remove events older than DPS_WINDOW
	damage_events = damage_events.filter(func(event): return current_time - event.time < DPS_WINDOW)
	
	# Calculate total damage in window
	var total_damage := 0.0
	for event in damage_events:
		total_damage += event.amount
	
	# Calculate DPS
	if damage_events.size() > 0:
		current_dps = total_damage / DPS_WINDOW
	else:
		current_dps = 0.0
	
	# Update label
	if dps_label:
		dps_label.text = "DPS: %d" % int(current_dps)
	
	# Print stats every second
	print_timer += delta
	if print_timer >= 1.0:
		print_timer = 0.0
		var gm = get_tree().get_first_node_in_group("game_manager")
		var level = gm.current_level if gm else 0
		print("[DPS STATS] Level %d | DPS=%.1f" % [level, current_dps])


func _on_damaged(amount: int) -> void:
	var current_time := Time.get_ticks_msec() / 1000.0
	
	# Add damage event
	damage_events.append({
		"amount": float(amount),
		"time": current_time
	})
	
	# Restore health to prevent death
	if health_component:
		health_component.health = health_component.max_health


func _on_died() -> void:
	# Prevent death - immediately restore HP
	if health_component:
		health_component.health = health_component.max_health
		health_component.is_dead = false
