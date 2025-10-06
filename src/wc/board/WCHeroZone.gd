class_name WCHeroZone
extends VBoxContainer

#TODO deprecate this class and move this either to HeroDeckData or to the Board
var hero_deck_data: HeroDeckData


var my_id = 0 setget set_player, get_player

# Called when the node enters the scene tree for the first time.
func _ready():
	if (not my_id):
		print_debug("WCHeroZone: error, called ready before id set")
		return	
	

func set_player(id:int):
	my_id = id

func load_hero():
	hero_deck_data = gameData.get_team_member(my_id)["hero_data"]
	var ckey = cfc.idx_card_id_to_name[hero_deck_data.hero_id]
	var card:WCCard = cfc.instance_card(ckey, my_id)
	
	#TODO better
	cfc.NMAP["deck" + str(my_id)].add_child(card)
	var grid: BoardPlacementGrid = cfc.NMAP.board.get_grid("identity" + str(my_id))
	var slot: BoardPlacementSlot
	if grid:
		slot = grid.find_available_slot()
		if slot:
			card.move_to(cfc.NMAP.board, -1, slot)		
	card.set_is_faceup(true)
		

func get_player():
	return my_id

func get_hero_card() -> Card:
	var grid: BoardPlacementGrid = cfc.NMAP.board.get_grid("identity"  + str(my_id))
	var slot: BoardPlacementSlot = grid.get_slot(0)	
	var result:Card = slot.occupying_card
	return result
	
