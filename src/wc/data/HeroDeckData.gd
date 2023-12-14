class_name HeroDeckData
extends Reference

var owner:PlayerData
var deck_id
var hero_id


func _init():
	owner = gameData.network_players[1] #Default to being owned by master
	deck_id = 0
	hero_id = ""
# Declare member variables here. Examples:
# var a = 2
# var b = "text"

