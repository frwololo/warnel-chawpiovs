extends Pile

# has_card_id moved from src/core CardContainer modifications
func has_card_id(card_id: String) -> Card:
	for card in get_all_cards():
		if card.canonical_id == card_id:
			return(card)
	return(null)
