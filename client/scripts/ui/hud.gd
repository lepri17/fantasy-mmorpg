extends CanvasLayer
## Connects the HUD widgets to the player. Only shows state, decides nothing.

@onready var _hp_bar = $HpBar


func _ready() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		push_warning("Hud: no node in group 'player'")
		return
	player.connect("hp_changed", Callable(_hp_bar, "set_values"))
	_hp_bar.set_values(player.get("hp"), player.get("max_hp"))
