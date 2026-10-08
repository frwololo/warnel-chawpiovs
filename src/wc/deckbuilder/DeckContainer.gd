class_name DeckContainer
extends Control

signal resize_done(new_size)

const DECK_CARD_SCALE = 1.12
const WAIT_BEFORE_PREVIEW = 0.7
const PREVIEW_CARD_SIZE = Vector2(450, 630)
const DECK_CARD_SPACING = 40
const MIN_SIZE_Y = 250

const aspects_dict := {}
const types_dict := {}
const costs_dict := {}
const card_cache := {}
const connections := {}

const aspects := []
const types := []
const costs := []

#key: card_id, value: quantity
var deck_data := {}
var deck_name := ""
var hero_code := ""
var deck_rows:= []

var _preview_rotation = 0
var current_hover_card = null
var current_active_card = null
var show_hero_cards = true
var can_add_cards = true
var loaded = 0
var max_size:= Vector2(0, 0)
var global_scale:= 1.0

var show_headers = false
var show_hero_card = true
var scrollable = true
var columns = 9
var _max_types_cache = []	
var _all_types_cache = {}

#GUI elements
onready var large_picture = get_node("%LargePicture")
onready var stats_label = get_node("%DeckStatsLabel")
onready var deck_container := get_node("%DeckRows")
onready var deck_name_label := get_node("%DeckName")
onready var info_container := get_node("%InfoContainer")
onready var deck_scroll := get_node("%ScrollContainer")

# Called when the node enters the scene tree for the first time.
func _ready():
	$Garbage.visible = false
	hide_deck_info()
	pass # Replace with function body.




func _process(_delta:float):
	if !loaded:
		return
		
	if loaded < 2:
		loaded+= 1
		return
		
	if loaded == 2:	
		display_deck_data()

		resize()
		loaded = 3
	
	
	
	WCUtils.large_card_preview_offset(large_picture, self, PREVIEW_CARD_SIZE)

func setup(settings := {}):

	$DeckContainer.add_constant_override("margin_top", 0)	
	$DeckContainer.add_constant_override("margin_left", 0)	
	for key in settings:
		match key:
			"show_deck_info":
				if settings[key]:
					show_deck_info()
				else:
					hide_deck_info()
			"show_headers":
				show_headers = settings[key]
			"show_hero":
				show_hero_card = settings[key]
			"columns":
				columns = settings[key]
			"scrollable":
				scrollable = settings[key]
			"can_add_cards":
				can_add_cards = settings[key]	
			"max_size_x":
				max_size.x = settings[key]	
			"max_size_y":
				max_size.y = settings[key]
			"margin_top":
				$DeckContainer.add_constant_override("margin_top", settings[key])
			"margin_left":
				$DeckContainer.add_constant_override("margin_left", settings[key])	
				
	set_max_size(max_size)												

func reset():
	deck_data = {}
	deck_name = ""
	hero_code = ""
	deck_rows = []
	loaded = 0
	_max_types_cache = []	
	_all_types_cache = {}	
	
	for container in deck_container.get_children():
		for object in container.get_children():
			if object as Card:
				#we don't delete cards, they stay in the cache
				var card_id = object.canonical_id
				container.remove_child(object)
				$Garbage.add_child(object)
				if !card_cache.has(card_id):
					card_cache[card_id] = []
				card_cache[card_id].append(object)
					
		deck_container.remove_child(container)
		$Garbage.add_child(container)
		container.queue_free()

		
	resize(Vector2(0,0))	

func hide_deck_info():
	info_container.visible = false

func show_deck_info():
	info_container.visible = true

func set_max_size(new_size):
	max_size = new_size
	#TODO no magic number
	var expected_size = Vector2(1800, 500)
	
	var scale = max_size / expected_size
	global_scale = min(scale.x, scale.y)
	var _tmp = 1


