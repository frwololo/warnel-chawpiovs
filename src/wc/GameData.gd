class_name GameData
extends Node

#Singleton for game data shared across menus and views
var network_players := {}

var id_to_network_id:= {}


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

func init_network_players(players:Dictionary):
	for player_network_id in players:
		var info = players[player_network_id]
		var new_player_data := PlayerData.new(info.name, info.id, player_network_id)
		network_players[player_network_id] = new_player_data 
		id_to_network_id[info.id] = player_network_id

func get_player_by_index(id):
	return network_players[id_to_network_id[id]]
