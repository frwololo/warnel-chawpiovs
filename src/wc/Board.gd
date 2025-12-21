# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED

# Code for a sample playspace, you're expected to provide your own ;)
extends Board

var heroZone = preload("res://src/wc/board/WCHeroZone.tscn")
var basicGrid = preload("res://src/wc/grids/BasicGrid.tscn")
var basicPile = preload("res://src/core/Pile.tscn")

onready var villain := $VillainZone
onready var options_menu = $OptionsMenu

onready var _server_activity = get_node("%ServerActivity")
var board_organizers: Array = []

# heroZones is 1 indexed (index is hero_id)
var heroZones: Dictionary = {}

const GRID_SETUP = CFConst.GRID_SETUP
const HERO_GRID_SETUP = CFConst.HERO_GRID_SETUP

enum LOADING_STEPS {
	NONE,
	RNG_INIT,
	READY_TO_LOAD,
	CARDS_PRELOADED,
	CARDS_PRELOADED_SKIP_LOAD,
	CARDS_MOVED,
	READY_TO_START,
	START_GAME
}

# a temporary variable to move cards after all clients have loaded them,
# to avoid scripts triggering incorrectly
var _post_load_move:= {}

var _cards_loaded:= {}
var _hero_zones_initialized:= {}
var _ready_to_load:= {}

var _team_size = 0
var _total_delta:float = 0.0

func get_team_size():
	if !_team_size:
		_team_size = gameData.get_team_size()
	return _team_size

func _init():
	gameData.stop_game()
	init_hero_zones()

func set_groups(grid_or_pile, additional_groups:= []):
	var grid_name = grid_or_pile.name
	if grid_name.begins_with("discard"):
		grid_or_pile.add_to_group("discard")

	for group in additional_groups:
		grid_or_pile.add_to_group(group)

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


	# warning-ignore:return_value_discarded
	#$DeckBuilderPopup.connect('popup_hide', self, '_on_DeckBuilder_hide')

	#gameData.init_save_folder()

	grid_setup()
	rpc("ready_for_step", LOADING_STEPS.RNG_INIT)

var _clients_ready_for_step = {}
remotesync func ready_for_step(next_step):
	var client_id = get_tree().get_rpc_sender_id()
	_clients_ready_for_step[client_id] = next_step
	if _clients_ready_for_step.size() != gameData.network_players.size():
		return
	for network_id in _clients_ready_for_step:
		if _clients_ready_for_step[network_id] != next_step:
			return

	_clients_ready_for_step = {}
	load_next_step(next_step)

func load_next_step(next_step):
	match next_step:
		LOADING_STEPS.RNG_INIT:
			if cfc.is_game_master():
				var my_seed = CFUtils.generate_random_seed()
				rpc("set_random_seed", my_seed)
		LOADING_STEPS.READY_TO_LOAD:
			load_cards()
			rpc("ready_for_step", LOADING_STEPS.CARDS_PRELOADED)
		LOADING_STEPS.CARDS_PRELOADED:
			post_load_move()
			rpc("ready_for_step", LOADING_STEPS.CARDS_MOVED)
		LOADING_STEPS.CARDS_PRELOADED_SKIP_LOAD:
			post_load_move()
			rpc("ready_for_step", LOADING_STEPS.START_GAME)
		LOADING_STEPS.CARDS_MOVED:
			post_cards_moved_load()
			#next step called from within function
		LOADING_STEPS.READY_TO_START:
			offer_to_load_last_game()
		LOADING_STEPS.START_GAME:
			gameData.start_game()

func _decline_offer_to_load_last_game():
	gameData.init_save_folder()
	rpc("ready_for_step", LOADING_STEPS.START_GAME)
	return

func _load_last_game():
	var json_data = gameData.get_ongoing_game()
	if !json_data:
		rpc("ready_for_step", LOADING_STEPS.START_GAME)
		return
	gameData.load_gamedata(json_data)

