# Code for a sample playspace, you're expected to provide your own ;)
extends Board

var heroZone = preload("res://src/wc/board/WCHeroZone.tscn")
var basicGrid = preload("res://src/wc/grids/BasicGrid.tscn")
var basicPile = preload("res://src/multiplayer/PileMulti.tscn")

onready var villain := $VillainZone
onready var options_menu = $OptionsMenu

var heroZones: Dictionary = {}

const GRID_SETUP = CFConst.GRID_SETUP
const HERO_GRID_SETUP = CFConst.HERO_GRID_SETUP

func _init():
	init_hero_zones()
	
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	cfc.map_node(self)	
	counters = $Counters
	# We use the below while to wait until all the nodes we need have been mapped
	# "hand" should be one of them.
	# We're assigning our positions programmatically,
	# instead of defining them on the scene.
	# This way any they will work with any size of viewport in a game.
	# Discard pile goes bottom right
	$FancyMovementToggle.pressed = cfc.game_settings.fancy_movement
	$OvalHandToggle.pressed = cfc.game_settings.hand_use_oval_shape
	$ScalingFocusOptions.selected = cfc.game_settings.focus_style
	$Debug.pressed = cfc._debug
	# Fill up the deck for demo purposes
	if not cfc.ut:
		cfc.game_rng_seed = CFUtils.generate_random_seed()
		$SeedLabel.text = "Game Seed is: " + cfc.game_rng_seed

	# warning-ignore:return_value_discarded
	#$DeckBuilderPopup.connect('popup_hide', self, '_on_DeckBuilder_hide')	
	
	
	for grid_name in GRID_SETUP.keys():

		var grid_info = GRID_SETUP[grid_name]
		if "pile" == grid_info.get("type", ""):
			var scene = grid_info.get("scene", basicPile)
			var pile: Pile = scene.instance()
			pile.add_to_group("piles")
			pile.name = grid_name
			pile.set_pile_name(grid_name)
			pile.set_position(Vector2(grid_info["x"], grid_info["y"]))
			pile.set_global_position(Vector2(grid_info["x"], grid_info["y"]))
			pile.scale = Vector2(0.5, 0.5)
			pile.faceup_cards = false
			add_child(pile)
		else:
			var grid_scene = grid_info.get("scene", basicGrid)
			var grid: BoardPlacementGrid = grid_scene.instance()
			grid.add_to_group("placement_grid")
			# A small delay to allow the instance to be added
			add_child(grid)
			grid.name = grid_name
			grid.name_label.text = grid_name
			grid.rect_position = Vector2(grid_info["x"], grid_info["y"])
			grid.auto_extend = true

	for i in range(gameData.get_team_size()):
		var hero_id = i+1
		var scale = 1
		var start_x = 500
		var start_y = 200
		
		if (hero_id > 1):
			scale = 0.3
			start_x = 0
			start_y = 200 + (hero_id * 200)
			
		for grid_name in HERO_GRID_SETUP.keys():
			var grid_info = HERO_GRID_SETUP[grid_name]
			var x = start_x + grid_info["x"]*scale
			var y = start_y + grid_info["y"]*scale	
			var real_grid_name = grid_name + str(hero_id)		
			if "pile" == grid_info.get("type", ""):
				var scene = grid_info.get("scene", basicPile)
				var pile: Pile = scene.instance()
				pile.add_to_group("piles")
				pile.name = real_grid_name
				pile.set_pile_name(real_grid_name)
				pile.set_position(Vector2(x,y))
				pile.set_global_position(Vector2(x,y))
				pile.scale = Vector2(0.5*scale, 0.5*scale)
				pile.faceup_cards = grid_info.get("faceup", false)
				add_child(pile)
			else:
				var grid_scene = grid_info.get("scene", basicGrid)
				var grid: BoardPlacementGrid = grid_scene.instance()
				grid.add_to_group("placement_grid")
				# Need to rescale before adding ???
				grid.rescale(CFConst.PLAY_AREA_SCALE * scale)
				add_child(grid)
				grid.name = real_grid_name
				grid.name_label.text = real_grid_name
				grid.rect_position = Vector2(x,y)
				grid.auto_extend = true

	#Game setup - Todo move somewhere else ?
	load_cards()

	#Signals
	scripting_bus.connect("current_playing_hero_changed", self, "_current_playing_hero_changed")

	
	gameData.assign_starting_hero()
	load_heroes()
	shuffle_decks()
	#Need to wait after shuffling decks
	for i in range(gameData.get_team_size()):
		var pile = cfc.NMAP["deck" + str(i+1)]	
		while pile.is_shuffling:
			yield(get_tree().create_timer(0.05), "timeout")		
	
	villain.load_scenario()

	
	draw_starting_hand()
	offer_to_mulligan()
	
	#Tests
	draw_cheat("Combat Training")
	draw_cheat("Mockingbird")
	draw_cheat("Backflip")
	#draw_cheat("Helicarrier")	
	draw_cheat("Swinging Web Kick")
	cfc.LOG_DICT(guidMaster.guid_to_object)
	
	#Save gamedata for restart
	gameData.save_gamedata_to_file("user://Saves/_restart.json")	
	

