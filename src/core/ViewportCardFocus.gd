# This class is meant to serve as your main scene for your card game
# In that case, it will enable the game to use hovering viewports
# For displaying card information
class_name ViewportCardFocus
extends Node2D

export(PackedScene) var board_scene : PackedScene
export(PackedScene) var info_panel_scene : PackedScene
# This array holds all the previously focused cards.
var _previously_focused_cards := {}
# This var hold the currently focused card duplicate.
var _current_focus_source : Card = null

onready var card_focus := $VBC/Focus
onready var focus_info := $VBC/FocusInfo
onready var _focus_viewport := $VBC/Focus/Viewport
onready var _focus_camera := $VBC/Focus/Viewport/Camera2D
onready var world_environemt : WorldEnvironment = $WorldEnvironment
onready var viewport = $ViewportContainer/Viewport

var canonical_size:= Vector2(0,0)
var vbc_rect_offset:= Vector2(0,0)

#I was having an impossible time getting the viewport/camera system to work
#in 1280x720. Instead I'm using a different method there, adding the cards
#directly into $VBC. It's gross but it works
var vbc_position_mode = true

# Called when the node enters the scene tree for the first time.
func _ready():
	cfc.map_node(self)
	var glow_enabled = cfc.game_settings.get('glow_enabled', true)
	world_environemt.environment.glow_enabled = glow_enabled
	
	var glow_intensity = cfc.game_settings.get('glow_intensity', world_environemt.environment.glow_intensity)
	world_environemt.environment.glow_intensity = glow_intensity
	
	# We use the below while to wait until all the nodes we need have been mapped
	# "hand" should be one of them.
	$ViewportContainer/Viewport.add_child(board_scene.instance())
	if not cfc.are_all_nodes_mapped:
		yield(cfc, "all_nodes_mapped")
	# warning-ignore:return_value_discarded
	get_viewport().connect("size_changed",self,"_on_Viewport_size_changed")
	_on_Viewport_size_changed()
	for container in get_tree().get_nodes_in_group("card_containers"):
		container.re_place()
	focus_info.info_panel_scene = info_panel_scene
	focus_info.setup()
	
	if vbc_position_mode:
		$VBC.remove_child(card_focus)
		$VBC.remove_child(focus_info)

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
	var viewport_size = get_viewport().size
	var spacer = 15
	if _current_focus_source and is_instance_valid(_current_focus_source):	
		var card = _current_focus_source
		var multiplier =  card.focused_scale * cfc.curr_scale		
		var card_size = card.canonical_size * multiplier
		if (card._horizontal and card.get_is_faceup()):
			$VBC.rect_rotation = 90
			vbc_rect_offset = Vector2 (card_size.y, 0)
			display_size = Vector2(card_size.y, card_size.x)
		else:
			$VBC.rect_rotation = 0
			vbc_rect_offset = Vector2 (0,0)
			display_size = Vector2(card_size.x, card_size.y)
		
		#if announcer has anannounce onthe right of the screen e.g. stackeventdisplay)
		#we don't want to cover it	
		if gameData.theAnnouncer.is_right_side_announce_ongoing():	
			display_position = Vector2( spacer, spacer)
			if mouse_pos.x < display_size.x + (spacer*2) and mouse_pos.y < display_size.y + (spacer*2):
				display_position.y = viewport.size.y -  display_size.y - spacer
		elif mouse_pos.x + display_size.x + (spacer*2) >= viewport_size.x :
			display_position = Vector2( spacer, spacer)
		else:
			display_position = Vector2(viewport_size.x - display_size.x - spacer,  spacer)
		pass

	$VBC.rect_position = display_position + vbc_rect_offset

