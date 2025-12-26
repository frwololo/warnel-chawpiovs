extends MarginContainer

onready var control = get_parent()
onready var owner_card = get_parent().get_parent()
var title:Label

#TODO this should move to an external config file
# to accomodate different renderings
var icons_by_type_code : = {
	"hero" : {
		"thwart" : [-2, 40], 
		"attack" :  [-2,80], 
		"defense" :  [-2,120], 
	},
	"alter_ego": {
		"recover":  [-2,40], 
	},
	"ally": {
		"thwart" :  [-2,52],  
		"attack" :  [-2,110], 
		"health" :  [150,154], 
	},
	"minion": {
		"scheme" :  [-2,42],  
		"attack" :  [-2,80], 
		"health" :  [153,141], 		
	},
	"villain": {
		"scheme" :  [-2,42],  
		"attack" :  [-2,80], 

	}			
}


var default_font_offset = Vector2(4, 4)

var font_offset_by_icon:= {
	"health": Vector2(-5, 0)				
}

var offsets_by_type_code : = {
	"ally": {
		"scale" : 1.06, 
		"x": 1
	}
}


var cache_dynamic_font = null
var icons = []
var icons_initialized = false
var show_icons = false
# Called when the node enters the scene tree for the first time.

func _init():
	pass

func _ready():
	reinit_children()
	owner_card.connect("state_changed", self, "owner_state_changed")
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

func owner_state_changed(_card, _before, _after):
	update_state()

func update_state():
	if !owner_card.state in [Card.CardState.PREVIEW, Card.CardState.DECKBUILDER_GRID, Card.CardState.VIEWPORT_FOCUS, Card.CardState.ON_PLAY_BOARD,Card.CardState.FOCUSED_ON_BOARD, Card.CardState.DROPPING_TO_BOARD]:
		show_icons = false
		return
	if owner_card.state  == Card.CardState.VIEWPORT_FOCUS:
		var origin = cfc.NMAP.main.get_origin_card(owner_card)
		if !origin or !is_instance_valid(origin) or !origin.is_onboard():
			show_icons = false
			return	

	show_icons = true

func _process(_delta):
	if !show_icons:
		self.visible = false
		return	
	if !icons_initialized:
		set_icons()
		self.visible = false
		return
	if !icons:
		self.visible = false
		return

	#if we're on a low fps machine,
	#reduce calls to this function
	if cfc.throttle_process_for_performance():
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
			child.rect_position = (Vector2(x, y) + Vector2(offset_x, offset_y)) * owner_card.card_size / CFConst.CARD_SIZE
			child.rect_scale = Vector2(0.15, 0.15) * offset_scale * owner_card.card_size / CFConst.CARD_SIZE
			var text = data_source.get_property(icon)
			if text:
				text = str(text)
			else:
				var can = data_source.get_property("can_" + icon, false)
				text = "0" if can else "-"
				
			var label = get_node("label_" + icon)
			var shadow = get_node("shadow_" + icon)			
			label.text = text
			shadow.text = text	
			var size = Vector2(label.rect_size.x, 0)
			
			label.rect_scale = Vector2(0.75, 0.75) *  offset_scale *owner_card.card_size / CFConst.CARD_SIZE
			var font_offset = font_offset_by_icon.get(icon, default_font_offset)
			label.rect_position = child.rect_position + Vector2((child.rect_size.x * child.rect_scale.x) / 2, 0) - (size * label.rect_scale)  + (font_offset * label.rect_scale)#child.rect_position
			
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


