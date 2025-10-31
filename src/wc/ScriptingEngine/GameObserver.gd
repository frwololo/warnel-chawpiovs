#a scriptable object that allows having alterants, etc...
#without being attached to a card
#to make it easier I make it inherit a WCCard object,
#but that means a lot of functions fail...
#A better approach would be for it to "implement" methods of an abstract class,
#but I got lazy and wanted a wayt to benefit from all WCCard stuff without having to rewrite all...
class_name GameObserver
extends Node2D


var _objects:= []
var removal_conditions:= []
var extra_script_removal_conditions:= []

# Declare member variables here. Examples:
# var a = 2
# var b = "text"

# Called when the node enters the scene tree for the first time.
func _ready():
	scripting_bus.connect("scripting_event_triggered", self, "removal_checks")

func add_script(parent_script, script_definition, remove_condition:= "", overrides = {}):
	var new_script = GameObserverItem.new()
	new_script.set_values(parent_script, script_definition, overrides)
	_objects.append(new_script)
	add_child(new_script)
	if remove_condition:
		removal_conditions.append({"trigger": remove_condition, "object": new_script})

func add_script_removal_effect(parent_script,subject, script_id, remove_condition:= ""):
	extra_script_removal_conditions.append({"trigger": remove_condition, "card": subject, "script_id": script_id})


func removal_checks(
		trigger_card = null,
		trigger: String = "manual",
		trigger_details: Dictionary = {},
		run_type := CFInt.RunType.NORMAL):
	if cfc.game_paused:		
		return
	if run_type != CFInt.RunType.NORMAL:
		return
	
	var to_remove = []
	
	for removal_condition in removal_conditions:
		if removal_condition["trigger"] == trigger:
			var object = removal_condition["object"]
			_objects.erase(object)
			remove_child(object)
			to_remove.append(removal_condition)
	for v in to_remove:
		removal_conditions.erase(v)
	
	to_remove = []	
	for removal_condition in extra_script_removal_conditions:
		if removal_condition["trigger"] == trigger:
			var card = removal_condition["card"]
			var script_id= removal_condition["script_id"]
			card.remove_extra_script(script_id)
			to_remove.append(removal_condition)
	for v in to_remove:
		extra_script_removal_conditions.erase(v)	

