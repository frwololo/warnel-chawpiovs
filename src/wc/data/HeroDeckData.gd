#Data that represents the Deck of cards of a hero

class_name HeroDeckData
extends Reference

var owner:PlayerData
var deck_id
var _hero_id setget set_hero_id,get_hero_id

func set_hero_id(id):
	_hero_id = id

func get_hero_id():
	return _hero_id

func _init():
	owner = gameData.network_players[1] #Default to being owned by master
	deck_id = 0
	_hero_id = ""

func get_hero_card_data() -> Dictionary:
	return cfc.get_card_by_id(_hero_id)
	
func get_alter_ego_card_data() -> Dictionary:
	var card_data = get_hero_card_data()
	var alter_ego_data = card_data["linked_card"]
	return alter_ego_data	

static func _get_deck_cards(_deck_id):
	var result : Array = []
	if (not _deck_id):
		return result
	var deck_data = cfc.deck_definitions[_deck_id]
	var slots = deck_data.slots
	for card_id in slots:
		var quantity = slots[card_id]
		for _i in range (quantity):
			var card_data = cfc.get_card_by_id(card_id)
			result.append(card_data)
	return result	
	
func get_deck_cards(): #todo cache?
	return _get_deck_cards(deck_id)


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
	_hero_id = cfc.get_corrected_card_id(hero)
	return true

	
	
