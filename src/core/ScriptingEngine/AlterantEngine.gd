# This class contains all the functionality required to modify a
# running task during runtime
#
# The automation is based on [ScriptAlter] definitions. 
#
# This class is on request when one of a number of specific tasks
# which allow it, are going through all the cards, looking for valid Alterants
# definitions. 
class_name AlterantEngine
extends Reference

const _ASK_INTEGER_SCENE_FILE = CFConst.PATH_CUSTOM + "AskInteger.tscn"
const _ASK_INTEGER_SCENE = preload(_ASK_INTEGER_SCENE_FILE)

# Emitted when all alterations have been run succesfully
signal alterations_completed

# This is checked by the yield in [get_altered_value](CFScriptUtils#get_altered_value)
# to know execution has completed.
var all_alterations_completed := false
# The total amount of alterations that this card's script will perform.
var alteration := 0
# In case the alteration is dependent on a subject, we store the one we're checking against here.
var subject
# The gathered list of alterant tasks objects to calcaulte
var alterants_queue: Array

func _ready() -> void:
	pass # Replace with function body.


# Sets the owner of this Scripting Engine
func _init(
		trigger_object: Card,
		alterant_object,
		scripts_queue: Array,
		task_details: Dictionary,
		_subject) -> void:
	subject = _subject
	var _scripts_queue = common_pre_run(scripts_queue, trigger_object)
	for alter_task_def in _scripts_queue:
		var alter_task := ScriptAlter.new(
				alter_task_def,
				trigger_object,
				alterant_object,
				task_details,
				subject)
		alterants_queue.append(alter_task)
	# Unlike Scripting Engine, the Alterant Engine executes immediately
	# As we don't have pre/post functions (yet)
	execute()

# The main engine starts here.
# It takes the array with all the possible alterations to execute,
# then turns each array element into a [ScriptAlter] object which check
# against the relevant filters and per_ requests.
func execute() -> void:
	for alter_task in alterants_queue:
		if not alter_task.is_primed:
			yield(alter_task,"primed")
		if alter_task.is_valid:
			calculate_alteration(alter_task)
	all_alterations_completed = true
	emit_signal("alterations_completed")


# This is called if the alterants passes all validity checks
# it calculates how much to alter, based on the script definition.
func calculate_alteration(script: ScriptAlter) -> void:
	var alteration_requested = script.get_property(SP.KEY_ALTERATION)
	if str(alteration_requested) == "custom_script":
		var custom := CustomScripts.new(false)
		alteration_requested += custom.custom_alterants(script)
	elif SP.VALUE_PER in str(alteration_requested):
		var per_definition = script.get_property(script.get_property(SP.KEY_ALTERATION))
		var per_msg = perMessage.new(
				script.get_property(SP.KEY_ALTERATION),
				script.owner,
				per_definition,
				script.trigger_object)

		#TODO this is a very hacky way to handle cards such as absorbing man ,which says:
		#"absorbing man gets the trait of each environment in play"
		#this is defined as "trait_*" in filter_property_name for alterants,
		#but after that we need to filter out the environments that only have the property we're trying to mimic
		var filters = {}
		if per_definition.get("filter_has_requested_property", false):
			var property_name = script.trigger_details.get("property_name", "")
			if property_name:
				filters = {"has_property" : property_name}
#		var property_name_filter = script.get_property("filter_property_name")
#		var filters = {}
#		if property_name_filter:
#				if property_name_filter.ends_with("*"):
#					var property_name = script.trigger_details.get("property_name", "")
#					property_name_filter = property_name_filter.substr(0, property_name_filter.length()-1)
#					if !property_name.begins_with(property_name_filter):
#						alteration = 0
#						return	
#					filters = {"has_property" : property_name}				
				
		alteration += per_msg.count_found_things(filters)
		if alteration:
			var _tmp =1
	else:
		alteration += alteration_requested

func common_pre_run(scripts_queue, _trigger_object):
	return scripts_queue.duplicate(true)
