# Represents a Zone on the board that can get cards. 
#Maybe redundant with the Framework's concept of grid?

class_name CardZone
extends Reference

var owner:PlayerData
var cards: Array


func _init():
	owner = gameData.network_players[1] #Default to being owned by master


#add a card to this zone. Calculate X,Y accordingly and add to array of global cards
#add to other indexes as appropriate
func add_card(card:WCCard):
	cards.append(card)
	pass
	
#remove card from this zone. Recalculate other card locations appropriately	
func remove_card(card:WCCard):	
	cards.remove(cards.find(card))
	pass
