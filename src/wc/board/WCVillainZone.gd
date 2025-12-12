extends Node2D


# Declare member variables here. Examples:
# var a = 2
# var b = "text"

var scenario_data: ScenarioDeckData
var villain = null

# a temporary variable to move cards after all clients have loaded them,
# to avoid scripts triggering incorrectly
var _post_load_move:= {}
var _cards_loaded:= {}

#things to do after everything is properly loaded.
#This will trigger execute_scripts
#so all clients need to be loaded before calling this
func post_load_move(details):
	for card in _post_load_move:
		var data = _post_load_move[card]
		var pile_name = data.get("pile", "")
		var slot = data.get("slot", null)
		
		if (pile_name):
			card.move_to(cfc.NMAP[pile_name])
		if slot:
			card.move_to(cfc.NMAP.board, -1, slot)		
			card.set_is_faceup(true)
		
	
				
#	for card in _post_load_move:				
#		#card.interruptTweening()
#		card.reorganize_self()	
	_post_load_move = {} #reset
	if details.get("shuffle", false):		
		shuffle_deck()	
	
	return			


remotesync func cards_preloaded(details):
	var client_id = get_tree().get_rpc_sender_id() 	
	_cards_loaded[client_id] = true
	if _cards_loaded.size() == gameData.network_players.size():
		_cards_loaded = {} #reset just in case
		post_load_move(details)

# Called when the node enters the scene tree for the first time.
func _ready():
	scenario_data = gameData.scenario

	
	pass # Replace with function body.


func get_all_cards():
	#todo
	var cardsArray := []
	for obj in get_children():
		if obj as Card: cardsArray.append(obj)	
	return(cardsArray)	

func load_scenario():
	# DONE in ScenarioDeckData.gd
	# select the villain
	# set all villain cards aside, and based on difficulty, put one of them in play
	# find all "main scheme" cards that belong to that villain and set them aside
	# retrieve the setup instructions for the first main scheme
	# Create encounter deck, add hero obligations
		# remaining villain cards
		# encounter sets
		# suggested modular
	
	#Create Draw Pile from encounter deck
	var card_array = []
	var encounter_deck_data = scenario_data.encounter_deck
	for card_data in encounter_deck_data:
			var quantity = card_data.get("quantity", 1)
			#cards.append(ckey)
			for _i in range (quantity):
				var ckey = card_data["_code"]
				card_array.append(cfc.instance_card(ckey, 0))

	for card in card_array:
		cfc.NMAP["deck_villain"].add_child(card)
		#card.set_is_faceup(false,true)
		card._determine_idle_state()
	
	
	var villain_data = scenario_data.villains[0]
	var ckey = villain_data["_code"] 

	var scheme_data = scenario_data.schemes[0]
	var scheme_ckey = scheme_data["_code"] 
	load_scheme(scheme_ckey)		
	load_villain(ckey)


	
func load_villain(card_id, call_preloaded = {"shuffle" : true}):	
	var card = gameData.retrieve_from_side_or_instance(card_id, 0)
	card.set_is_faceup(true)	
	#TODO cleaner way to add the villain there?
	#cfc.NMAP["deck_villain"].add_child(card)
	var grid: BoardPlacementGrid = cfc.NMAP.board.get_grid("villain")
	var slot: BoardPlacementSlot
	if grid:
		slot = grid.find_available_slot()
		if slot:
			_post_load_move[card] = {
				"slot": slot
			}
		else:
			var _error = 1
	villain = card
	if call_preloaded:
		rpc("cards_preloaded", call_preloaded)
	return villain
	

func load_scheme(card_id, call_preloaded = {}):	
	# Put first main scheme in play --> this should trigger its "put in play" abilitiies
	# TODO how to "flip" a card...
	var card = gameData.retrieve_from_side_or_instance(card_id, 0)
	card.set_is_faceup(true)
	#card.set_is_faceup(true)	
	#TODO cleaner way to add the villain there?
	if !card.get_parent():
		cfc.NMAP["deck_villain"].add_child(card)
	card._determine_idle_state()
	
	
	var grid: BoardPlacementGrid = cfc.NMAP.board.get_grid("schemes")
	var slot: BoardPlacementSlot
	if grid:
		slot = grid.find_available_slot()
		if slot:
			_post_load_move[card] = {
				"slot": slot,
			}
	if call_preloaded:
		rpc("cards_preloaded", call_preloaded)		
	return card	
	pass


func shuffle_deck() -> void:
	var pile = cfc.NMAP["deck_villain"]
	while pile.are_cards_still_animating():
		yield(pile.get_tree().create_timer(0.2), "timeout")
	pile.shuffle_cards()

func get_villain():
	return villain
		