func offer_to_load_last_game():
	if !cfc.is_game_master():
		rpc("ready_for_step", LOADING_STEPS.START_GAME)
		return

	var json_data = gameData.get_ongoing_game()
	if !json_data:
		rpc("ready_for_step", LOADING_STEPS.START_GAME)
		return

	#only offer to load if the previous save game had the same number of heroes
	var hero_data:Array = json_data.get("heroes", [])
	if hero_data.size() != gameData.get_team_size():
		rpc("ready_for_step", LOADING_STEPS.START_GAME)
		return


	var load_dialog:ConfirmationDialog = ConfirmationDialog.new()
	load_dialog.window_title = "Load last game?"
	load_dialog.get_cancel().connect("pressed", self, "_decline_offer_to_load_last_game")
	load_dialog.connect("confirmed", self, "_load_last_game")
	add_child(load_dialog)
	load_dialog.popup_centered()

remotesync func set_random_seed(my_seed):
	cfc.LOG("setting random seed to " + str(my_seed))
	cfc.game_rng_seed = my_seed
	$SeedLabel.text = "Game Seed is: " + cfc.game_rng_seed
	rpc("ready_for_step", LOADING_STEPS.READY_TO_LOAD)


func blocking_activity_ongoing():
	if !gameData.theStack.is_player_allowed_to_click():
		return true
	if _server_activity.visible:
		return true
	if gameData.is_ongoing_blocking_announce():
		return true

func _process(delta:float):
	_total_delta += delta
	#todo this is a heavy call, maybe do it only when cards move
	if board_organizers:
		for board_organizer in board_organizers:
			board_organizer.organize()

	if blocking_activity_ongoing():
		var last_index = get_child_count() - 1
		move_child(_server_activity, last_index)
		_server_activity.visible = true
		_server_activity.rect_position = self.mouse_pointer.determine_global_mouse_pos() - _server_activity.rect_size * _server_activity.rect_scale
		_server_activity.modulate = Color(1, 1, 1, sin(_total_delta*2)*0.4 + 0.5)
		_server_activity.rect_rotation = _total_delta * 100
	pass

func grid_setup():
	_team_size = 0 #reset team size to fetch it from gameData
	for grid_name in GRID_SETUP.keys():
		var grid_info = GRID_SETUP[grid_name]
		if "pile" == grid_info.get("type", ""):
			if cfc.NMAP.has(grid_name): #skip if already exists
				continue
			var scene = grid_info.get("scene", basicPile)
			var pile: Pile = scene.instance()
			pile.add_to_group("piles")
			pile.name = grid_name
			pile.set_pile_name(grid_name)
			pile.set_position(Vector2(grid_info["x"], grid_info["y"]))
			pile.set_global_position(Vector2(grid_info["x"], grid_info["y"]))
			var pile_scale = grid_info.get("scale", 1)
			pile.scale = Vector2(pile_scale, pile_scale)
			pile.faceup_cards = grid_info.get("faceup", false)
			add_child(pile)
			set_groups(pile, grid_info.get("groups", []))
		else:
			if has_node(grid_name): #skip if already exists
				continue
			var grid_scene = grid_info.get("scene", basicGrid)
			var grid: BoardPlacementGrid = grid_scene.instance()
			grid.add_to_group("placement_grid")
			var grid_scale = grid_info.get("scale", 1)
			grid.rescale(CFConst.PLAY_AREA_SCALE  * grid_scale)
			# A small delay to allow the instance to be added
			add_child(grid)
			grid.name = grid_name
			grid.name_label.text = grid_name
			grid.rect_position = Vector2(grid_info["x"], grid_info["y"])
			grid.auto_extend = grid_info.get("auto_extend", true)
			set_groups(grid, grid_info.get("groups", []))

	for i in range(get_team_size()):
		var hero_id = i+1
		var scale = 1
		var start_x = 500
		var start_y = 220

		if (hero_id > 1):
			scale = 0.3
			start_x = 0
			start_y = 220 + (hero_id * 200)

		for grid_name in HERO_GRID_SETUP.keys():
			var grid_info = HERO_GRID_SETUP[grid_name]
			var x = start_x + grid_info["x"]*scale
			var y = start_y + grid_info["y"]*scale
			var real_grid_name = grid_name + str(hero_id)
			if "pile" == grid_info.get("type", ""):
				if cfc.NMAP.has(real_grid_name): #skip if already exists
					continue
				var scene = grid_info.get("scene", basicPile)
				var pile: Pile = scene.instance()
				pile.add_to_group("piles")
				pile.name = real_grid_name
				pile.set_pile_name(real_grid_name)
				pile.set_position(Vector2(x,y))
				pile.set_global_position(Vector2(x,y))
				var pile_scale = grid_info.get("scale", 1)
				pile.scale = Vector2(scale*pile_scale,scale*pile_scale)
				pile.faceup_cards = grid_info.get("faceup", false)
				add_child(pile)
				set_groups(pile, grid_info.get("groups", []))
			else:
				if has_node(real_grid_name): #skip if already exists
					continue
				var grid_scene = grid_info.get("scene", basicGrid)
				var grid: BoardPlacementGrid = grid_scene.instance()
				grid.add_to_group("placement_grid")
				# Need to rescale before adding ???
				var grid_scale = grid_info.get("scale", 1)
				grid.rescale(CFConst.PLAY_AREA_SCALE * scale * grid_scale)
				add_child(grid)
				grid.name = real_grid_name
				grid.name_label.text = real_grid_name
				grid.rect_position = Vector2(x,y)
				grid.auto_extend = grid_info.get("auto_extend", true)
				set_groups(grid, grid_info.get("groups", []))

	init_board_organizers(1)
