class_name DamageScript
extends Node

var target #: WCCard avoid cyclic dependency
var amount: int
var script_definition
var tags

func get_class(): return "DamageScript"
func is_class(name): return name == "DamageScript" or .is_class(name) 

# Just calls the parent class.
func _init(_target, _amount, _script_definition, _tags) -> void:
	target = _target
	amount = _amount
	script_definition =_script_definition
	tags = _tags
	pass


func added_to_global_stack():
	scripting_bus.emit_signal("damage_incoming", target, script_definition)	
	return
	
func execute():
	var retcode: int = CFConst.ReturnCode.CHANGED		
	retcode = target.tokens.mod_token("damage",
		amount,false,false, tags)	
	
	scripting_bus.emit_signal("card_damaged", target, script_definition)
					
	var total_damage:int =  target.tokens.get_token_count("damage")
	var health = target.get_property("health", 0)
	
	if total_damage >= health:
		target.die()
	return	
