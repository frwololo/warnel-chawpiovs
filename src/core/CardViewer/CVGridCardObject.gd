# A container for a card instance which is meant to be placed in a grid container.
# It will also show a larger image of the card when moused-over
class_name CVGridCardObject
extends CenterContainer

var display_card: Card = null
var card_list_object
var has_focus = false
var selected = false
var show_card_focus = true
onready var preview_popup := $PreviewPopup

const cached_cards:= {}

func _ready() -> void:
# warning-ignore:return_value_discarded
	show_card_focus = cfc.NMAP.main.show_card_focus
	get_viewport().connect("size_changed", self, '_on_viewport_resized')
	cfc.NMAP.main.connect("show_card_focus_changed", self, "_show_card_focus_changed")

func _show_card_focus_changed(new_value):
	if new_value == show_card_focus:
		return
	show_card_focus = new_value
	if show_card_focus:
		try_to_show_preview()
	else:
		hide_preview()

func setup(card) -> Card:
	if typeof(card) == TYPE_STRING:
		display_card = cfc.instance_card(card, -18)
	else:
		display_card = card
		display_card.position = Vector2(0,0)
		display_card.scale = Vector2(1,1)
	var parent = display_card.get_parent()
	if parent:
		cfc.LOG("card " + display_card.canonical_name + "wasn't properly removed from " + parent.name)
		parent.remove_child(display_card)
	add_child(display_card)
	cached_cards[display_card] = true
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

func try_to_show_preview():
	if !show_card_focus:
		return

	if (!display_card):
		return
	
	if (!has_focus):
		return		
	
	cfc.NMAP.main.focus_card(display_card)	
#	var card = preview_popup.show_preview_card(display_card.canonical_id)	
#	if card:
#		card.is_duplicate_of = display_card
#		if display_card.is_duplicate_of:
#			card.is_duplicate_of = display_card.is_duplicate_of
func hide_preview():
	cfc.NMAP.main.unfocus(display_card)
#	preview_popup.hide_preview_card()
	
func gain_focus():
	if (!display_card):
		return

	has_focus = true
	
	try_to_show_preview()	
	
	if !gamepadHandler.is_mouse_input():
		display_card.highlight.set_highlight(true, CFConst.FOCUS_COLOUR_ACTIVE)

func _on_GridCardObject_focus_exited():
	lose_focus()
	
func lose_focus():
	hide_preview()
		
	has_focus = false

	if (! is_instance_valid(display_card)):
		return	
	
	if selected:
		display_card.highlight.set_highlight(true)
	else:
		display_card.highlight.set_highlight(false)

#on exit we remove cards instead of freeing them, to reuse them later
func _exit_tree():
	for child in get_children():
		if child as Card:
			remove_child(child)

static func queue_free_cache():
	for card in cached_cards.keys():
		if is_instance_valid(card):
			#This is dumb but I have to add the child somewhere
			#to prevent it from showing up in stray nodes
			var parent = card.get_parent()
			if !is_instance_valid(parent):
				cfc.add_child(card)
			card.queue_free()
		cached_cards.erase(card)
