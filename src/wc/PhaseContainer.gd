extends VBoxContainer

var phaseButton

func _init():
	phaseButton = PhaseButton.new()
	add_child(phaseButton)
# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