func load_heroes():
	var hero_count: int = gameData.get_team_size()
	for i in range (hero_count): 
		heroZones[i+1].load_hero()
		

func init_hero_zones():
	var hero_count: int = gameData.get_team_size()
	for i in range (hero_count): 
		var new_hero_zone = heroZone.instance()
		add_child(new_hero_zone)
		new_hero_zone.set_player(i+1)
		new_hero_zone.rect_position = Vector2(500, 600) #TODO better than this
		heroZones[i+1] = new_hero_zone		

# Returns an array with all children nodes which are of Card class
func get_all_cards() -> Array:
	var cardsArray := []
	for obj in get_children():
		if obj as Card: cardsArray.append(obj)
	cardsArray += $VillainZone.get_all_cards()

	return(cardsArray)

func delete_all_cards():
	
	#delete everything on board and grids
	var cards:Array = get_all_cards()
	for obj in cards:
		remove_child(obj)
		obj.queue_free()
		
	#delete everything in hands	
	for i in range(gameData.get_team_size()):
		var hand:Hand = cfc.NMAP["hand" + str(i+1)]
		hand.delete_all_cards()
		
	#delete everything in other piles
	for grid_name in GRID_SETUP.keys():
		var grid_info = GRID_SETUP[grid_name]
		if "pile" == grid_info.get("type", ""):
			var pile:Pile = cfc.NMAP[grid_name]
			pile.delete_all_cards()
		else: #it's a grid
			var grid: BoardPlacementGrid = cfc.NMAP.board.get_grid(grid_name)
			grid.delete_all_slots()
			

	for i in range(gameData.get_team_size()):
		var hero_id = i+1
		for grid_name in HERO_GRID_SETUP.keys():
			var grid_info = HERO_GRID_SETUP[grid_name]
			var real_grid_name = grid_name + str(hero_id)		
			if "pile" == grid_info.get("type", ""):
				var pile:Pile = cfc.NMAP[real_grid_name]
				pile.delete_all_cards()
			else: #it's a grid
				var grid: BoardPlacementGrid = cfc.NMAP.board.get_grid(real_grid_name)
				grid.delete_all_slots()								

func _close_game():
	cfc.quit_game()
	get_tree().change_scene("res://src/wc/MainMenu.tscn")
	
func _retry_game(message:String):
	#TODO
	cfc.quit_game()
	get_tree().change_scene("res://src/wc/MainMenu.tscn")	

func end_game(result:String):
	cfc.set_game_paused(true)
	var end_dialog:AcceptDialog = AcceptDialog.new()
	end_dialog.window_title = result
	end_dialog.add_button ( "retry", true, "retry")
	end_dialog.connect("custom_action", self, "_retry_game")
	end_dialog.connect("confirmed", self, "_close_game")
	add_child(end_dialog)
	end_dialog.popup_centered()
	
	
# This function is to avoid relating the logic in the card objects
# to a node which might not be there in another game
# You can remove this function and the FancyMovementToggle button
# without issues
func _on_FancyMovementToggle_toggled(_button_pressed) -> void:
#	cfc.game_settings.fancy_movement = $FancyMovementToggle.pressed
	cfc.set_setting('fancy_movement', $FancyMovementToggle.pressed)


