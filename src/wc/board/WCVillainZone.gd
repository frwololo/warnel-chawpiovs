extends Node2D


# Declare member variables here. Examples:
# var a = 2
# var b = "text"

var scenario_data: ScenarioDeckData

# Called when the node enters the scene tree for the first time.
func _ready():
	scenario_data = gameData.scenario
	
	#TODO Not sure why this is needed since the values are hardcoded in the editor, but somehow it doesn't work
	$ControlDiscard/discard_villain.set_pile_name("discard_villain")
	$ControlDiscard/discard_villain.name = "discard_villain"
	$ControlDeck/deck_villain.set_pile_name("deck_villain")
	$ControlDeck/deck_villain.name = "deck_villain"
	
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
			card_array.append(cfc.instance_card(ckey))

	for card in card_array:
		cfc.NMAP["deck_villain"].add_child(card)
		#card.set_is_faceup(false,true)
		card._determine_idle_state()
		
	var villain_data = scenario_data.villains[0]
	var ckey = villain_data["Name"] #TODO we have name and "Name" which is a problem here...
	var card = cfc.instance_card(ckey)
	card.set_is_faceup(true)
	
	#TODO cleaner way to add the villain there?
	cfc.NMAP["deck_villain"].add_child(card)
	var grid: BoardPlacementGrid = cfc.NMAP.board.get_grid("villain")
	var slot: BoardPlacementSlot
	if grid:
		slot = grid.find_available_slot()
		if slot:
			card.move_to(cfc.NMAP.board, -1, slot)	
	
	
	#TODO next	
	# Put first main scheme in play --> this should trigger its "put in play" abilitiies
	# TODO how to "flip" a card...
	pass
