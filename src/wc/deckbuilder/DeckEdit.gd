# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED

extends Node


#
#sub scenes
#
#var deckData = preload("res://src/wc/deckbuilder/DeckData.tscn")



#
#data
#
const card_collection = {}
var deck_data := {}
const card_cache := {}
var cache_pending := []
var current_collection_subset := []
var current_page = 0
var CARDS_PER_PAGE = 0
 
const DECK_CARD_SCALE = 1.12
const COLLECTION_CARD_SCALE = 0.65
const WAIT_BEFORE_PREVIEW = 0.7
const PREVIEW_CARD_SIZE = Vector2(450, 630)
const DECK_CARD_SPACING = 40

var ERROR_COLOR := 	Color(1,0.11,0.1)
var OK_COLOR := 	Color(0.1,11,0.1)

var _preview_rotation = 0
var current_hover_card = null
var current_active_card = null
var show_hero_cards = true
var rules_enforced = true
var loaded = 0

const aspects_dict := {}
const types_dict := {}
const costs_dict := {}

const aspects := []
const types := []
const costs := []

#
# shortcuts
#
onready var error_label := get_node("%message")
onready var done_button := get_node("%DoneButton")
onready var back_button := get_node("%BackButton")
onready var search_button := get_node("%SearchButton")
onready var collection_left_button := get_node("%CollectionLeftButton")
onready var collection_right_button := get_node("%CollectionRightButton")
onready var large_picture = get_node("%LargePicture")
onready var stats_label = get_node("%DeckStatsLabel")

onready var deck_container := get_node("%DeckRows")
onready var deck_name := get_node("%DeckName")
onready var collection_grid := get_node("%CollectionGrid")
onready var deck_scroll := get_node("%ScrollContainer")
var deck_rows:= []
var mouse_pointer:MousePointer


func grab_default_focus():
	for child in deck_container.get_children():
		child.grab_focus()	
		return
	
	#last hope
	get_node("%BackButton").grab_focus()

func critical_error():
	error_label.visible = true
	error_label.add_color_override("font_color", Color8(255, 50,50))
	error_label.text = "It seems there was a critical issue loading the database. Please check your network connection and your local files (settings, Sets/*, etc...)"

func _ready():
	
	var loading_panel = get_node("%LoadingPanel")
	$LoadingPanel/ColorRect.rect_min_size = get_viewport().size/cfc.screen_scale
	loading_panel.visible = true
	#get_viewport().connect("gui_focus_changed", self, "gui_focus_changed")	
	get_viewport().connect("size_changed", self, '_on_Menu_resized')

	cfc.buttons_grab_focus_on_mouse_entered(self)	

	#buttons signals
	back_button.connect("pressed", self, "_on_CancelButton_pressed")
	done_button.connect("pressed", self, "_on_DoneButton_pressed")
	
	

	CARDS_PER_PAGE = collection_grid.columns * 2
	#load data


#TODO: need to do this hack because gamepadHandler "gui_focus_changed" only works automatically when the
#board has been set up
#this is because a new viewport is created for the board
func gui_focus_changed(control):
	gamepadHandler.gui_focus_changed(control)

	

func _process(delta:float):
	if loaded < 2:
		loaded+= 1
	if loaded == 2:	
		_build_card_collection()	
		_load_deck()
		
	#	mouse_pointer = load(CFConst.PATH_MOUSE_POINTER).instance()
	#	mouse_pointer.priority_sort_function = "sort_index_ascending_alternate"
	#	add_child(mouse_pointer)
		
		#initial UI state
		load_page(0)
		guess_aspect_from_deck()

		resize()
		var loading_panel = get_node("%LoadingPanel")
		loading_panel.visible = false		
		loaded = 3
	
	
	
	WCUtils.large_card_preview_offset(large_picture, self, PREVIEW_CARD_SIZE)


	
	if cache_pending:
		var card_id = cache_pending.pop_back()
		create_collection_card(card_id)
		
	var screen_size = get_viewport().size/cfc.screen_scale
	for card in collection_grid.get_children():
		if card.is_animating():
			continue

		if card.position.x > screen_size.x or card.position.x < -10:
			recycle_collection_card(card)
	

