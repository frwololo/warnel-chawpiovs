# Card Gaming Framework ScriptingEngine Utilities
#
# This is a library of static functions we had to separate to avoid
# cyclic dependencies
#
# This class needs to have no references to [ScriptingObject]
class_name CFScriptUtils
extends Reference

const _alteration_super_cache := {
	"properties": {},
	"wildcard_properties" : {},
	"initialized": false
}


# Finds all values in a dictionary (including nested dictionaries)
# where the key matches the given target_key.
# Supports nested dictionaries and lists containing dictionaries.
static func find_all_values_by_key(container, target_key: String) -> Array:
	var results: Array = []

	if typeof(container) == TYPE_DICTIONARY:
		for key in container.keys():
			if str(key) == target_key:
				results.append(container[key])
			else:
				results+= find_all_values_by_key(container[key], target_key)  # Recursively search deeper
	elif typeof(container) == TYPE_ARRAY:
		for item in container:
			results+= find_all_values_by_key(item, target_key) # Search inside arrays too	
	else:
		return []
			

	return results

static func init_alterants_super_cache():
	_alteration_super_cache["properties"] = {}
	_alteration_super_cache["wildcard_properties"] = {}
	var scriptables_array :Array =\
		cfc.get_tree().get_nodes_in_group("scriptables")
	
	scriptables_array +=\
			cfc.get_tree().get_nodes_in_group("cards")
	
	for obj in scriptables_array:
		var all_scripts = obj.retrieve_all_scripts()
		var altered_properties = find_all_values_by_key(all_scripts, "filter_property_name")
		for property in altered_properties:
			if property.ends_with("*"):
				property = property.substr(0, property.length() - 1)
				_alteration_super_cache["wildcard_properties"][property] = true
			else:
				_alteration_super_cache["properties"][property] = true

	_alteration_super_cache["initialized"] = true
	return

# Handles modifying the intensity of tasks based on altering scripts on cards
#
# Returns a Dictionary holding two keys
# * value_alteration: The total modification found from all alterants
# * alterants_details: A dictionary where each key is the Card object
# 	of each alterant, and each value is the modification done by that
#	specific alterant.
static func get_altered_value(
		_owner,
		task_name: String,
		task_properties: Dictionary,
		value: int,
		subject = null) -> Dictionary:


	#bypass the whole calculation if we know that no item in the game alters this
	if _alteration_super_cache["initialized"] and task_properties.has(SP.KEY_PROPERTY_NAME):
		var property_name = task_properties[SP.KEY_PROPERTY_NAME]
	
		if ! _alteration_super_cache["properties"].get(property_name):
			for key in _alteration_super_cache["wildcard_properties"]:
				if property_name.begins_with(key):
					_alteration_super_cache["properties"][property_name] = true
					break			

		if ! _alteration_super_cache["properties"].get(property_name):
			return {
					"value_alteration": 0,
					"alterants_details": {}
				}			
					
	# The key for the alterant cache is the hash of the
	# values passed to this function.
	# This is the only way to compare dicts.
	var alterant_cache_key = {
		"_owner_card": _owner,
		"task_name": task_name,
		"task_properties": task_properties,
		"value": value,
		"subject": subject,
	}.hash()
	var return_dict: Dictionary
	# If we've already performed this alterant engine run, we just
	# use the previously discovered value.
	if cfc.alterant_cache.get(alterant_cache_key):
		return_dict = cfc.alterant_cache[alterant_cache_key]
	else:
		var value_alteration := 0
		var alterants_details := {}
		var scriptables_array :Array =\
			cfc.get_tree().get_nodes_in_group("scriptables")
		
		scriptables_array +=\
				cfc.get_tree().get_nodes_in_group("cards")
		for obj in scriptables_array:
			var alterants_key = obj.get_alterants_key()
			if !alterants_key:
				continue
			var scripts = obj.retrieve_scripts(alterants_key)
			# We select which scripts to run from the card, based on it state
			var any_state_scripts = scripts.get('all', [])
			var state_scripts = scripts.get(obj.get_state_exec(), any_state_scripts)			
			# To avoid unnecessary operations
			# we evoke the AlterantEngine only if we have something to execute
			var task_details = _generate_trigger_details(task_name, task_properties)
			if len(state_scripts):
#				if task_properties.get("property_name", "") == "attack" and alterants_key == "boost_alterants" and _owner.get_property("shortname", "") == "Proxima Midnight":
#					var _tmp = 1				
				var alteng = cfc.alterant_engine.new(
						_owner,
						obj,
						state_scripts,
						task_details,
						subject)
				if not alteng.all_alterations_completed:
					yield(alteng,"alterations_completed")
				value_alteration += alteng.alteration
				# We don't want to register alterants which didn't modify the number.
				if alteng.alteration != 0:
					# Each key in the alterants_details dictionary is the
					# card object of the alterant. The value is the alteration
					# this alterant has added to the total.
					alterants_details[obj] = alteng.alteration
		# As a general rule, we don't want a positive number to turn
		# negative (and the other way around) due to an alteration
		# For example: if a card says, "decrease all costs by 3",
		# we don't want a card with 1 cost, to end up giving the player 2 money.
		if value < 0 and value + value_alteration > 0:
			# warning-ignore:narrowing_conversion
			value_alteration = abs(value)
		elif value > 0 and value + value_alteration < 0:
			value_alteration = -value
		return_dict = {
			"value_alteration": value_alteration,
			"alterants_details": alterants_details
		}
		# If this is the first time we discover this alteration value
		# we also store it in our alterant cache
		cfc.alterant_cache[alterant_cache_key] = return_dict
	return(return_dict)

# Parses a [ScriptTask]'s properties and extracts the details a [ScriptAlter]
# needs to check if its allowed to modify that task.
static func _generate_trigger_details(task_name, task_properties) -> Dictionary:
	var details = {
		SP.KEY_TAGS: task_properties.get(SP.KEY_TAGS),
		SP.TRIGGER_TASK_NAME: task_name}
	# This dictionary key is a ScriptEngine task name which can be modified
	# by alterants. The value is an array or task properties we need to pass
	# to the trigger filter, to check if this task is relevant to be altered.
	var details_needed_per_task := {
		"mod_tokens": [SP.KEY_TOKEN_NAME,],
		"mod_counter": [SP.KEY_COUNTER_NAME,],
		"modify_properties": [
			SP.TRIGGER_PROPERTY_NAME,
			SP.KEY_MODIFICATION,
			SP.TRIGGER_PREV_COUNT,
			SP.TRIGGER_NEW_COUNT,
		],
		"spawn_card": [SP.KEY_CARD_NAME,],
		"get_token": [SP.KEY_TOKEN_NAME,],
		"get_property": [SP.KEY_PROPERTY_NAME,],
		"get_counter": [SP.KEY_COUNTER_NAME,],}
	for property in details_needed_per_task.get(task_name,[]):
		details[property] = task_properties.get(property)
	return(details)
