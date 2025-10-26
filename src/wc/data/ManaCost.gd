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

const RESOURCE_TEXT := [
	"UNC",
	"MENTAL",
	"PHYSICAL",
	"ENERGY",
	"WILD"
]

const RESOURCE_TEXT_TO_ENUM := {
	"UNC" : Resource.UNCOLOR,
	"MENTAL" : Resource.MENTAL,
	"PHYSICAL" : Resource.PHYSICAL,
	"ENERGY" : Resource.ENERGY,
	"WILD" : Resource.WILD,
}

static func get_resource_from_keyword (keyword:String): 
	var key = keyword.to_upper()
	if RESOURCE_TEXT_TO_ENUM.has(key):
		return RESOURCE_TEXT_TO_ENUM[key]
	
	#Failsafe but not great
	return Resource.UNCOLOR 
	

var pool := {}

func converted_mana_cost() -> int:
	var total = 0
	for k in Resource.values():
		total += pool[k]
	return total	

func get_normalized_type(type):
	if typeof(type) == TYPE_STRING:
		return get_resource_from_keyword(type)
	return type

# Called when the node enters the scene tree for the first time.
func _init():
	for k in Resource.values():
		pool[k] = 0

func reset() :
	for k in pool.keys():
		pool[k] = 0

func set_cost(values:Dictionary):
	reset()
	for k in values.keys():
		pool[k] = values[k]

#_type is either an in or a matching Keyword
func add_resource(_type, amount) :
	var type = get_normalized_type(_type)
	pool[type] += amount
	

#TODO not used ? Delete	
#func duplicate(to:ManaCost):
#	to.set_cost(self.pool)

	
			
#Return true if this mana cost represents a cost deficit (at least one of its members is negative)	
func is_negative() :		
	for v in pool.values():
		if v < 0 :
			return true
	return false	

#Return true if all components of this mana cost are zeroes	
func is_zero() :		
	for v in pool.values():
		if v != 0 :
			return false
	return true	

#Converts a text (or int) into a manacost.
#TODO Simple int for now, will need to expand	
func init_from_expression(expression):
	var i = int(expression)
	set_cost({Resource.UNCOLOR : i})

func init_from_dictionary(dict:Dictionary):
	for k in dict.keys():
		add_resource(k, dict[k])

func add_manacost(other_manacost):
	if !other_manacost:
		return
	for k in Resource.values():
		pool[k] += other_manacost.pool[k]	