func create_collection_card(card_id):
	if card_cache.has(card_id):
		return
		
	var card_data = cfc.get_card_by_id(card_id)	
	var card = cfc._instance_card(card_id)
	card.set_script(load("res://src/wc/deckbuilder/DeckBuilderCard.gd"))
	card.canonical_name = card_data["Name"]
	card.canonical_id = card_id			
	card.set_main_scene(self)
	card.set_deck_hero_id(deck_data["hero_code"])

	card_cache[card_id] = card

func display_collection_card(card_id, position_id, direction):
	if !card_cache.get(card_id, null):
		create_collection_card(card_id)
		if !card_cache.get(card_id, null):
			var _error = 1
			return	

	var card = card_cache[card_id]	
	card_cache.erase(card_id)
	collection_grid.add_child(card)
	var offset_x = 15
	var offset_y = 15
	var x = position_id % collection_grid.columns
	var y = position_id / collection_grid.columns
	x = x * CFConst.CARD_SIZE.x * COLLECTION_CARD_SCALE + offset_x
	y = y * CFConst.CARD_SIZE.y * COLLECTION_CARD_SCALE + offset_y
	card.set_state(Card.CardState.DECKBUILDER_GRID)
	card.scale =  Vector2(COLLECTION_CARD_SCALE,COLLECTION_CARD_SCALE)
	card.set_is_faceup(true,true)
	var start_x = x
	var start_y = y
	var view_size =  get_viewport().size/cfc.screen_scale
	if direction > 0:
		start_x = x + view_size.x
	elif direction < 0:
		start_x = x - view_size.x
	card.position = Vector2(start_x, start_y)
	card.set_target_position(Vector2(x, y))	
	#card._control.connect("mouse_entered", card, "gain_focus")	
	
	card._control.connect("mouse_entered", card, "gain_focus")
	card._control.connect("mouse_exited", card, "lose_focus")
	card.monitoring = true	

func hide_collection_card(card, direction):
	if !card in collection_grid.get_children():
		return
		
	var start_x = card.position.x
	var start_y = card.position.y
	var dest_x =  start_x
	var dest_y = start_y
	var view_size =  get_viewport().size/cfc.screen_scale
	if direction == 0:
		dest_y = -500
	elif direction > 0:
		dest_x = start_x - view_size.x
	elif direction < 0:
		dest_x = start_x + view_size.x
	card.position = Vector2(start_x, start_y)
	card.set_target_position(Vector2(dest_x, dest_y))			

func recycle_collection_card(card):
	if !card in collection_grid.get_children():
		return
	
	card.monitoring = false
	card._control.disconnect("mouse_entered", card, "gain_focus")
	card._control.disconnect("mouse_exited", card, "lose_focus")	
		
	collection_grid.remove_child(card)
	card_cache[card.canonical_id] = card					

func load_page(page_id, previous_page_id = -1):

	collection_left_button.disabled = (page_id == 0)
	collection_left_button.focus_mode = Control.FOCUS_ALL if page_id != 0 else Control.FOCUS_NONE
	 
	var start_index = page_id * CARDS_PER_PAGE
	if start_index > current_collection_subset.size():
		set_current_page(0)
		return
	var end_index = start_index + CARDS_PER_PAGE
	end_index = min(end_index, current_collection_subset.size())

	var direction = 0
	if previous_page_id != -1:
		#negative = move to the right
		#positive = move to the left
		direction = page_id - previous_page_id
	
	for card in collection_grid.get_children():
		hide_collection_card(card, direction)
	
	for i in range(start_index, end_index):
		display_collection_card(current_collection_subset[i], i - start_index, direction)

func set_current_page(value):
	var previous = current_page
	current_page = value
	load_page(current_page, previous)

#shortcut for cleanliness because get_focus_owner needs a control node...
func get_focus_owner():
	var focus_owner = back_button.get_focus_owner()
	if !focus_owner:
		grab_default_focus()
		focus_owner = back_button.get_focus_owner()
	return focus_owner

func guess_aspect_from_deck():
	if _deck_aspects.size() != 1:
		return
	for key in _deck_aspects:
		var aspect_filter:OptionButton = get_node("%AspectFilter")
		for i in range(aspect_filter.get_item_count()):
			if aspect_filter.get_item_text(i) == key:
				aspect_filter.select(i)
				filter_collection()
				break

