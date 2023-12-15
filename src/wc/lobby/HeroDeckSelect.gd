extends VBoxContainer

#onready var lobby = find_parent("Lobby")
#onready var playerName := $PlayerName
#onready var kick := $Kick

var my_owner = 0
var my_index = 0
var hero_id = 0
var deck_id = 0

#
#shortcuts
# 
onready var playerName := $PlayerName
onready var deckSelect := $DeckSelect
onready var lobby = find_parent("TeamSelection")

func _ready():
	playerName.connect("item_selected", self, "_on_owner_changed")
	deckSelect.connect("item_selected", self, "_on_deck_changed")	
	_load_players()
	
func set_idx(idx):
	my_index = idx
	
func _load_players():
	var playerSelector:OptionButton = get_node("%PlayerName")
	var players:Dictionary = gameData.network_players
	for player in players:
		playerSelector.add_item(players[player].name, players[player].id)
	set_owner(0)
	if (not cfc.is_game_master()):
		playerSelector.set_disabled(true)
	if (players.size() < 2):
		playerSelector.hide()

func _toggle_gui():
	var my_owner_network_id = gameData.get_player_by_index(my_owner).network_id
	if (get_tree().get_network_unique_id() == my_owner_network_id) :
		deckSelect.set_disabled(false)
	else:
		deckSelect.set_disabled(true)	
	
func set_owner (id):
	var playerSelector:OptionButton = get_node("%PlayerName")
	playerSelector.select(playerSelector.get_item_index(id))
	my_owner = id
	_toggle_gui()
		
func _on_deck_changed(index):
	var my_owner_network_id = gameData.get_player_by_index(my_owner).network_id
	if (get_tree().get_network_unique_id() == my_owner_network_id) :
		var _deck_id = deckSelect.get_item_id(index)
		lobby.deck_changed(_deck_id, my_index)

func set_deck (_deck_id):
	var deckSelector:OptionButton = get_node("%DeckSelect")
	var index = deckSelector.get_item_index(_deck_id)
	deckSelector.select(index)
	deck_id = _deck_id
	
func _on_owner_changed(id):
	if get_tree().is_network_server():
		my_owner = id
		_toggle_gui()
		lobby.owner_changed(id, my_index)

func load_hero(_hero_id):
	hero_id = _hero_id

	var hero_picture: TextureRect = get_node("%HeroPicture")
	var deck_select: OptionButton = get_node("%DeckSelect")
	deck_select.clear()
	
	var img = 0
	var decks = 0
	if (hero_id):
		img = cfc.get_hero_portrait(hero_id)
		decks = cfc.idx_hero_to_deck_ids[hero_id]
	if (img and decks):
		var imgtex = ImageTexture.new()
		imgtex.create_from_image(img)	
		hero_picture.texture = imgtex
		hero_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		for deck_id in decks:
			var deck_data = cfc.deck_definitions[deck_id]
			var hero_name = cfc.idx_card_id_to_name[hero_id]
			var deck_name: String = deck_data.name
			deck_name = deck_name.replacen(hero_name, "").trim_prefix(" ")
			deck_name = deck_name.trim_prefix("- ")
			deck_select.add_item(deck_name, deck_data.id)
		#force refresh of selected data	
		_on_deck_changed(deckSelect.selected)		
	else:
		hero_picture.texture = null	


func _on_HeroDeckSelect_gui_input(event):
	if event is InputEventMouseButton: #TODO better way to handle Tablets and consoles
		if event.button_index == BUTTON_LEFT and event.pressed:
			#Tell the server I want this hero
			lobby.request_release_hero_slot(hero_id)
