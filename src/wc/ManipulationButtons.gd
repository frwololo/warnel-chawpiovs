extends ManipulationButtons

#signal up_pressed()
#signal down_pressed()

var current_counter_value: int = 0
var min_counter_value: int = 0
var max_counter_value: int = 0
var counter_label = null

func _ready() -> void:
	# The methods to use each of these should be defined in this script
	needed_buttons = {
#		"Up": "+",
#		"Down": "-",

	}
	spawn_manipulation_buttons()

## Hover button which rotates the card 90 degrees
#func _on_Up_pressed() -> void:
## warning-ignore:return_value_discarded
#	emit_signal("up_pressed")
#	owner_node.set_card_rotation(90, true)
#
#
## Hover button which rotates the card 180 degrees
#func _on_Down_pressed() -> void:
## warning-ignore:return_value_discarded
#	emit_signal("up_pressed")
#	owner_node.set_card_rotation(180, true)

