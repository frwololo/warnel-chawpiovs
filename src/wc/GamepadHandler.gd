extends Node2D


# Declare member variables here. Examples:
# var a = 2
# var b = "text"

enum INPUT_MODE {
	NONE,
	MOUSE,
	CONTROLLER
}

const ENABLE_GAMEPAD_SUPPORT = false

var input_mode = INPUT_MODE.NONE
var fake_mouse_position = Vector2(960, 540)
var fake_mouse_pointer: TextureRect = null

func _init():
	var filename = "res://assets/icons/pointer.png"
	var new_img = WCUtils.load_img(filename)
	if not new_img:
		return


	var imgtex = ImageTexture.new()	
	imgtex.create_from_image(new_img)
	fake_mouse_pointer = TextureRect.new()	
	fake_mouse_pointer.texture = imgtex
	fake_mouse_pointer.rect_position = fake_mouse_position
	fake_mouse_pointer.visible = false
	
# Called when the node enters the scene tree for the first time.
func _ready():

	#show above everything else
	self.z_index = 4000
	add_child(fake_mouse_pointer)
	Input.connect("joy_connection_changed", self, "_on_joy_connection_changed")
	_check_input_device()	


func _check_input_device():
	if !ENABLE_GAMEPAD_SUPPORT:
		set_input_mode(INPUT_MODE.MOUSE)
		return
		
	# Check if any joypad is connected
	var joypads = Input.get_connected_joypads()
	if joypads.size() > 0:
		set_input_mode(INPUT_MODE.CONTROLLER)
	else:
		set_input_mode(INPUT_MODE.MOUSE)
		
func _on_joy_connection_changed(device: int, connected: bool):
	# Recheck input device when joypad connection changes
	_check_input_device()	

func set_input_mode(new_mode):
	if new_mode == input_mode:
		return

	if !ENABLE_GAMEPAD_SUPPORT:
		new_mode = INPUT_MODE.MOUSE
	
	match new_mode:
		INPUT_MODE.CONTROLLER:
			set_fake_mouse_position(get_real_mouse_position())
			Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
			input_mode = INPUT_MODE.CONTROLLER
			fake_mouse_pointer.visible = true 
		_:
			set_real_mouse_position(fake_mouse_position)
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			input_mode = INPUT_MODE.MOUSE 
			fake_mouse_pointer.visible = false

func set_fake_mouse_position (position):
	fake_mouse_position = position
	if fake_mouse_pointer:
		fake_mouse_pointer.rect_position = fake_mouse_position

#func _process(delta):
#	match input_mode:
#		INPUT_MODE.CONTROLLER: 
#			fake_mouse_pointer.rect_position = fake_mouse_position
	pass
	


func _input(event):
	# Show mouse when mouse is moved, hide when joypad is used`
	if event is InputEventMouseMotion:
		set_input_mode(INPUT_MODE.MOUSE)
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		set_input_mode(INPUT_MODE.CONTROLLER)

var mouse_sens= 500.0	
func _physics_process(delta):
	var direction: Vector2
	direction.x = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	direction.y = Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")


	if abs(direction.x) == 1 and abs(direction.y) == 1:
		direction = direction.normalized()

	var movement = mouse_sens * direction * delta
	if (movement):
		match input_mode:
			INPUT_MODE.CONTROLLER: 
				set_fake_mouse_position(fake_mouse_position + movement)
			_:
				var viewport = get_viewport()
				if viewport:	
					set_real_mouse_position(viewport.get_mouse_position() + movement, viewport)	
			

func set_real_mouse_position(position, viewport = null):
	if !viewport:	
		viewport = get_viewport()
	if viewport:	
		viewport.warp_mouse(position)	
		

func get_real_mouse_position():
	var viewport = get_viewport()
	if !viewport:
		return Vector2(1000, 500)	
	return viewport.get_mouse_position()	
