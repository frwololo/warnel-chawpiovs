extends OVUtils


func get_subjects(script: ScriptObject, _subject_request, _stored_integer : int = 0) -> Array:
	var results: Array = []
	match _subject_request:
		SP.KEY_SUBJECT_V_HOST:
			var owner:WCCard = script.owner
			if (owner.current_host_card):
				results.append(owner.current_host_card)
	return results
