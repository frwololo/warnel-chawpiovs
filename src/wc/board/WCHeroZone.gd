# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED

class_name WCHeroZone
extends VBoxContainer

#TODO deprecate this class and move this either to HeroDeckData or to the Board
var hero_deck_data: HeroDeckData
var identity_card = null

var my_id = 0 setget set_player, get_player

# a temporary variable to move cards after all clients have loaded them,
# to avoid scripts triggering incorrectly
var _post_load_move:= {}
var _cards_loaded:= {}

var post_move_modifiers:= {}

func _process (delta:float):
	for card in post_move_modifiers.keys():
		if card.is_animating():
			continue
			
		var modifiers = post_move_modifiers[card]
		var callback_function = modifiers.get("callback", "")
		var callback_params = modifiers.get("callback_params", {})
		modifiers.erase("callback")
		modifiers.erase("callback_params")
		card.import_modifiers(modifiers)
		post_move_modifiers.erase(card)
		if callback_function:
			card.call(callback_function, callback_params)
		
	#exhausted status sometimes doesn't catch up	
	if identity_card and is_instance_valid(identity_card): 
		if identity_card._is_exhausted and ( abs(identity_card.card_rotation) < 40): 	
			identity_card.set_card_rotation(90, false, false)
	else:
		identity_card = null		

#things to do after everything is properly loaded.
#This will trigger execute_scripts
#so all clients need to be loaded before calling this
func post_load_move():
	for card in _post_load_move:
		var data = _post_load_move[card]
		var pile_name = data.get("pile", "")
		var slot = data.get("slot", null)
		
		if (pile_name):
			card.move_to(cfc.NMAP[pile_name])
		if slot:
			card.move_to(cfc.NMAP.board, -1, slot)		
			card.set_is_faceup(true)
			var modifiers = data.get("modifiers", {})
			if modifiers:
				post_move_modifiers[card] = modifiers
				
#	for card in _post_load_move:				
#		card.interruptTweening()
#		card.reorganize_self()	
		
	_post_load_move = {} #reset		
	return			


remotesync func cards_preloaded():
	var client_id = cfc.get_rpc_sender_id() 	
	_cards_loaded[client_id] = true
	if _cards_loaded.size() == gameData.network_players.size():
		_cards_loaded = {} #reset just in case
		post_load_move()


# Called when the node enters the scene tree for the first time.
func _ready():
	if (not my_id):
		print_debug("WCHeroZone: error, called ready before id set")
		return	
	

func set_player(id:int):
	my_id = id

func load_starting_identity():
	hero_deck_data = gameData.get_team_member(my_id)["hero_data"]
	var hero_card_data = cfc.get_card_by_id(hero_deck_data.get_hero_id())
	var alter_ego_id = hero_card_data.get("back_card_code", "")
	if !alter_ego_id:
		#TODO error
		return
	var ckey = alter_ego_id
	load_nemesis_aside(hero_card_data)	
	load_identity (ckey)
	
func load_nemesis_aside(hero_card_data):
	#return	
	var hero_set = hero_card_data["card_set_code"]
	var nemesis_set = hero_set + "_nemesis"
	
	var nemesis_cards_data = cfc.cards_by_set.get(nemesis_set, [])
	if !nemesis_cards_data:
		cfc.LOG("nemesis data missing for "  + hero_set)
	for card_data in nemesis_cards_data:
		var quantity = card_data.get("quantity", 1)
		for _i in range (quantity):
			var card_key = card_data["_code"]
			 #0 sets owner to villain so that nemesis cards get discarded into villain pile
			var card = cfc.instance_card(card_key, 0)
			#moving the card forces a rescale
			cfc.NMAP["deck" + str(my_id)].add_child(card)
			card._determine_idle_state()
			_post_load_move[card] = {
				"pile": "set_aside"
			}

	
func load_identity(card_id, modifiers ={}):
	var card = gameData.retrieve_from_side_or_instance(card_id, my_id)
	
	#cfc.NMAP["deck" + str(my_id)].add_child(card)
	card._determine_idle_state()
	var grid: BoardPlacementGrid = cfc.NMAP.board.get_grid("identity" + str(my_id))
	var slot: BoardPlacementSlot
	if grid:
		slot = grid.get_slot(0)   # .find_available_slot()
		if slot:
			_post_load_move[card] = {
				"slot": slot,
				"modifiers": modifiers
			}
	if !grid or !slot:
		cfc.LOG("{error} grid/slot not found for " + card.canonical_name)
		
	set_identity_card(card)
	cfc._rpc(self,"cards_preloaded")
	return identity_card

func set_identity_card(card):
	identity_card = card
	#TODO I've had issues where moving the card out of the identity zone has caused objects to
	#disappear. Not sure what is happening
	identity_card.disable_dragging_from_board = true
	identity_card.disable_dragging_from_pile = true		

func reorganize():
	#identity_card.move_to(cfc.NMAP["hand" + str(my_id)])
	#identity_card.set_is_faceup(true)
#	var grid: BoardPlacementGrid = cfc.NMAP.board.get_grid("allies" + str(my_id))
#	var slot: BoardPlacementSlot
#	if grid:
#		slot = grid.get_slot(0)   # .find_available_slot()
#		if slot:
#			identity_card.move_to(cfc.NMAP.board, -1, slot)	
	pass

func get_player():
	return my_id

func get_identity_card():
	return identity_card
	
func is_hero_form() -> bool:
	var hero_card = get_identity_card()
	return hero_card.is_hero_form()
	
func is_alter_ego_form() -> bool:
	return !is_hero_form()		
