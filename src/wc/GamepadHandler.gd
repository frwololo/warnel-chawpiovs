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
var last_joy_name = ""
var last_joy_full_name = ""


func is_mouse_input():
	return (input_mode == INPUT_MODE.MOUSE)

func is_controller_input():
	return (input_mode == INPUT_MODE.CONTROLLER)
	
# Called when the node enters the scene tree for the first time.
func _ready():
	# warning-ignore:return_value_discarded
	Input.connect("joy_connection_changed", self, "_on_joy_connection_changed")
	_check_input_device()	

func connect_viewport():
	var viewport = cfc.NMAP.main.get_main_viewport()
	viewport.connect("gui_focus_changed", self, "gui_focus_changed")
	
	#another chance to deactivate the mouse
	if cfc.NMAP.has("board") and !is_mouse_input():
		cfc.NMAP.board.mouse_pointer.disable()

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
			var _tmp = 1
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
		last_joy_full_name = Input.get_joy_name(joypads[0])
		set_input_mode(INPUT_MODE.CONTROLLER)
	else:
		set_input_mode(INPUT_MODE.MOUSE)
		
func _on_joy_connection_changed(_device: int, _connected: bool):
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
				cfc.NMAP.board.mouse_pointer.disable()
		_:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			input_mode = INPUT_MODE.MOUSE 
			if cfc.NMAP.has("board"):
				cfc.NMAP.board.mouse_pointer.enable()		


	

func is_ui_accept_pressed(event):
	if event is InputEventJoypadButton:
		#replacing PS "X" as an ok instead of a cancel
		if event.get_button_index() == JOY_SONY_X and event.is_pressed():
			var controller_name = get_simplified_device_name(Input.get_joy_name(event.device))
			if controller_name =="ps":
				return true
	return event.is_action_pressed("ui_accept")

func is_ui_cancel_pressed(event):
	if event is InputEventJoypadButton:
		#replacing PS "X" as an ok instead of a cancel
		if event.get_button_index() == JOY_SONY_X:
			var controller_name = get_simplified_device_name(Input.get_joy_name(event.device))
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
		last_joy_full_name = Input.get_joy_name(event.device)
		var controller_name = get_simplified_device_name(last_joy_full_name)		
		#replacing PS "X" as an ok instead of a cancel
		if event.get_button_index() == JOY_SONY_X:
			if controller_name =="ps":
				var new_event := InputEventJoypadButton.new()
				new_event.set_device(event.device)
				new_event.set_button_index(JOY_SONY_CIRCLE)
				new_event.set_pressed(event.is_pressed())
				Input.parse_input_event(new_event)
				get_tree().root.set_input_as_handled() # prevent original event
	elif event is InputEventKey:
		set_input_mode(INPUT_MODE.KEYBOARD)


var _controller_name = {}
func get_simplified_device_name(raw_name: String) -> String:
	if !_controller_name.has(raw_name):
		_controller_name[raw_name] = get_simplified_device_name_no_cache(raw_name)
	
	last_joy_name = _controller_name[raw_name]	
	return last_joy_name

func get_simplified_device_name_no_cache(raw_name: String) -> String:
	match raw_name:
		"XInput Gamepad", "Xbox Series Controller":
			return "xbox"
		
		"Sony DualSense", "PS5 Controller", "PS4 Controller":
			return "ps"
		
		#Seems like the homebrew switch build uses the generic name "pad"
		"Switch", "pad":
			return "switch"
		
		_:
			return "generic"

func get_icon_for_action(action_name):
	match last_joy_name:
		"switch":
			match action_name:
				"ui_cancel":
					return load("res://assets/icons/switch_B.png")
		"ps":
			match action_name:
				"ui_cancel":
					return load("res://assets/icons/ps_X.png")
	return null

func get_full_joy_name():
	return last_joy_full_name
