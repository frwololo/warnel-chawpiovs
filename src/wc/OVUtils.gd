extends OVUtils


func get_subjects(script: ScriptObject, _subject_request, _stored_integer : int = 0) -> Array:
	var results: Array = []
	match _subject_request:
		SP.KEY_SUBJECT_V_HOST:
			var owner:WCCard = script.owner
			if (owner.current_host_card):
				results.append(owner.current_host_card)
		SP.KEY_SUBJECT_V_MY_HERO:
			var owner:WCCard = script.owner
			var hero_card = gameData.get_identity_card(owner.get_controller_hero_id())
			if (hero_card.is_hero_form()):
				results.append(hero_card)
		SP.KEY_SUBJECT_V_MY_IDENTITY:
			var owner:WCCard = script.owner
			var hero_card = gameData.get_identity_card(owner.get_controller_hero_id())
			results.append(hero_card)
		SP.KEY_SUBJECT_V_MY_ALTER_EGO:
			var owner:WCCard = script.owner
			var hero_card = gameData.get_identity_card(owner.get_controller_hero_id())
			if (hero_card.is_alter_ego_form()):
				results.append(hero_card)							
		SP.KEY_SUBJECT_V_VILLAIN:
			results.append(gameData.get_villain())					
	return results