func can_add_card(card):
	if !rules_enforced:
		return true	
			
	var card_id = card.canonical_id
	var currently_in_deck = deck_data["slots"].get(card_id, 0)
	
	#also need to count duplicates
	if card.get_property("duplicate_of_code"):
		currently_in_deck += deck_data["slots"].get(card.get_property("duplicate_of_code"), 0)
	for duplicate_reverse_id in cfc.reverse_duplicates.get(card_id, []):
		currently_in_deck += deck_data["slots"].get(duplicate_reverse_id, 0)
	
	if currently_in_deck > 2:
		return false
			
	if currently_in_deck>0 and card.get_property("is_unique", 0):	
		return false	

	var text = card.get_property("real_text", "").to_lower()
	
	if ("max 1 per deck" in text) and currently_in_deck > 0:
		return false
	if ("max 2 per deck" in text) and currently_in_deck > 1:
		return false			
		
	return true

func card_clicked(object):
	if object in collection_grid.get_children():
		if can_add_card(object):
			add_card_to_deck(object)
	else:
		if current_active_card:
			current_active_card.clear_highlight()
			current_active_card.deactivate_quantity_editor()
		current_active_card = object
		current_active_card.set_target_highlight(CFConst.FOCUS_COLOUR_ACTIVE)
		current_active_card.activate_quantity_editor()
	reorganize_deck()

func add_card_to_deck(card):
	var card_id = card.canonical_id
	var current = deck_data["slots"].get(card_id, 0) 
	card_quantity_changed(card, current, current+1)
	
func card_quantity_changed(card, before, after):
	var card_id = card.canonical_id
	if after == 0:
		deck_data["slots"].erase(card_id)
		card.get_parent().remove_child(card)
		$Garbage.add_child(card)
		
	else:
		if !deck_data["slots"].has(card_id):
			deck_data["slots"][card_id] = after
			var card_data = cfc.get_card_by_id(card_id)
		
			var new_card = new_deck_card(card_data)
			add_card_to_deck_container(new_card, card_data)
		else:
			deck_data["slots"][card_id] = after		

	count_deck_aspects() #is this necessary ?
	reorganize_deck()
	
func reorganize_deck():
	var total_cards = 0
	var hero_cards = 0
	var cards_by_type = {}
	var total_cost = 0
	var total_cards_counted_for_cost = 0
	for container in deck_container.get_children():
		var total_row_cards = 0
		var offset_y = 0
		for card in container.get_children():
			if card as Label:
				offset_y = card.rect_size.y + 5
				continue
			var quantity = deck_data["slots"][card.canonical_id]
			#update requird in some cases
			card.set_quantity(quantity)
			total_cards += quantity
			var type_code = card.get_property("type_code", "")
			if !cards_by_type.has(type_code):
				cards_by_type[type_code] = 0
			cards_by_type[type_code] += quantity
			 
			card.visible = true
			if type_code != "hero":
				var cost = card.get_property("cost", 0)
				if type_code !="resource" or cost > 0:
					total_cost+= cost
					total_cards_counted_for_cost += 1
				if (card.get_property("faction_code") == "hero") or (card.get_property("card_set_type_name_code") == "hero"):
					hero_cards += quantity
					if !show_hero_cards:
						quantity = 0
						card.visible = false
				
			card.set_target_position(Vector2(0, (DECK_CARD_SPACING * total_row_cards  *DECK_CARD_SCALE) + offset_y))

			if quantity > 1:
				quantity = 2
			if card == current_active_card:
				quantity = 4
			total_row_cards += quantity
			container.rect_min_size.y = (400 + DECK_CARD_SPACING * total_row_cards) *DECK_CARD_SCALE

	for container in deck_container.get_children():
		var type_code = container.name
		var label = container.get_children()[0]
		if label.text:		
			label.text = make_readable(type_code)
			#don't display number for hero
			if type_code == "hero":
				continue
			label.text += " (" +str(cards_by_type.get(type_code, 0)) +")"
			
	total_cards -=1 #removing hero card from count
	stats_label.text = "Cards in deck: " + str(total_cards) +" (" +str(hero_cards)+ " hero cards, " + str(total_cards-hero_cards) + " others)"
 
	var avg_cmc:float = stepify(float(total_cost) / float(total_cards_counted_for_cost), 0.1)
	stats_label.text += " - AVG Cost: " + str(avg_cmc)
