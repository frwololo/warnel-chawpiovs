# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED

class_name WCHeroZone
extends VBoxContainer

#TODO deprecate this class and move this either to HeroDeckData or to the Board
var hero_deck_data: HeroDeckData
var identity_card = null

var my_id = 0 setget set_player, get_player

# Called when the node enters the scene tree for the first time.
func _ready():
	if (not my_id):
		print_debug("WCHeroZone: error, called ready before id set")
		return	
	

func set_player(id:int):
	my_id = id

func load_starting_identity():
	hero_deck_data = gameData.get_team_member(my_id)["hero_data"]
	var hero_card_data = cfc.get_card_by_id(hero_deck_data.hero_id)
	var alter_ego_id = hero_card_data.get("back_card_code", "")
	if !alter_ego_id:
		#TODO error
		return
	var ckey = cfc.idx_card_id_to_name[alter_ego_id]
	load_identity (ckey)
	
func load_identity(card_name):
	var card = cfc.instance_card(card_name, my_id)
	
	#TODO better
	cfc.NMAP["deck" + str(my_id)].add_child(card)
	var grid: BoardPlacementGrid = cfc.NMAP.board.get_grid("identity" + str(my_id))
	var slot: BoardPlacementSlot
	if grid:
		slot = grid.get_slot(0)   # .find_available_slot()
		if slot:
			card.move_to(cfc.NMAP.board, -1, slot)		
	card.set_is_faceup(true)
	identity_card = card
	return identity_card
		

func get_player():
	return my_id

func get_identity_card():
	return identity_card
	
func is_hero_form() -> bool:
	var hero_card = get_identity_card()
	if "hero" == hero_card.properties.get("type_code", ""):
		return true
	return false
	
func is_alter_ego_form() -> bool:
	return !is_hero_form()		
