class_name StackScript
extends Node

var event_name:String
var script_details:Dictionary = {}

func get_event_name():
	return event_name
	
func added_to_global_stack():
	#scripting_bus.emit_signal("before_" + get_event_name())	
	return	

func matches_filters(filters:Dictionary, owner_card):
	var owner_hero_id = owner_card.get_owner_hero_id()
	if (owner_hero_id > 0):
		for v in ["my_hero"]:
			#TODO move to const
			WCUtils.search_and_replace(filters, v, gameData.get_hero_card(owner_hero_id), true)

	if (filters):
		var tmp = 0	
	
	var result = WCUtils.is_element1_in_element2(filters, script_details)

	return result