func _on_OvalHandToggle_toggled(_button_pressed: bool) -> void:
	cfc.set_setting("hand_use_oval_shape", $OvalHandToggle.pressed)
	for c in cfc.NMAP.hand1.get_all_cards(): #TODO fix? Or delete
		c.reorganize_self()


# Reshuffles all Card objects created back into the deck
func _on_ReshuffleAllDeck_pressed() -> void:
	reshuffle_all_in_pile(cfc.NMAP.deck)


func _on_ReshuffleAllDiscard_pressed() -> void:
	reshuffle_all_in_pile(cfc.NMAP.discard)

func reshuffle_all_in_pile(pile = cfc.NMAP.deck):
	for c in get_tree().get_nodes_in_group("cards"):
		if c.get_parent() != pile and c.state != Card.CardState.DECKBUILDER_GRID:
			c.move_to(pile)
			yield(get_tree().create_timer(0.1), "timeout")
	# Last card in, is the top card of the pile
	var last_card : Card = pile.get_top_card()
	if last_card._tween.is_active():
		yield(last_card._tween, "tween_all_completed")
	yield(get_tree().create_timer(0.2), "timeout")
	pile.shuffle_cards()


# Button to change focus mode
func _on_ScalingFocusOptions_item_selected(index) -> void:
	cfc.set_setting('focus_style', index)


# Button to make all cards act as attachments
func _on_EnableAttach_toggled(button_pressed: bool) -> void:
	for c in get_tree().get_nodes_in_group("cards"):
		if button_pressed:
			c.attachment_mode = Card.AttachmentMode.ATTACH_BEHIND
		else:
			c.attachment_mode = Card.AttachmentMode.DO_NOT_ATTACH


func _on_Debug_toggled(button_pressed: bool) -> void:
	cfc._debug = button_pressed

# Loads card decks
func load_cards() -> void:
	for i in range(gameData.get_team_size()):
		var hero_id = i+1
		var hero_deck_data: HeroDeckData = gameData.get_team_member(hero_id)["hero_data"] #TODO actually load my player's stuff
		var card_ids = hero_deck_data.get_deck_cards()
		
		var card_data:Array = []
		for card_id in card_ids:
			#cards.append(ckey)
			card_data.append({
				"card" : card_id,
				"owner_hero_id": hero_id
			})
		load_cards_to_pile(card_data, "deck" + str(hero_id))

	
func load_cards_to_pile(card_data:Array, pile_name):
	var card_array = []
	for card in card_data:
		var card_id:String = card["card"]
		var hero_id = card.get("owner_hero_id", 1)
		
		#card_id here is either a card id or a card name, we try to accomodate for both
		var card_name = cfc.idx_card_id_to_name.get(
			card_id, 
			cfc.lowercase_card_name_to_name.get(card_id.to_lower(), "")
		)
		var new_card:WCCard = cfc.instance_card(card_name, hero_id)
		card_array.append(new_card)

	for card in card_array:
		if (cfc.NMAP.has(pile_name)): #it's a pile
			cfc.NMAP[pile_name].add_child(card)
			card._determine_idle_state()
		else: #it's a grid
			#TODO cleaner way to add the card there?
			#card.set_is_faceup(true)	
			add_child(card)
			card._determine_idle_state()
			var grid: BoardPlacementGrid = cfc.NMAP.board.get_grid(pile_name)
			var slot: BoardPlacementSlot
			if grid:
				slot = grid.find_available_slot()
				if slot:
					card.move_to(cfc.NMAP.board, -1, slot)	

	for card in card_array:				
		#card.interruptTweening()
		card.reorganize_self()		
	return
			
func load_cards_to_grid(card_data:Array, grid_name):
	load_cards_to_pile(card_data, grid_name) #TODO probably doesn't work, need to check	
	return

func export_cards_to_json(pile_name, cards) -> Dictionary:
	var export_arr:Array = []
	for card in cards:
		var owner_hero_id = card.get_owner_hero_id()
		var card_id = card.properties.get("_code")
		export_arr.append({
			"card" : card_id,
			"owner_hero_id": owner_hero_id
		})
	var result:Dictionary = {pile_name : export_arr}	
	return result	

