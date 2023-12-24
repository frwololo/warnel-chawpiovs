extends Node2D


# Declare member variables here. Examples:
# var a = 2
# var b = "text"


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


func get_all_cards():
	#todo
	var cardsArray := []
	for obj in get_children():
		if obj as Card: cardsArray.append(obj)	
	return(cardsArray)	

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