func resize():
	var stretch_mode = cfc.get_screen_stretch_mode()

	var screen_size = get_viewport().size/cfc.screen_scale
	
	collection_grid.rect_min_size.y = (COLLECTION_CARD_SCALE * CFConst.CARD_SIZE.y * 2)
	collection_grid.rect_min_size.x = screen_size.x - 100
	
	var back_button_y = back_button.rect_global_position.y
	var lowest_point = collection_grid.rect_min_size.y + back_button_y + back_button.rect_size.y - 20
	var remaining_space = screen_size.y - lowest_point	
	deck_scroll.rect_min_size.y =  max (deck_scroll.rect_min_size.y,remaining_space)
	deck_scroll.rect_min_size.x = screen_size.x - 100
	if stretch_mode == SceneTree.STRETCH_MODE_VIEWPORT and screen_size.x > 1800:
		pass
	else:	
		pass

func show_preview(card):
	if cfc.get_setting("disable_card_images"):
		return
		#TODO support for text mode
			
	var card_id = card.canonical_id
	var card_data = cfc.get_card_by_id(card_id)
	var horizontal = card_data["_horizontal"]
	var filename = cfc.get_img_filename(card_id)	
	var new_img = WCUtils.load_img(filename)
	if not new_img:
		return	
	var imgtex = ImageTexture.new()
	imgtex.create_from_image(new_img)	
	large_picture.texture = imgtex
	large_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	# In case the generic art has been modulated, we switch it back to normal colour
	large_picture.self_modulate = Color(1,1,1)
	large_picture.visible = false
	current_hover_card = card	
	
	if horizontal:
		_preview_rotation = 90
	else:
		_preview_rotation = 0
		
	large_picture.rect_rotation = _preview_rotation	
	large_picture.rect_size = PREVIEW_CARD_SIZE	
	
	yield(get_tree().create_timer(WAIT_BEFORE_PREVIEW), "timeout")
	if !large_picture.texture:
		return
	large_picture.visible = true


func hide_preview(card):
	if current_hover_card != card:
		return
	current_hover_card = null	
	large_picture.texture = null	
	large_picture.visible = false


func save_deck():
	var id = deck_data.get("id", 0)
	if !id:
		var _error = 1
		return
	if !deck_name.text:
		deck_name.text = "New Deck"	
	deck_data["name"] = deck_name.text
	
	#we have the hero in ourd deck for convenience,
	#but it shouldn't end up in the saved data
	#we temporarily remove it before saving
	var hero_code = deck_data["hero_code"]
	var backup_hero_qty = 0
	if deck_data["slots"].has(hero_code):
			backup_hero_qty	= deck_data["slots"][hero_code]
			deck_data["slots"].erase(hero_code) 
	cfc.save_one_deck_to_file(deck_data)
	
	if backup_hero_qty:
		deck_data["slots"][hero_code] = backup_hero_qty

func _load_deck():
	deck_data = gameData.editor_deck_data
	display_deck_data()

func add_deck_row(type, index = ""):
	var container = GridContainer.new()
	container.rect_min_size = Vector2(180, 100) * DECK_CARD_SCALE
	container.name = type + index
	deck_rows.append(
		{
			"type": type,
			"container": container
		}
	)
	deck_container.add_child(container)	
	var label:Label = Label.new()
	if !index:
		label.text = make_readable(type)
	else:
		label.text = ""
	container.add_child(label)

func init_deck_container():
	if deck_container.get_children():
		return
	
	var max_types = compute_max_types()
	
	for type in ["hero", "ally", "event", "upgrade", "support",  "resource", "player_side_scheme",]:
		add_deck_row(type)
		if type in max_types:
			add_deck_row(type, "1")

