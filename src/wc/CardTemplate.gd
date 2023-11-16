class_name WCCard
extends Card


# Declare member variables here. Examples:
# var a = 2
# var b = "text"


func setup() -> void:
	.setup()
	set_card_art()

func set_card_art():
	var card_code = get_property("_code")
	var card_set = get_property("_set")
	if card_code and card_set:
		card_front.set_card_art("user://Sets/" + card_set + "/" + card_code + ".png")