#	board_organizer.organize()

func init_board_organizers(current_hero_id):
	board_organizers = []
	var other_counter = 0
	for i in range(get_team_size()):
		var hero_id = i+1
		var scale = 1
		var start_x = 500
		var start_y = 220
		var grid_layout = CFConst.HERO_GRID_LAYOUT.duplicate(true)

		if (hero_id != current_hero_id):
			scale = 0.3
			start_x = 0
			start_y = 220 + (other_counter * 200)
			other_counter+=1
			#hacky way to force resize
			var right_container_def = grid_layout["children"][1]
			right_container_def["max_width"] = 400
			right_container_def["max_height"] = 200
		var board_organizer = BoardOrganizer.new()
		board_organizer.setup(grid_layout,hero_id, scale)
		board_organizer.set_absolute_position(Vector2(start_x, start_y))
		board_organizers.append(board_organizer)
		board_organizer.organize()



func post_cards_moved_load():
	#Signals
	scripting_bus.connect("current_playing_hero_changed", self, "_current_playing_hero_changed")

	hide_all_hands()
	gameData.assign_starting_hero()


	load_heroes()
	#loading heroes requires moving cards around, this can interfere with
	#the shuffling afterwards
	var hero_count: int = get_team_size()
	for i in range (hero_count):
		while (heroZones[i+1].post_move_modifiers or heroZones[i+1]._post_load_move):
			yield(get_tree().create_timer(0.5), "timeout")

	shuffle_decks()
	#Need to wait after shuffling decks
	yield(get_tree().create_timer(0.5), "timeout")
	for i in range(gameData.get_team_size()):
		var pile = cfc.NMAP["deck" + str(i+1)]
		while pile.is_shuffling:
			yield(get_tree().create_timer(0.05), "timeout")

	villain.load_scenario()
	while villain._post_load_move or cfc.NMAP["deck_villain"].is_shuffling:
		yield(get_tree().create_timer(0.05), "timeout")

	draw_starting_hand()
	#Tests
	if gameData.get_team_size() < 2:
		#draw_cheat_ghost("Web-Shooter")
		#draw_cheat_ghost("Combat Training")
		#draw_cheat_ghost("Jessica Jones")
		#draw_cheat_ghost("Mockingbird")
		#draw_cheat("Black Cat")
		#draw_cheat("Energy")
		#draw_cheat("Backflip")
		#draw_cheat("Helicarrier")
		#draw_cheat("Swinging Web Kick")
		pass
	cfc.LOG_DICT(guidMaster.guid_to_object)

	for i in range (get_team_size()):
		heroZones[i+1].reorganize()

	while are_cards_still_animating():
		yield(get_tree().create_timer(0.1), "timeout")

	#TODO better way to do a reveal ?
	var current_villain = get_villain_card()
	var func_return = current_villain.execute_scripts_no_stack(current_villain, "reveal")
	if func_return is GDScriptFunctionState && func_return.is_valid():
		yield(func_return, "completed")

	var scheme = null
	while !scheme: #in network settings, this varialbe sometimes takes some time to get to us
		scheme = gameData.get_main_scheme()
		yield(get_tree().create_timer(0.1), "timeout")

	func_return = scheme.execute_scripts_no_stack(scheme, "setup")
	if func_return is GDScriptFunctionState && func_return.is_valid():
		yield(func_return, "completed")

	func_return = scheme.execute_scripts_no_stack(scheme, "reveal")
	if func_return is GDScriptFunctionState && func_return.is_valid():
		yield(func_return, "completed")

	#Save gamedata for restart
	gameData.save_gamedata_to_file("user://Saves/_restart.json")

	rpc("ready_for_step", LOADING_STEPS.READY_TO_START)

