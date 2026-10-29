# This class is meant to serve as your main scene for your card game
# In that case, it will enable the game to use hovering viewports
# For displaying card information
class_name ViewportCardFocus
extends Node2D

const WAIT_BEFORE_PREVIEW = 0.7

signal show_card_focus_changed(value)

export(PackedScene) var board_scene : PackedScene
export(PackedScene) var info_panel_scene : PackedScene
# This array holds all the previously focused cards.
var _previously_focused_cards := {}
# This var hold the currently focused card duplicate.
var _current_focus_source : Card = null

onready var left_container = $VBC/CardDisplay/Left
onready var left_card_container = $VBC/CardDisplay/Left/Container
onready var left_text_container = $VBC/CardDisplay/Left/MsgContainer
onready var right_container = $VBC/CardDisplay/Right

onready var world_environemt : WorldEnvironment = $WorldEnvironment
var viewport

var canonical_size:= Vector2(0,0)
var vbc_rect_offset:= Vector2(0,0)

var show_card_focus = true

func _process(_delta:float):
#	display_debug_info()
	resize()
	pass

func resize():
	if _current_focus_source and is_instance_valid(_current_focus_source):
		var card = _previously_focused_cards[_current_focus_source]
		card.get_parent().rect_min_size = 	card.card_size*card.scale
	pass
	

func display_debug_info():
	if !OS.has_feature("debug"):
		return

	var debug_node = get_node_or_null("Debug")	
	
	if !cfc._debug:
		if debug_node:
			debug_node.visible = false
		return
	

	if !debug_node:
		debug_node = Label.new()
		debug_node.name = "Debug"
		debug_node.rect_position = Vector2(0, 200)
		add_child(debug_node)
		
	var result =""
	var vsize = get_tree().get_root().size
	var mouse_pos = get_global_mouse_position()
	var hand_pos = cfc.NMAP["hand1"].global_position
	result += "viewport size:" + str(vsize.x) + "x" + str(vsize.y) + "\n"
	result += "cfc.screenscale" + str(cfc.screen_scale.x) + "x" + str(cfc.screen_scale.x) + "\n"
	result += "cfc.hardcoded_pos_modifier" + str(cfc.hardcoded_positions_modifier.x) + "x" + str(cfc.hardcoded_positions_modifier.x) + "\n"	
	result += "mouse position" + str(mouse_pos.x) + "x" + str(mouse_pos.y) + "\n"
	result += "hand_position" + str(hand_pos.x) + "x" + str(hand_pos.y) + "\n"
	debug_node.text = result

# Called when the node enters the scene tree for the first time.
func _ready():
	$VBC.visible = false
	viewport = get_tree().get_root()
	cfc.map_node(self)
	var glow_enabled = cfc.game_settings.get('glow_enabled', true)
	world_environemt.environment.glow_enabled = glow_enabled
	
	var glow_intensity = cfc.game_settings.get('glow_intensity', world_environemt.environment.glow_intensity)
	world_environemt.environment.glow_intensity = glow_intensity
	
	# We use the below while to wait until all the nodes we need have been mapped
	# "hand" should be one of them.
	add_child(board_scene.instance())
	if not cfc.are_all_nodes_mapped:
		yield(cfc, "all_nodes_mapped")
	# warning-ignore:return_value_discarded
	scripting_bus.connect("card_reloaded", self, "_on_card_reloaded")
	get_viewport().connect("size_changed",self,"_on_Viewport_size_changed")
	_on_Viewport_size_changed()
	for container in get_tree().get_nodes_in_group("card_containers"):
		container.re_place()

func add_card(card, parent_card):
	card.visible = true
	if true:
		for c in left_card_container.get_children():
			left_card_container.remove_child(c)
		left_card_container.rect_min_size = card.card_size * card.scale
		left_card_container.rect_size = left_card_container.rect_min_size
		left_card_container.add_child(card)

	var msg = ""
	if parent_card.get_state_exec() == "hand":
		msg = parent_card.get_cant_pay_cost_status()

	if msg:
		left_text_container.visible = true
		var label:Label = get_node("%InfoLabel")
		label.text = msg
	else:
		left_text_container.visible = false	


	

