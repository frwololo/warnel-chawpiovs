#Data that represents the Deck of cards of a hero

class_name HeroDeckData
extends Reference

var owner:PlayerData
var deck_id
var hero_id


func _init():
	owner = gameData.network_players[1] #Default to being owned by master
	deck_id = 0
	hero_id = ""

func get_hero_card_data() -> Dictionary:
	return cfc.get_card_by_id(hero_id)
	
func get_alter_ego_card_data() -> Dictionary:
	var card_data = get_hero_card_data()
	var alter_ego_data = card_data["linked_card"]
	return alter_ego_data	

func get_deck_cards(): #todo cache?
	var result : Array = []
	if (not deck_id):
		return result
	var deck_data = cfc.deck_definitions[deck_id]
	var slots = deck_data.slots
	for card_id in slots:
		var quantity = slots[card_id]
		for i in range (quantity):
			result.append(card_id)
	return result


func savestate_to_json() -> Dictionary:
	var json_data:Dictionary = {
		"herodeckdata": {
			"owner" : self.owner.get_id(),
			"deck_id" : self.deck_id,
			"hero" : self.hero_id
		}
	}
	return json_data
	
func loadstate_from_json(json:Dictionary) -> bool:
	var json_data = json.get("herodeckdata", null)
	if (null == json_data):
		#herodeckdata should always be set, even if with minimalistic info
		return false
	var owner_id:int = 	int(json_data.get("owner", 0) + 1)
	owner = gameData.network_players.get(owner_id) #Default to being owned by master
	deck_id = json_data.get("deck_id", 0)
	
	#Hero might be a card id or card name. We try to accomodate for both use cases here
	var hero:String = json_data.get("hero", "")
	if (!hero):
		#TODO error
		return false
	var hero_card_name = cfc.lowercase_card_name_to_name.get(hero.to_lower(), "")
	if (hero_card_name):
		hero_id = cfc.card_definitions[hero_card_name]["_code"]
	else:
		hero_id = hero
	return true

