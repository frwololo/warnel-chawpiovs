extends HBoxContainer


# Declare member variables here. Examples:
# var a = 2
# var b = "text"

var room_name = ""
var parent_scene = null
onready var button = get_node("%Button")
	
# Called when the node enters the scene tree for the first time.
func _ready():
	get_node("%Label").text = room_name
	button.connect('mouse_entered', button, 'grab_focus')
	pass # Replace with function body.

func setup(_room_name, _parent_scene):
	room_name = _room_name
	parent_scene = _parent_scene
	var label = get_node("%Label")
	if label:
		label.text = room_name
# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass

func set_disabled(disable=false):
	button.disabled = disable

func grab_focus():
	button.grab_focus
	

func _on_Button_pressed():
	parent_scene.request_join_room(room_name)
	pass # Replace with function body.
