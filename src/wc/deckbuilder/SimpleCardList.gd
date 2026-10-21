class_name SimpleCardList
extends Control

signal card_clicked(card_code)

onready var cards_container:GridContainer = get_node("%CardsContainer")

var cards_data = []
var cards_size = null

# Called when the node enters the scene tree for the first time.
func _ready():
	refresh_cards()


func refresh_cards():
	for c in cards_container.get_children():
		cards_container.remove_child(c)
	for card_code in cards_data:
		var new_card:SimpleCardDisplay = SimpleCardDisplay.new()
		new_card.connect("pressed", self, "card_clicked", [card_code])
		cards_container.add_child(new_card)
		new_card.load_card(card_code)
		if cards_size:
			new_card.set_card_size(cards_size)
		
			

func init_cards(pack_data):
	cards_data = pack_data.duplicate(true)
	if cards_container:
		refresh_cards()

func card_clicked(card_code):
	emit_signal("card_clicked", card_code)

func set_columns(columns):
	cards_container.columns = columns
		
func set_cards_size(new_size):
	cards_size = new_size
	refresh_cards()
