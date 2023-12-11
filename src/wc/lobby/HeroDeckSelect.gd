extends VBoxContainer

#onready var lobby = find_parent("Lobby")
#onready var playerName := $PlayerName
#onready var kick := $Kick

var my_owner = 0
var my_index= 0
onready var playerName := $PlayerName
onready var lobby = find_parent("TeamSelection")

func _ready():
	playerName.connect("item_selected", self, "_on_owner_changed")	
	_load_players()
	
func set_idx(idx):
	my_index = idx
	
func _load_players():
	var playerSelector:OptionButton = get_node("%PlayerName")
	var players:Dictionary = gameData.network_players
	for player in players:
		playerSelector.add_item(players[player].name, players[player].id)
	set_owner(0)
	if (not is_network_master()):
		playerSelector.set_disabled(true)
	
func set_owner (id):
	var playerSelector:OptionButton = get_node("%PlayerName")
	playerSelector.select(playerSelector.get_item_index(id))
	my_owner = id
	
func _on_owner_changed(id):
	if get_tree().is_network_server():
		lobby.owner_changed(id, my_index)

	
