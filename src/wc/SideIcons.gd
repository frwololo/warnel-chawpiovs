extends MarginContainer

onready var control = get_parent()
onready var owner_card = get_parent().get_parent()

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
# Called when the node enters the scene tree for the first time.

func _init():
	pass

func _ready():
	reinit_children()	

func init_font() -> DynamicFont:
	if cache_dynamic_font:
		return cache_dynamic_font
	cache_dynamic_font = DynamicFont.new()
	cache_dynamic_font.font_data = load("res://fonts/Bangers-Regular.ttf")
	cache_dynamic_font.size = 32
	cache_dynamic_font.set_use_filter(true)
	return cache_dynamic_font

func reinit_children():
	for child in get_children():
		child.queue_free()
		remove_child(child)

func set_icons():
	reinit_children()
	
	icons = icons_by_type_code.get(owner_card.get_property("type_code", ""), {})
	
		
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

			var dynamic_font = init_font()
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


func _process(delta):
	if !owner_card.state in [Card.CardState.PREVIEW, Card.CardState.DECKBUILDER_GRID, Card.CardState.VIEWPORT_FOCUS, Card.CardState.ON_PLAY_BOARD,Card.CardState.FOCUSED_ON_BOARD, Card.CardState.DROPPING_TO_BOARD]:
		reinit_children()
		return
		
	if !icons:
		set_icons()
	for icon in icons:
		var offset_data = offsets_by_type_code.get(owner_card.get_property("type_code", ""), {})		
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
			var text = owner_card.get_property(icon)
			if text:
				text = str(text)
			else:
				var can = owner_card.get_property("can_" + icon, false)
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
		
		pass
# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass


