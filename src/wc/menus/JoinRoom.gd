extends HBoxContainer


# Declare member variables here. Examples:
# var a = 2
# var b = "text"

var room_name = ""
var parent_scene = null
# online (WebRTC) room: joined directly with its code, no lobby server request
var room_code = ""
onready var button = get_node("%Button")
	
# Called when the node enters the scene tree for the first time.
func _ready():
	get_node("%Label").text = room_name
	button.connect('mouse_entered', button, 'grab_focus')
	pass # Replace with function body.

# _room_code: for an online room, its code. _room_name is then only displayed
func setup(_room_name, _parent_scene, _room_code = ""):
	room_name = _room_name
	parent_scene = _parent_scene
	room_code = _room_code
	var label = get_node("%Label")
	if label:
		label.text = room_name
# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass

func set_disabled(disable=false):
	button.disabled = disable
	

func _on_Button_pressed():
	if room_code:
		parent_scene.join_game(room_code)
	else:
		parent_scene.request_join_room(room_name)
	pass # Replace with function body.
