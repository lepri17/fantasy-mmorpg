extends Node
## Plays the short sound effects. Anyone can ask for a sound with:
##   get_tree().call_group("sfx", "play", "hit")
## If this node is missing, the game simply stays silent.

const SOUNDS := {
	"swing": preload("res://assets/audio/swing.wav"),
	"hit": preload("res://assets/audio/hit.wav"),
	"hurt": preload("res://assets/audio/hurt.wav"),
	"coin": preload("res://assets/audio/coin.wav"),
	"potion": preload("res://assets/audio/potion.wav"),
	"skill": preload("res://assets/audio/skill.wav"),
	"levelup": preload("res://assets/audio/levelup.wav"),
	"defeat": preload("res://assets/audio/defeat.wav"),
}


func _ready() -> void:
	add_to_group("sfx")


func play(sound_name: String) -> void:
	if not SOUNDS.has(sound_name):
		return
	var player := AudioStreamPlayer.new()
	player.stream = SOUNDS[sound_name]
	player.bus = "Sounds"
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
