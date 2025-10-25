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

# Stores a reference to the owning BoardPlacementGrid object
onready var owner_grid = get_parent().get_parent()

func _ready() -> void:
	# We set the initial size of our highlight and area, to 
	# fit the size of the cards on the board.

#	rect_min_size = Vector2(0,0)
#	self.rect_size = Vector2(0,0)
#
#	#$Area2D/CollisionShape2D.scale = Vector2(0.1, 0.1)
#
#	$Area2D/CollisionShape2D.shape.extents = Vector2(0,0)
#	$Area2D/CollisionShape2D.position = Vector2(0,0)
#
#	$Highlight.rect_min_size = Vector2(0,0)
#	$Highlight.rect_size = Vector2(0,0)
	

	
	rescale()


# Returns true if this slot is highlighted, else false
func is_highlighted() -> bool:
	return($Highlight.visible)


func set_occupying_card(card):
	var slot_was_occupied = (occupying_card !=null)
	occupying_card = card

	if card:
		var tmp = rect_global_position
		var tmp2 = self.rect_size
		card._set_target_position(rect_global_position + Vector2(self.rect_size.x/2 - card.card_size.x/2*get_scale_modifier(), 0))
	
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
	
func get_scale_modifier() -> float:
	if (!owner_grid):
		return CFConst.PLAY_AREA_SCALE	
	return owner_grid.card_play_scale