func resize(_target_size = max_size):

	if !scrollable and deck_scroll.visible:
		deck_scroll.remove_child(deck_container)
		get_node("%VBoxContainer").add_child(deck_container)
		deck_scroll.visible = false

	var target_size = _target_size
	var actual_size = deck_container.rect_size
	var target_size_x = min(target_size.x, actual_size.x)
	var target_size_y = min(target_size.y, actual_size.y)
	target_size.x = target_size_x
	target_size.y = target_size_y
	
	deck_scroll.rect_min_size = target_size
	deck_scroll.rect_size = deck_scroll.rect_min_size
	deck_container.rect_min_size = target_size
	deck_container.rect_size = deck_container.rect_min_size
	
	self.rect_min_size = deck_container.rect_min_size
	self.rect_size = self.rect_min_size
	var _tmp = self.rect_size
	var new_size = deck_container.rect_size

#	var style_box = StyleBoxFlat.new()
#	style_box.border_color = Color(0.9, 0.9, 0.9) # Set border color
#	style_box.bg_color = Color(0, 0, 0) # Set border color
#	style_box.corner_radius_top_left = 10
#	style_box.corner_radius_top_right = 10
#	style_box.corner_radius_bottom_left = 10
#	style_box.corner_radius_bottom_right = 10
#	style_box.set_border_width_all(5)
#
#	get_node("%PanelContainer").add_stylebox_override("panel", style_box)
#
	emit_signal("resize_done", new_size)
	
func load_cards(deck_info):
	if deck_info.has("slots"):
		deck_data = deck_info["slots"].duplicate()
		deck_name = deck_info.get("name", "")
		hero_code = deck_info.get("hero_code", "")
	else:
		#TODO
		pass
	loaded = 1
	
func remove_card():
	pass

func add_card():
	pass
func rescale():
	pass

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
				if show_headers:
					offset_y = card.rect_size.y + 5
				continue
			var quantity = deck_data[card.canonical_id]
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
				
			card.set_target_position(Vector2(0, (DECK_CARD_SPACING * total_row_cards  * DECK_CARD_SCALE * global_scale) + offset_y))

			if quantity > 1:
				quantity = 2
			if card == current_active_card:
				quantity = 4
			total_row_cards += quantity
			container.rect_min_size.y = (MIN_SIZE_Y+ DECK_CARD_SPACING * total_row_cards) *DECK_CARD_SCALE * global_scale

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


func compute_max_types():
	if _max_types_cache:
		return _max_types_cache
			
	var slots = deck_data
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

	_all_types_cache = slots_by_type
	
	var sorting_list := []
	for s in slots_by_type:
		sorting_list.append({
					"type": s,
					"value": -slots_by_type[s]
				})
	sorting_list.sort_custom(CFUtils,'sort_by_card_field')
	
	_max_types_cache = []
	for i in sorting_list.size():
		_max_types_cache.append(sorting_list[i])
	return _max_types_cache


func display_deck_data():
	if !deck_name_label:
		return
		
	deck_name_label.text = deck_name
	var slots = deck_data
	slots[hero_code] = 1	
	init_deck_container()
	
	for card_id in slots:
		var card_data = cfc.get_card_by_id(card_id)
			
		var card = new_deck_card(card_data)
		add_card_to_deck_container(card, card_data)

	count_deck_aspects()
	reorganize_deck()

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

func get_card_from_cache(card_data):
	var card_id = card_data["_code"]	
	if !card_cache.has(card_id):
		card_cache[card_id] = []
	
	if !card_cache[card_id]:		
		var card = cfc._instance_card(card_id)
		card.set_script(load("res://src/wc/deckbuilder/DeckBuilderCard.gd"))
		card.canonical_name = card_data["Name"]
		card.canonical_id = card_id			
		card_cache[card_id].append(card)
	
	var card = card_cache[card_id].pop_back()
	card.set_main_scene(self)

			
	if card.get_parent():
		card.get_parent().remove_child(card)
	return card
	
func new_deck_card(card_data):
	var card = get_card_from_cache(card_data)
	card.set_deck_hero_id(hero_code)
	return card

func add_card_to_deck(card):
	var card_id = card.canonical_id
	var current = deck_data.get(card_id, 0) 
	card_quantity_changed(card, current, current+1)
	
