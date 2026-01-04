extends VBoxContainer

onready var lobby = find_parent("TeamSelection")
onready var button: Button= get_node("%ModularButton")
#onready var playerName := $PlayerName
#onready var kick := $Kick
var modular_id



func gain_focus():
#	$Panel/VerticalHighlights.visible = true
#	$Panel/HorizontalHighlights.visible = true
#	$Panel/HorizontalHighlights.rect_size = scenario_picture.rect_size
#	#$HorizontalHighlights.rect_position = rect_position
#	$Panel/VerticalHighlights.rect_size = scenario_picture.rect_size	
#	lobby.show_preview(villain_id)
	pass
	
func lose_focus():
#	$Panel/VerticalHighlights.visible = false
#	$Panel/HorizontalHighlights.visible = false
#	lobby.hide_preview(villain_id)
	pass
	
	
func resize():
	pass
	
func _ready():
	# warning-ignore:return_value_discarded
	get_viewport().connect("gui_focus_changed", self, "gui_focus_changed")
	resize()
	
func gui_focus_changed(_control):
	pass
	
func grab_focus():
	pass

func load_modular(modular_string) -> bool:
	modular_id = modular_string
	button.text = modular_string
	return true

func get_modular_id():
	return modular_id

func set_disabled(value):
	button.disabled = value
	
func init_status(value):
	button.set_pressed_no_signal(value)

func _on_ModularButton_toggled(button_pressed):
	if button_pressed:
		lobby.modular_select(modular_id)
	else:
		lobby.modular_deselect(modular_id)		