func get_villain_card():
	return villain.get_villain()


func load_villain(card_id, call_preloaded = {"shuffle" : false}):
	return villain.load_villain(card_id, call_preloaded)

func load_scheme(card_id, call_preloaded = {"shuffle" : false}):
	return villain.load_scheme(card_id, call_preloaded)

func load_heroes():
	var hero_count: int = get_team_size()
	for i in range (hero_count):
		heroZones[i+1].load_starting_identity()


func hide_all_hands():
	#exchange hands
	for i in range (CFConst.MAX_TEAM_SIZE):
		for v in ["GhostHand", "Hand"]:
			var old_hand: Hand = get_node("%" + v + str(i+1))
			if old_hand.is_in_group("bottom"):
				old_hand.remove_from_group("bottom") #todo fix hack
			WCUtils.disable_and_hide_node(old_hand)
			old_hand.re_place()
			old_hand.position = Vector2(20000, 20000)



func init_hero_zones():
	var hero_count: int = get_team_size()
	if hero_count == heroZones.size():
		return
	while hero_count < heroZones.size():
		heroZones.erase(heroZones.size())

	while hero_count > heroZones.size():
		var index = heroZones.size()+1
		var new_hero_zone = heroZone.instance()
		new_hero_zone.name = "HeroZone" + str(index)
		add_child(new_hero_zone)
		new_hero_zone.set_player(index)
		new_hero_zone.rect_position = Vector2(500, 600) #TODO better than this
		heroZones[index] = new_hero_zone

# Returns an array with all children nodes which are of Card class
func get_all_cards() -> Array:
	var cardsArray := []
	for obj in get_children():
		if obj as Card: cardsArray.append(obj)
	cardsArray += $VillainZone.get_all_cards() #technically villain zone has no cards AFAIK

	return(cardsArray)

func get_all_cards_controlled_by(hero_id):
	var cardsArray := []
	for obj in get_children():
		if obj as Card:
			if (obj.get_controller_hero_id() == hero_id):
				cardsArray.append(obj)
	return cardsArray

func get_all_cards_by_property(property:String, value):
	var cardsArray := []
	for obj in get_children():
		if obj as Card:
			if (obj.get_property(property) == value):
				cardsArray.append(obj)
	return cardsArray

func reset_board():
	gameData.stop_game()
	delete_all_cards()
	_team_size = 0
	init_hero_zones()
	grid_setup()

func server_activity(on = true):
	_server_activity.visible = on
	pass

func delete_all_cards():

	#delete everything on board and grids
	var cards:Array = get_all_cards()
	for obj in cards:
		remove_child(obj)
		obj.queue_free()

	#delete everything in hands
	for i in range(get_team_size()):
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
			grid.delete_all_slots_but_one()


	for i in range(get_team_size()):
		var hero_id = i+1
		for grid_name in HERO_GRID_SETUP.keys():
			var grid_info = HERO_GRID_SETUP[grid_name]
			var real_grid_name = grid_name + str(hero_id)
			if "pile" == grid_info.get("type", ""):
				var pile:Pile = cfc.NMAP[real_grid_name]
				pile.delete_all_cards()
			else: #it's a grid
				var grid: BoardPlacementGrid = cfc.NMAP.board.get_grid(real_grid_name)
				grid.delete_all_slots_but_one()

func _close_game():
	cfc.quit_game()
	get_tree().change_scene("res://src/wc/MainMenu.tscn")

