class_name PlayerData
extends Reference

var name = "Player" setget set_name, get_name
var id = 0 setget set_id, get_id
var network_id = 0 setget set_network_id, get_network_id

#Getters/Setters
func _init(_name:String, _id:int, _network_id:int):
	name = _name
	id = _id
	network_id = _network_id

func set_name(a:String):
	name = a
	
func get_name():
	return name
	
func set_id(i:int):
	id = i
	
func get_id():
	return id

func set_network_id(i:int):
	network_id = i
	
func get_network_id():
	return network_id
