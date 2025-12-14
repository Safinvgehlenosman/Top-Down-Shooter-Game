extends Node

var total_kills:int = 0
var total_deaths:int = 0
var highest_level:int = 0

func _ready() -> void:
	load_from_disk()
	save_to_disk()

func load_from_disk() -> void:
	var path := "user://stats.json"
	if not FileAccess.file_exists(path):
		return

	var file := FileAccess.open(path, FileAccess.ModeFlags.READ)
	if file == null:
		return

	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	var data: Dictionary = parsed

	total_kills = int(data.get("total_kills", total_kills))
	total_deaths = int(data.get("total_deaths", total_deaths))
	highest_level = int(data.get("highest_level", highest_level))


func save_to_disk() -> void:
	var path := "user://stats.json"
	var file := FileAccess.open(path, FileAccess.ModeFlags.WRITE)
	if file == null:
		return

	var data := {
		"total_kills": total_kills,
		"total_deaths": total_deaths,
		"highest_level": highest_level
	}

	var text: String = JSON.stringify(data)
	file.store_string(text)
	file.close()

# Time tracking removed — only persistent counters remain
