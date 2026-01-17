# This scene creates a popup confirmation dialogue
# Which confirms with the player to execute a card script.
extends Container

signal selected

var is_accepted := false
var is_master := true
var dialog_text
var has_been_centered = false

func get_cancel():
	return get_node("%NoButton")

func get_ok():
	return get_node("%YesButton")

func _ready() -> void:
	var no_button = get_cancel()
	var yes_button = get_ok()	
	no_button.text = "No"
	yes_button.text = "Yes"
	
	# warning-ignore:return_value_discarded
	no_button.connect("pressed", self, "_on_OptionalConfirmation_cancelled")
	no_button.icon = gamepadHandler.get_icon_for_action("ui_cancel")	
	# warning-ignore:return_value_discarded	
	yes_button.connect("pressed", self, "_on_OptionalConfirmation_confirmed")	

	for button in[no_button, yes_button]:
		button.connect("mouse_entered", self, "_mouse_entered", [button])

func prep(card_name: String, task_name: String, _is_master:bool = true) -> void:
		dialog_text =  card_name + ": Do you want to activate " + task_name + "?"
		get_node("%Title").text = dialog_text
		
		#cfc.NMAP.board.add_child(self) #TODO shouldn't that be removed from the board eventually ?
		cfc.NMAP.board.add_child_to_top_layer(self)		
		is_master = _is_master
		if (!is_master):
			get_ok().disabled = true
			get_cancel().disabled = true
		
		# We spawn the dialogue at the middle of the screen.
		#popup_centered()
		#self.set_as_toplevel(true)


		scripting_bus.emit_signal(
			"optional_window_opened",
			self,
			{"card_name": card_name, "is_master": is_master}
		)		

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


func _on_OptionalConfirmation_confirmed() -> void:
	cfc._rpc(self,"confirmed")


func _on_OptionalConfirmation_cancelled() -> void:
	cfc._rpc(self,"cancelled")		

remotesync func confirmed() -> void:
	is_accepted = true
	GameRecorder.add_entry(GameRecorder.ACTIONS.CHOOSE, "yes", dialog_text)
	emit_signal("selected")
	scripting_bus.emit_signal(
		"optional_window_closed",
		self,
		{"is_accepted": is_accepted}
	)
	
remotesync func cancelled() -> void:
	is_accepted = false
	GameRecorder.add_entry(GameRecorder.ACTIONS.CHOOSE, "no" , dialog_text)	
	emit_signal("selected")
	scripting_bus.emit_signal(
		"optional_window_closed",
		self,
		{"is_accepted": is_accepted}
	)					

func _mouse_entered(button):
	button.grab_focus()

func force_select_by_title(keyword: String):
	if keyword in ["yes", "ok", "confirm"]:
		_on_OptionalConfirmation_confirmed()
	_on_OptionalConfirmation_cancelled()

func init_default_focus():
	cfc.default_button_focus($Panel)

func _input(event):	
	if gamepadHandler.is_ui_cancel_pressed(event):
		get_tree().is_input_handled()
		_on_OptionalConfirmation_cancelled()
		return
