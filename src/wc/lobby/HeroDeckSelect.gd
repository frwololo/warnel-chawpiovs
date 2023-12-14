extends VBoxContainer

#onready var lobby = find_parent("Lobby")
#onready var playerName := $PlayerName
#onready var kick := $Kick

var my_owner = 0
var my_index = 0
var hero_id = 0

#
#shortcuts
# 
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

func load_hero(_hero_id):
	hero_id = _hero_id

	var hero_picture: TextureRect = get_node("%HeroPicture")
	var img = 0
	if (hero_id):
		img = cfc.get_hero_portrait(hero_id)
	if (img):
		var imgtex = ImageTexture.new()
		imgtex.create_from_image(img)	
		hero_picture.texture = imgtex
		hero_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	else:
		hero_picture.texture = null	


func _on_HeroDeckSelect_gui_input(event):
	if event is InputEventMouseButton: #TODO better way to handle Tablets and consoles
		if event.button_index == BUTTON_LEFT and event.pressed:
			#Tell the server I want this hero
			lobby.request_release_hero_slot(hero_id)
