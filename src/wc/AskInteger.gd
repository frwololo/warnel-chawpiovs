# This scene creates a popup confirmation dialogue
# Which confirms with the player to execute a card script.
extends Container

signal selected
signal popup_hide

var is_accepted := false
var dialog_text
var has_been_centered = false
onready var plus_button:Button = get_node("%PlusButton")
onready var minus_button:Button = get_node("%MinusButton")
onready var yes_button:Button = get_node("%OKButton")
onready var value:Label = get_node("%Value")
var max_value:int = 1
var min_value:int = 0
var number = 0

func get_ok():
	return yes_button

func _ready() -> void:
	yes_button.text = "OK"
		
	# warning-ignore:return_value_discarded	
	yes_button.connect("pressed", self, "_on_AskInteger_confirmed")	
	plus_button.connect("pressed", self, "_plus")
	minus_button.connect("pressed", self, "_minus")	
	
	for button in[yes_button, plus_button, minus_button]:
		button.connect("mouse_entered", self, "_mouse_entered", [button])

func prep(title_reference: String, min_req: int, max_req : int) -> void:
		dialog_text = title_reference
		get_node("%Title").text = dialog_text
		
		#cfc.NMAP.board.add_child(self) #TODO shouldn't that be removed from the board eventually ?
		cfc.NMAP.board.add_child_to_top_layer(self)		
		_set_value(min_req)
		min_value = min_req
		max_value = max_req
#
#		scripting_bus.emit_signal(
#			"optional_window_opened",
#			self,
#			{"card_name": card_name, "is_master": is_master}
#		)		

func _set_value(new_value):
	var value_int = int(new_value)
	if value_int > max_value:
		return
	if value_int < min_value:
		return	
	value.text = str(value_int)
	number = value_int
	

func _plus():
	var value_int = int(value.text)
	value_int +=1
	_set_value(value_int)

func _minus():
	var value_int = int(value.text)
	value_int -=1
	_set_value(value_int)

func _process(_delta):
	popup_centered()

func popup_centered():
	if has_been_centered:
		return	
	
	var container = $Panel
		
	if !container.rect_size:
		return

	var size = container.rect_size * self.rect_scale

	self.rect_position = get_viewport().size/2	- size/2
	
	# One again we need two different Panels due to 
	# https://github.com/godotengine/godot/issues/32030
	$HorizontalHighlights.rect_size = container.rect_size
	$HorizontalHighlights.rect_position = Vector2(0,0)
	$VerticalHighlights.rect_size = container.rect_size
	$VerticalHighlights.rect_position = Vector2(0,0)	
	
	has_been_centered = true

	call_deferred("init_default_focus")	


func _on_AskInteger_confirmed() -> void:
	cfc._rpc(self,"confirmed")


func _on_AskInteger_cancelled() -> void:
	cfc._rpc(self,"cancelled")		

remotesync func confirmed() -> void:
	is_accepted = true
	GameRecorder.add_entry(GameRecorder.ACTIONS.CHOOSE, "yes", dialog_text)
	emit_signal("selected")
	self.hide()
	
remotesync func cancelled() -> void:
	is_accepted = false
	GameRecorder.add_entry(GameRecorder.ACTIONS.CHOOSE, "no" , dialog_text)	
	emit_signal("selected")
	self.hide()
	
func hide():
	.hide()
	emit_signal("popup_hide")
				

func _mouse_entered(button):
	button.grab_focus()

#for tests
func force_select_by_title(keyword: String):
	match keyword.to_lower():
		"yes", "ok", "confirm":
			_on_AskInteger_confirmed()
		"+", "plus":
			_plus()
		"-", "minus":
			_minus()
		_:		
			var int_value = int(keyword)
			_set_value(int_value)
			_on_AskInteger_confirmed()


func init_default_focus():
	cfc.default_button_focus($Panel)

func _input(event):	
	if gamepadHandler.is_ui_cancel_pressed(event):
		get_tree().is_input_handled()
		_on_AskInteger_cancelled()
		return
