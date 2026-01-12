# This scene creates a popup confirmation dialogue
# Which confirms with the player to execute a card script.
extends ConfirmationDialog

signal selected

var is_accepted := false
var is_master := true

func _ready() -> void:
	get_cancel().text = "No"
	get_ok().text = "Yes"
	
	# warning-ignore:return_value_discarded
	get_cancel().connect("pressed", self, "_on_OptionalConfirmation_cancelled")

	get_cancel().icon = gamepadHandler.get_icon_for_action("ui_cancel")	


func prep(card_name: String, task_name: String, _is_master:bool = true) -> void:
		dialog_text =  card_name + ": Do you want to activate " + task_name + "?"
		cfc.NMAP.board.add_child(self) #TODO shouldn't that be removed from the board eventually ?
		
		is_master = _is_master
		if (!is_master):
			get_ok().disabled = true
			get_cancel().disabled = true
			get_close_button().visible = false
		
		# We spawn the dialogue at the middle of the screen.
		popup_centered()
		# One again we need two different Panels due to 
		# https://github.com/godotengine/godot/issues/32030
		$HorizontalHighlights.rect_size = rect_size
		$HorizontalHighlights.rect_position = Vector2(0,0)
		$VecticalHighlights.rect_size = rect_size
		$VecticalHighlights.rect_position = Vector2(0,0)

		scripting_bus.emit_signal(
			"optional_window_opened",
			self,
			{"card_name": card_name, "is_master": is_master}
		)		


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


func force_select_by_title(keyword: String):
	if keyword in ["yes", "ok", "confirm"]:
		_on_OptionalConfirmation_confirmed()
	_on_OptionalConfirmation_cancelled()