func _retry_game(message:String):
	#TODO
	cfc.quit_game()
	get_tree().change_scene("res://src/wc/MainMenu.tscn")

func _reload_last_save():
	gameData.reload_round_savegame(gameData.current_round)


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


func get_enemies_engaged_with(hero_id):
	var grid = get_grid("enemies" + str(hero_id))
	return grid.get_all_cards()

func _on_ReshuffleAllDiscard_pressed() -> void:
	reshuffle_all_in_pile(cfc.NMAP.discard)

func reshuffle_all_in_pile(pile = cfc.NMAP.deck):
	cfc.add_ongoing_process(self, "reshuffle_all_in_pile")
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
	cfc.remove_ongoing_process(self, "reshuffle_all_in_pile")


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



func get_owner_from_pile_name(pile_name:String):
	#exception for piles controlled by the player but where cards belong to villain
	if pile_name.begins_with("encounters") or pile_name.begins_with("enemies"):
		return 0 #villain

	for i in CFConst.MAX_TEAM_SIZE:
		var hero_id = i+1
		if (pile_name.ends_with(str(hero_id))):
			return hero_id
	return 0 #villain

func get_controller_from_pile_name(pile_name:String):
	return gameData.get_grid_controller_hero_id(pile_name)
#things to do after everything is properly loaded.
#This will trigger execute_scripts
#so all clients need to be loaded before calling this
func post_load_move():
	for card in _post_load_move:
		var data = _post_load_move[card]
		var pile_name = data.get("grid", "")
		var host_id = data.get("host_id", "")

		if (pile_name):
			var grid: BoardPlacementGrid = cfc.NMAP.board.get_grid(pile_name)
			var slot: BoardPlacementSlot
			if grid:
				slot = grid.find_available_slot()
				if slot:
					card.move_to(cfc.NMAP.board, -1, slot)
		if host_id:
			var host_card = find_card_by_name(host_id)
			if host_card:
				card.attach_to_host(host_card)

	for card in _post_load_move:
		#card.interruptTweening()
		card.reorganize_self()

	_post_load_move = {} #reset


	return


func load_cards_to_pile(card_data:Array, pile_name):
	var card_array = []
	var pile_owner = get_owner_from_pile_name(pile_name)
	var pile_controller = get_controller_from_pile_name(pile_name)
	var card_to_card_data = {}
	for card in card_data:
		var card_id_or_name:String = card["card"]
		var card_owner = card.get("owner_hero_id", pile_owner)

		#card_id here is either a card id or a card name, we try to accomodate for both
		var card_id = cfc.get_corrected_card_id(card_id_or_name)
		if !card_id:
			var _error = 1
			cfc.LOG("error, couldn't find card named " + str(card_id_or_name))
			continue
		var new_card:WCCard = cfc.instance_card_with_owner(card_id, card_owner)
		if card_owner != pile_controller:
			new_card.set_controller_hero_id(pile_controller)
		#new_card.load_from_json(card)
		card_array.append(new_card)
		card_to_card_data[new_card] = card

	for card in card_array:
		if (pile_name and cfc.NMAP.has(pile_name)): #it's a pile
			cfc.NMAP[pile_name].add_child(card)
			card._determine_idle_state()
		else: #it's a grid or the board
			#TODO cleaner way to add the card there?
			#card.set_is_faceup(true)
			add_child(card)
			card._determine_idle_state()
			_post_load_move[card] = {
				"grid": pile_name,
				"host_id":card_to_card_data[card].get("host", {})
			}
		card.load_from_json(card_to_card_data[card])

		#dirty way to set some important variables
		if (pile_name =="villain"):
			villain.villain = card
		if (pile_name.begins_with("identity")):
			heroZones[pile_owner].set_identity_card(card)

	for card in card_array:
		#card.interruptTweening()
		card.reorganize_self()

	return

func load_cards_to_grid(card_data:Array, grid_name):
	load_cards_to_pile(card_data, grid_name)
	return

func export_cards_to_json(pile_name, cards) -> Dictionary:
	var export_arr:Array = []
	for card in cards:
		var card_description = card.export_to_json()
		export_arr.append(card_description)
	var result:Dictionary = {pile_name : export_arr}
	return result