var _deck_aspects := {}
func count_deck_aspects(include_hero_cards:= true, additional_rules = {}):
	_deck_aspects = {}
	var slots = deck_data["slots"]

	var types_to_exclude = additional_rules.get("exclude_card_types", [])	
	
	for card_id in slots:
		var card_data = cfc.card_definitions[card_id]
		var aspect = card_data["faction_code"]
	
		if types_to_exclude:
			var card_type = card_data["type_code"]
			if card_type in types_to_exclude:
				continue
				
		if !include_hero_cards:
			var card_set_type_name_code =card_data.get("card_set_type_name_code","")
			if card_set_type_name_code == "hero":
				continue
		var quantity = slots[card_id] 
		if aspects_dict.has(aspect) and aspect != "basic":
			if !_deck_aspects.has(aspect):
				_deck_aspects[aspect] = 0
			_deck_aspects[aspect] += quantity		
	
	return _deck_aspects
	
func new_deck_card(card_data):
	var card_id = card_data["_code"]

	var card = cfc._instance_card(card_id)
	card.set_script(load("res://src/wc/deckbuilder/DeckBuilderCard.gd"))
	card.canonical_name = card_data["Name"]
	card.canonical_id = card_id			
	card.set_main_scene(self)
	card.set_deck_hero_id(deck_data["hero_code"])
	return card

func add_card_to_deck_container(card, card_data):
	var type_code = card_data["type_code"]
	var card_id = card_data["_code"]
	var container = deck_container.get_node(type_code)
	if deck_container.has_node(type_code + "1"):
		var container2 = deck_container.get_node(type_code + "1")
		if container.get_child_count() > container2.get_child_count():
			container = container2
		
	
	var total_cards = 0
	var offset_y = 0
	for c in container.get_children():
		if c as Label:
			offset_y = c.rect_size.y + 5
			continue
		var quantity = c.get_quantity()
		if quantity > 1:
			quantity = 2
		if c == current_active_card:
			quantity = 4
		total_cards += quantity		
	
	container.add_child(card)
	
	card.position = Vector2(0, (total_cards * 40  *DECK_CARD_SCALE) + offset_y) 
	var quantity = deck_data["slots"][card_id]
	card.set_quantity(quantity)
	if quantity > 1:
		quantity = 2
	total_cards += quantity
	container.rect_min_size.y = (400 + DECK_CARD_SPACING * total_cards) *DECK_CARD_SCALE
	card.set_state(Card.CardState.DECKBUILDER_GRID)
	card.scale =  Vector2(DECK_CARD_SCALE,DECK_CARD_SCALE)
	card.set_is_faceup(true,true)
	card._control.connect("mouse_entered", card, "gain_focus")
	card._control.connect("mouse_exited", card, "lose_focus")
	card.monitoring = true
	card.connect("quantity_changed", self, "card_quantity_changed")

var _max_types_cache = []	
func compute_max_types():
	if _max_types_cache:
		return _max_types_cache
			
	var slots = deck_data.get("slots", {})
	var slots_by_type = {}
	
	for card_id in slots:
		var card_data = cfc.get_card_by_id(card_id)
		var type_code = card_data["type_code"]
		var quantity = slots[card_id]
		if quantity > 2:
			quantity = 2
			
		if !slots_by_type.has(type_code):
			slots_by_type[type_code] = 0
		
		slots_by_type[type_code] += quantity

	var sorting_list := []
	for s in slots_by_type:
		sorting_list.append({
					"type": s,
					"value": -slots_by_type[s]
				})
	sorting_list.sort_custom(CFUtils,'sort_by_card_field')
	
	_max_types_cache = []
	for i in sorting_list.size():
		_max_types_cache.append(sorting_list[i]["type"])
		#only send the max 2
		if i == 1:
			break
	return _max_types_cache

func display_deck_data():
	deck_name.text = deck_data.get("name", "")
	var slots = deck_data.get("slots", {})
	slots[deck_data["hero_code"]] =  1	
	init_deck_container()
	
	for card_id in slots:
		var card_data = cfc.get_card_by_id(card_id)
			
		var card = new_deck_card(card_data)
		add_card_to_deck_container(card, card_data)

	count_deck_aspects()
	reorganize_deck()

func _on_Menu_resized() -> void:
	resize()

const key_to_label:= {
	"player_side_scheme" : "Side Scheme"
}

func make_readable(key):
	if key_to_label.has(key):
		return key_to_label[key]
	
	return key.replace("_", " ").capitalize()


func make_filterable(readable_key):
	for key in key_to_label:
		if key_to_label[key].to_lower()==readable_key.to_lower():
			return key
			
	return readable_key.replace(" ", "_").to_lower()

