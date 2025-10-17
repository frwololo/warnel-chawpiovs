# Pops up a menu for the player to choose on of the card
# options
extends PopupMenu

var id_selected := 0
var selected_key: String

# Called from Card.execute_scripts() when a card has multiple options.
#
# It prepares the menu items based on the dictionary keys and bring the
# popup to the front.
func prep(title_reference: String, script_with_choices: Dictionary) -> void:
		set_item_text(0, "Please choose option for " + title_reference)
		# The dictionary passed is a card script which contains
		# an extra dictionary before the task definitions
		# When that happens, it specifies multiple choice
		# and the dictionary keys, are the choices in human-readable text.
		for key in script_with_choices.keys():
			add_item(key)
		cfc.NMAP.board.add_child(self)
		popup_centered()
		# One again we need two different Panels due to 
		# https://github.com/godotengine/godot/issues/32030
		$HorizontalHighlights.rect_size = rect_size
		$VecticalHighlights.rect_size = rect_size
		# We spawn the dialogue at the middle of the screen.

func force_select_by_title(keyword: String):
	for i in range (get_item_count()):
		var id = get_item_id(i)
		var item_text = get_item_text(id).to_lower()
		if (item_text == keyword.to_lower()):
			_on_CardChoices_id_pressed(id)
			emit_signal("id_pressed", id_selected)
			return
	

func _on_CardChoices_id_pressed(id: int) -> void:
	id_selected = id
	selected_key = get_item_text(id)

# It ensures the "id_pressed" signal is emited even when no choice has
# been made, to allow the script execution to continue and not
# leave yields waiting
func _on_CardChoices_popup_hide() -> void:
	# We also allow Unit Tests to send the signal through this function
	if not id_selected or cfc.ut:
		emit_signal("id_pressed", id_selected)

func force_cancel():
	self.hide()
