class_name WCHeroZone
extends VBoxContainer


var hero_deck_data: HeroDeckData
onready var row1 := $Row1 #engaged enemies
onready var row2 := $Row2 #hero, allies
onready var row3 := $Row3 #support
onready var row4 := $Row4 #draw, discard, support

var my_id = 0 setget set_player, get_player

# Called when the node enters the scene tree for the first time.
func _ready():
	if (not my_id):
		print_debug("WCHeroZone: error, called ready before id set")
		return	
	hero_deck_data = gameData.get_team_member(my_id)["hero_data"]
	var ckey = cfc.idx_card_id_to_name[hero_deck_data.hero_id]
	var card = cfc.instance_card(ckey)
	card.set_is_faceup(true)
	row2.add_child(card)

func set_player(id:int):
	my_id = id
	#CFC expects all piles to have unique names at setup
	var deck_name = "Deck" + str(id)
	var discard_name = "Discard" + str(id)
	$Row4/ControlDeck/Deck.set_pile_name(deck_name)
	$Row4/ControlDiscard/Discard.set_pile_name(discard_name)
	$Row4/ControlDeck/Deck.name = deck_name
	$Row4/ControlDiscard/Discard.name = discard_name

func get_player():
	return my_id

func get_hero_card() -> Card:
	var result:Card = row2.get_child(0)
	return result
	
# Returns an array with all children nodes which are of Card class
func get_all_cards() -> Array:
	var cardsArray := []
	for row in get_children():
		if row as Container:
			for obj in row.get_children():
				if obj as Card: cardsArray.append(obj)	
	return(cardsArray)

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
