# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED

class_name StackObject
extends Reference

var stack_uid:int = 0
var display_name: = ""

#task elements, generally speaking, should be ScriptTask objects
#at the very least, they need a script_definition and a script_name value
var tasks:= []

#can be overriden by children classes
func get_tasks():
	return tasks

#can be overriden by children classes
func get_script_by_event_details(_details):
	return null

#can be overriden by children classes
func execute():
	pass

#replacement tasks
func add_tags(new_tags:Array):
	for task in get_tasks():
		var tags = task.get_property("tags", [])
		tags+= new_tags
		task.script_definition["tags"] = tags

func replace_subjects(new_subjects:Array):
	pass
	
func replace_ability(new_ability_name:String):
	pass	

func prevent_value(property, amount_prevented):
	pass		

#todo in the future this needs to redo targeting, etc...
func get_modify_subjects(value, script):
	match value:
		"self":
			return [script.owner]
		"my_hero":
			return [script.owner.get_controller_hero_card()]			
		_:
			#not implemented
			return []
					

#modification scripts such as partial prevent and replacement effects
func modify(script):
	match script.script_name:
		"prevent":
			var amount = script.retrieve_integer_property("amount")
			if !amount:
				var _error = 1
			else:
				self.prevent_value("amount", amount)
		_:
			var replacements = script.get_property("replacements", {})
			for property in replacements.keys():
				var value = replacements[property]
				match property:
					"subject":
						var new_subjects = get_modify_subjects(value, script)
						replace_subjects(new_subjects)
					"name":
						replace_ability(value)
					"additional_tags":
						add_tags(value)
					_:
						#not implemented
						pass

#TODO this function shouldn't be here? doesn't use any of its data
func matches_filters(task, filters:Dictionary, owner_card):
	var owner_hero_id = owner_card.get_owner_hero_id()
	if (owner_hero_id > 0):
		for v in ["my_hero"]:
			#TODO move to const
			filters = WCUtils.search_and_replace(filters, v, gameData.get_identity_card(owner_hero_id), true)

	#TODO move to const
	filters = WCUtils.search_and_replace(filters, "villain", gameData.get_villain(), true)


	if (filters):
		var _tmp = 0	
	var script_details = task.script_definition
	var result = WCUtils.is_element1_in_element2(filters, script_details, ["tags"])

	return result

func get_first_task_name():
	for task in get_tasks():
		return task.script_name
	return ""

func get_display_name():
	if display_name:
		return display_name
		
	for task in get_tasks():
		return task.owner.canonical_name + "-" + task.script_name

func set_display_name(_name):
	display_name = _name



static func sort_stack(a, b):
	if a.stack_uid < b.stack_uid:
		return true
	return false