func remove_card():
	pass

func remove_all_cards():
	for container in [left_card_container]:
		for c in container.get_children():
			container.remove_child(c)

func reposition_vbc():
	var mouse_pos: Vector2
	if gamepadHandler.is_mouse_input():
		mouse_pos = get_global_mouse_position()	
	else:
		mouse_pos = gamepadHandler.get_approx_position()	
	
	$VBC.margin_right = 0
	$VBC.margin_bottom = 0
	
	var display_size = Vector2(0,0)
	var display_position = Vector2(0,0)
	var view_size = get_viewport().size / cfc.screen_scale
	var spacer = 15
	$VBC.visible = false
	
	if _current_focus_source and is_instance_valid(_current_focus_source):	
		var card = _previously_focused_cards[_current_focus_source]
		$VBC.visible = true
		#
		#use cases where we don't want to show the preview
		#
		var show_preview = true
		#settings can choose to hide cards in hands
		if card.get_state_exec() == "hand":

			show_preview = cfc.game_settings.get("show_hand_cards_preview", true)
		
		#if the screen is crowded with menus, we don't show the preview			
		if gameData.theAnnouncer.is_right_side_announce_ongoing(false):
			var modal_menu = cfc.get_modal_menu()
			if modal_menu and modal_menu.visible:
				show_preview = false
		
		
		if !show_preview:
			$VBC.visible = false
			return
		
		
			
		#We're showing the preview! keep processing	
		var multiplier =  card.focused_scale #* cfc.curr_scale		
		display_size = card.canonical_size * multiplier
		var board_card_size = card.card_size * card.scale
		var board_top_left_corner = card._control.get_global_position()
		var source_bounding:Rect2 = Rect2(board_top_left_corner,board_card_size)
		if !source_bounding.has_point(mouse_pos):
			mouse_pos = board_top_left_corner + Vector2(10, 10)		
		if (card._horizontal and card.get_is_faceup()):
			$VBC.rect_rotation = 90
			vbc_rect_offset = Vector2 ( display_size.y, 0)
			display_size = Vector2( display_size.y,  display_size.x)
			board_card_size = Vector2(board_card_size.y, board_card_size.x)
			board_top_left_corner.x = board_top_left_corner.x - board_card_size.x 
		else:
			$VBC.rect_rotation = 0
			vbc_rect_offset = Vector2 (0,0)
		
		#if announcer has an announce on the right of the screen e.g. stackeventdisplay)
		#we don't want to cover it	
		if gameData.theAnnouncer.is_right_side_announce_ongoing(false):	
			display_position = Vector2( spacer, spacer)
			if mouse_pos.x < display_size.x + (spacer*2) and mouse_pos.y < display_size.y + (spacer*2):
				display_position.y = view_size.y -  display_size.y - spacer
		elif mouse_pos.x + display_size.x + (spacer*2) >= view_size.x :
			display_position = Vector2( spacer, spacer)
		else:
			display_position = Vector2(view_size.x - display_size.x - spacer,  spacer)
		
		#last resort if I end up overlapping my own card
		var vbc_bounding:Rect2 = Rect2(display_position, display_size)
		if vbc_bounding.intersects( source_bounding):
			display_position.x = board_top_left_corner.x + board_card_size.x + spacer
			if display_position.x + display_size.x + (spacer*2) >= view_size.x :
				display_position.x = spacer
		

					
		#For testing: create two ColorRect nodes as children of Main.tscn
		#named  ColorRect and ColorRect2
#		var color_rect = get_node("%ColorRect")
#		color_rect.rect_min_size = source_bounding.size	
#		color_rect.rect_size = color_rect.rect_min_size
#		color_rect.rect_position = source_bounding.position
#		color_rect.visible = true
#
#		var color_rect2 = get_node("%ColorRect2")
#		color_rect2.rect_min_size = vbc_bounding.size	
#		color_rect2.rect_size = color_rect2.rect_min_size
#		color_rect2.rect_position = vbc_bounding.position
#		color_rect2.visible = true

	$VBC.rect_position = display_position + vbc_rect_offset


