extends BoardPlacementSlot

# reposition function moved from src/core BoardPlacementSlot modifications
func reposition(new_position:Vector2):
	if (occupying_card):
		occupying_card._maintain_rotation_when_moving = true
		occupying_card.move_to(cfc.NMAP.board, -1, self)
	pass

# rescale function moved from src/core BoardPlacementSlot modifications
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
