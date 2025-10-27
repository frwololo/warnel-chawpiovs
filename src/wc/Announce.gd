extends Node

onready var top_text = $Top/Margin/Label
onready var bottom_text = $Bottom/Margin/Label
onready var top_color = $Top/ColorRect
onready var bottom_color = $Bottom/ColorRect

var _top_text := ""
var _bottom_text:= ""
var _top_color:= Color8(50, 50, 50, 255)
var _bottom_color := Color8(18, 18, 18, 255)
const delta_max = 3.0
var bottom_target = 900
var delta_total: float = 0
var ongoing = true

func fade(object, modulation):
	if "modulate" in object:
		object.modulate.a = modulation
	for child in object.get_children():
		fade(child, modulation)

func _process(delta):
	delta_total+=delta
	
	if delta_total >delta_max:
		ongoing = false
		return
	var square = (delta_max/2 - delta_total) /(delta_max/2)
	square = square *square 	
	var modulation = 1 - square 
	self.fade(self, modulation)
	var big_number = 100.0 * (delta_total/delta_max)
	var new_position = -$Top.rect_size.x/big_number
	$Top.rect_position = Vector2(new_position , $Top.rect_position.y)
	$Bottom.rect_position = Vector2(bottom_target - $Top.rect_position.x, $Bottom.rect_position.y)

func _ready():
	top_text.text = _top_text
	bottom_text.text = _bottom_text
	top_color.color = _top_color
	bottom_color.color = _bottom_color
	self.fade(self, 0)

func set_bg_colors(top, bottom):
	_top_color = top
	_bottom_color = bottom
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
	var right_string = text.substr(half_size)
	var right = text.find(" ", half_size)
	var left = left_string.rfind(" ")
	
	var found = left
	if right-half_size < left_string.length()-left:
		found = right
	
	var left_text = text.substr(0, found)
	var right_text = text.substr(found)
	set_text_top(left_text)
	set_text_bottom(right_text)
	 
