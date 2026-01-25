# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:UNUSED_VARIABLE
# warning-ignore-all:RETURN_VALUE_DISCARDED

# Represents a spot on the placement grid that is used to organize
# cards on the board.
class_name BoardPlacementSlot
extends Control


# If a card is placed on this spot, this variable will hold a reference
# to the Card object
# and no other card can be placed in this slot
var occupying_card = null
var reserved = null
var card_position_confirmed:= false

# Stores a reference to the owning BoardPlacementGrid object
onready var owner_grid = get_parent().get_parent()

func _ready() -> void:
	if CFConst.HIDE_GRID_BACKGROUND:
		modulate = Color(0,0,0,0)
	rescale()

func _process(delta):
	#due to timing issues sometimes the occupying card gets positioned before this has finished loading
	#So we reposition the card just in case
#	if (!card_position_confirmed):
		if occupying_card:
			var tmp = rect_global_position
			var tmp2 = self.rect_size
			var card_x = occupying_card.card_size.x
			var scale_modifier = get_scale_modifier()
			occupying_card._set_target_position(rect_global_position + Vector2(self.rect_size.x/2 - occupying_card.card_size.x*get_scale_modifier()/2, 0))
		card_position_confirmed = true
	
	
# Returns true if this slot is highlighted, else false
func is_highlighted() -> bool:
	return($Highlight.visible)

#when a card intends to occupy this slot in the near future
func reserve(card):
	reserved = card

#a safer way for a card to remove itself from this slot
#(rather than drectly calling set_occupying_card null)
func remove_occupying_card(card):
	reserved = null
	
	if occupying_card == card:
		set_occupying_card(null)
		card._placement_slot = null

func set_occupying_card(card):
	reserved = null
	
	var slot_was_occupied = (occupying_card !=null)
	if (slot_was_occupied and occupying_card != card):
		if (is_instance_valid(occupying_card)):
			occupying_card._placement_slot = null
		
	occupying_card = card
	if card:
		card._placement_slot = self		
		var tmp = rect_global_position
		var tmp2 = self.rect_size
		card._set_target_position(rect_global_position + Vector2(self.rect_size.x/2 - card.card_size.x*get_scale_modifier()/2, 0))

	card_position_confirmed = false
	
	if (slot_was_occupied and !occupying_card):
		owner_grid.emit_signal("card_removed_from_slot", self)
	if (occupying_card and !slot_was_occupied):
		owner_grid.emit_signal("card_added_to_slot", self)
	

# Changes card highlight colour.
func set_highlight(requested: bool,
		hoverColour = owner_grid.highlight) -> void:
	if CFConst.DEACTIVATE_SLOTS_HIGHLIGHT:
		return
	$Highlight.visible = requested
	if requested:
		$Highlight.modulate = hoverColour


# Returns the name of the grid which is hosting this slot.
# This is typically used with CFConst.BoardDropPlacement.SPECIFIC_GRID
func get_grid_name() -> String:
	return(owner_grid.name_label.text)

func reposition(new_position:Vector2):
	if (occupying_card):
		occupying_card._maintain_rotation_when_moving = true
		occupying_card.move_to(cfc.NMAP.board, -1, self)	
	pass

func rescale():
	if (!owner_grid):
		return
	var tmp = owner_grid.card_size *  owner_grid.card_play_scale
	var max_axis = max(tmp.x, tmp.y)
	var tmp2:Vector2 = Vector2(max_axis, max_axis)
	rect_min_size = tmp2
	self.rect_size = rect_min_size		
	
	$Area2D/CollisionShape2D.shape.extents = rect_min_size / 2
	$Area2D/CollisionShape2D.position = rect_min_size / 2
	
	$Highlight.rect_min_size = tmp2
	$Highlight.rect_size = tmp2
	
	card_position_confirmed = false
	
func get_scale_modifier() -> float:
	if (!owner_grid):
		return CFConst.PLAY_AREA_SCALE	
	return owner_grid.card_play_scale
