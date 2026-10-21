class_name CompactDeckContainer
extends Control


const RESOURCE_TO_ICON = {
	"physical":"resource_red.png",
	"mental": "resource_blue.png",
	"wild": "resource_green.png",
	"energy": "resource_yellow.png"
		
}

#vars
onready var cards_container := get_node("%CardsContainer")
onready var left_container := get_node("%LeftContainer")
onready var right_container := get_node("%RightContainer")
onready var large_picture :TextureRect= get_node("%LargePicture")
onready var deck_name: = get_node("%DeckName")
onready var deck_stats = get_node("%DeckStatsLabel")

var deck_data: HeroDeckData = null
var init_done = false
var current_hover_card = ""
# Called when the node enters the scene tree for the first time.
func _ready():
	#todo enable these features
	deck_name.visible = false
	deck_stats.visible = false
	
	init_cards()

func _process(_delta):
	WCUtils.large_card_preview_offset(large_picture, self)	


func init_cards():
	if !deck_data:
		return
	if init_done: 
		return
	
	for container in [cards_container, left_container, right_container]:
		for c in container.get_children():
			container.remove_child(c)	
		
	var cards_by_type = deck_data.get_cards_by_type(true)	

	var sorting_list = []
	for type in cards_by_type:
		if type in ["hero"]:
			#will go in the generic list at the top
			continue
		sorting_list.append({
			"type": type,
			"value": -cards_by_type[type].size()
		})
	sorting_list.sort_custom(CFUtils,'sort_by_card_field')
	var lefts = []
	var rights = []
	
	var left = true
	for i in sorting_list.size():
		if left:
			lefts.append(sorting_list[i]["type"])
		else:
			rights.append(sorting_list[i]["type"])
		left = !left

	
	for type in HeroDeckData.ORDERED_PLAYER_TYPES:
		if cards_by_type.has(type):
			var type_label:Label = Label.new()
			type_label.text = type.capitalize()
			var my_container = cards_container
			if rights.has(type):
				my_container = right_container
			elif lefts.has(type):
				my_container = left_container
			
			my_container.add_child(type_label)
			
			for card_code in cards_by_type[type]:
				var hbox = HBoxContainer.new()
				var quantity = cards_by_type[type][card_code]
				var card_data = cfc.get_card_by_id(card_code)
				var card_name = WCUtils.get_translated_property(card_code, "Name")
				var label:Label = Label.new()
				label.name = "card_" + card_code
				label.mouse_filter = Control.MOUSE_FILTER_STOP
				label.connect("mouse_entered", self, "label_entered", [label.name])
				label.connect("mouse_exited", self, "label_exited", [label.name])
				label.text = "  " + str(quantity) + "x " + card_name.capitalize() 
				hbox.add_child(label)
				var icons = compute_resources(card_data)
				var rightbox = HBoxContainer.new()
				for icon in icons:
					rightbox.add_child(icon)
					icon.rect_min_size = Vector2(15,15)	
					icon.rect_size = icon.rect_min_size
					icon.expand = true	
					icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED				
				hbox.add_child(rightbox)
				my_container.add_child(hbox)			
	init_done = true

func compute_resources(card_data):
	var result = []
	var resources = ["physical", "mental", "energy", "wild"]
	for resource in resources:
		var property = "resource_" + resource
		var quantity = card_data.get(property, 0)
		for i in quantity:
			var img_name = RESOURCE_TO_ICON[resource] 

			var textrect : TextureRect = TextureRect.new()
			var new_texture = ImageTexture.new();
			var tex = load(CFConst.PATH_ASSETS + "icons/" + img_name)
			var image = tex.get_data()
			new_texture.create_from_image(image)
			textrect.texture = new_texture
			result.append(textrect)
	return result

func label_entered(label_name):
	if !label_name.begins_with("card_"):
		return
	var code = label_name.replace("card_", "")
	show_preview(code)

func label_exited(label_name):
	if !label_name.begins_with("card_"):
		return
	var code = label_name.replace("card_", "")
	hide_preview(code)

func load_deck_data(_deck_data):
	if !deck_data:
		deck_data = HeroDeckData.new()
	deck_data.set_deck_data(_deck_data)
	init_cards()

func show_preview(card_id):
	current_hover_card = card_id	
	WCUtils.show_preview(card_id, large_picture)	


func add_card(card_id):
	init_done = false
	deck_data.add_card(card_id)
	init_cards()

func count_cards():
	var all_cards = deck_data.get_deck_cards()
	return all_cards.size()	

func save_deck():
	DeckEdit.save_player_deck(deck_data.deck_data)

func hide_preview(card_id):
	if current_hover_card != card_id:
		return
	current_hover_card = ""	
	large_picture.texture = null	
	large_picture.visible = false		

func get_deck_data():
	return deck_data.deck_data
