#Data that represents the Deck of cards of a hero

class_name HeroDeckData
extends Reference

const ORDERED_PLAYER_TYPES = ["hero", "ally", "event", "upgrade", "support",  "resource", "player_side_scheme",]

var owner:PlayerData
var deck_id
var _hero_id setget set_hero_id,get_hero_id
var deck_data:= {}
var _flattened_deck_data:= []
var _cards_by_type:= {}

func set_hero_id(id):
	_hero_id = id

func get_hero_id():
	return _hero_id

func _init():
	if gameData.network_players:
		owner = gameData.network_players[1] #Default to being owned by master
	else:
		owner = PlayerData.new("tmp_user_name", 1, 1)
	deck_id = 0
	_hero_id = ""

func get_hero_card_data() -> Dictionary:
	return cfc.get_card_by_id(_hero_id)
	
func get_alter_ego_card_data() -> Dictionary:
	var card_data = get_hero_card_data()
	var alter_ego_data = card_data.get("linked_card", {})
	if !alter_ego_data:
		var linked_card_id = card_data.get("linked_to_code", "")
		if linked_card_id:
			alter_ego_data = cfc.get_card_by_id(linked_card_id)
	return alter_ego_data	

static func _get_deck_cards(_deck_data):
	var result : Array = []
	var slots = _deck_data.slots
	for card_id in slots:
		var quantity = slots[card_id]
		var card_data = cfc.get_card_by_id(card_id)		
		for _i in range (quantity):
			result.append(card_data)
	return result	

func clear_cache():
	_flattened_deck_data = []
	_cards_by_type = {}

func set_deck_id(_deck_id):
	if !_deck_id:
		return
	clear_cache()
	deck_data = cfc.deck_definitions[_deck_id].duplicate(true)
	_flattened_deck_data = _get_deck_cards(deck_data)

func add_card(card_id):
	clear_cache()
	var slots = deck_data["slots"]
	if !slots.has(card_id):
		slots[card_id] = 0
	slots[card_id] += 1

func set_deck_data(_deck_data):
	if !deck_id:
		if _deck_data.has("id"):
			deck_id = _deck_data.get("id")
	if !_hero_id:
		var hero_id = _deck_data.get("hero_code",_deck_data.get("investigator_code", ""))
		_hero_id = hero_id
	
	deck_data = _deck_data.duplicate()
	_flattened_deck_data = _get_deck_cards(deck_data)
			
func get_deck_cards():
	if !_flattened_deck_data:
		if deck_data:
			_flattened_deck_data = _get_deck_cards(deck_data)
		elif deck_id:
			set_deck_id(deck_id)

	return _flattened_deck_data

func get_cards_by_type(include_hero = false):
	if !_cards_by_type:
		var cards = get_deck_cards()
		for card in cards:
			var card_code = card["code"]
			var card_type = card.get("type_code", "")
			if !_cards_by_type.has(card_type):
				_cards_by_type[card_type] = {}
			if !_cards_by_type[card_type].has(card_code):
				_cards_by_type[card_type][card_code] = 0
			_cards_by_type[card_type][card_code] += 1
		if include_hero:
			_cards_by_type["hero"] = {_hero_id: 1}			
	return _cards_by_type

#any additional cards from a hero that need to be set aside during setup
func get_extra_deck_cards(container:= "set_aside"):
	var alter_ego_data = get_alter_ego_card_data()
	var alter_ego_id = alter_ego_data.get("_code", "")
	if !alter_ego_id:
		#TODO error
		return []
	
	var result = []
	var extra_cards_str = "additional_cards_" + container		
	var extra_cards = cfc.set_scripts.get(alter_ego_id,{}).get(extra_cards_str,[]).duplicate(true)

	for card in extra_cards:
		var card_id_or_name = card.get("card", "")
		if !card_id_or_name:
			continue
		var card_id = cfc.get_corrected_card_id(card_id_or_name)
		var card_data = cfc.get_card_by_id(card_id)
		var quantity = card.get("quantity", 1)
		card_data["_setup_quantity"] = quantity
		result.append(card_data)

	return result

func savestate_to_json() -> Dictionary:
	var json_data:Dictionary = {
		"herodeckdata": {
			"owner" : self.owner.get_id(),
			"deck_id" : self.deck_id,
			"hero" : self._hero_id
		}
	}
	return json_data
	
func loadstate_from_json(json:Dictionary) -> bool:
	var json_data = json.get("herodeckdata", null)
	if (null == json_data):
		#herodeckdata should always be set, even if with minimalistic info
		return false
	var owner_id:int = 	int(json_data.get("owner", 1))
	owner = gameData.network_players.get(gameData.id_to_network_id.get(owner_id)) #Default to being owned by master
	deck_id = json_data.get("deck_id", -1) #-1 here to force initialization if needed
	
	#Hero might be a card id or card name. We try to accomodate for both use cases here
	var hero:String = json_data.get("hero", "")
	if (!hero):
		#TODO error
		return false
	_hero_id = cfc.get_corrected_card_id(hero, {"type_code": "hero"})
	return true

	

static func get_hero_base_deck(hero_id):
	var hero_data = cfc.get_card_by_id(hero_id)
	var set_name = hero_data["card_set_code"].to_lower()
	var all_set_cards = cfc.cards_by_set[set_name]
	var slots = {}
	for card in all_set_cards:
		var type = card["type_code"].to_lower()
		if type in ["hero", "alter_ego", "obligation"]:
			continue 
		if !type in CFConst.PLAYER_CARD_TYPES:
			continue
		var quantity = card.get("quantity", 1)
		slots[card["_code"]] = quantity

	return {
		"id": "base_" + hero_id,
		"hero_code": hero_id,
		"slots": slots		
	}