#creates the collection of player cards usable for deck editing, removing duplicates, encounter cards, etc...
func _build_card_collection():
	if card_collection:
		return
	for card_id in cfc.card_definitions:
		var card_data = cfc.card_definitions[card_id]
		
		#skip encounters, hero cards, etc...
		var type_code = card_data["type_code"]
		if !(type_code in ["ally", "event", "resource", "support", "upgrade", "player_side_scheme"]):
			continue 
		var faction_code = card_data.get("faction_code", "")
		if faction_code in ["campaign", "encounter", "hero"]:
			continue
		
		var card_set_type_name_code = card_data.get("card_set_type_name_code", "")
		if card_set_type_name_code:
			continue			
			
		#skip duplicates
		var duplicate_of = card_data.get("duplicate_of_code","")
		var alternate_art = card_data.get("alternate_art",false)
		if duplicate_of and cfc.card_definitions.has(duplicate_of) and !alternate_art:
			continue
		
		var cost = card_data.get("Cost", null)
		
		types_dict[type_code] = true
		aspects_dict[faction_code] = true
		if !cost == null:
			costs_dict[str(cost)] = true
		

		
					
		cache_pending.append(card_id)
		card_collection[card_id] = card_data
		current_collection_subset.append(card_id)
		
	for key in types_dict:
		types.append(key)
	for key in aspects_dict:
		aspects.append(key)
	for key in costs_dict:
		costs.append(key)
	
	types.sort()
	aspects.sort()
	costs.sort()
	
	var aspect_filter = get_node("%AspectFilter")
	for key in aspects:
		aspect_filter.add_item(key)		
		
	var type_filter = get_node("%TypeFilter")
	for key in types:
		type_filter.add_item(make_readable(key))	
		
	var cost_filter = get_node("%CostFilter")
	for key in costs:
		cost_filter.add_item(key)					

func filter_collection(collection:= {}):
	var aspect_filter:OptionButton = get_node("%AspectFilter")	
	var type_filter:OptionButton = get_node("%TypeFilter")
	var cost_filter:OptionButton = get_node("%CostFilter")

	var aspect_idx = aspect_filter.get_selected()	
	var type_idx = type_filter.get_selected()
	var cost_idx = cost_filter.get_selected()
	
	var aspect = aspect_filter.get_item_text(aspect_idx) if aspect_idx else null
	var type = type_filter.get_item_text(type_idx) if type_idx else null
	if type:
		type = make_filterable(type)
	var cost = int(cost_filter.get_item_text(cost_idx)) if cost_idx else null
	
	current_collection_subset = []
	if !collection:
		collection = card_collection
		reset_search_text()
	for card_id in collection:
		var card_data = card_collection[card_id]

		if aspect != null:
			if card_data["faction_code"] != aspect:				
				continue

		if type != null:
			if card_data["type_code"] != type:				
				continue
						
		if cost != null:
			if card_data.get("Cost", null) != cost:	
				continue
	
		current_collection_subset.append(card_id)
	
	set_current_page(0)
	
func _on_CancelButton_pressed():
	back_to_decks()

func back_to_decks():
	self.queue_free()
	gameData.disconnect_from_network()
	get_tree().change_scene(CFConst.PATH_CUSTOM + 'deckbuilder/DeckManagement.tscn')

