extends HBoxContainer


# Declare member variables here. Examples:
# var a = 2
# var b = "text"

const COLOR_MISSING: = Color(0,0,0, 0)
const COLOR_HEALTH = Color(0, 1.2, 0.2, 0.5)
const COLOR_CRITICAL = Color(1.2, 0.2, 0.2, 0.5)

var current_value
var max_value

func set_health(_max_value, _value ):
	if _max_value== max_value and _value == current_value:
		return
	
	max_value = _max_value
	current_value = _value
	
	var health_color = COLOR_HEALTH if _value > _max_value*0.25 else COLOR_CRITICAL
	
	var total_length = 200.0
	var height = 6.0
	self.rect_min_size = Vector2(total_length, height) 

	self.rect_size = self.rect_min_size	
	for child in get_children():
		remove_child(child)
	for i in range (_max_value):
		var tex:ColorRect = ColorRect.new()
		tex.modulate = health_color if i < _value else COLOR_MISSING
		add_child(tex)
		tex.rect_min_size = Vector2(total_length/(float(_max_value)) - 2.0, height)
		tex.rect_size = tex.rect_min_size
	get_parent().visible = true
	pass

func set_visible(value:bool= false):
	get_parent().visible = value

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
