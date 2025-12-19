class_name UserInteractionAuthority
extends Reference

var owner_card = null
var trigger_card = null
var trigger
var trigger_details
var run_type
var authority_cache := {}

var _last_error

func _init (
		_owner_card,
		_trigger_card = null,
		_trigger: String = "manual",
		_trigger_details: Dictionary = {},
		_run_type := CFInt.RunType.NORMAL):
	owner_card = _owner_card
	trigger_card = _trigger_card
	if !trigger_card:
		trigger_card = owner_card
	trigger = _trigger
	trigger_details = _trigger_details
	run_type = _run_type

func interaction_authorized() -> bool:
	var authority_status = compute_authority()
	return authority_status["authorized"]

func authorized_hero_id() -> bool:
	var authority_status = compute_authority()
	return authority_status["authorized_hero_id"]

func compute_authority() -> Dictionary:
	if authority_cache:
		return authority_cache
	
	authority_cache = {
		"authorized": false,
		"authorized_hero_id": 0,
		"authorized_network_id": 0,
		"error": ""
	}	
	
	if !owner_card:
		authority_cache["error"] = "UserInteractionAuthority uninitialized"
		return authority_cache

	if (owner_card.get_owner_hero_id() == -1):
		authority_cache["error"] = "Requesting card has no owner"
		return authority_cache
	
	if owner_card.canonical_name == CFConst.SCRIPT_BREAKPOINT_CARD_NAME and trigger == CFConst.SCRIPT_BREAKPOINT_TRIGGER_NAME:
		var _tmp = 1

	var override_controller_id = trigger_details.get("override_controller_id", 0)
	var for_hero_id = trigger_details.get("for_hero_id", 0)

	var authorized_hero_id = override_controller_id if override_controller_id else for_hero_id

	if override_controller_id:
		if gameData.get_current_local_hero_id() != override_controller_id:
			authority_cache["error"] = "Current Local hero id (" +  str(gameData.get_current_local_hero_id()) + ") not matching override " + str(override_controller_id)
			return authority_cache
	else:
	#can only trigger if I'm the controller of the ability or if enemy card (will send online to other clients)

		if for_hero_id:
			if !gameData.can_hero_play_this_ability(for_hero_id, owner_card):
				authority_cache["error"] = "Requested for_hero_id (" +  str(for_hero_id) + ") cannot play this ability"
				return authority_cache
		else:
			var allowed_hero_id = gameData.can_i_play_this_ability(owner_card, trigger)
			if allowed_hero_id:
				authorized_hero_id = allowed_hero_id
			else:
				authority_cache["error"] = "I am not allowed to play " + owner_card.canonical_name
				return authority_cache
		
	#enemy cards, multiple players can react except when they're the specific target
	if owner_card.get_controller_hero_id() <= 0:
		var can_i_play_enemy_card = false
		var allowed_heroes = gameData.get_currently_playing_hero_ids()
		if !allowed_heroes:
#			cfc.LOG("error in compute_authority : no allowed heroes to play " + trigger + " for " + owner_card.canonical_name)
			allowed_heroes = [gameData.first_player_hero_id()] 
		#ran into a bug were an encounter ability triggered twice,
		#executed once by each player. We want to avoid that
		if trigger != "manual" and allowed_heroes.size() > 1:
			if trigger_details.get("use_stack", true):
				#might need to find a better approach
				allowed_heroes = [allowed_heroes[0]]
			
		if for_hero_id:
			if for_hero_id in allowed_heroes:
				can_i_play_enemy_card = true
		else:	
			for my_hero in (gameData.get_my_heroes()):
				if my_hero in (allowed_heroes):
					can_i_play_enemy_card = true
					authorized_hero_id = my_hero
		if !can_i_play_enemy_card:
			authority_cache["error"] = "not allowed to play enemy card"
			return authority_cache

	#looks like I'm good to go!
	authority_cache = {
		"authorized": true,
		"authorized_hero_id": authorized_hero_id,
		"authorized_network_id": cfc.get_network_unique_id(),
		"error": ""
	}
	return authority_cache	
