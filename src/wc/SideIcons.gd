# warning-ignore:return_value_discarded
class_name SideIcons
extends Node2D

onready var control = get_parent()
onready var owner_card = get_parent().get_parent()
var title:Label

#TODO this should move to an external config file
# to accomodate different renderings
var icons_by_type_code : = {
	"hero" : {
		"thwart" : [0, 34], 
		"attack" :  [0,74.5], 
		"defense" :  [0,114.5],
		"heart": [0, 155],
	},
	"alter_ego": {
		"recover":  [0,34],	
		"heart": [0, 145],
		 
	},
	"ally": {
		"thwart" :  [0,45],  
		"attack" :  [0,103], 
		"health" :  [150,154,28,28], 
	},
	"minion": {
		"scheme" :  [0,38],  
		"attack" :  [0,75], 
		"health" :  [153,141,28,28], 		
	},
	"villain": {
		"scheme" :  [0,38],  
		"attack" :  [0,74.5], 
		"heart": [0, 145],
	}			
}

var icons_to_property: = {
	"heart": {"func_name": "get_remaining_damage"}
}

var default_font_offset = Vector2(-2, 10)

var font_offset_by_icon:= {
	"health": Vector2(-5, 0),
	"heart": Vector2(-2, 5)					
}

var offsets_by_type_code : = {
	"ally": {
		"scale" : 1.15, 
		"x": 0
	}
}


var cache_dynamic_font = null
var icons = []
var icons_initialized = false
var show_icons = false
var _refresh_icon_passes = 0
# Called when the node enters the scene tree for the first time.

func _init():
	pass

func _ready():
	reinit_children()
	owner_card.connect("state_changed", self, "owner_state_changed")
	# warning-ignore:return_value_discarded
	scripting_bus.connect("card_moved_to_board", self, "_card_moved_to_board")
	update_state()
	
func init_font() -> DynamicFont:
	if cache_dynamic_font:
		return cache_dynamic_font
	cache_dynamic_font = cfc.get_font("res://fonts/Bangers-Regular.ttf", 32)
	return cache_dynamic_font

func reinit_children():
	for child in get_children():
		child.queue_free()
		remove_child(child)
	icons = []
	icons_initialized = false
	self.visible = false		

func set_icons():
	reinit_children()
	self.visible = false
	icons = icons_by_type_code.get(owner_card.get_property("type_code", ""), {})

	if !icons:
		icons_initialized = true
		return

	title = Label.new()
	var dynamic_font = init_font()	
	title.add_font_override("font", dynamic_font)
	title.set_h_size_flags(Control.SIZE_SHRINK_CENTER)
	add_child(title)
		
	for icon in icons:
		var textrect: TextureRect = TextureRect.new()
		var new_texture = ImageTexture.new()
		var img_path = CFConst.PATH_ASSETS + "icons/" + icon  + ".png"
		var tex = load(img_path)
		if tex:		
			var image = tex.get_data()
			new_texture.create_from_image(image)
			textrect.texture = new_texture
			textrect.name = "texture_" + icon
			textrect.expand = true
			textrect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			#textrect.rect_position = Vector2(0, y_positions[icon])
			#textrect.rect_size = Vector2(20, 20)
			add_child(textrect)	


			var label_shadow = Label.new()
			label_shadow.add_font_override("font", dynamic_font)
			label_shadow.add_color_override("font_color", Color8(0, 0, 0))
			label_shadow.name = "shadow_" + icon
			add_child(label_shadow )	
			
			var label:Label = Label.new()
			label.add_font_override("font", dynamic_font)
			label.name = "label_" + icon
			label.set_h_size_flags(Control.SIZE_SHRINK_CENTER)
			add_child(label)

	icons_initialized = true

#when my card owner moves to board, I'm resetting everything
func _card_moved_to_board(card, _details):
	var origin = owner_card
	
	if owner_card.state  == Card.CardState.VIEWPORT_FOCUS:
		origin = cfc.NMAP.main.get_origin_card(owner_card)
	
	if card != origin:
		return
	
	reinit_children()	
	

func owner_state_changed(_card, _before, _after):
	update_state()