func card_quantity_changed(card, _before, after):
	var card_id = card.canonical_id
	if after == 0:
		deck_data.erase(card_id)
		card.get_parent().remove_child(card)
		$Garbage.add_child(card)
		
	else:
		if !deck_data.has(card_id):
			deck_data[card_id] = after
			var card_data = cfc.get_card_by_id(card_id)
		
			var new_card = new_deck_card(card_data)
			add_card_to_deck_container(new_card, card_data)
		else:
			deck_data[card_id] = after		

	count_deck_aspects() #is this necessary ?
	reorganize_deck()

func add_card_to_deck_container(card, card_data):
	var type_code = card_data["type_code"]
	var card_id = card_data["_code"]
	if !deck_container.has_node(type_code):
		return

	var container = deck_container.get_node(type_code)
	var found = 1
	while found:
		var next_container = type_code + str(found)
		if deck_container.has_node(next_container):
			var container2 = deck_container.get_node(next_container)
			if container.get_child_count() > container2.get_child_count():
				container = container2
				found += 1
			else:
				found = 0
		else:
			found = 0
		
	
	var total_cards = 0
	var offset_y = 0
	for c in container.get_children():
		if c as Label:
			if show_headers:
				offset_y = c.rect_size.y + 5
			continue
		var quantity = c.get_quantity()
		if quantity > 1:
			quantity = 2
		if c == current_active_card:
			quantity = 4
		total_cards += quantity		
	
	container.add_child(card)
	
	card.position = Vector2(0, (total_cards * 40  *DECK_CARD_SCALE * global_scale) + offset_y) 
	var quantity = deck_data[card_id]
	card.set_quantity(quantity)
	if quantity > 1:
		quantity = 2
	total_cards += quantity
	container.rect_min_size.y = (MIN_SIZE_Y + DECK_CARD_SPACING * total_cards) *DECK_CARD_SCALE * global_scale
	card.set_state(Card.CardState.DECKBUILDER_GRID)
	card.scale =  Vector2(DECK_CARD_SCALE,DECK_CARD_SCALE) * global_scale
	card.set_is_faceup(true,true)

	card.monitoring = true
	if !connections.has(card):
		card._control.connect("mouse_entered", card, "gain_focus")
		card._control.connect("mouse_exited", card, "lose_focus")
		connections[card] = true
		
	if can_add_cards:
		card.connect("quantity_changed", self, "card_quantity_changed")

var _deck_aspects := {}
func count_deck_aspects(include_hero_cards:= true, additional_rules = {}):
	_deck_aspects = {}
	var slots = deck_data

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
	
func init_deck_container():
	if deck_container.get_children():
		return
	
	var max_types_data = compute_max_types()
	
	var all_types = ["ally", "event", "upgrade", "support",  "resource", "player_side_scheme",]
	var types = all_types.duplicate()
	if !can_add_cards:
		types = []
		for type in all_types:
			if _all_types_cache.has(type):
				types.append(type)
	if show_hero_card:
		types = ["hero"] + types

	var max_to_compute = columns - types.size()
	var max_types = max_types_data.slice(0, max_to_compute - 1)
	var count_types = {}
	for i in types:
		count_types[i] = 1
	
	for value in max_types:
		count_types[value["type"]] = 2	
	for i in max_types.size()/2:
		var big = max_types[i]
		var small = max_types[max_types.size() - 1 -i]
		var big_value = -big["value"]
		var small_value = -small["value"]
		if (big_value / 2) > small_value:
			count_types[big["type"]] = 3
			count_types[small["type"]] = 1
		else:
			count_types[big["type"]] = 2
			count_types[small["type"]] = 2		
	
	for type in types:
		var count = count_types.get(type,0)
		for i in count:
			if i:
				add_deck_row(type + str(i))
			else:	
				add_deck_row(type)
			
func add_deck_row(type, index = ""):
	var container = GridContainer.new()
	container.rect_min_size = Vector2(180, 100) * DECK_CARD_SCALE * global_scale
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
	if !show_headers:
		label.visible = false	
	
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

func can_add_card(_object):
	return true

func card_clicked(_object):
	pass
