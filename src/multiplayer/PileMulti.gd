# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED

# Pile with specific Multiplayer functionality
class_name PileMulti
extends Pile

#func _ready():
#	scripting_bus.connect('shuffle_completed', self, '_on_shuffle_completed')	
#
#func _on_shuffle_completed(card_container,details):
#	is_shuffling = false	
#
#	if (card_container != self):
#		return
#
#
#	#if we're the game master, feed the new deck to all peers	
#	if (get_tree().get_network_peer() and cfc.is_game_master()):
#		sort_from_master()
#
#func shuffle_cards(animate = true) -> void:
#	is_shuffling = true
#	#if we're a client in a network game, don't shuffle
#	if (not cfc.is_game_master()):
#		return	
#	else:
#		#do the actual shuffle to get the animation, etc
#		.shuffle_cards(animate) 	
#
#func sort_from_master():
#	if (not get_tree().is_network_server()):
#		return -1
#	rpc("feed_me_cards", get_all_cards_by_guid())
#
#func get_all_cards_by_guid():
#	var cardsArray = get_all_cards()
#	var uidArray:Array = []
#
#	for card in cardsArray:
#		uidArray.append(guidMaster.get_guid(card))
#
#	return uidArray
#
#puppet func feed_me_cards(guidArray:Array):
#	for carduid in guidArray:
#		var card = guidMaster.get_object_by_guid(carduid)
#		move_child(card, guidArray.find(carduid))
#	is_shuffling = false #emit signal instead ?
