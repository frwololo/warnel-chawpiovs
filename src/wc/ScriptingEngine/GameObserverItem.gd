class_name GameObserverItem
extends WCCard

var parent_script = null
var script_definition:= {}

# Declare member variables here. Examples:
# var a = 2
# var b = "text"

func set_values(_parent_script, _script: Dictionary):
	parent_script = _parent_script
	script_definition = _script
		
func get_parent_script():
	return parent_script

# Called when the node enters the scene tree for the first time.
func _class_specific_ready():
	add_to_group("scriptables")
	scripting_bus.connect("scripting_event_triggered", self, "execute_scripts")


func retrieve_scripts(trigger, _filters:={}) -> Dictionary:
	return script_definition.get(trigger, {})
	
func retrieve_all_scripts():
	return script_definition

#Functions from Card/WCCard we want to override with empty stuff (related to display, etc...)
func _class_specific_input(_event) -> void:
	pass
	
func _class_specific_process(_delta):
	pass



func _init_card_layout() -> void:
	pass

	
func init_default_max_tokens():
	pass
	
func set_card_size(_value: Vector2, _ignore_area = false) -> void:
	pass
