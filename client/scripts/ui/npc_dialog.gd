extends PanelContainer
## What a townsperson says, with a button for each thing they offer
## (npcs.json "services"): the shop, healing, storage, travel, and quest
## rows the HUD adds. A choice is a request the HUD carries out.

signal close_requested
signal request(method: String, argument: Variant)

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const GameData := preload("res://scripts/data/game_data.gd")
const OPTION := Color(0.32, 0.22, 0.42)

var npc_id: String = ""
var _name_label: Label
var _text_label: Label
var _options: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UiStyle.frame_style())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_name_label = UiStyle.label("", 22, UiStyle.GOLD_TEXT)
	column.add_child(_name_label)
	_text_label = UiStyle.label("", 17, Color.WHITE)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.custom_minimum_size = Vector2(600, 0)
	column.add_child(_text_label)
	_options = VBoxContainer.new()
	_options.add_theme_constant_override("separation", 6)
	column.add_child(_options)
	add_child(column)


## Shows a townsperson. extra: [text, method, argument] rows to add (quests);
## text replaces the greeting; with_services false shows only extra and Goodbye.
func open(id: String, extra: Array = [], text: String = "", with_services: bool = true) -> void:
	npc_id = id
	var data: Dictionary = GameData.table("npcs")[id]
	_name_label.text = "%s, %s" % [data["name"], data["title"]]
	_text_label.text = text if text != "" else data["greeting"]
	for child in _options.get_children():
		_options.remove_child(child)
		child.queue_free()
	for service in data["services"] if with_services else []:
		match service:
			"shop":
				_add_option("Buy and sell", "open_shop", id)
			"heal":
				_add_option("Heal me", "heal_at_npc", null)
			"storage":
				_add_option("Open my storage", "open_storage", null)
			"teleport":
				_add_travel_options()
			"wish":
				var cost: int = int(data["wish"]["cost"])
				_add_option("Toss in %d gold and make a wish" % cost, "make_wish", id)
	for row in extra:
		_add_option(row[0], row[1], row[2])
	_add_option("Goodbye", "close", null)


## The buttons shown now, by their text (for tests and the keyboard).
func option(text: String) -> Button:
	for button in _options.get_children():
		if button.text.begins_with(text):
			return button
	return null


func _add_travel_options() -> void:
	var maps: Dictionary = GameData.table("maps")
	var here: String = maps["town"]
	var game = get_tree().get_first_node_in_group("game")
	if game != null and game.map != null:
		here = game.map.map_id  # a guide in any town sends you anywhere but here
	for map_id in maps["maps"]:
		if map_id == here or maps["maps"][map_id].get("no_teleport", false):
			continue
		var cost: int = int(maps["maps"][map_id].get("teleport_price", 0))
		var fare: String = "free" if cost == 0 else "%d G" % cost
		_add_option("Go to %s (%s)" % [maps["maps"][map_id]["name"], fare], "travel", map_id)


func _add_option(text: String, method: String, argument: Variant) -> void:
	var button := UiStyle.button(text, OPTION, Vector2(0, 44))
	button.pressed.connect(_choose.bind(method, argument))
	_options.add_child(button)


func _choose(method: String, argument: Variant) -> void:
	if method == "close":
		close_requested.emit()
	else:
		request.emit(method, argument)
