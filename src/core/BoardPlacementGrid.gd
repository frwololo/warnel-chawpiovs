# Creates a GridContainer in which cards can be placed organized next
# to each other.
#
# To use this scene properly, create an inherited scene,
# then add as many instanced BoardPlacementSlots as you need this grid to hold
#
# Adjust its highlight colour and the amount of columns it should have as well
#
# The BoardPlacementSlots will adjust to card_size on runtime, but
# If you want to visually see on the editor your result

# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED

class_name BoardPlacementGrid
extends Control

#emitted by children
# warning-ignore:unused_signal
signal card_removed_from_slot (slot)
# warning-ignore:unused_signal
signal card_added_to_slot (slot)

# Used to add new BoardPlacementSlot instances to grids. We have to add the consts
# together before passing to the preload, or the parser complains
const _SLOT_SCENE_FILE = CFConst.PATH_CORE + "BoardPlacementSlot.tscn"
const _SLOT_SCENE = preload(_SLOT_SCENE_FILE)

const LABEL_ORIENTATION_VERTICAL:= true

# Set the highlight colour for all contained BoardPlacementSlot slots
export(Color) var highlight = CFConst.TARGET_HOVER_COLOUR
# If set to true, the grid will automatically add more slots
# when find_available_slot() is used and there's no more available slots
# (only useful when using the ScriptingEngine)
export var auto_extend := false
# Used to adjust the grid according to the card size that will be put into it.
# This size should match the
export var card_size := CFConst.CARD_SIZE
export var card_play_scale := CFConst.PLAY_AREA_SCALE

# Sets a custom label for this grid
onready var name_label:Label = $Control/Label
var display_name = ""
var modulate_color = Color(0.0, 0.0, 0.0)

func set_display_name(value):
	display_name = value.capitalize()
	if name_label:
		name_label.text = display_name

func set_bg_color(value):
	modulate_color = Color(value)
	refresh_display()

func _ready() -> void:
	#grids don't take clicks (slots use the mouse pointer's Area2D, cards
	#handle their own): an invisible grid covered a hero portrait
	_ignore_mouse(self)
	_ignore_mouse($Control)
	_ignore_mouse($GridContainer)
	for slot in $GridContainer.get_children():
		_ignore_mouse(slot)
	rescale(card_play_scale)
	# We ensure the separation of the grid slots is always 1 pixel larger
	# Than the radius of the mouse pointer collision area.
	# This ensures that we don't highlight 2 slots at the same time.
	$GridContainer.set("custom_constants/vseparation",
			MousePointer.MOUSE_RADIUS * 2 + 1)
	$GridContainer.set("custom_constants/hseparation",
			MousePointer.MOUSE_RADIUS * 2 + 1)
	
	if LABEL_ORIENTATION_VERTICAL:
		name_label.rect_rotation = -90
		name_label.rect_position.x = 0		
	name_label.text = display_name
	
	if CFConst.HIDE_GRID_BACKGROUND:
		$GridContainer.modulate = Color(0,0,0,0)
		self.self_modulate = Color(0,0,0,0)
		
	connect("card_added_to_slot", self, "_card_added")
	connect("card_removed_from_slot", self, "_card_removed")
	refresh_display()

func _process(_delta: float):
	if self.rect_size.y < 150:
		name_label.visible = false
		return
	else:
		name_label.visible = true
		
	if LABEL_ORIENTATION_VERTICAL:
		name_label.rect_position.y = self.rect_size.y	

func _card_added(card):
	#add new slots ahead of time as needed, to avoid "yield" related issues
	if (!auto_extend):
		return
	#find_available_slot()
	refresh_display()	

func _card_removed(card):
	if (auto_extend):
		var empty_slots = get_available_slots()
		for empty_slot in empty_slots:
			$GridContainer.remove_child(empty_slot)
			$Garbage.add_child(empty_slot)
	
	refresh_display()

func refresh_display():			
	if get_all_cards() and display_name:
		var sb = get_stylebox("panel").duplicate()  # duplicate so other panels sharing the theme aren't affected
		sb.bg_color = modulate_color          # works if it's a StyleBoxFlat
		add_stylebox_override("panel", sb)		
		self.modulate.a = 1.0
	else:
		self.modulate.a = 0.0

# If a BoardPlacementSlot object child in this container is highlighted
# Returns the object. Else returns null
func get_highlighted_slot() -> BoardPlacementSlot:
	var ret_slot: BoardPlacementSlot = null
	for slot in get_all_slots():
		if slot.is_highlighted():
			ret_slot = slot
	return(ret_slot)


# Returns the slot at the specified index.
func get_slot(idx: int) -> BoardPlacementSlot:
	var ret_slot: BoardPlacementSlot = $GridContainer.get_child(idx)
	return(ret_slot)


# Adds new placement slot to the grid.
# Returns the slot object
func add_slot() -> BoardPlacementSlot:
	var new_slot : BoardPlacementSlot = _SLOT_SCENE.instance()
	_ignore_mouse(new_slot)
	$GridContainer.add_child(new_slot)
	return(new_slot)


# Returns a slot that is not currently occupied by a card
func find_available_slot() -> BoardPlacementSlot:		
	var found_slot : BoardPlacementSlot
	if not get_available_slots().empty():
		found_slot = get_available_slots().front()
	elif auto_extend:
		found_slot = add_slot()

	#do some cleanup while we're at it
	garbage_collection()		
				
	return(found_slot)

func garbage_collection():
	for child in $Garbage.get_children():
		if (is_instance_valid(child)):
			child.queue_free()

# Returns an array containing all the BoardPlacementSlot nodes
func get_all_slots() -> Array:
	return($GridContainer.get_children())

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

# Returns the amount of BoardPlacementSlot contained.
func get_slot_count() -> int:
	return(get_all_slots().size())


# Returns an array with all slots not occupied by a card
func get_available_slots() -> Array:
	var available_slots := []
	for slot in get_all_slots():
		if !is_instance_valid(slot):
			continue
		if slot.occupying_card or slot.reserved:
			continue
		available_slots.append(slot)
	return(available_slots)

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

# Returns the count of all available slots
func count_available_slots() -> int:
	return(get_available_slots().size())
	
func reposition(new_position:Vector2, forced = false):
	if rect_position == new_position and !forced:
		return
	rect_position = new_position
	
	var slots:Array = get_all_slots()
	for slot in slots:
		slot.reposition(new_position)			
	
func rescale(scale, forced:bool= false):
	if scale == card_play_scale and !forced:
		return
	card_play_scale = scale

	var slots:Array = get_all_slots()
	for slot in slots:
		slot.rescale()		
		
	rect_size = (card_size * card_play_scale) + Vector2(4,4)
	

func set_h_separation(value):
	$GridContainer.add_constant_override("hseparation", value)

func set_columns(value):
	$GridContainer.columns = value


static func _ignore_mouse(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
