class_name Drafter
extends Panel


var draft_aspect = ""
var cards_per_pack = 5
var current_draft_step = 0
var hero_id = ""
var deck_id = 0

var callback_menu_command = null


onready var deck:CompactDeckContainer = get_node("%Deck")
onready var aspects_container:HFlowContainer = get_node("%AspectsContainer")
onready var hero_picture :SimpleCardDisplay= get_node("%HeroCardDisplay")
onready var draft_cards: SimpleCardList = get_node("%SimpleCardList")
onready var card_count: Label = get_node("%CardCount")

# Called when the node enters the scene tree for the first time.
func _ready():
	draft_cards.set_columns(4)
	setup_setup()
	if gameData.menu_command:
		process_command(gameData.menu_command)
		gameData.menu_command = {}
	else:
		#default for testing
		process_command({"hero_id": "01001a"})
	resize()


func process_command(command):
	if typeof(command) != TYPE_DICTIONARY:
		return
	callback_menu_command  = command.get("callback", {})	
	hero_id = command.get("hero_id", "")
	if !hero_id:
		#unsupported for now
		return

	hero_picture.set_card_size(Vector2(300, 419))
	hero_picture.load_card(hero_id)
	
	var init_deck = HeroDeckData.get_hero_base_deck(hero_id)
	deck_id = CFConst.DRAFT_DECK_ID + hero_id.to_int()
	init_deck["id"] = deck_id
	init_deck["name"] = "DRAFT Deck"		
	if !init_deck:
		return
	deck.load_deck_data(init_deck)
	select_tab("SetupTab")

#prepare the setup panel
func setup_setup():
	for aspect in CFConst.ASPECTS:
		var button:Button = Button.new()
		button.name = "aspect_" + aspect
		button.text = aspect.capitalize()
		button.set_toggle_mode(true)
		button.connect('pressed', self, 'on_button_pressed', [button.name])
		aspects_container.add_child(button)
	
	set_draft_aspect("aggression")
		
func select_tab(tab_name):
	for _tab_name in ["DraftTab", "SetupTab", "FinishedTab"]:
		var tab = get_node("%" + _tab_name)
		tab.visible = false

	get_node("%" + tab_name).visible = true
	#cfc.default_button_focus(get_node("%" + tab_name))

func on_button_pressed(button_name:String):
	var action = button_name
	if action.begins_with("aspect_"):
		action = action.replace("aspect_", "")
		set_draft_aspect(action)

func set_draft_aspect(aspect):
	draft_aspect = aspect.to_lower()
	var to_match = "aspect_" + draft_aspect
	for child in aspects_container.get_children():
		if child.name.to_lower() == to_match:
			child.set_pressed_no_signal(true)
		else:
			child.set_pressed_no_signal(false)
	

func resize():
	resize_hero_picture()

func resize_hero_picture():
	var screen_size = get_viewport().size/cfc.screen_scale
	if screen_size.x > 1800:
		hero_picture.rect_min_size = Vector2(300, 419)
	else:		
		hero_picture.rect_min_size = Vector2(150, 200)			
	hero_picture.rect_size = hero_picture.rect_min_size	

var _my_collection = []
func generate_draft_pack():
	if !_my_collection:
		#restrict "teamup" cards to the heroes who can play them
		var all_team_cards = WCUtils.get_team_up_cards().keys()
		var my_team_up_cards = WCUtils.find_team_up_cards_for_hero(hero_id)
		
		#restrict cards with trait restrictions only if my hero or alter_ego has them
		var my_hero_data = cfc.get_card_by_id(hero_id)
		var my_alter_ego_data = cfc.get_alter_ego_data(hero_id)
		
		var collection = DeckEdit.get_card_collection()
		for card_id in collection:
			var card_data = collection[card_id]
			if !card_data.get("faction_code", "") in ["basic", draft_aspect]:
				continue
			if (card_id in all_team_cards) and !(card_id in my_team_up_cards):
				continue
			var trait_constraints = card_data.get("play_only_if_traits", [])
			if trait_constraints:
				var found = false
				for trait in trait_constraints:
					var property = "trait_" + trait
					if my_hero_data.get(property) or my_alter_ego_data.get(property):
						found = true
						break
				if !found:
					continue		
			_my_collection.append(card_id)
	randomize()			
	_my_collection.shuffle()
	
	var result = []
	var i = 0
	while result.size() < cards_per_pack:
		var card_id = _my_collection[i]
		var card_data = cfc.get_card_by_id(card_id)
		var currently_in_deck = deck.get_deck_data()
		if DeckEdit.can_add_card_to_deck(card_data, currently_in_deck):			
			result.append(_my_collection[i])
		else:
			pass
		i += 1
	return result
	

func start_draft():
	select_tab("DraftTab")
	next_draft_step()
	
func add_card_to_deck(card_code):
	var card_data = cfc.get_card_by_id(card_code)
	if card_data.get("is_unique", false):
		_my_collection.erase(card_code)
	deck.add_card(card_code)
	
func next_draft_step():
	var deck_count = deck.count_cards()
	card_count.text = "Cards: " + str(deck_count) + "/ 40"
	if deck_count >= 40:
		select_tab("FinishedTab")
	current_draft_step += 1
	var current_draft_pack = generate_draft_pack()
	draft_cards.init_cards(current_draft_pack)	

func _on_BackButton_pressed():
	gameData.editor_deck_data = {}
	self.queue_free()
	gameData.disconnect_from_network()
	get_tree().change_scene(CFConst.PATH_CUSTOM + 'MainMenu.tscn')



func _on_StartButton_pressed():
	start_draft()


func _on_OptionButton_item_selected(index):
	cards_per_pack = index + 5
	if cards_per_pack > 8:
		draft_cards.set_columns(5)
		draft_cards.set_cards_size(Vector2(220, 300))
	else:
		draft_cards.set_columns(4)
		draft_cards.set_cards_size(Vector2(300, 419))

func _on_SimpleCardList_card_clicked(card_code):
	add_card_to_deck(card_code)
	next_draft_step()


func _on_BackToGameButton_pressed():
	deck.save_deck()
	if callback_menu_command:
		#overwrite deck value with draft deck id, to force load it
		#on the next screen
		if callback_menu_command.has("heroes"):
			for hero in callback_menu_command.get("heroes", []):
				if hero["hero_id"] == hero_id:
					hero["deck_id"] = deck_id
		gameData.menu_command = callback_menu_command
		
		self.queue_free()
		get_tree().change_scene(CFConst.PATH_CUSTOM + 'lobby/TeamSelection.tscn')	

