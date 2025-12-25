# A container for a card instance which is meant to be placed in a grid container.
# It will also show a larger image of the card when moused-over
class_name CVGridCardObject
extends CenterContainer

var display_card: Card = null
var card_list_object
var has_focus = false
var selected = false

onready var preview_popup := $PreviewPopup


func _ready() -> void:
# warning-ignore:return_value_discarded
	get_viewport().connect("size_changed", self, '_on_viewport_resized')

func setup(card) -> Card:
	if typeof(card) == TYPE_STRING:
		display_card = cfc.instance_card(card, -18)
	else:
		display_card = card
		display_card.position = Vector2(0,0)
		display_card.scale = Vector2(1,1)
	add_child(display_card)
	display_card.set_owner(self)
	if CFConst.VIEWPORT_FOCUS_ZOOM_TYPE == "scale":
		display_card.scale = Vector2(1,1) * display_card.thumbnail_scale * cfc.curr_scale
	else:
		display_card.resize_recursively(display_card._control, display_card.thumbnail_scale * cfc.curr_scale)
		display_card.get_card_front().scale_to(display_card.thumbnail_scale * cfc.curr_scale)
	display_card.set_state(Card.CardState.DECKBUILDER_GRID)
	rect_min_size = display_card.canonical_size * display_card.thumbnail_scale * cfc.curr_scale
	rect_size = rect_min_size
	return(display_card)


func _on_GridCardObject_mouse_entered() -> void:
	gain_focus()



func _on_GridCardObject_mouse_exited() -> void:
	lose_focus()


func get_class() -> String:
	return("CVGridCardObject")


# Resizes the grid container so that the preview cards fix snuggly.
func _on_viewport_resized() -> void:
	if (!display_card):
		return	
	rect_min_size = display_card.canonical_size * display_card.thumbnail_scale * cfc.curr_scale
	rect_size = rect_min_size



func _on_GridCardObject_focus_entered():
	gain_focus()


func set_selected(value):
	selected = value


func gain_focus():
	if (!display_card):
		return
	preview_popup.show_preview_card(display_card.canonical_id)	
	has_focus = true
	if !gamepadHandler.is_mouse_input():
		display_card.highlight.set_highlight(true, CFConst.FOCUS_COLOUR_ACTIVE)
	pass

func _on_GridCardObject_focus_exited():
	lose_focus()
	
func lose_focus():
	if (!display_card):
		return	
	preview_popup.hide_preview_card()
		
	has_focus = false
	if selected:
		display_card.highlight.set_highlight(true)
	else:
		display_card.highlight.set_highlight(false)
	pass