func update_state(forced = false):
	var previous_show_icons = show_icons

	show_icons = true
	if !owner_card.state in [Card.CardState.PREVIEW, Card.CardState.DECKBUILDER_GRID, Card.CardState.VIEWPORT_FOCUS, Card.CardState.ON_PLAY_BOARD,Card.CardState.FOCUSED_ON_BOARD, Card.CardState.DROPPING_TO_BOARD]:
		show_icons = false
	elif owner_card.state  == Card.CardState.VIEWPORT_FOCUS:
		var origin = cfc.NMAP.main.get_origin_card(owner_card)
		if !origin or !is_instance_valid(origin) or !origin.is_onboard():
			show_icons = false

	if forced or (show_icons != previous_show_icons):
		#two iterations of _process are needed to take into account scale changes of some items...
		_refresh_icon_passes = 2

func _process(_delta):
	if cfc.throttle_process_for_performance():
		return
	
	#don't update if something else is going on,
	#we'll wait for idle time
	if gameData.gui_activity_ongoing():
		return
	
	if _refresh_icon_passes:
		display_icons()
		_refresh_icon_passes -= 1
	pass
	
func display_icons():
	if !show_icons:
		self.visible = false
		return	
	if !icons_initialized:
		set_icons()
	if !icons:
		self.visible = false
		return

	var data_source = owner_card 
	if owner_card.state  == Card.CardState.VIEWPORT_FOCUS:
		data_source = cfc.NMAP.main.get_origin_card(owner_card)
	if !data_source or ! is_instance_valid(data_source):
		self.visible = false
		return

	
	
	if !data_source.is_faceup:
		title.text = data_source.get_display_name()
		title.rect_position = Vector2(control.rect_size.x/2 - title.rect_size.x/2, 10) # * owner_card.card_size / CFConst.CARD_SIZE
		title.rect_scale =  owner_card.card_size / CFConst.CARD_SIZE	
	for icon in icons:
		var offset_data = offsets_by_type_code.get(data_source.get_property("type_code", ""), {})		
		var offset_y = offset_data.get("y", 0)
		var offset_x = offset_data.get("x", 0)		
		var offset_scale = offset_data.get("scale", 1)
		var child = get_node("texture_" + icon)
		if child:
			var x_y = icons[icon]
			var x = x_y[0]
			var y = x_y[1] 
			var texture_size = Vector2(38, 38)
			if x_y.size()> 2:
				texture_size.x = x_y[2]
				texture_size.y = x_y[3]
			
			child.rect_position = (Vector2(x, y) + Vector2(offset_x, offset_y)) * owner_card.card_size / CFConst.CARD_SIZE
			#child.rect_scale = Vector2(0.15, 0.15) * offset_scale * owner_card.card_size / CFConst.CARD_SIZE
			child.rect_min_size =  texture_size * offset_scale * owner_card.card_size / CFConst.CARD_SIZE
			child.rect_size = child.rect_min_size
			var property = icons_to_property.get(icon, icon)
			var text = ""
			match typeof(property):
				TYPE_STRING:
					text = data_source.get_property(property)
				TYPE_DICTIONARY:
					if property.has("func_name"):
						var params = property.get("func_params", {})
						text = cfc.ov_utils.func_name_run(data_source, property["func_name"], params)
	
			if text:
				text = str(text)
			else:
				var can = data_source.get_property("can_" + property, false)
				text = "0" if can else "-"
				
			var label = get_node("label_" + icon)
			var shadow = get_node("shadow_" + icon)			
			label.text = text
			shadow.text = text	
			
			#label.rect_min_size = Vector2(10, 10) *  offset_scale *owner_card.card_size / CFConst.CARD_SIZE
			label.rect_scale = Vector2(0.75, 0.75) *  offset_scale *owner_card.card_size / CFConst.CARD_SIZE
			var font_offset = font_offset_by_icon.get(icon, default_font_offset)
			label.rect_position.x = child.rect_position.x  + child.rect_size.x*child.rect_scale.x / 2  - label.rect_size.x*label.rect_scale.x/2 + (font_offset.x * label.rect_scale.x)#child.rect_position
			label.rect_position.y = child.rect_position.y + (font_offset * label.rect_scale).y
			#shadow.rect_min_size = label.rect_min_size 
			shadow.rect_scale = label.rect_scale
			shadow.rect_position = label.rect_position + (Vector2(3,3) * label.rect_scale)#child.rect_position
		else:
			#bug ?
			show_icons = false
			set_icons()
		
		if show_icons:
			self.visible = true
		else:
			self.visible = false	
		pass


