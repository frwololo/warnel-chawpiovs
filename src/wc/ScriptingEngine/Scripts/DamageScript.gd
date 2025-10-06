class_name DamageScript
extends StackScript


func get_class(): return "DamageScript"
func is_class(name): return name == "DamageScript" or .is_class(name) 

func _init(_target, _amount, _script_definition, _tags) -> void:
	script_details = {
	"target" : _target,
	"amount" : _amount,
	"script_definition" :_script_definition,
	"tags" : _tags
	}
	event_name = "damage"

	
func execute():
	var retcode: int = CFConst.ReturnCode.CHANGED
	var target = script_details["target"]	
	retcode = target.tokens.mod_token("damage",
		script_details["amount"],false,false, script_details["tags"])	
	
	scripting_bus.emit_signal("card_damaged", script_details["target"], script_details["script_definition"])
					
	var total_damage:int =  target.tokens.get_token_count("damage")
	var health = target.get_property("health", 0)
	
	if total_damage >= health:
		target.die()
	return	
