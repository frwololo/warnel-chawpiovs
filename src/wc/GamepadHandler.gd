class_name GamepadHandler
extends Node2D


# Declare member variables here. Examples:
# var a = 2
# var b = "text"

enum INPUT_MODE {
	NONE,
	MOUSE,
	CONTROLLER,
	KEYBOARD
}

const ENABLE_GAMEPAD_SUPPORT = true
const SIMULATE_MOUSE = false 

var input_mode = INPUT_MODE.NONE
var fake_mouse_position = Vector2(960, 540)
var fake_mouse_pointer: TextureRect = null
var current_focused_control = null
var approx_position = Vector2(0,0)

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

func is_mouse_input():
	return (input_mode == INPUT_MODE.MOUSE)

func is_controller_input():
	return (input_mode == INPUT_MODE.CONTROLLER)
	
# Called when the node enters the scene tree for the first time.
func _ready():

	#show above everything else
	self.z_index = CFConst.Z_INDEX_MOUSE_POINTER
	add_child(fake_mouse_pointer)
	Input.connect("joy_connection_changed", self, "_on_joy_connection_changed")
	_check_input_device()	

func connect_viewport():
	var viewport = cfc.NMAP.main.get_viewport()
	viewport.connect("gui_focus_changed", self, "gui_focus_changed")


func gui_focus_changed(control):
	current_focused_control = control
	if control != null:
		var parent = current_focused_control.get_parent()
		if parent and parent.has_method("get_global_center"):
			approx_position = parent.get_global_center()		
		elif current_focused_control.has_method("get_global_center"):
			approx_position = current_focused_control.get_global_center() 
		else:
			approx_position = current_focused_control.get_global_position() + Vector2(10, 10)
	else:
		approx_position = Vector2(0,0)
		
func get_approx_position():
	if current_focused_control == null:
		return Vector2(0,0)
	else:
		var _tmp = typeof(current_focused_control)
		return approx_position

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
		INPUT_MODE.CONTROLLER, INPUT_MODE.KEYBOARD:
			Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
			input_mode = new_mode
			set_fake_mouse_position(get_real_mouse_position())
			if SIMULATE_MOUSE:		
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
	

func is_ui_accept_pressed(event):
	if event is InputEventJoypadButton:
		#replacing PS "X" as an ok instead of a cancel
		if event.get_button_index() == JOY_SONY_X and event.is_pressed():
			var controller_name = get_simplified_device_name_no_cache(Input.get_joy_name(event.device))
			if controller_name =="ps":
				return true
	return event.is_action_pressed("ui_accept")

func is_ui_cancel_pressed(event):
	if event is InputEventJoypadButton:
		#replacing PS "X" as an ok instead of a cancel
		if event.get_button_index() == JOY_SONY_X:
			var controller_name = get_simplified_device_name_no_cache(Input.get_joy_name(event.device))
			if controller_name =="ps":
				return false
	return event.is_action_pressed("ui_cancel")

func _input(event):
	# Show mouse when mouse is moved, hide when joypad is used`
	if event is InputEventMouseMotion:
		set_input_mode(INPUT_MODE.MOUSE)
	elif event is InputEventJoypadMotion:
		set_input_mode(INPUT_MODE.CONTROLLER)
	elif event is InputEventJoypadButton:
		set_input_mode(INPUT_MODE.CONTROLLER)
		#replacing PS "X" as an ok instead of a cancel
		if event.get_button_index() == JOY_SONY_X:
			var controller_name = get_simplified_device_name_no_cache(Input.get_joy_name(event.device))
			if controller_name =="ps":
				var new_event := InputEventJoypadButton.new()
				new_event.set_device(event.device)
				new_event.set_button_index(JOY_SONY_CIRCLE)
				new_event.set_pressed(event.is_pressed())
				Input.parse_input_event(new_event)
				get_tree().root.set_input_as_handled() # prevent original event
	elif event is InputEventKey:
		set_input_mode(INPUT_MODE.KEYBOARD)
	else:
		var _tmp = 1	

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
				if SIMULATE_MOUSE: 
					set_fake_mouse_position(fake_mouse_position + movement)
				else:
					pass
					#focus_on_next_object(direction, movement)
			_:
				if SIMULATE_MOUSE: 
					var viewport = get_viewport()
					if viewport:	
						set_real_mouse_position(viewport.get_mouse_position() + movement, viewport)	
				else:
					pass
					
func focus_on_next_object(direction, movement):
	set_fake_mouse_position(fake_mouse_position + movement)

#	var current_location = fake_mouse_position
#	var current_focus_control = get_focus_owner()
#	var _tmp = 1
#	if !current_focus_control:
					

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

var _controller_name = ""
func get_simplified_device_name(raw_name: String) -> String:
	if !_controller_name:
		_controller_name = get_simplified_device_name_no_cache(raw_name)
	return _controller_name

func get_simplified_device_name_no_cache(raw_name: String) -> String:
	match raw_name:
		"XInput Gamepad", "Xbox Series Controller":
			return "xbox"
		
		"Sony DualSense", "PS5 Controller", "PS4 Controller":
			return "ps"
		
		"Switch":
			return "switch"
		
		_:
			return "generic"