func reposition():
	if vbc_position_mode:
		reposition_vbc()
		return
		
	var mouse_pos: Vector2
	if gamepadHandler.is_mouse_input():
		mouse_pos = get_global_mouse_position()	
	else:
		mouse_pos = gamepadHandler.get_approx_position()	
	
	var viewport_size = get_viewport().size
			
	if _current_focus_source and is_instance_valid(_current_focus_source)\
			and _current_focus_source.get_state_exec() != "pile"\
			and cfc.game_settings.focus_style == CFInt.FocusStyle.BOTH_INFO_PANELS_ONLY:
		if mouse_pos.y + focus_info.rect_size.y/2 > viewport_size.y:
			$VBC.rect_position.y = viewport_size.y - focus_info.rect_size.y
		else:
			$VBC.rect_position.y = mouse_pos.y - focus_info.rect_size.y / 2
		if mouse_pos.x + focus_info.rect_size.x + 60 > viewport_size.x:
			$VBC.rect_position.x = viewport_size.x - focus_info.rect_size.x
			$VBC.rect_position.y = mouse_pos.y - 500
		else:
			$VBC.rect_position.x = mouse_pos.x + 60

	elif _current_focus_source and is_instance_valid(_current_focus_source)\
			and mouse_pos.x > viewport_size.x - canonical_size.x*2.5\
			and mouse_pos.y < canonical_size.y*2:
		$VBC.rect_position.x = 0
		$VBC.rect_position.y = 0
	elif _current_focus_source:
		$VBC.rect_position.x = viewport_size.x - vbc_rect_offset.x
		$VBC.rect_position.y = 0


	if not is_instance_valid(_current_focus_source)\
			and $VBC/Focus.modulate.a != 0\
			and not $VBC/Focus/Tween.is_active():
		$VBC/Focus.modulate.a = 0

func garbage_collection():
	# The below performs some garbage collection on previously focused cards.
	var to_delete = []
	for c in _previously_focused_cards:
		if not is_instance_valid(_previously_focused_cards[c]):
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
			if vbc_position_mode or not $VBC/Focus/Tween.is_active():
				current_dupe_focus.visible = false
	for c in to_delete:
		var _found = _previously_focused_cards.erase(c)

# Displays the card closeup in the Focus viewport
func focus_card(card: Card, show_preview := true) -> void:
	# We check if we're already focused on this card, to avoid making duplicates
	# the whole time		
	if not _current_focus_source == card:
		# We make a duplicate of the card to display and add it on its own in
		# our viewport world
		# This way we can standardize its scale and look and not worry about
		# what happens on the table.
		var dupe_focus: Card
		if _previously_focused_cards.has(card) and is_instance_valid(_previously_focused_cards[card]):
			dupe_focus = _previously_focused_cards[card]
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
			dupe_focus.is_duplicate_of = card
			dupe_focus.remove_from_group("cards")
			_extra_dupe_preparation(dupe_focus, card)
			# We display a "pure" version of the card
			# This means we hide buttons, tokens etc
			dupe_focus.set_state(Card.CardState.VIEWPORT_FOCUS)
			if vbc_position_mode:
				dupe_focus.set_position(Vector2(0,0))						
				$VBC.add_child(dupe_focus)
			else:
				_focus_viewport.add_child(dupe_focus)
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
		# If the card is facedown, we don't want the info panels
		# giving away information
		if not dupe_focus.is_faceup:
			focus_info.visible = false
		else:
			cfc.ov_utils.populate_info_panels(card,focus_info)
			focus_info.visible = true
		# We store all our previously focused cards in an array, and clean them
		# up when they're not focused anymore
		_previously_focused_cards[card] = dupe_focus
		
		if vbc_position_mode:
			garbage_collection()
			reposition()
			return
		
		set_camera_position(dupe_focus)

		# We always make sure to clean tweening conflicts
		$VBC/Focus/Tween.remove_all()
		# We do a nice alpha-modulate tween
		$VBC/Focus/Tween.interpolate_property($VBC/Focus,'modulate',
				$VBC/Focus.modulate, Color(1,1,1,1), 0.25,
				Tween.TRANS_SINE, Tween.EASE_IN)
		if focus_info.visible_details > 0:
			$VBC/Focus/Tween.interpolate_property(focus_info,'modulate',
					focus_info.modulate, Color(1,1,1,1), 0.25,
					Tween.TRANS_SINE, Tween.EASE_IN)
		else:
			$VBC/Focus/Tween.interpolate_property(focus_info,'modulate',
					focus_info.modulate, Color(1,1,1,0), 0.25,
					Tween.TRANS_SINE, Tween.EASE_IN)
		$VBC/Focus/Tween.start()
		card_focus.visible = show_preview
		# Now that the display panels can expand horizontally
		# we need to set their parent container size to 0 here
		# To ensure they are shown as expected on the screen
		# I.e. the card doesn't appear mid-screen for no reason etc
		card_focus.rect_size = Vector2(0,0)
		$VBC.rect_size = Vector2(0,0)
		
		#handle rendering horizontal cards
		if (card._horizontal and card.get_is_faceup()):
			$VBC.rect_rotation = 90
		else:
			$VBC.rect_rotation = 0
		
		garbage_collection()
		reposition()		

