class_name WCCard
extends Card


# Declare member variables here. Examples:
# var a = 2
# var b = "text"


func setup() -> void:
	.setup()
	set_card_art()

func set_card_art():
	var filename = cfc.get_img_filename(get_property("_code"))
	if (filename):
		card_front.set_card_art(filename)
