class_name Announce
extends Container

onready var top_text = $Top/Margin/Label
onready var bottom_text = $Bottom/Margin/Label
onready var top_color = $Top/ColorRect
onready var bottom_color = $Bottom/ColorRect
onready var bg_color = $ColorRect
onready var top_texture = $Top/TextureRect
onready var bottom_texture = $Bottom/TextureRect
onready var top = $Top
onready var bottom = $Bottom

enum ANIMATION_STYLE {
	DEFAULT,
	SPEED_OUT
}

var _top_text := ""
var _bottom_text:= ""
var _top_texture_filename := ""
var _bottom_texture_filename:= ""
var _top_color:= Color8(50, 50, 50, 255)
var _bottom_color := Color8(18, 18, 18, 255)
var _bg_color := Color8(255,255,255,75)
var delta_max := 3.0
var bottom_target_x_offset = 0
var delta_total: float = 0
var _animation_style = ANIMATION_STYLE.DEFAULT
var ongoing = true
var fade_duration := 0.5

func fade(object, modulation):
	if "modulate" in object:
		object.modulate.a = modulation
	for child in object.get_children():
		fade(child, modulation)

func set_animation_style(style):
	_animation_style = style

func fade_in_out():
	if fade_duration <=0:
		self.fade(self, 1)
		return
		
	if delta_total <= fade_duration:
		var modulation = log(1 + (exp(1)-1) * delta_total/fade_duration)
		self.fade(self, modulation)
		return
		
	if delta_max-delta_total <= fade_duration:
		var modulation = log(1 + (exp(1)-1) * (delta_max-delta_total)/fade_duration)
		self.fade(self, modulation	)	
		return
		
	self.fade(self, 1)
		
func _process(delta):
	delta_total+=delta
	
	if delta_total >delta_max:
		ongoing = false
		return

	self.rect_position = get_viewport().size/2 - rect_scale*self.rect_size/2

	match _animation_style:
		ANIMATION_STYLE.DEFAULT:
#			var square = (delta_max/2 - delta_total) /(delta_max/2)
#			square = square *square 	
#			var modulation = 1 - square 
#			self.fade(self, modulation)
			fade_in_out()
			
			var current_point = (exp(-delta_total*2)-exp(-delta_max*2))/(1 -exp(-delta_max*2))
			var target_x_multiplier = 0.4 *(1- current_point) + 0.2 
			var pos_top_x_end = rect_size.x * target_x_multiplier
			var pos_top_x = pos_top_x_end - top.rect_size.x
			var pos_bottom_x = rect_size.x  - pos_top_x_end  + bottom_target_x_offset	
			
			top.rect_position = Vector2(pos_top_x , top.rect_position.y)
			bottom.rect_position = Vector2(pos_bottom_x, bottom.rect_position.y)
		ANIMATION_STYLE.SPEED_OUT:
#			var square = (delta_max/2 - delta_total) /(delta_max/2)
#			square = square *square 	
#			var modulation = 1 - square 
#			self.fade(self, modulation)
			fade_in_out()
			
			var current_point = 0
			var target_x_multiplier = 0
			if (delta_total < delta_max/2):
				current_point = (exp(-delta_total*4)-exp(-delta_max*2))/(1 -exp(-delta_max*2))
				target_x_multiplier = 0.4 *(1- current_point) + 0.2
			else:
				var temp_delta = delta_max - delta_total
				current_point =  (exp(-temp_delta*4)-exp(-delta_max*2))/(1 -exp(-delta_max*2))
				target_x_multiplier = 0.4 *(1+ current_point) + 0.2
			
			var pos_top_x_end = rect_size.x * target_x_multiplier
			var pos_top_x = pos_top_x_end - top.rect_size.x
			var pos_bottom_x = rect_size.x  - pos_top_x_end  + bottom_target_x_offset	
			
			top.rect_position = Vector2(pos_top_x , top.rect_position.y)
			bottom.rect_position = Vector2(pos_bottom_x, bottom.rect_position.y)			
			

func _ready():
	top_text.text = _top_text
	bottom_text.text = _bottom_text
	top_color.color = _top_color
	bottom_color.color = _bottom_color
	bg_color.color = _bg_color
	load_texture(top_texture, _top_texture_filename)
	load_texture(bottom_texture, _bottom_texture_filename)	
	self.fade(self, 0)
	self.rect_position = get_viewport().size/2 - self.rect_size/2
	#set_scale(0.5)
	#set_bg_color(Color(0,0,0,0))

func set_bg_color(color):
	_bg_color = color
	if bg_color:
		bg_color.color = _bg_color

func set_bg_colors(_top, _bottom):
	_top_color = _top
	_bottom_color = _bottom
	if top_color:
		top_color.color = _top_color
	if bottom_color:
		bottom_color.color = _bottom_color			
	
func set_text_top(text):
	_top_text = text
	if top_text:
		top_text.text = _top_text

func set_text_bottom(text):
	_bottom_text = text
	if bottom_text:
		bottom_text.text = _bottom_text
	
func set_text(text:String):
	var half_size = int(text.length()/2)
	var left_string = text.substr(0, half_size)

	var right = text.find(" ", half_size)
	var left = left_string.rfind(" ")
	
	var found = left
	if right-half_size < left_string.length()-left:
		found = right
	
	var left_text = text.substr(0, found)
	var right_text = text.substr(found)
	set_text_top(left_text)
	set_text_bottom(right_text)
	 
func set_top_texture(filename):
	_top_texture_filename = filename
	if top_texture:
		load_texture(top_texture, filename)

func set_bottom_texture(filename):
	_bottom_texture_filename = filename
	if bottom_texture:
		load_texture(bottom_texture, filename)

func set_duration(delta):
	delta_max = delta
	
func set_scale(scale):
	self.rect_scale = Vector2(scale, scale)

		
func load_texture(target, filename):
	if !filename:
		return
	var new_img = WCUtils.load_img(filename)
	if not new_img:
		return	
	var imgtex = ImageTexture.new()
	imgtex.create_from_image(new_img)	
	target.texture = imgtex
	target.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	target.expand = true
	# In case the generic art has been modulated, we switch it back to normal colour
	#art.self_modulate = Color(1,1,1)
