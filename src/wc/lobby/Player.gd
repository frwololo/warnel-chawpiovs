extends HBoxContainer

signal option_changed()

onready var lobby = find_parent("Lobby")
onready var playerName := $PlayerName
onready var kick := $Kick

func get_options():
	var opt = {}
	opt.PlayerName = playerName.text
	return opt

# Send all options to remote peer_id
# of this person and can only be called by its network_master
func set_options_on(peer_id):
	playerName.rset_id(peer_id, "text", playerName.text)

func set_playerName(val):
	playerName.set_text(str(val))

func _on_option_changed(value):
	playerName.rset("text", value)
	lobby.set_my_info({name =  value})
	emit_signal("option_changed")

func _ready():
	# Set-up remote options for other peers in the room so when a choice is made 
	# it is reflected globally for every peer in that room
	#var rpc_mode = MultiplayerAPI.RPC_MODE_REMOTE
	#playerName.rset_config("text", rpc_mode)
	
	playerName.connect("text_entered", self, "_on_option_changed")
	playerName.connect("text_changed", self, "_on_option_changed")
