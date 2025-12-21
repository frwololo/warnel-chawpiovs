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

func get_user_interaction_status():
	var status = CFConst.USER_INTERACTION_STATUS.NOT_CHECKED_YET
	for t in get_tasks():
		var t_status = t.user_interaction_status
		match t_status:
			CFConst.USER_INTERACTION_STATUS.NOK_UNAUTHORIZED_USER:
				#unauthorized, return immediately
				return CFConst.USER_INTERACTION_STATUS.NOK_UNAUTHORIZED_USER
			CFConst.USER_INTERACTION_STATUS.DONE_AUTHORIZED_USER:
				status = CFConst.USER_INTERACTION_STATUS.DONE_AUTHORIZED_USER
			CFConst.USER_INTERACTION_STATUS.NOT_CHECKED_YET:
				var _error = 1
				#this shouldn't happen
	if status == CFConst.USER_INTERACTION_STATUS.NOT_CHECKED_YET:
		status = CFConst.USER_INTERACTION_STATUS.DONE_AUTHORIZED_USER
	
	return status
		

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
						var new_subjects = SP.retrieve_subjects(value, script)
						replace_subjects(new_subjects)
					"name":
						replace_ability(value)
					"additional_tags":
						add_tags(value)
					_:
						#not implemented
						pass

#TODO this function shouldn't be here? doesn't use any of its data
func matches_filters(task, _filters:Dictionary, owner_card, _trigger_details):
	var filters = _filters #.duplicate(true)
	var controller_hero_id = owner_card.get_controller_hero_id()
	
	
	var replacements = {
		"villain": gameData.get_villain(),
		"self": owner_card
	}	
	if (controller_hero_id > 0):
		replacements["my_hero"] = gameData.get_identity_card(controller_hero_id)

	filters = WCUtils.search_and_replace_multi(filters, replacements, true)

	var trigger_details = guidMaster.replace_guids_to_objects(_trigger_details)

	
	if filters.has("filter_state_event_source"):
		var script = trigger_details.get("event_object")
		if !script:
			return false
		var owner = script.owner
		if !owner:
			return false		
		var is_valid = SP.check_validity(owner, filters, "event_source")
		if !is_valid:
			return false
		filters.erase("filter_state_event_source")


	if (filters):
		var _tmp = 0	
	#var script_details = task.script_definition
	var result = WCUtils.is_element1_in_element2(filters, trigger_details, ["tags"])

	return result

func get_owner_card():
	var first_task = get_first_task()
	if first_task:
		return first_task.owner
	return null

func get_subjects():
	var first_task = get_first_task()
	
	if first_task and ("subjects" in first_task):
		return first_task.subjects
	return []		

func get_first_task_name():
	var first_task = get_first_task()
	if first_task:
		return first_task.script_name
	return ""

func get_display_name():
	if display_name:
		return display_name
		
	for task in get_tasks():
		return task.owner.canonical_name + "-" + task.script_name

var _cache_display_text = ""
func get_display_text():
	if !_cache_display_text:
		_cache_display_text = _get_display_text_nocache()		
	return _cache_display_text

func _get_display_text_nocache():	
	var task = get_first_task()
	var result = get_display_name()
	if task: 	
		var owner = task.owner
		var owner_name = owner.canonical_name if owner else ""
		var subjects = get_subjects()
		var only_one_subject = (subjects and subjects.size() == 1)
		match task.script_name:
			"reveal_encounter":
				if owner:
					var text = owner.get_printed_text("when revealed")
					if text:
						return text
					var text1 = owner.get_printed_text("When Revealed (Alter-Ego)")	
					var text2 = owner.get_printed_text("When Revealed (Hero)")
					if text1 or text2:
						return "(Alter-Ego) " + text1 + "\n(Hero) " + text2
			"add_threat":
				var amount = task.retrieve_integer_property("amount", 0)
				result = owner_name + " adds " + str(amount) + " threat"
				return result
				
	result = result.replace("_", " ")
	return result
			


func set_display_name(_name):
	display_name = _name

func get_first_task():
	for task in get_tasks():
		return task
	return null

static func sort_stack(a, b):
	if a.stack_uid < b.stack_uid:
		return true
	return false
