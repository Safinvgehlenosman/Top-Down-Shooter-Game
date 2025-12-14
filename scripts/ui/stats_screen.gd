extends CanvasLayer

@onready var back_button: Button = get_node_or_null("BackButton") as Button
@onready var highest_label: Label = get_node_or_null("Stats/HighestLevel") as Label
@onready var total_kills_label: Label = get_node_or_null("Stats/TotalKills") as Label
@onready var total_deaths_label: Label = get_node_or_null("Stats/TotalDeaths") as Label

func _resolve_fallback_labels() -> void:
	if highest_label and total_kills_label and total_deaths_label:
		return

	var vbox := get_node_or_null("VBoxContainer")
	if vbox and vbox.get_child_count() >= 3:
		if highest_label == null:
			highest_label = vbox.get_child(0) as Label
		if total_kills_label == null:
			total_kills_label = vbox.get_child(1) as Label
		if total_deaths_label == null:
			total_deaths_label = vbox.get_child(2) as Label

func _ready() -> void:
	if back_button:
		back_button.pressed.connect(_on_back_pressed)

	visibility_changed.connect(_on_visibility_changed)

	_resolve_fallback_labels()
	refresh()

func _on_visibility_changed() -> void:
	if visible:
		refresh()


func refresh() -> void:
	_resolve_fallback_labels()

	if highest_label:
		highest_label.text = "Highest Level: %d" % Stats.highest_level
	if total_kills_label:
		total_kills_label.text = "Total Kills: %d" % Stats.total_kills
	if total_deaths_label:
		total_deaths_label.text = "Total Deaths: %d" % Stats.total_deaths

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/start_screen.tscn")
