# Data that represents the available mana/energy for the player
class_name ManaCost
extends Reference



enum Resource {
	UNCOLOR,
	MENTAL,
	PHYSICAL,
	ENERGY,
	WILD
}


var pool := {
	Resource.UNCOLOR : 0,
	Resource.MENTAL  : 0,
	Resource.PHYSICAL : 0,
	Resource.ENERGY :0,
	Resource.WILD :0,
}

# Called when the node enters the scene tree for the first time.
func _init():
	pass # Replace with function body.

func set_cost(values:Dictionary):
	for k in values.keys():
		pool[k] = values[k]

func add_resource(type, amount) :
	pool[type] += amount
	
func duplicate() -> ManaCost:
	var dup:ManaCost
	dup.set_cost(self.pool)
	return dup	
