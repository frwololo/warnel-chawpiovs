class_name WCMousePointer
extends MousePointer

# Modifications from src/core/MousePointer.gd migration
# In Godot 3.6.2, parent's _ready() and _process() run BEFORE child's versions
# We initialize cfc.NMAP["hand"] = null in CFControlExtended to prevent errors
# in the parent's _process() which accesses cfc.NMAP.hand

func _process(_delta: float) -> void:
	# Override to change hand check from cfc.NMAP.hand to is_in_group("hands")
	# and use set_current_focused_card() instead of direct assignment
	if current_focused_card:
		# After a card has been dragged, it generally clears its
		# focused state. This check ensures that if the mouse hovers over
		# the card still after the drag, we focus it again
		if current_focused_card.get_parent() == cfc.NMAP.board \
				and current_focused_card.state == Card.CardState.ON_PLAY_BOARD:
			current_focused_card.state = Card.CardState.FOCUSED_ON_BOARD
		# Changed from cfc.NMAP.hand to is_in_group("hands") to support multiple hands
		if current_focused_card.get_parent().is_in_group("hands") \
				and current_focused_card.state == Card.CardState.IN_HAND:
			current_focused_card.state = Card.CardState.FOCUSED_IN_HAND
	if cfc.card_drag_ongoing and cfc.card_drag_ongoing != current_focused_card:
		# Changed to use set_current_focused_card instead of direct assignment
		set_current_focused_card(cfc.card_drag_ongoing)
	if cfc._debug:
		$DebugShape/current_focused_card.text = "MOUSE: " + str(current_focused_card)

func _on_MousePointer_area_entered(area: Area2D) -> void:
	# Override to uncomment the print statement
	if not is_disabled:
		# We add an extra check in case that the card was not cleared from overlaps
		# through the _on_MousePointer_area_exited function
		# (sometimes it happens. Haven't figured out what causes it)
		_check_for_stale_overlaps()
		overlaps.append(area)
		print("enter:",area.name)
		_discover_focus()

func _on_MousePointer_area_exited(area: Area2D) -> void:
	# Override to change from "if area as Card or area as CardContainer" to separate checks
	if not is_disabled:
		# We stop the highlight on any areas we exit with the mouse.
		if area as Card :
			var _temp = 1
		elif area as CardContainer:
			area.highlight.set_highlight(false)
		elif area.get_parent() as BoardPlacementSlot:
			area.get_parent().set_highlight(false)
		overlaps.erase(area)
		_discover_focus()

func forget_focus() -> void:
	# Override to use set_current_focused_card instead of direct assignment
	set_current_focused_card(null)

# New function added in migration
func set_current_focused_card(value):
	if current_focused_card == value:
		return
	if current_focused_card:
		current_focused_card._on_Card_mouse_exited()

	current_focused_card = value
	if current_focused_card:
		current_focused_card._on_Card_mouse_entered()

func _discover_focus() -> void:
	# Override to add DISABLE_MANUAL_ATTACHMENTS check, DEACTIVATE_SLOTS_HIGHLIGHT check,
	# and use set_current_focused_card() instead of direct assignment
	var potential_cards := []
	var potential_slots := []
	var potential_containers := []
	var potential_hosts := []
	# We might overlap cards or their token drawers, but we hihglight
	# only cards.
	for area in overlaps:
		if area as Card:
			potential_cards.append(area)
			# To check for potential hosts, the card has to be dragged
			# And it has to be an attachment
			# and the checked area has to not be the dragged card
			# and the checked area has to not be an attachment to the
			# dragged card
			# and the checked area has to be on the board
			if current_focused_card \
					and current_focused_card == cfc.card_drag_ongoing \
					and (current_focused_card.attachment_mode != Card.AttachmentMode.DO_NOT_ATTACH) \
					and area != current_focused_card \
					and not area in current_focused_card.attachments \
					and area.state == Card.CardState.ON_PLAY_BOARD:
						potential_hosts.append(area)
		if area.get_parent() as BoardPlacementSlot \
				and _is_placement_slot_valid(area.get_parent(),potential_cards):
			potential_slots.append(area.get_parent())
		if area as CardContainer and cfc.card_drag_ongoing:
		# If disable_dropping_to_cardcontainers is set to true, we still
		# Allow the player to return the card where they got it.
			if not cfc.card_drag_ongoing.disable_dropping_to_cardcontainers\
					or (cfc.card_drag_ongoing.disable_dropping_to_cardcontainers
					and cfc.card_drag_ongoing.get_parent() == area):
				potential_containers.append(area)
	# Dragging into containers takes priority over draggging onto board
	if not potential_containers.empty():
		cfc.card_drag_ongoing.potential_container = \
				Highlight.highlight_potential_container(
				CFConst.TARGET_HOVER_COLOUR,
				potential_containers,
				potential_cards,
				potential_slots)
	# Dragging onto cards, takes priority over board placement grid slots
	elif not potential_cards.empty():
		if cfc.card_drag_ongoing:
			cfc.card_drag_ongoing.potential_container = null
		# We sort the potential cards by their index on the board
		potential_cards.sort_custom(CFUtils,"sort_index_ascending")
		# The candidate always has the highest index as it's drawn on top of
		# others.
		var card : Card = potential_cards.back()
		# if this card was not already focused...
		if current_focused_card != card:
			# We don't want to change focus while we're either dragging
			# a card around, or we're hovering over a previously
			# focused card's token drawer.
			if not (current_focused_card
					and current_focused_card.state == Card.CardState.DRAGGED) \
				and not (current_focused_card
					and current_focused_card.tokens.are_hovered()
					and current_focused_card.tokens.is_drawer_open):
				# If we already highlighted a card that is lower in index
				# we remove it's focus state
				if current_focused_card:
					current_focused_card._on_Card_mouse_exited()
				if not cfc.card_drag_ongoing:
					# Changed to use set_current_focused_card instead of direct assignment
					set_current_focused_card(card)
		# If we have potential hosts, then we highlight the highest index one
		# Added check for CFConst.DISABLE_MANUAL_ATTACHMENTS
		if not potential_hosts.empty() and !CFConst.DISABLE_MANUAL_ATTACHMENTS:
			cfc.card_drag_ongoing.potential_host = \
					current_focused_card.highlight.highlight_potential_card(
					CFConst.HOST_HOVER_COLOUR,potential_hosts,potential_slots)
		# If we have potential placements, then there should be only 1
		# as their placement should not allow the mouse to overlap more than 1
		# We also clear potential hosts since there potential_hosts was emty
		elif not potential_slots.empty():
			cfc.card_drag_ongoing.potential_host = null
			# Added check for CFConst.DEACTIVATE_SLOTS_HIGHLIGHT
			if CFConst.DEACTIVATE_SLOTS_HIGHLIGHT:
				pass
			else:
				potential_slots.back().set_highlight(true)
		# If card is being dragged, but has no potential target
		# We ensure we clear potential hosts
		elif cfc.card_drag_ongoing:
			cfc.card_drag_ongoing.potential_host = null
	# If we don't collide with any objects, but we have been focusing until
	# now, we make sure we're not hovering over the card drawer.
	# if not, then we remove focus.
	#
	# Because sometimes the mouse moves faster than a dragged card,
	# We make sure we don't try to change the current_focused_card while
	# in the process of dragging one.
	elif current_focused_card and current_focused_card.state != Card.CardState.DRAGGED:
		if not current_focused_card.tokens.are_hovered() \
				or not current_focused_card.tokens.is_drawer_open:
			current_focused_card._on_Card_mouse_exited()
			current_focused_card = null
