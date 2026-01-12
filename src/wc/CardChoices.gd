# Pops up a menu for the player to choose on of the card
# options
extends Container


signal id_pressed(id)

var id_selected := 0
var selected_key: String
var rules: Dictionary = {}
onready var menu = get_node("%MenuItems")
onready var title_label = get_node("%Title")
var items:= []
var text_to_id:= {}
var title = "test title"
var has_been_centered = false

var SCALE = 1.2
# Called from Card.execute_scripts() when a card has multiple options.
#
# It prepares the menu items based on the dictionary keys and bring the
# popup to the front.
func prep(title_reference: String, script_with_choices: Dictionary, _rules:Dictionary = {}) -> void:
		set_title("Please choose option for " + title_reference)


		# The dictionary passed is a card script which contains
		# an extra dictionary before the task definitions
		# When that happens, it specifies multiple choice
		# and the dictionary keys, are the choices in human-readable text.
		for key in script_with_choices.keys():
			add_item(key)

		rules = _rules
		var forced = rules.get("forced", false)
		if !forced and !gamepadHandler.is_mouse_input():
			add_item("cancel")	
			
		cfc.NMAP.board.add_child_to_top_layer(self)


		# We spawn the dialogue at the middle of the screen.

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	if items:
		for child in menu.get_children():
			menu.remove_child(child)
	title_label.text = title
	var i = 0
	for item in items:
		i+=1		
		var button:Button = Button.new()
		# warning-ignore:return_value_discarded
		button.connect("pressed", self, "_button_pressed", [button])
		# warning-ignore:return_value_discarded
		button.connect("mouse_entered", self, "_mouse_entered", [button])
		button.text = item
		if item == "cancel":
			button.icon = gamepadHandler.get_icon_for_action("ui_cancel")		
		text_to_id[item.to_lower()] = i		
		menu.add_child(button)
		
	cfc.default_button_focus(menu)
	self.rect_scale = Vector2(SCALE, SCALE)

func _process(_delta:float):
	popup_centered()	
	$HorizontalHighlights.rect_size = $Panel.rect_size
	#$HorizontalHighlights.rect_position = rect_position
	$VerticalHighlights.rect_size = $Panel.rect_size
	#$VerticalHighlights.rect_position = rect_position

	
func _mouse_entered(button):
	button.grab_focus()
	
	
func _button_pressed(button):
	var text = button.text
	select_by_title(text)
	get_tree().root.set_input_as_handled()
	
func set_title(text):
	title = text

func add_item(text):
	items.append(text)

func popup_centered():
	if has_been_centered:
		return	
		
	if !$Panel.rect_size:
		return

	var size = $Panel.rect_size * self.rect_scale

	self.rect_position = get_viewport().size/2	- size/2
	has_been_centered = true
		
func force_select_by_title(keyword: String):
	select_by_title(keyword)

func select_by_title(keyword):
	
	GameRecorder.add_entry(GameRecorder.ACTIONS.CHOOSE, keyword)
	
	var id = text_to_id.get(keyword.to_lower(), 0)
	
	if keyword == "cancel":
		id = 0
	
	id_selected = id
	
	if id_selected:
		selected_key = items[id_selected-1]
	

	emit_signal("id_pressed", id_selected)

func cancel_input():
	select_by_title("cancel")
	
#handling input outside of the window for cancel

func force_cancel():
	cancel_input()

func _input(event):
	#get_viewport().set_input_as_handled()  # Prevents further propagation
	var forced = rules.get("forced", false)
	if forced:
		return
	
	if gamepadHandler.is_ui_cancel_pressed(event):
		cancel_input()
		return
		
	if not event is InputEventMouseButton: return
	if not event.pressed: return
	var control_rect = $Panel.get_rect()
	control_rect.position = $Panel.get_global_position()
	control_rect.size *= SCALE
	var local_rect = control_rect
	var xy = cfc.NMAP.board.mouse_pointer.determine_global_mouse_pos()
	if local_rect.has_point(xy): 
		return
	cancel_input()
