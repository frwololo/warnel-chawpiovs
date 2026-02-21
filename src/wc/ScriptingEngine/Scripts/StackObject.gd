# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED

class_name StackObject
extends Reference

var stack_uid:int = 0
var display_name: = ""
var interrupt_marker = false

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

func get_sceng():
	return null

#replacement tasks
func add_tags(new_tags:Array, task_object = null):
	for task in get_tasks():
		if task_object and task != task_object:
			continue
		var tags = task.get_property("tags", [])
		tags+= new_tags
		task.script_definition["tags"] = tags

func replace_subjects(new_subjects:Array,  task_object = null):
	pass
	
func replace_ability(new_ability_name:String, task_object = null):
	pass	

func prevent_value(property, amount_prevented, task_object = null):
	pass		

func replace_script_property(key, value, task_object = null):
	for task in get_tasks():
		if task_object and task != task_object:
			continue		
		task.script_definition[key] = value
	
func is_silent():
	return false

func get_trigger():
	#TODO I've seen cases where the stackobject trigger is "interrupt" but all is children are "manual".
	# Where does this come from and how to fix?
	if "trigger" in self and self.trigger:
		return self.trigger 
	for task in get_tasks():
		if "trigger" in task and task.trigger:
			return task.trigger
	return ""


#modification scripts such as partial prevent and replacement effects
func modify(script, task_object = null):
	var result = {}
	match script.script_name:
		"prevent":
			var amount = script.retrieve_integer_property("amount")
			if !amount:
				var _error = 1
				return {}
			else:
				var prevented_amount = self.prevent_value("amount", amount, task_object)
				return {"amount_prevented" : prevented_amount}
		_:
			var replacements = script.get_property("replacements", {})
			for property in replacements.keys():
				var value = replacements[property]
				match property:
					"subject":
						var new_subjects = SP.retrieve_subjects(value, script)
						replace_subjects(new_subjects, task_object)
						result["TODO"] =  "todo"
					"name":
						replace_ability(value, task_object)
						result["TODO"] =  "todo"
					"additional_tags":
						add_tags(value, task_object)
						result["additional_tags"] = value #TODO only the ones that are new?
					_:
						replace_script_property(property, value, task_object)
						result["TODO"] =  "todo"
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


func get_display_name():
	if display_name:
		return display_name
		
	var task = get_first_task()
	if is_instance_valid(task) and is_instance_valid(task.owner):
		return task.owner.get_property("shortname", "") + "-" + task.script_name

	return ""

var _cache_display_text = ""
func get_display_text():
	if !_cache_display_text:
		_cache_display_text = _get_display_text_nocache()		
	return _cache_display_text

func _get_display_text_nocache():	
	var task = get_first_task()
	var result = get_display_name()
	var subjects = ""	
	if task: 	
		var owner = task.owner
		var owner_name = owner.get_property("shortname", "") if owner else ""

		var separator = ""
		if "subjects" in task:
			for subject in task.subjects:
				var shortname = subject.get_property("shortname","") if subject.is_faceup else "facedown card"
				subjects += separator + shortname
				separator = ", "
			if subjects:
				subjects = " (" + subjects + ")"
			
		match task.script_name:
			"add_threat":
				var amount = task.retrieve_integer_property("amount", 0)
				result = owner_name + " adds " + str(amount) + " threat" + subjects
				return result			
			"reveal_encounter":
				if owner:
					var text = owner.get_printed_text("when revealed")
					if text:
						return text
					var text1 = owner.get_printed_text("When Revealed (Alter-Ego)")	
					var text2 = owner.get_printed_text("When Revealed (Hero)")
					if text1 or text2:
						return "(Alter-Ego) " + text1 + "\n(Hero) " + text2
			"surge":
				result = owner_name + " - Surge"
				return result
		var trigger = self.get_trigger()

		if trigger.begins_with("interrupt"):
			if owner:
				for id in ["forced interrupt", "interrupt", "forced response", "response"]:
					var text = owner.get_printed_text(id)
					if text:
						return text		
		match trigger:							
			"boost":
				if owner:
					var text = owner.get_printed_text("boost")
					if text:
						return text												
	result = result.replace("_", " ")
	result = result + subjects
	if "constraints" in result:
		var _tmp =1
	return result
			


func set_display_name(_name):
	if "constraints" in _name:
		var _tmp = 1
	display_name = _name

func get_first_task_name(meaningful = true):
	var first_task = get_first_task(meaningful)
	if first_task:
		return first_task.script_name
	return ""

const _meaningless_tasks := ["nop", "constraints"]
func get_first_task(meaningful = true):
	for skip_cost_tasks in [true, false]:
		for task in get_tasks():
			if meaningful and (task.script_name in _meaningless_tasks):
				continue
			if skip_cost_tasks and task.has_method("get_property"):
				if task.get_property("is_cost", false):
					continue		
			return task
	return null


static func sort_stack(a, b):
	if a.stack_uid < b.stack_uid:
		return true
	return false
