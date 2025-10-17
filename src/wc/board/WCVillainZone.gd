extends Node2D


# Declare member variables here. Examples:
# var a = 2
# var b = "text"

var scenario_data: ScenarioDeckData
var villain = null

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
			#cards.append(ckey)
			var ckey = card_data["name"]
			card_array.append(cfc.instance_card(ckey, 0))

	for card in card_array:
		cfc.NMAP["deck_villain"].add_child(card)
		#card.set_is_faceup(false,true)
		card._determine_idle_state()
	
	
	var villain_data = scenario_data.villains[0]
	var ckey = villain_data["Name"] #TODO we have name and "Name" which is a problem here...
		
	load_villain(ckey)
	load_scheme()
	shuffle_deck()
	
func load_villain(card_name):	
	var card = cfc.instance_card(card_name, 0)
	card.set_is_faceup(true)	
	#TODO cleaner way to add the villain there?
	cfc.NMAP["deck_villain"].add_child(card)
	var grid: BoardPlacementGrid = cfc.NMAP.board.get_grid("villain")
	var slot: BoardPlacementSlot
	if grid:
		slot = grid.find_available_slot()
		if slot:
			card.move_to(cfc.NMAP.board, -1, slot)
	villain = card
	return villain
	

func load_scheme():	
	# Put first main scheme in play --> this should trigger its "put in play" abilitiies
	# TODO how to "flip" a card...
	var scheme_data = scenario_data.schemes[0]
	var ckey = scheme_data["Name"] #TODO we have name and "Name" which is a problem here...
	var card = cfc.instance_card(ckey, 0)
	#card.set_is_faceup(true)	
	#TODO cleaner way to add the villain there?
	cfc.NMAP["deck_villain"].add_child(card)
	var grid: BoardPlacementGrid = cfc.NMAP.board.get_grid("schemes")
	var slot: BoardPlacementSlot
	if grid:
		slot = grid.find_available_slot()
		if slot:
			card.move_to(cfc.NMAP.board, -1, slot)		
	pass


func shuffle_deck() -> void:
	var pile = cfc.NMAP["deck_villain"]
	while pile.are_cards_still_animating():
		yield(pile.get_tree().create_timer(0.2), "timeout")
	pile.shuffle_cards()

func get_villain():
	return villain
	