func export_pile_to_json(pile_name, seen_cards:= {}) -> Dictionary:
	var pile: CardContainer = cfc.NMAP[pile_name]
	var cards:Array = pile.get_all_cards()
	for card in cards:
		seen_cards[card] = true
	return export_cards_to_json(pile_name, cards)

func export_grid_to_json(grid_name, seen_cards:= {}) -> Dictionary:
	var grid:BoardPlacementGrid = get_grid(grid_name)
	var cards:Array = grid.get_all_cards()
	for card in cards:
		seen_cards[card] = true
	return export_cards_to_json(grid_name, cards)

func shuffle_decks() -> void:
	for i in range(gameData.get_team_size()):
		var pile_name = "deck" + str(i+1)
		var pile = cfc.NMAP[pile_name]
		while pile.are_cards_still_animating():
			yield(pile.get_tree().create_timer(0.2), "timeout")
		cfc.LOG("shuffling deck " + str(pile_name))
		pile.shuffle_cards()

func draw_starting_hand() -> void:
	gameData.draw_all_players()


func draw_cheat(cardName : String, hand = "hand1") -> void:
	var card_key = cfc.get_corrected_card_id(cardName)
	var card = cfc.instance_card_with_owner(card_key, 1)
	var pile = cfc.NMAP["deck1"]
	pile.add_child(card)
	cfc.NMAP[hand].draw_card (pile)

func draw_cheat_ghost(cardName : String) -> void:
	draw_cheat(cardName, "ghosthand1")


func are_cards_still_animating(check_everything:bool = true) -> bool:
	for c in get_all_cards():
		if c.is_animating():
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

	for container in get_tree().get_nodes_in_group("hands"):
		container.disable()
	for v in ["GhostHand", "Hand"]:
		var new_hand: Hand = get_node("%" + v + str(new_hero_id))
		new_hand.add_to_group("bottom")
		WCUtils.enable_and_show_node(new_hand)
		new_hand.enable()
		new_hand.re_place()

	init_board_organizers(new_hero_id)

	if (previous_hero_id == new_hero_id):
		return

	#exchange hands
	for v in ["GhostHand", "Hand"]:
		var old_hand: Hand = get_node("%" + v + str(previous_hero_id))
		if old_hand.is_in_group("bottom"):
			old_hand.remove_from_group("bottom") #todo fix hack
		WCUtils.disable_and_hide_node(old_hand)
		old_hand.re_place()
		old_hand.position = Vector2(20000, 20000)
		var new_hand: Hand = get_node("%" + v + str(new_hero_id))
		new_hand.add_to_group("bottom")
		WCUtils.enable_and_show_node(new_hand)
		new_hand.enable()

	for v in ["GhostHand", "Hand"]:
		var new_hand: Hand = get_node("%" + v + str(new_hero_id))
		new_hand.re_place()






func savestate_to_json() -> Dictionary:
	var json_data:Dictionary = {}
	var seen_cards:= {}
	for grid_name in GRID_SETUP.keys():
		var grid_info = GRID_SETUP[grid_name]
		if "pile" == grid_info.get("type", ""):
			json_data.merge(export_pile_to_json(grid_name, seen_cards))
		else:
			json_data.merge(export_grid_to_json(grid_name, seen_cards))

	for i in range(gameData.get_team_size()):
		var hero_id = i+1

		for grid_name in HERO_GRID_SETUP.keys():
			var grid_info = HERO_GRID_SETUP[grid_name]
			var real_grid_name = grid_name + str(hero_id)
			if "pile" == grid_info.get("type", ""):
				json_data.merge(export_pile_to_json(real_grid_name, seen_cards))
			else:
				json_data.merge(export_grid_to_json(real_grid_name, seen_cards))

		#save hand
		var hand_name = "hand" + str(hero_id)
		json_data.merge(export_pile_to_json(hand_name, seen_cards))

	#orphan cards (not in pile or grid)
	var other_cards = []
	for card in get_all_cards():
		if ! seen_cards.get(card, false):
			other_cards.append(card)
	if other_cards:
		#other cards don't come back in the right order, due to how cards
		#are added to the game in the first place
		#doing this sort for now until I figure out something better
		var json_dict = export_cards_to_json("others", other_cards)
		json_dict["others"].sort_custom(WCUtils, "sort_cards")
		json_data.merge(json_dict)

	var result: Dictionary = {"board" : json_data}
	return result