func export_pile_to_json(pile_name) -> Dictionary:
	var pile: CardContainer = cfc.NMAP[pile_name]
	var cards:Array = pile.get_all_cards()
	return export_cards_to_json(pile_name, cards)
	
func export_grid_to_json(grid_name) -> Dictionary:
	var grid:BoardPlacementGrid = cfc.NMAP.board.get_grid(grid_name)
	var cards:Array = grid.get_all_cards()	
	return export_cards_to_json(grid_name, cards)	
		
func shuffle_decks() -> void:
	for i in range(gameData.get_team_size()):
		var pile = cfc.NMAP["deck" + str(i+1)]
		while pile.are_cards_still_animating():
			yield(pile.get_tree().create_timer(0.2), "timeout")
		pile.shuffle_cards()
	
func draw_starting_hand() -> void:
	gameData.draw_all_players()


func draw_cheat(cardName : String) -> void:
	var card = cfc.instance_card(cardName, 1)
	var pile = cfc.NMAP["deck1"]
	pile.add_child(card)
	cfc.NMAP["hand1"].draw_card (pile)
	
func offer_to_mulligan() -> void:
	#TODO
	pass	
	
func are_cards_still_animating(check_everything:bool = true) -> bool:
	for c in get_all_cards():
		var tt : Tween = c._tween
		if tt.is_active():
			return(true)
	
	if (!check_everything):
		return false

	#check hands	
	for i in range(gameData.get_team_size()):
		var hand:Hand = cfc.NMAP["hand" + str(i+1)]
		if (hand.are_cards_still_animating()):
			return true
		
	#check other piles
	#Villain piles
	for grid_name in GRID_SETUP.keys():
		var grid_info = GRID_SETUP[grid_name]
		if "pile" == grid_info.get("type", ""):
			var pile:Pile = cfc.NMAP[grid_name]
			if (pile.are_cards_still_animating()):
				return true
	#hero piles		
	for i in range(gameData.get_team_size()):
		var hero_id = i+1
		for grid_name in HERO_GRID_SETUP.keys():
			var grid_info = HERO_GRID_SETUP[grid_name]
			var real_grid_name = grid_name + str(hero_id)		
			if "pile" == grid_info.get("type", ""):
				var pile:Pile = cfc.NMAP[real_grid_name]
				if (pile.are_cards_still_animating()):
					return true					
			
	return(false)				

func _on_DeckBuilder_pressed() -> void:
	cfc.game_paused = true
	$DeckBuilderPopup.popup_centered_minsize()

func _on_DeckBuilder_hide() -> void:
	cfc.game_paused = false


func _on_BackToMain_pressed() -> void:
	cfc.quit_game()
	get_tree().change_scene("res://src/wc/MainMenu.tscn")

func _current_playing_hero_changed (trigger_details: Dictionary = {}):
	var previous_hero_id = trigger_details["before"]
	var new_hero_id = trigger_details["after"]

	#TODO move to config
	#TODO convert to nice animation
	var scale_new = 1
	var scale_previous = 0.3	
			
	for grid_name in HERO_GRID_SETUP.keys():
		var previous_grid_name = grid_name + str(previous_hero_id)
		var new_grid_name = grid_name + str(new_hero_id)	
		var grid_info = HERO_GRID_SETUP[grid_name]


		if "pile" == grid_info.get("type", ""):
			var previous_pile: Pile = cfc.NMAP[previous_grid_name]
			var new_pile: Pile = cfc.NMAP[new_grid_name]
			var backup_position:Vector2 = previous_pile.global_position
			previous_pile.set_position(new_pile.global_position)
			previous_pile.set_global_position(new_pile.global_position)			
			previous_pile.scale = Vector2(0.5*scale_previous, 0.5*scale_previous)
			
			new_pile.set_position(backup_position)
			new_pile.set_global_position(backup_position)			
			new_pile.scale = Vector2(0.5*scale_new, 0.5*scale_new)			
		else:			
			var previous_grid: BoardPlacementGrid = cfc.NMAP.board.get_grid(previous_grid_name)
			var new_grid: BoardPlacementGrid = cfc.NMAP.board.get_grid(new_grid_name)
			var backup_position:Vector2 = previous_grid.rect_position
			
			previous_grid.rescale(CFConst.PLAY_AREA_SCALE * scale_previous)
			previous_grid.reposition(new_grid.rect_position)
				
			new_grid.rescale(CFConst.PLAY_AREA_SCALE * scale_new)
			new_grid.reposition(backup_position)			
	
	#exchange hands
	var old_hand: Hand = get_node("%Hand" + str(previous_hero_id))	
	old_hand.remove_from_group("bottom") #todo fix hack
	WCUtils.disable_and_hide_node(old_hand)
	old_hand.re_place()
	old_hand.position = Vector2(20000, 20000)
	var new_hand: Hand = get_node("%Hand" + str(new_hero_id))
	WCUtils.enable_and_show_node(new_hand)
	new_hand.re_place()