func final_rules_check_error():

	var hero_id = deck_data["hero_code"]
	var hero_data = cfc.card_definitions[hero_id]
	var hero_deck_requirements = hero_data.get("deck_requirements", {})
	if hero_deck_requirements:
		hero_deck_requirements = hero_deck_requirements[0]
	var count_aspects = hero_deck_requirements.get("aspects", 1)
	var quantity_limit = hero_deck_requirements.get("limit", 3)
	
	var result =""
	var slots = deck_data["slots"]
	var total_cards = 0
	var permanent_warning = ""
	var permanent_str = "(permanents and identity are not counted)\n"
	for card_id in slots:
		var card_data = cfc.card_definitions[card_id]
		var aspect = card_data["faction_code"]
		
		#permanent cards and hero are not counted for deck validity
		if card_data.get("permanent", false):
			permanent_warning = permanent_str
			continue
		if card_data["type_code"] in ["hero", "alter_ego"]:
			continue			
		var quantity = slots[card_id]
		
		if aspect!= "hero":
			if quantity > quantity_limit:
				var copy_str ="copies"
				if quantity_limit < 2:
					copy_str = "copy"
				result = "Some cards have more than " + str(quantity_limit) + " " + copy_str +"\n"
		
		total_cards+= quantity
	var additional_rules = {}
	var hero_deck_options = hero_data.get("deck_options", [])
	for deck_option in hero_deck_options:
		if typeof(deck_option) != TYPE_DICTIONARY:
			continue
		if deck_option.has("type"):
			additional_rules["exclude_card_types"] = deck_option["type"]
		
	var deck_aspects = count_deck_aspects(false, additional_rules)
	if deck_aspects.size() != count_aspects:
		var aspect_str = "aspect"
		var comparison_str = "More"
		if count_aspects > 1:
			aspect_str = "aspects"
		if deck_aspects.size() < count_aspects:
			comparison_str = "Less"
		result += comparison_str + " than " + str(count_aspects) +  " " + aspect_str + " in Deck" + "\n"
	if total_cards > 50:
		result += "More than 50 cards in Deck" + "\n" + permanent_warning
	elif total_cards < 40:	
		result += "Less than 40 cards in Deck" + "\n" + permanent_warning
	return result

func _on_DoneButton_pressed():

	var deck_error_msg = ""
	
	if rules_enforced:
		deck_error_msg = final_rules_check_error()
			
	if !deck_error_msg:
		save_confirmed()
		return
		

	var save_dialog:ConfirmationDialog = ConfirmationDialog.new()
	save_dialog.window_title = "Deck might be invalid. Save anyway?"
	save_dialog.get_ok().text = "Save anyway"
	save_dialog.set_text("Your Deck has the following issues:\n" + deck_error_msg)
	save_dialog.connect("modal_closed", self, "_decline_save")
	save_dialog.get_close_button().connect("pressed", self, "_decline_save")
	save_dialog.get_cancel().connect("pressed", self, "_decline_save")
	save_dialog.connect("confirmed", self, "save_confirmed")
	add_child(save_dialog)
	save_dialog.popup_centered()		

		


func _decline_save():
	pass
	

func save_confirmed():	
	save_deck()
	back_to_decks()

func enforce_rules(value):
	rules_enforced = value
	for container in deck_container.get_children():
		for card in container.get_children():
			card.enforce_deckbuilding_rules(value)

func _on_EnforceRulesButton_toggled(button_pressed):
	enforce_rules(button_pressed)


func _on_CollectionLeftButton_pressed():
	if !current_page:
		return
	set_current_page(current_page - 1)


func _on_CollectionRightButton_pressed():
	set_current_page(current_page + 1)

func set_show_hero_cards(value):
	show_hero_cards = value
	reorganize_deck()

func _on_ShowHeroCards_toggled(button_pressed):
	set_show_hero_cards(button_pressed)


func _on_AspectFilter_item_selected(index):
	filter_collection()


func _on_TypeFilter_item_selected(index):
	filter_collection()


func _on_CostFilter_item_selected(index):
	filter_collection()


func _on_Search_focus_entered():
	var node = get_node("%Search")
	if node.text in ["search...", "No results :("]:
		node.text = ""

func reset_search_text():
	var node = get_node("%Search")
	node.text = "search..."

func _on_Search_focus_exited():
	var node = get_node("%Search")
	if node.text =="":	
		reset_search_text()

func search_cards(text):
	var result = {}
	var to_search = text.to_lower()
	for card_id in card_collection:
		var card_data = card_collection[card_id]
		for key in ["text", "name", "subname", "traits"]:
			var lc_txt = card_data.get(key, "").to_lower()
			if to_search in lc_txt:
				result[card_id] = card_data
				break
	if result:
		filter_collection(result)
	else:
		var node = get_node("%Search")
		node.text = "No results :("
			

func _on_SearchButton_pressed():
	var node = get_node("%Search")
	if node.text.length() < 3:	
		reset_search_text()
		return
	if node.text in ["search...", "No results :("]:
		return
	search_cards(node.text)	


func _on_Search_text_entered(new_text):
	_on_SearchButton_pressed()
