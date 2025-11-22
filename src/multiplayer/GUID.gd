#Class that stores a global UID for an object in the game
#All network clients just need to ensure the GUIDS are 
#created in the exact same order for cards thay want to compare
#this can be enforced by having the master create the cards
#and sending that exact same list for clients to create
class_name GUID
extends Node

var current_guid_int:int = 0
var guid_to_object:Dictionary = {}
var guid_to_name: Dictionary = {}
var object_to_guid:Dictionary = {}


func int_to_guid(int_guid:int) -> String:
	return "guid_" + str(int_guid)

static func is_guid(to_test) -> bool:
	if not typeof(to_test) == TYPE_STRING:
		return false
	if not to_test.begins_with("guid_"):
		return false
	return true	

func guid_to_int(guid:String) -> int:
	if not (is_guid(guid)):
		return 0
	var guid_str = guid.substr(5)
	return int(guid_str)
	
#sets/gets a guid for a new object and returns the result
func set_guid(stuff) -> int:
	if (object_to_guid.has(stuff)):
		return object_to_guid[stuff]
	current_guid_int += 1
	var current_guid = int_to_guid(current_guid_int)
	guid_to_object[current_guid] = stuff
	if "canonical_name" in stuff:
		guid_to_name[current_guid] = stuff.canonical_name
	else:
		guid_to_name[current_guid] = stuff.name
	object_to_guid[stuff] = current_guid
	return current_guid
	
func get_guid(stuff) -> String:
	if (object_to_guid.has(stuff)):
		return object_to_guid[stuff]	
	return "guid_unknown" #TODO error case

func get_object_by_guid(uid:String):
	if (guid_to_object.has(uid)):
		return guid_to_object[uid]
	gameData.display_debug("error: couldn't find object for guid:" + uid)
	return null	

#Forces a specific guid to align all network clients	
remote func force_set_guid(stuff, uid) -> String:
	guid_to_object[uid] = stuff
	object_to_guid[stuff] = uid
	var uid_int =  guid_to_int(uid)
	#set current_guid to this value for next occurrences as needed
	if (current_guid_int < uid_int):
		current_guid_int = uid_int
	return uid

func array_of_objects_to_guid(objects:Array)-> Array:
	var results:Array = []
	for o in objects:
		var uid = get_guid(o)
		results.append(uid)
	return results
	
func array_of_guid_to_objects(uids:Array)-> Array:
	var results:Array = []
	for uid in uids:
		var o = get_object_by_guid(uid)
		results.append(o)
	return results
	
func get_guids_check_data():
	var result = {}
	for guid in guid_to_object:
		result[guid] = guid_to_name[guid]
	return result

func reset():
	current_guid_int = 0
	guid_to_object = {}
	guid_to_name = {}
	object_to_guid = {}

func replace_guids_to_objects (script_definition):
	var result
	match typeof(script_definition):
		TYPE_DICTIONARY:
			result = {}	
			for key in script_definition.keys():
				result[key] = replace_guids_to_objects(script_definition[key])
		TYPE_ARRAY:	
			result = []
			for value in script_definition:
				result.append(replace_guids_to_objects(value))
		TYPE_STRING:
			if guid_to_object.has(script_definition):
				result = guid_to_object[script_definition]
			else:
				result = script_definition
		_:
			result = script_definition
	return result;
	
func replace_objects_to_guids (script_definition):
	var result
	match typeof(script_definition):
		TYPE_DICTIONARY:
			result = {}	
			for key in script_definition.keys():
				result[key] = replace_objects_to_guids(script_definition[key])
		TYPE_ARRAY:	
			result = []
			for value in script_definition:
				result.append(replace_objects_to_guids(value))
		TYPE_OBJECT:
			if (object_to_guid.has(script_definition)):
				result = object_to_guid[script_definition]
			else:
				result = script_definition	
		_:
			result = script_definition
	return result;	