func set_camera_position(dupe_focus):
	if !_current_focus_source or !is_instance_valid(_current_focus_source):
		return

	# We have to copy these internal vars because they are reset
	# see https://github.com/godotengine/godot/issues/3393
	# We make the viewport camera focus on it
	_focus_camera.position = dupe_focus.global_position
	#horizontal case
	if (_current_focus_source._horizontal) and _current_focus_source.get_state_exec() != "pile":
		canonical_size = Vector2(_current_focus_source.canonical_size.y, _current_focus_source.canonical_size.x )	
		vbc_rect_offset = Vector2 (30, $VBC.rect_size.x)
		_focus_camera.set_offset(Vector2(0, -20))
	#normal case
	else:
		vbc_rect_offset =  $VBC.rect_size
		canonical_size = _current_focus_source.canonical_size 
		_focus_camera.set_offset(Vector2(0, 0))

# Hides the focus viewport when we're done looking at it
func unfocus(card: Card) -> void:
	if _current_focus_source == card:
		_current_focus_source = null
		if !vbc_position_mode:
			$VBC/Focus/Tween.remove_all()
			$VBC/Focus/Tween.interpolate_property($VBC/Focus,'modulate',
					$VBC/Focus.modulate, Color(1,1,1,0), 0.25,
					Tween.TRANS_SINE, Tween.EASE_IN)
			if focus_info.modulate != Color(1,1,1,0):
				$VBC/Focus/Tween.interpolate_property(focus_info,'modulate',
						focus_info.modulate, Color(1,1,1,0), 0.25,
						Tween.TRANS_SINE, Tween.EASE_IN)
			$VBC/Focus/Tween.start()
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
	dupe_focus.properties = card.properties.duplicate()
	focus_info.hide_all_info()


# Overridable function for games to extend processing of dupe card
# after adding it to the scene
# warning-ignore:unused_argument
# warning-ignore:unused_argument
func _extra_dupe_ready(dupe_focus: Card, card: Card) -> void:
	var multiplier =  dupe_focus.focused_scale * cfc.curr_scale 
	if CFConst.VIEWPORT_FOCUS_ZOOM_TYPE == "scale":
		dupe_focus.scale = Vector2(1,1) * multiplier
	else:
		dupe_focus.resize_recursively(dupe_focus._control, multiplier)
		dupe_focus.get_card_front().scale_to( multiplier)
		dupe_focus.tokens.token_drawer(false, true)

	dupe_focus.scale = Vector2(2,2) 
func _input(event):
	# We use this to allow the developer to take card screenshots
	# for any number of purposes
	if event.is_action_pressed("screenshot_card"):
		var img = _focus_viewport.get_texture().get_data()
		yield(get_tree(), "idle_frame")
		yield(get_tree(), "idle_frame")
		img.convert(Image.FORMAT_RGBA8)
		img.flip_y()
		img.save_png("user://" + _current_focus_source.canonical_name + ".png")
		
	if event.is_action_pressed("toggle_fullscreen"):
		OS.set_window_fullscreen(!OS.window_fullscreen)	


# Takes care to resize the child viewport, when the main viewport is resized
func _on_Viewport_size_changed() -> void:
	resize()
	
func resize():
	var stretch_mode = cfc.get_screen_stretch_mode()
	if stretch_mode == SceneTree.STRETCH_MODE_2D:
		return

	if is_instance_valid(get_viewport()):
		$ViewportContainer.rect_min_size = get_viewport().size
		$ViewportContainer.rect_size = get_viewport().size



func toggle_glow(is_enabled := true) -> void:
	world_environemt.environment.glow_enabled = is_enabled

func get_origin_card(dupe_card):
	return dupe_card.is_duplicate_of


func get_main_viewport():
	return viewport 
