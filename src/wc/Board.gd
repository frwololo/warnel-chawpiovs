# Code for a sample playspace, you're expected to provide your own ;)
extends Board

var heroZone = preload("res://src/wc/board/WCHeroZone.tscn")
var basicGrid = preload("res://src/wc/grids/BasicGrid.tscn")
onready var villain := $VillainZone

const GRID_SETUP := {
	"villain" : {
		"x" : 300,
		"y" : 0,
	},
	"schemes" : {
		"x" : 500,
		"y" : 0,
	},
	"villain_misc" : {
		"x" : 1500,
		"y" : 0,
	},
	"enemies" : {
		"x" : 500,
		"y" : 200,
	},
	"identity" : {
		"x" : 500,
		"y" : 400,
	},
	"allies" : {
		"x" : 800,
		"y" : 400,
	},
	"upgrade_support" : {
		"x" : 800,
		"y" : 600,
	},									
}

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
	$DeckBuilderPopup.connect('popup_hide', self, '_on_DeckBuilder_hide')	
	
	for grid_name in GRID_SETUP.keys():
		var grid_info = GRID_SETUP[grid_name]
		var grid_scene = grid_info.get("grid_scene", basicGrid)
		var grid: BoardPlacementGrid = grid_scene.instance()
		grid.add_to_group("placement_grid")
		# A small delay to allow the instance to be added
		add_child(grid)
		# If the grid name is empty, we use the predefined names in the scene.
		if grid_name != "":
			grid.name = grid_name
			grid.name_label.text = grid_name
		grid.rect_position = Vector2(grid_info.x, grid_info.y)
		grid.auto_extend = true

	#Game setup - Todo move somewhere else ?
	load_cards()
	shuffle_decks()
	#Need to wait after shuffling decks
	for i in range(gameData.get_team_size()):
		var pile = cfc.NMAP["deck" + str(i+1)]	
		yield(pile, "shuffle_completed")	
	
	villain.load_scenario()


	draw_starting_hand()
	offer_to_mulligan()
	
	#Tests
	draw_cheat("Mockingbird")
	draw_cheat("Swinging Web Kick")


func init_hero_zones():
	var hero_count: int = gameData.get_team_size()
	for i in range (hero_count): 
		var new_hero_zone = heroZone.instance()
		add_child(new_hero_zone)
		new_hero_zone.set_player(i+1)
		new_hero_zone.rect_position = Vector2(500, 600) #TODO better than this		

# Returns an array with all children nodes which are of Card class
func get_all_cards() -> Array:
	var cardsArray := []
	for obj in get_children():
		if obj as Card: cardsArray.append(obj)
		if obj as WCHeroZone: cardsArray.append(obj.get_all_cards())
	cardsArray.append_array($VillainZone.get_all_cards())
	return(cardsArray)


# This function is to avoid relating the logic in the card objects
# to a node which might not be there in another game
# You can remove this function and the FancyMovementToggle button
# without issues
func _on_FancyMovementToggle_toggled(_button_pressed) -> void:
#	cfc.game_settings.fancy_movement = $FancyMovementToggle.pressed
	cfc.set_setting('fancy_movement', $FancyMovementToggle.pressed)


func _on_OvalHandToggle_toggled(_button_pressed: bool) -> void:
	cfc.set_setting("hand_use_oval_shape", $OvalHandToggle.pressed)
	for c in cfc.NMAP.hand.get_all_cards():
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
		var card_array = []
		var hero_deck_data: HeroDeckData = gameData.get_team_member(i+1)["hero_data"] #TODO actually load my player's stuff
		var card_ids = hero_deck_data.get_deck_cards()
		for card_id in card_ids:
			#cards.append(ckey)
			var ckey = cfc.idx_card_id_to_name[card_id]
			card_array.append(cfc.instance_card(ckey))

		for card in card_array:
			cfc.NMAP["deck" + str(i+1)].add_child(card)
			#card.set_is_faceup(false,true)
			card._determine_idle_state()
			
func shuffle_decks() -> void:
	for i in range(gameData.get_team_size()):
		var pile = cfc.NMAP["deck" + str(i+1)]
		while pile.are_cards_still_animating():
			yield(pile.get_tree().create_timer(0.2), "timeout")
		pile.shuffle_cards()
	
func draw_starting_hand() -> void:
	for i in range(gameData.get_team_size()):
		var hero_deck_data: HeroDeckData = gameData.get_team_member(i+1)["hero_data"] #TODO actually load my player's stuff
		var alter_ego_data = hero_deck_data.get_alter_ego_card_data()
		var hand_size = alter_ego_data["hand_size"]
		var pile = cfc.NMAP["deck" + str(i+1)]
		for j in range(hand_size):
			cfc.NMAP["hand"].draw_card (pile)

func draw_cheat(cardName : String) -> void:
	var card = cfc.instance_card(cardName)
	var pile = cfc.NMAP["deck1"]
	pile.add_child(card)
	cfc.NMAP["hand"].draw_card (pile)
	
func offer_to_mulligan() -> void:
	pass				

func _on_DeckBuilder_pressed() -> void:
	cfc.game_paused = true
	$DeckBuilderPopup.popup_centered_minsize()

func _on_DeckBuilder_hide() -> void:
	cfc.game_paused = false


func _on_BackToMain_pressed() -> void:
	cfc.quit_game()
	get_tree().change_scene("res://src/wc/MainMenu.tscn")