func reposition():
	if show_card_focus:
		$VBC.visible = true
	else:
		$VBC.visible = false
	
	reposition_vbc()
	return

func garbage_collection():
	# The below performs some garbage collection on previously focused cards.
	var to_delete = []
	for c in _previously_focused_cards:
		if not is_instance_valid(_previously_focused_cards[c]) or not is_instance_valid(c):
			to_delete.append(c)
			continue
		var current_dupe_focus: Card = _previously_focused_cards[c]
		
		#TODO I've had cards stuck in limbo that show up and are impossible
		#to remove from the preview mode. This is an attempt to fix this 
		if current_dupe_focus.state == Card.CardState.IN_PILE:
			to_delete.append(c)
		# We don't delete old dupes, to avoid overhead to the engine
		# insteas, we just hide them.
		if _current_focus_source != c:
			current_dupe_focus.visible = false
	for c in to_delete:
		forget_card(c)

func forget_card(c):
	var dupe = _previously_focused_cards[c]
	if is_instance_valid(dupe):
		#This is dumb but I have to add the child somewhere
		#to prevent it from showing up in stray nodes
		var parent = dupe.get_parent()
		if !is_instance_valid(parent):
			cfc.add_child(dupe)
		dupe.queue_free()
	var _found = _previously_focused_cards.erase(c)	
	if _current_focus_source == c:
		_current_focus_source = null
	if is_instance_valid(c):	
		c.disconnect("card_texture_changed",self , "_on_texture_reloaded")	

# Displays the card closeup in the Focus viewport
func focus_card(card: Card, _show_preview := true) -> void:
	if !show_card_focus:
		return
			
	# We check if we're already focused on this card, to avoid making duplicates
	# the whole time		
	if _current_focus_source != card:
		
		#cleanup previous card focus state in case something fishy happened (I've seen it with my own eyes!)
		if is_instance_valid(_current_focus_source):
			_current_focus_source.lose_focus()
		
		#remove children cards to always only keep one displayed
		remove_all_cards()
				
		# We make a duplicate of the card to display and add it on its own in
		# our viewport world
		# This way we can standardize its scale and look and not worry about
		# what happens on the table.
		var dupe_focus: Card
		if _previously_focused_cards.has(card) and is_instance_valid(_previously_focused_cards[card]):
			dupe_focus = _previously_focused_cards[card]
			add_card(dupe_focus, card)
			# Not sure why, but sometimes the dupe card will report is_faceup
			# while having the card back visible. Workaround until I figure it out.
			if dupe_focus.get_node('Control/Back').visible == dupe_focus.is_faceup:
				# warning-ignore:return_value_discarded
				dupe_focus.set_is_faceup(!dupe_focus.is_faceup, true)
			# warning-ignore:return_value_discarded
			dupe_focus.set_is_faceup(card.is_faceup, true)
			dupe_focus.is_viewed = card.is_viewed
			var tokens_dict = card.tokens.export_to_json()
			dupe_focus.tokens.load_from_json(tokens_dict)
		else:
			dupe_focus = card.duplicate(DUPLICATE_USE_INSTANCING)
			card.connect("card_texture_changed", self, "_on_texture_reloaded")
			dupe_focus.is_duplicate_of = card
			dupe_focus.name = dupe_focus.name + "-VBC"
			dupe_focus.remove_from_group("cards")
			_extra_dupe_preparation(dupe_focus, card)
			# We display a "pure" version of the card
			# This means we hide buttons, tokens etc
			dupe_focus.set_state(Card.CardState.VIEWPORT_FOCUS)
			
			#remove unecessary children
			if dupe_focus.targeting_arrow:
				dupe_focus.targeting_arrow.queue_free()

			dupe_focus.set_position(Vector2(0,0))						
			add_card(dupe_focus, card)
			_extra_dupe_ready(dupe_focus, card)

			dupe_focus.is_faceup = card.is_faceup
			dupe_focus.is_viewed = card.is_viewed
			# We check that the card front was not left half-visible because it was duplicated
			# in the middle of the flip animation
			if dupe_focus._card_front_container.rect_scale.x != 1:
				if dupe_focus.is_viewed:
					dupe_focus._flip_card(dupe_focus._card_back_container, dupe_focus._card_front_container,true)
				else:
					dupe_focus._flip_card(dupe_focus._card_front_container,dupe_focus._card_back_container, true)
		_current_focus_source = card
		
	
		
		for c in _previously_focused_cards.values():
			if not is_instance_valid(c):
				continue
			if c != dupe_focus:
				c.visible = false
			else:
				c.visible = true
		# We store all our previously focused cards in an array, and clean them
		# up when they're not focused anymore
		_previously_focused_cards[card] = dupe_focus

							
		garbage_collection()
		reposition()

		#hide everything and wait until display
		$VBC.visible = false