func savestate_to_json() -> Dictionary:	
	var json_data:Dictionary = {}
	for grid_name in GRID_SETUP.keys():
		var grid_info = GRID_SETUP[grid_name]
		if "pile" == grid_info.get("type", ""):
			json_data.merge(export_pile_to_json(grid_name))
		else:
			json_data.merge(export_grid_to_json(grid_name))

	for i in range(gameData.get_team_size()):
		var hero_id = i+1

		for grid_name in HERO_GRID_SETUP.keys():
			var grid_info = HERO_GRID_SETUP[grid_name]
			var real_grid_name = grid_name + str(hero_id)		
			if "pile" == grid_info.get("type", ""):
				json_data.merge(export_pile_to_json(real_grid_name))
			else:
				json_data.merge(export_grid_to_json(real_grid_name))
				
		#save hand	
		var hand_name = "hand" + str(hero_id)
		json_data.merge(export_pile_to_json(hand_name))	
		
	var result: Dictionary = {"board" : json_data}
	return result
	
func loadstate_from_json(json:Dictionary):
	var json_data = json.get("board", null)
	if (null == json_data):
		return #TODO Error msg

	delete_all_cards()
	
	#Load all grids with matching data
	for grid_name in GRID_SETUP.keys():
		var grid_info = GRID_SETUP[grid_name]
		var card_data = json_data.get(grid_name, [])
		if "pile" == grid_info.get("type", ""):
			load_cards_to_pile(card_data, grid_name)
		else:
			load_cards_to_grid(card_data, grid_name)

	for i in range(gameData.get_team_size()):
		var hero_id = i+1

		for grid_name in HERO_GRID_SETUP.keys():
			var grid_info = HERO_GRID_SETUP[grid_name]
			var real_grid_name = grid_name + str(hero_id)
			var card_data = json_data.get(real_grid_name, [])		
			if "pile" == grid_info.get("type", ""):
				load_cards_to_pile(card_data, real_grid_name)
			else:
				load_cards_to_grid(card_data, real_grid_name)

		#load everything in hands	
		var hand_name = "hand" + str(hero_id)
		var card_data = json_data.get(hand_name, [])
		load_cards_to_pile(card_data, hand_name)

	
	return
#The game engine doesn't really have a concept of double sided cards, so instead,
#when flipping such a card, we destroy it and create a new card
func flip_doublesided_card(card:WCCard):
	var back_code = card.get_card_back_code()
	if (back_code):
		var new_card = cfc.instance_card(back_code,card.get_owner_hero_id())
		#TODO copy tokens, state, etc...
		var slot = card._placement_slot
		add_child(new_card)
		card.copy_modifiers_to(new_card)
		card.queue_free() #is more required to remove it?		
		#new_card._determine_idle_state()
		#new_card.move_to(cfc.NMAP.board, -1, slot)	
		new_card.position = slot.rect_global_position
		new_card._placement_slot = slot
		slot.occupying_card = new_card
		new_card.state = Card.CardState.ON_PLAY_BOARD
		#new_card.reorganize_self()
		
		
	else:
		return
		#TODO mabe flip anyway?

func _on_OptionsButton_pressed():
	cfc.set_game_paused(true)
	options_menu.set_as_toplevel(true)
	options_menu.visible = true
	pass # Replace with function body.
