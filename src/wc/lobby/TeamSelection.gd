extends Node


var heroDeckSelect = preload("res://src/wc/lobby/HeroDeckSelect.tscn")
onready var main_menu := $MainMenu

# Called when the node enters the scene tree for the first time.
func _ready():
	get_viewport().connect("size_changed", self, '_on_Menu_resized')
	
	var heroes_container = get_node("%TeamContainer")
	for i in 4: #TODO 4 should be a custom var
		var new_team_member = heroDeckSelect.instance()
		new_team_member.set_idx(i)
		heroes_container.add_child(new_team_member)

func owner_changed(id, index):
	rpc("remote_owner_changed",id,index)

remote func remote_owner_changed (id, index):
	var heroes_container = get_node("%TeamContainer")
	var heroDeckSelect = heroes_container.get_child(index)
	heroDeckSelect.set_owner(id)

func _on_Menu_resized() -> void:
	for tab in [main_menu]:
		if is_instance_valid(tab):
			tab.rect_size = get_viewport().size
			if tab.rect_position.x < 0.0:
					tab.rect_position.x = -get_viewport().size.x
			elif tab.rect_position.x > 0.0:
					tab.rect_position.x = get_viewport().size.x