#		for c in _previously_focused_cards.values():
#			if not is_instance_valid(c):
#				continue
#			c.visible = false		
		yield(get_tree().create_timer(WAIT_BEFORE_PREVIEW), "timeout")	
		if is_instance_valid(_current_focus_source):
			$VBC.visible = true
#			var c = _previously_focused_cards.get(_current_focus_source, null)
#			if is_instance_valid(c) and c == dupe_focus:
#				c.visible = true			
		
		return
			

func _on_texture_reloaded(card):
	if _previously_focused_cards.has(card):
		forget_card(card)

func _on_card_reloaded(card, _details):
	if _previously_focused_cards.has(card):
		forget_card(card)

# Hides the focus viewport when we're done looking at it
func unfocus(card: Card) -> void:
	if _current_focus_source == card:
		_current_focus_source = null
		garbage_collection()
		reposition()


# Tells the currently focused card to stop focusing.
func unfocus_all() -> void:
	if _current_focus_source:
		_current_focus_source.set_to_idle()
		garbage_collection()
		reposition()


# Overridable function for games to extend preprocessing of dupe card
# before adding it to the scene
func _extra_dupe_preparation(dupe_focus: Card, card: Card) -> void:
	dupe_focus.canonical_name = card.canonical_name
	dupe_focus.canonical_id = card.canonical_id
	dupe_focus.properties = card.properties.duplicate()



# Overridable function for games to extend processing of dupe card
# after adding it to the scene
# warning-ignore:unused_argument
# warning-ignore:unused_argument
func _extra_dupe_ready(dupe_focus: Card, card: Card) -> void:
	dupe_focus.set_card_art()
	dupe_focus.refresh_card_front()
	var multiplier =  dupe_focus.focused_scale #* cfc.curr_scale
	if CFConst.VIEWPORT_FOCUS_ZOOM_TYPE == "scale":
		dupe_focus.scale = Vector2(1,1) * multiplier
	else:
		dupe_focus.resize_recursively(dupe_focus._control, multiplier)
		dupe_focus.get_card_front().scale_to( multiplier)
		dupe_focus.tokens.token_drawer(false, true)

	dupe_focus.scale = Vector2(2,2) 
func _input(event):				
	if event.is_action_pressed("ui_toggle_big_card"):	
		show_card_focus = !show_card_focus
		emit_signal("show_card_focus_changed", show_card_focus)
		reposition()		


# Takes care to resize the child viewport, when the main viewport is resized
func _on_Viewport_size_changed() -> void:
	resize()
	


func toggle_glow(is_enabled := true) -> void:
	world_environemt.environment.glow_enabled = is_enabled


func show_options_menu():
	$OptionsMenu.show_me()

func get_main_viewport():
	return viewport 

func queue_free():
	for c in _previously_focused_cards.keys():
		forget_card(c)	
	.queue_free()
