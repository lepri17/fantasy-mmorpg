extends CanvasLayer
## Connects the HUD widgets to the player. Only shows state, decides nothing.

var _player: Node = null

@onready var _panel = $PlayerPanel
@onready var _message: Label = $Message


func _ready() -> void:
	_message.hide()
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		push_warning("Hud: no node in group 'player'")
		return
	_player.connect("hp_changed", Callable(_panel, "set_hp"))
	_player.connect("stamina_changed", Callable(_panel, "set_stamina"))
	_player.connect("stats_changed", _refresh_progress)
	_player.connect("died", _on_player_died)
	_player.connect("respawned", _message.hide)
	_panel.set_hp(_player.get("hp"), _player.get("max_hp"))
	_panel.set_stamina(_player.get("stamina"), _player.get("max_stamina"))
	_refresh_progress()


func _refresh_progress() -> void:
	var stats = _player.get("stats")
	_panel.set_progress(stats.level, stats.xp, stats.xp_to_next(), stats.gold, stats.potions)


func _on_player_died() -> void:
	_message.text = "Defeated..."
	_message.show()