func loadstate_from_json(json:Dictionary):
	gameData.stop_game()
	cfc.set_game_paused(true)

	var json_data = json.get("board", null)
	if (null == json_data):
		return #TODO Error msg

	reset_board()

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

	#load cards that aren't on any grid or piles
	var other_data = json_data.get("others", [])
	load_cards_to_pile(other_data, "")

	rpc("ready_for_step", LOADING_STEPS.CARDS_PRELOADED_SKIP_LOAD) #tell everyone we're done preloading

	#gameData.start_game()
	return
#The game engine doesn't really have a concept of double sided cards, so instead,
#when flipping such a card, we destroy it and create a new card
func flip_doublesided_card(card:WCCard):
	var back_code = card.get_card_back_code()
	if (back_code):
		var type_code = card.get_property("type_code")
		if type_code in ["hero", "alter_ego"]:
			var modifiers = card.export_modifiers()
			modifiers["callback"] = "changed_form"
			modifiers["callback_params"] = {"before": type_code}
			gameData.set_aside(card)
			var new_card = heroZones[card.get_owner_hero_id()].load_identity(back_code, modifiers)
			return new_card
		else:
			var new_card = cfc.instance_card_with_owner(back_code, card.get_owner_hero_id())
			#TODO copy tokens, state, etc...
			var slot = card._placement_slot
			add_child(new_card)
			card.copy_modifiers_to(new_card)
			gameData.set_aside(card) #is more required to remove it?
			#new_card._determine_idle_state()
			#new_card.move_to(cfc.NMAP.board, -1, slot)
			new_card.position = slot.rect_global_position
			slot.set_occupying_card(new_card)
			new_card.state = Card.CardState.ON_PLAY_BOARD
			#new_card.reorganize_self()
			return new_card


	else:
		return null
		#TODO mabe flip anyway?

func count_card_per_player_in_play(unique_card:WCCard, hero_id = 0, exclude_self = false):
	var unique_name = unique_card.get_unique_name().to_lower()
	var all_cards
	if hero_id:
		all_cards = self.get_all_cards_controlled_by(hero_id)
	else:
		all_cards = self.get_all_cards()
	var result = 0
	for card in all_cards:
		if !card.is_faceup:
			continue
		if card == unique_card and exclude_self:
			continue
		var card_unique_name = card.get_unique_name().to_lower()
		if card_unique_name == unique_name:
			result +=1
	return result

func unique_card_in_play(unique_card:WCCard):
	#note: sometimes subname can be set but still equal to null, so we have to force it to empty string
	var unique_name = unique_card.get_unique_name().to_lower()

	var all_cards = self.get_all_cards()
	for card in all_cards:
		if !card.is_faceup:
			continue
		var card_unique_name = card.get_unique_name().to_lower()
		if card_unique_name == unique_name:
			return true
	return false

func _on_OptionsButton_pressed():
	cfc.set_game_paused(true)
	options_menu.set_as_toplevel(true)
	options_menu.visible = true
	pass # Replace with function body.

#card_id_or_name can be an id, a shortname, or a name
func find_card_by_name(card_id_or_name, include_back:= false):
	var card_name = cfc.get_card_name_by_id(card_id_or_name)
	if !card_name:
		card_name = card_id_or_name.to_lower()
		card_name = cfc.shortname_to_name.get(card_name, "")
	if !card_name:
		card_name = card_id_or_name
	card_name = card_name.to_lower()

	for card in get_all_cards():
		if (card.canonical_name.to_lower() == card_name):
			return card
		if (include_back):
			var back_code = card.get_card_back_code()
			if (back_code):
				var back_name = cfc.get_card_name_by_id(back_code)
				if back_name.to_lower() == card_name:
					return card
	return null




func _on_ServerActivity_gui_input(event):
	if event is InputEventMouseButton:
		if event.doubleclick and cfc.is_game_master():
			gameData.theStack.attempt_unlock()

	pass # Replace with function body.
