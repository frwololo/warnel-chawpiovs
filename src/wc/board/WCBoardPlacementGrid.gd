extends BoardPlacementGrid

# Override to use WCBoardPlacementSlot instead of BoardPlacementSlot
const _WC_SLOT_SCENE_FILE = "res://src/wc/board/WCBoardPlacementSlot.tscn"
var _WC_SLOT_SCENE = null

func _ready() -> void:
	._ready()
	# Load the WC slot scene
	_WC_SLOT_SCENE = load(_WC_SLOT_SCENE_FILE)

# Override add_slot to create WCBoardPlacementSlot instances
func add_slot() -> BoardPlacementSlot:
	if _WC_SLOT_SCENE:
		var new_slot : BoardPlacementSlot = _WC_SLOT_SCENE.instance()
		$GridContainer.add_child(new_slot)
		return(new_slot)
	else:
		# Fallback to parent if scene not loaded
		return .add_slot()

# get_all_cards and has_card moved from src/core BoardPlacementGrid modifications
func get_all_cards() -> Array:
	var results:Array = []
	var slots:Array = get_all_slots()
	for slot in slots:
		var card = slot.occupying_card
		if card : results.append(card)
	return results

func has_card(card) -> bool:
	var all_cards = get_all_cards()
	return (card in all_cards)

# delete_all_slots and delete_all_slots_but_one moved from src/core BoardPlacementGrid modifications
func delete_all_slots():
	var slots:Array = get_all_slots()
	for slot in slots:
		$GridContainer.remove_child(slot)
		slot.queue_free()
	return

func delete_all_slots_but_one():
	var slots:Array = get_all_slots()
	slots.pop_front()
	for slot in slots:
		$GridContainer.remove_child(slot)
		slot.queue_free()
	return

# reposition function moved from src/core BoardPlacementGrid modifications
func reposition(new_position:Vector2, forced = false):
	if rect_position == new_position and !forced:
		return
	rect_position = new_position

	var slots:Array = get_all_slots()
	for slot in slots:
		# Check if slot has reposition method (WCBoardPlacementSlot) or skip if not
		if slot.has_method("reposition"):
			slot.reposition(new_position)

# rescale function moved from src/core BoardPlacementGrid modifications
func rescale(scale, forced:bool = false):
	if scale == card_play_scale and !forced:
		return
	card_play_scale = scale

	var slots:Array = get_all_slots()
	for slot in slots:
		# Check if slot has rescale method (WCBoardPlacementSlot) before calling
		if slot.has_method("rescale"):
			slot.rescale()

	rect_size = (card_size * card_play_scale) + Vector2(4,4)
