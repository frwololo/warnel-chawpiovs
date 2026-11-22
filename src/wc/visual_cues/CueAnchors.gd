# Converts a position on this client's board to something every client can
# place on its own board, and back.
#
# Raw coordinates do not work: each client lays out its own hero zone big
# and the other ones small, in its own order (Board.init_board_organizers),
# only shows its own hand, and scales everything to its window
# (cfc.hardcoded_positions_modifier). So a position is sent relative to
# what is under it, the most precise first:
#   "card"  a card on the board: guid, position within the card (0..1)
#   "hand"  the sender's own hand: horizontal position within it (0..1).
#           Other clients do not show that hand: they place it along
#           the bottom of the sender's hero zone
#   "item"  a pile or grid of a hero zone (BoardOrganizer): its name
#           ("allies2"), position within it (0..1)
#   "zone"  elsewhere in a hero zone: hero id, position within it (0..1)
#   "board" anywhere else (villain area...): position on a 1920x1080 board
#   "none"  not on the board
extends Reference

const BOARD_STATES = [
	Card.CardState.ON_PLAY_BOARD,
	Card.CardState.FOCUSED_ON_BOARD,
	Card.CardState.DROPPING_TO_BOARD,
]
const HAND_STATES = [
	Card.CardState.IN_HAND,
	Card.CardState.FOCUSED_IN_HAND,
]

static func encode(position: Vector2, hovered_card = null) -> Dictionary:
	var board = cfc.NMAP.get("board")
	if !board:
		return {"a": "none"}

	if is_instance_valid(hovered_card) and hovered_card.state in BOARD_STATES:
		var local = hovered_card.to_local(position) / hovered_card.card_size
		return {"a": "card", "k": hovered_card.get_guid(), "x": _r(local.x), "y": _r(local.y)}

	var hand = _hand(gameData.get_current_local_hero_id())
	if hand:
		var hand_rect = _container_rect(hand)
		var in_hand = is_instance_valid(hovered_card) and hovered_card.state in HAND_STATES
		if _is_rect(hand_rect) and (in_hand or hand_rect.has_point(position)):
			return {"a": "hand", "x": _r(_fraction(position, hand_rect).x)}

	var zones = []
	for organizer in board.board_organizers:
		var zone_rect = null
		for item_data in organizer.get_item_nodes():
			var rect = _item_rect(item_data["item"])
			if !_is_rect(rect):
				continue
			if rect.has_point(position):
				var f = _fraction(position, rect)
				return {"a": "item", "k": item_data["name"], "x": _r(f.x), "y": _r(f.y)}
			zone_rect = zone_rect.merge(rect) if _is_rect(zone_rect) else rect
		if _is_rect(zone_rect):
			zones.append([organizer.my_hero_id, zone_rect])
	for zone in zones:
		if zone[1].has_point(position):
			var f = _fraction(position, zone[1])
			return {"a": "zone", "k": zone[0], "x": _r(f.x), "y": _r(f.y)}

	var board_position = position / cfc.hardcoded_positions_modifier
	return {"a": "board", "x": stepify(board_position.x, 0.1), "y": stepify(board_position.y, 0.1)}

#where to show, on this client, a position that hero_id's player encoded;
#null if it cannot be shown
static func decode(data: Dictionary, hero_id: int):
	var board = cfc.NMAP.get("board")
	if !board:
		return null
	var f = Vector2(float(data.get("x", 0)), float(data.get("y", 0)))
	match data.get("a", "none"):
		"card":
			var card = guidMaster.get_object_by_guid(str(data.get("k", "")))
			if !is_instance_valid(card) or !(card.state in BOARD_STATES) or !card.is_visible_in_tree():
				return null
			return card.to_global(f * card.card_size)
		"hand":
			var hand_zone_rect = _zone_rect(hero_id)
			if !_is_rect(hand_zone_rect):
				return null
			return Vector2(hand_zone_rect.position.x + f.x * hand_zone_rect.size.x, hand_zone_rect.end.y)
		"item":
			var item = _find_item(str(data.get("k", "")))
			var rect = _item_rect(item) if item else null
			if !_is_rect(rect):
				return null
			return rect.position + f * rect.size
		"zone":
			var hero_zone_rect = _zone_rect(int(data.get("k", 0)))
			if !_is_rect(hero_zone_rect):
				return null
			return hero_zone_rect.position + f * hero_zone_rect.size
		"board":
			return f * cfc.hardcoded_positions_modifier
	return null

#Rect2 or null (comparing a Rect2 to null is an error in Godot 3)
static func _is_rect(value) -> bool:
	return typeof(value) == TYPE_RECT2

static func _r(value: float) -> float:
	return stepify(value, 0.001)

static func _fraction(position: Vector2, rect: Rect2) -> Vector2:
	var result = Vector2(0, 0)
	if rect.size.x:
		result.x = (position.x - rect.position.x) / rect.size.x
	if rect.size.y:
		result.y = (position.y - rect.position.y) / rect.size.y
	return result

static func _hand(hero_id: int):
	var board = cfc.NMAP.get("board")
	if !board or !hero_id:
		return null
	return board.get_node_or_null("%Hand" + str(hero_id))

#rect of a pile, a grid or a hand on the board, null if not shown
static func _item_rect(item):
	if !is_instance_valid(item) or !item.is_visible_in_tree():
		return null
	if item is BoardPlacementGrid:
		var rect: Rect2 = item.get_global_rect()
		for slot in item.get_all_slots():
			rect = rect.merge(slot.get_global_rect())
		return null if rect.has_no_area() else rect
	if item is CardContainer:
		return _container_rect(item)
	return null

static func _container_rect(container):
	if !is_instance_valid(container) or !container.is_visible_in_tree() or !is_instance_valid(container.control):
		return null
	var rect = Rect2(container.control.rect_global_position, container.control.rect_size * container.global_scale)
	return null if rect.has_no_area() else rect

static func _find_item(item_name: String):
	var board = cfc.NMAP.get("board")
	if !board:
		return null
	for organizer in board.board_organizers:
		for item_data in organizer.get_item_nodes():
			if item_data["name"] == item_name:
				return item_data["item"]
	return null

#all the piles and grids of a hero zone, as laid out on this client
static func _zone_rect(hero_id: int):
	var board = cfc.NMAP.get("board")
	if !board:
		return null
	for organizer in board.board_organizers:
		if organizer.my_hero_id != hero_id:
			continue
		var zone_rect = null
		for item_data in organizer.get_item_nodes():
			var rect = _item_rect(item_data["item"])
			if _is_rect(rect):
				zone_rect = zone_rect.merge(rect) if _is_rect(zone_rect) else rect
		return zone_rect
	return null
