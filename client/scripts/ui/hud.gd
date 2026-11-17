extends CanvasLayer
## Connects the HUD widgets to the player. Only shows state, decides nothing:
## requests from the inventory are passed on to the player.

const ACTION_INVENTORY := "inventory"
## The round touch buttons on the right (ATK, SPIN, POT) are in this group.
const ACTION_BUTTONS_GROUP := "action_buttons"
## Player methods the inventory may ask for.
const ITEM_ACTIONS := [
	"equip_from_bag", "unequip", "use_from_bag", "drop_from_bag", "drop_equipped"
]

var _player: Node = null

@onready var _panel = $PlayerPanel
@onready var _message: Label = $Message
@onready var _bag_button: Button = $BagButton
@onready var _inventory = $Inventory
@onready var _log = $MessageLog


func _ready() -> void:
	_message.hide()
	_style_bag_button()
	_bag_button.pressed.connect(toggle_inventory)
	_inventory.connect("close_requested", toggle_inventory)
	_inventory.connect("item_action", _on_item_action)
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		push_warning("Hud: no node in group 'player'")
		return
	_player.connect("hp_changed", Callable(_panel, "set_hp"))
	_player.connect("stamina_changed", Callable(_panel, "set_stamina"))
	_player.connect("stats_changed", _refresh_progress)
	_player.connect("died", _on_player_died)
	_player.connect("respawned", _message.hide)
	_player.connect("message", Callable(_log, "add_message"))
	_panel.set_hp(_player.get("hp"), _player.get("max_hp"))
	_panel.set_stamina(_player.get("stamina"), _player.get("max_stamina"))
	_refresh_progress()


## Read in the physics step, the same way the player reads its actions.
func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed(ACTION_INVENTORY):
		toggle_inventory()
	if _player != null:
		_update_action_buttons()


## Opens or closes the inventory. While it is open the round action buttons
## are hidden, because the panel covers them.
func toggle_inventory() -> void:
	_inventory.visible = not _inventory.visible
	if _inventory.visible and _player != null:
		_inventory.refresh(_player.get("stats"), _player.get("look_texture"))
	get_tree().call_group(ACTION_BUTTONS_GROUP, "set_visible", not _inventory.visible)


func _on_item_action(method: String, argument: Variant) -> void:
	if _player != null and method in ITEM_ACTIONS:
		_player.call(method, argument)


## POT shows how many potions are left. Skill buttons show their cooldown, fade
## when they would do nothing, and show the level that unlocks them ("Lv3").
func _update_action_buttons() -> void:
	var stats = _player.get("stats")
	for button in get_tree().get_nodes_in_group(ACTION_BUTTONS_GROUP):
		var action: String = button.get("action")
		if action == "use_potion":
			button.set("badge", str(stats.potions))
			button.set("dimmed", stats.potions == 0)
			continue
		button.set("cooldown", _player.call("cooldown_left", action))
		var skill_id: String = _player.call("skill_for_action", action)
		if skill_id == "":
			continue
		var unlocked: bool = _player.call("skill_unlocked", skill_id)
		var unlock_level: int = int(_player.call("skills_data")[skill_id]["unlock_level"])
		button.set("badge", "" if unlocked else "Lv%d" % unlock_level)
		button.set("dimmed", not _player.call("can_use", skill_id))


func _refresh_progress() -> void:
	var stats = _player.get("stats")
	_panel.set_progress(stats.level, stats.xp, stats.xp_to_next(), stats.gold, stats.potions)
	if _inventory.visible:
		_inventory.refresh(stats, _player.get("look_texture"))


func _style_bag_button() -> void:
	for state in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.1, 0.06, 0.1, 0.55 if state == "normal" else 0.8)
		box.border_color = Color(0.85, 0.68, 0.32)
		box.set_border_width_all(2)
		box.set_corner_radius_all(18)
		box.set_content_margin_all(8)
		_bag_button.add_theme_stylebox_override(state, box)


func _on_player_died() -> void:
	_message.text = "Defeated..."
	_message.show()
