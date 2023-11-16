extends "res://src/wc/CardFront.gd"


# Declare member variables here. Examples:
# var a = 2
# var b = "text"


# Called when the node enters the scene tree for the first time.
func _ready():
	card_labels["Health"] = find_node("Health")
	card_label_min_sizes["Health"] = Vector2(16,16)
	original_font_sizes["Health"] = 15


# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
