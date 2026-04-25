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

func reset():
	_objects = []
	_remove_all_children()

func setup(scenario:ScenarioDeckData):
	var extra_rules = scenario.scenario_data.get("extra_rules", [])
	if extra_rules:
		for extra_rule in extra_rules:
			add_script(null, extra_rule)

func execute_scripts(trigger):
	for child in get_children():
		child.execute_scripts(child, trigger)

func _get_script_sceng(trigger, script = null, run_bg_cost_check = true):
	for child in get_children():
		var sceng = child._get_script_sceng(trigger, script, run_bg_cost_check)
		if sceng:
			return sceng
	return null	

#cleans up everything during reset phase (new game, etc...)
func _remove_all_children():
	for removal_condition in removal_conditions:
			var object = removal_condition["object"]
			_objects.erase(object)
			remove_child(object)
			object.queue_free()

	for removal_condition in extra_script_removal_conditions:
			var card = removal_condition["card"]
			var script_id= removal_condition["script_id"]
			card.remove_extra_script(script_id)

	removal_conditions = []
	extra_script_removal_conditions = []
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_objects = []
	cfc.flush_cache()

# Called when the node enters the scene tree for the first time.
func _ready():
	scripting_bus.connect("after_scripting_event_triggered", self, "removal_checks")
	scripting_bus.connect("scripting_event_about_to_trigger", self, "early_removal_checks")

func add_script(parent_script, script_definition, remove_condition = null):
	var new_script = GameObserverItem.new()
	new_script.set_values(parent_script, script_definition)
	_objects.append(new_script)
	add_child(new_script)
	cfc.flush_cache()
	if remove_condition:
		add_script_removal_effect(parent_script, new_script, 0, remove_condition)
		
func add_script_removal_effect(_parent_script,subject, script_id = 0, remove_condition = null):
	if !remove_condition:
		return false

	var remove_condition_arr = remove_condition
	var filters = {}
	if typeof(remove_condition) == TYPE_DICTIONARY:
		remove_condition_arr = remove_condition.get("trigger", "")
		filters = remove_condition.get("event_filters", {})
	
	if typeof(remove_condition_arr) == TYPE_STRING:
		remove_condition_arr = [remove_condition_arr]
	
	for remove_condition_str in remove_condition_arr:
		if script_id:
			extra_script_removal_conditions.append({"trigger": remove_condition_str, "event_filters": filters, "card": subject, "script_id": script_id})
		else:
			removal_conditions.append({"trigger": remove_condition_str, "filters": filters, "object": subject})

func early_removal_checks(
		trigger_card = null,
		trigger: String = "manual",
		trigger_details: Dictionary = {},
		run_type := CFInt.RunType.NORMAL):
	return removal_checks(trigger_card, "before_" + trigger, trigger_details, run_type)

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
		if matches_condition(trigger_card, trigger, trigger_details, removal_condition):
			var object = removal_condition["object"]
			_objects.erase(object)
			remove_child(object)
			to_remove.append(removal_condition)
	if to_remove:
		cfc.flush_cache()
	for v in to_remove:
		removal_conditions.erase(v)
	
	to_remove = []	
	for removal_condition in extra_script_removal_conditions:
		if matches_condition(trigger_card, trigger, trigger_details, removal_condition):
			var card = removal_condition["card"]
			var script_id = removal_condition["script_id"]
			card.remove_extra_script(script_id)
			to_remove.append(removal_condition)
	for v in to_remove:
		extra_script_removal_conditions.erase(v)	

func matches_condition(
		trigger_card = null,
		trigger: String = "manual",
		trigger_details: Dictionary = {},
		removal_condition: Dictionary = {}):
	if !removal_condition:
		return false
		
	if removal_condition.get("trigger", "") != trigger:
		return false
		
	var filters = removal_condition.get("event_filters", {})
	if !filters:
		return true

	#fishy, not sure what card to compare it to at the moment...
	var card = removal_condition.get("card", trigger_card)
	var result =  cfc.ov_utils.matches_filters( filters, card, trigger_details)
	return result
