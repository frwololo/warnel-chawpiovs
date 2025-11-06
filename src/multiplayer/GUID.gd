#Class that stores a global UID for an object in the game
class_name GUID
extends Node

var current_guid:int = 0
var guid_to_object:Dictionary = {}
var guid_to_name: Dictionary = {}
var object_to_guid:Dictionary = {}

#sets/gets a guid for a new object and returns the result
func set_guid(stuff) -> int:
	if (object_to_guid.has(stuff)):
		return object_to_guid[stuff]
	current_guid += 1
	guid_to_object[current_guid] = stuff
	if "canonical_name" in stuff:
		guid_to_name[current_guid] = stuff.canonical_name
	else:
		guid_to_name[current_guid] = stuff.name
	object_to_guid[stuff] = current_guid
	return current_guid
	
func get_guid(stuff) -> int:
	if (object_to_guid.has(stuff)):
		return object_to_guid[stuff]	
	return 0 #TODO error case

func get_object_by_guid(uid:int):
	if (guid_to_object.has(uid)):
		return guid_to_object[uid]
	gameData.display_debug("error: couldn't find object for guid:" +str(uid))
	return null	

#Forces a specific guid to align all network clients	
remote func force_set_guid(stuff, uid) -> int:
	guid_to_object[uid] = stuff
	object_to_guid[stuff] = uid
	
	#set current_guid to this value for next occurrences as needed
	if (current_guid < uid):
		current_guid = uid
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
	current_guid = 0
	guid_to_object = {}
	guid_to_name = {}
	object_to_guid = {}
