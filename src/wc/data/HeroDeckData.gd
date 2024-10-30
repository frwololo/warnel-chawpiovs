class_name HeroDeckData
extends Reference

var owner:PlayerData
var deck_id
var hero_id


func _init():
	owner = gameData.network_players[1] #Default to being owned by master
	deck_id = 0
	hero_id = ""


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

