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

var input_mode = INPUT_MODE.NONE
var current_focused_control = null
var approx_position = Vector2(0,0)


func is_mouse_input():
	return (input_mode == INPUT_MODE.MOUSE)

func is_controller_input():
	return (input_mode == INPUT_MODE.CONTROLLER)
	
# Called when the node enters the scene tree for the first time.
func _ready():
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
			if cfc.NMAP.has("board"):
				cfc.NMAP.board.mouse_pointer.set_disabled(true)
		_:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			input_mode = INPUT_MODE.MOUSE 
			if cfc.NMAP.has("board"):
				cfc.NMAP.board.mouse_pointer.set_disabled(false)			


	

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
