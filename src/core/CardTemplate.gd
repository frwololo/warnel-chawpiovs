# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED

# A basic card object which includes functionality for handling its own
# placement and focus.
#
# This class is meant to be used as the basis for your card scripting
# Simply make your card scripts extend this class and you'll have all the
# provided scripts available.
# If your card node type is not Area2D, make sure you change the extends type.
class_name Card
extends Area2D

# All the Card's Finite State Machine states
#
# This simply is a way to refer to the values with a human-readable name.
#
# See _process_card_state()
enum CardState {
	IN_HAND					#0
	FOCUSED_IN_HAND			#1
	MOVING_TO_CONTAINER		#2
	REORGANIZING			#3
	PUSHED_ASIDE			#4
	DRAGGED					#5
	DROPPING_TO_BOARD		#6
	ON_PLAY_BOARD			#7
	FOCUSED_ON_BOARD		#8
	IN_PILE					#9
	VIEWED_IN_PILE			#10
	IN_POPUP				#11
	FOCUSED_IN_POPUP		#12
	VIEWPORT_FOCUS			#13
	PREVIEW					#14
	DECKBUILDER_GRID		#15
	MOVING_TO_SPAWN_DESTINATION		#16
}
# Specifies where a card is allowed to drop on the board
#
# * NONE:  Cards cannot be manually dropped on the board
# * SPECIFIC_GRID: Cards can only be manually dropped in Grids of a specific
# name on the board. They will use mandatory_grid_name to specify which grid.
# * ANY_GRID: Cards can only be manually dropped in BoardPlacementGrids
# * ANYWHERE: Cards can only be manually dropped anywhere on the board
enum BoardPlacement{
	NONE
	SPECIFIC_GRID
	GRID_AUTOPLACEMENT
	ANY_GRID
	ANYWHERE
}
enum AttachmentMode{
	DO_NOT_ATTACH
	ATTACH_BEHIND
	ATTACH_IN_FRONT
}
enum AttachmentOffset{
	TOP_LEFT
	TOP
	TOP_RIGHT
	RIGHT
	LEFT
	BOTTOM_LEFT
	BOTTOM
	BOTTOM_RIGHT
}
# Used to spawn CardChoices. We have to add the consts together
# before passing to the preload, or the parser complains.
const _CARD_CHOICES_SCENE_FILE = CFConst.PATH_CUSTOM + "CardChoices.tscn"
const _CARD_CHOICES_SCENE = preload(_CARD_CHOICES_SCENE_FILE)
const _TARGETING_SCENE_FILE = CFConst.PATH_CORE + "Card/TargetingArrow.tscn"
const _TARGETING_SCENE = preload(_TARGETING_SCENE_FILE)

const _CARDBACK_SCENE_FILE = CFConst.PATH_CUSTOM + "CardBack.tscn"
const _CARDBACK_SCENE = preload(_CARDBACK_SCENE_FILE)
const _CARDFRONT_SCENE_FILE = CFConst.PATH_CUSTOM + "CardFront.tscn"
const _CARDFRONT_SCENE = preload(_CARDFRONT_SCENE_FILE)

# Sent when the player start dragging the card
signal dragging_started(card)
# Sent when the card's state changes
signal state_changed(card, old_state, new_state)
signal scripts_executed(card, sceng, trigger)

#horizontal cards
var _horizontal:= false

#when creating duplicates, this can be used to track the original card
var is_duplicate_of = null

# The properties dictionary will be filled in by the setup() code
# according to the card definintion.
export var properties : Dictionary
# We export this variable to the editor to allow us to add scripts to each card
# object directly instead of only via code.
#
# If this variable is set, it takes precedence over scripts
# found in `CardScriptDefinitions.gd`
#
# See `CardScriptDefinitions.gd` for the proper format of a scripts dictionary
export var scripts : Dictionary
# If true, the card can be attached to other cards and will follow
# their host around the table. The card will always return to its host
# when dragged away
export(AttachmentMode) var attachment_mode = AttachmentMode.DO_NOT_ATTACH
# If true, staggers the attachment so the side is also visible
export(AttachmentOffset) var attachment_offset = AttachmentOffset.BOTTOM_RIGHT
# If true, the card front will be displayed when mouse hovers over the card
# while it's face-down
export var is_viewed  := false setget set_is_viewed, get_is_viewed
# Specifies the card rotation in increments of 90 degrees
export(int, 0, 270, 90) var card_rotation  := 0 \
		setget set_card_rotation, get_card_rotation
# Specifies where on the board the card may be placed
export(BoardPlacement) var board_placement \
		:= BoardPlacement.ANYWHERE
export var mandatory_grid_name : String
# Contains the scene which has the Card Back design to use for this card type
# It needs to be scene which uses a CardBack class script.
export(PackedScene) var card_back_design : PackedScene = _CARDBACK_SCENE
export(PackedScene) var card_front_design : PackedScene = _CARDFRONT_SCENE
# We use this variable, so that the scene can be overriden with a custom one
export var targeting_arrow_scene = _TARGETING_SCENE
# If true, the player will not be able to drop dragged cards back into
# CardContainers. The player will only be allowed to drop cards to the board
# or back into the container they picked them front
# The game logic will have to provide another way to send cards to the various
# piles
# Be careful with this setting, as it will allow the player to drop cards
# on top of the hand or pile areas.
export var disable_dropping_to_cardcontainers := false
# If true, the player will not be able to drag cards out of the hand manually
export var disable_dragging_from_hand := false
# If true, the player will not be able to drag cards around the board manually
export var disable_dragging_from_board := false
# If true, the player will not be able to drag cards out of piles
# (Either directly from top, or from popup window
export var disable_dragging_from_pile := false
# If true, and the player attempt to drag the card out of hand
#	then the card will be check on whether it has scripts
#	which are [targeting other cards](SP#KEY_SUBJECT_V_TARGET) and if so
#	will initiate them.
#
# Be aware that if the targeting task is not [is_cost](SP#KEY_IS_COST), then
# other costs and effects of the card will trigger, even if player
# decided not to, or couldn't, target anything.
#
# If not, it will act according to
# [disable_dragging_from_hand](#disable_dragging_from_hand)
export var hand_drag_starts_targeting := false
# The duration of the tweening animation when cards rotate in hand
export(float, 0.0, 1.0, 0.05) var in_hand_tween_duration := 0.3
# The duration of the tweening animation when reorganizing cards in hand
export(float, 0.0, 1.0, 0.05) var reorganization_tween_duration := 0.4
# The duration of the tweening animation when focusing a card in hand
export(float, 0.0, 1.0, 0.05) var focus_tween_duration := 0.3
# The duration of the tweening animation when moving a card between containers
export(float, 0.0, 1.0, 0.05) var to_container_tween_duration := 0.3
# The duration of the tweening animation when cards are pushed aside
# due to a neighbor being focused
export(float, 0.0, 1.0, 0.05) var pushed_aside_tween_duration := 0.3
# The duration of the tweening animation when cards are dropping to the board
export(float, 0.0, 1.0, 0.05) var to_board_tween_duration := 0.25
# The duration of the tweening animation when cards are scaled in play area on the board
export(float, 0.0, 1.0, 0.05) var on_board_tween_duration := 0.3
# The duration of the tweening animation when cards are scaled when being dragged
export(float, 0.0, 1.0, 0.05) var dragged_tween_duration := 0.2
# Stores the normal size of the card as it should appear on the hand.
# It should typically should be the same as card_size,
# but unlike card_size, it should not be adjusted in runtime
export var canonical_size := CFConst.CARD_SIZE
# the size of the card when seen smaller (usually in a card-grid of selection window)
export var play_area_scale := CFConst.PLAY_AREA_SCALE
# the size of the card when seen smaller (usually in a card-grid of selection window)
export var thumbnail_scale := CFConst.THUMBNAIL_SCALE
# The size of the card when seen a thumbnail is moused-over
export var preview_scale := CFConst.PREVIEW_SCALE
# The size of the card when seen larger in the viewport focus window
export var focused_scale := CFConst.FOCUSED_SCALE

# This is **the** authorative name for this node
#
# If not set, will be set to the value of the Name label in the front.
# if that is also not set, will be set.
# to the human-readable value of the "name" node property.
var canonical_name : String setget set_card_name, get_card_name
var canonical_id: String
# Ensures all nodes fit inside this rect.
var card_size := canonical_size setget set_card_size
# Starting state for each card
var state : int = CardState.PREVIEW setget set_state
# If this card is hosting other cards,
# this list retains links to their objects in order.
var attachments := []
# If this card is set as an attachment to another card,
# this tracks who its host is.
var current_host_card : Card = null
# If true, the card will be displayed faceup. If false, it will be facedown
var is_faceup := false setget set_is_faceup, get_is_faceup
# Used to keep the card and mouse cursor in sync when dragging the card around
# Represents the cursor's position relative to the card origin when drag was initiated
var _drag_offset: Vector2
# Used for animating the card.
var _target_position: Vector2
# Used for animating the card.
var _target_rotation: float
# Used to avoid the focus animation repeating once it's completed.
var _focus_completed: bool = false
# We use this to know at which stage of fancy movement this is.
var _fancy_move_second_part := false
# We use this to track multiple cards
# when our card is about to drop onto or target them
var potential_host: Card = null
# We use this to track multiple [CardContainer]s
# when our card is about to drop onto them
var potential_container = null
# If the card is placed in a placement grid, this will hold
# a reference to the slot where this card is placed
var _placement_slot : BoardPlacementSlot = null
# This hold modifiers to card properties that will be active temporarily.
# This avoids triggering the card_properties_modified signal.
#
# Each key is a ScriptingEngine reference, and each value is a dictionary
# With the following keys:
# * requesting_object: The object which has requested this temp modifier
# * modifer: A dictionary with all the modifications requested by this card
#	Each key is a (numerical) property name,
#	and value is the temp modifier requested for this property.
#
# This allows multiple modifiers may be active at the same time, even from
# nested tasks on the same card during an execute_scripts task.
#
# Typically used during
# an [execute_scripts()](ScriptingEngine#execute_scripts] task.
var temp_properties_modifiers := {}

# Used for picking a card to start the compiler on
var _debugger_hook := false
# Debug for stuck tweens
var _tween_stuck_time = 0
# This variable is being used to avoid an infinite loop when alterants
# are altering get_property based on filtering properties of cards
var _is_property_being_altered := false
# The node which has the design of the card back
# And the methods which are used for its potential animation.
# This will be loaded in `_init_card_back()`
var card_back : CardBack

# The node which has the design of the card front
# And the methods which are used for modifying the card labels and sizing.
# This will be loaded in `_init_card_layout()`
var card_front : CardFront
var _card_text
# Holds which controls have already been resized through resize_recursively()
# to avoid trying to resize them again
var _original_layouts:= {}
# This is true while the card is in the process of executing its scripts
# This flag not used in the core CGF, but games build on it can use
# This flag to prevent the player from "double-dipping" on a script
# while animations are playing.
var is_executing_scripts := false
# If this card is freshly spawned, this variable will hold the CardContainer
# which is the final constainer to put it in
var spawn_destination

# This variable will point to the scene which controls the targeting arrow
var targeting_arrow

var _tween
var _flip_tween 
var _control 
# This is the control node we've setup to host the card_front design
var _card_front_container
# This is the control node we've setup to host the card_back design
var _card_back_container 

# The node which hosts all manipulation buttons belonging to this card
# as well as methods to hide/show them, and connect them to this card.
var buttons 
# The node which hosts all tokens belonging to this card
# as well as the methods retrieve them and to to hide/show their drawer.
var tokens: TokenDrawer
# The node which manipulates the highlight borders.
var highlight 

#can temporarily set this to true to avoid creating a tween that would rotate the card
var _maintain_rotation_when_moving := false 

#overridable function if needed
func _class_specific_ready():
	_tween = $Tween
	_flip_tween = $Control/FlipTween
	_control = $Control
	# This is the control node we've setup to host the card_front design
	_card_front_container = $Control/Front
	# This is the control node we've setup to host the card_back design
	_card_back_container = $Control/Back

	# The node which hosts all manipulation buttons belonging to this card
	# as well as methods to hide/show them, and connect them to this card.
	buttons = $Control/ManipulationButtons
	# The node which hosts all tokens belonging to this card
	# as well as the methods retrieve them and to to hide/show their drawer.
	tokens = $Control/Tokens
	# The node which manipulates the highlight borders.
	highlight = $Control/Highlight	
	
	targeting_arrow = targeting_arrow_scene.instance()
	add_child(targeting_arrow)
	set_card_size(card_size)

	_init_card_layout()

	# The below call ensures out canonical_name variable is set.
	# Normally the setup() function should be used to set it,
	# but setting the name here as well ensures that a card can be also put on
	# The board without calling setup() and then use its hardcoded labels
	_init_card_name()
	setup()	



	# warning-ignore:return_value_discarded
	$Control.connect("gui_input", self, "_on_Card_gui_input")
	$Control.connect("tree_exiting", self, "_on_tree_exiting")
#	cfc.signal_propagator.connect_new_card(self)
	scripting_bus.connect("scripting_event_triggered", self, "execute_scripts")

	#cleanup for when this cards is instantiated as a copy of another
	clear_highlight()
	#TODO forcing here in the hope that it will fix the issue in selectionwindow
	tokens.set_is_drawer_open(false, true)
	

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	#this gives an options for subclasses to skip this parent's ready calls if needed
	_class_specific_ready()

func get_card_back():
	if !card_back:
		_init_card_back()
	return card_back

func _init_card_back():
	# Because we duplicate the card when adding to the viewport focus
	# It already has a CardBack node, so we don't want to replicate it
	# so we only add a CardBack node, if we know it's not a dupe focus

	# If it is a viewport focus dupe, we still need to setup the
	# card_back variable, as the .duplicate() method does not copy
	# internal variables.	
	
	if _card_back_container.get_children():
		card_back = _card_back_container.get_child(0)	
	else:
		# We do not need to instance the card_back when card is seen
		# in a preview card grid
		if get_parent().get_class() != "CVGridCardObject":
			var card_back_instance = card_back_design.instance()
			_card_back_container.add_child(card_back_instance)
			card_back = card_back_instance
			_card_back_container.move_child(card_back,0)



func get_card_front():
	if !card_front:
		_init_card_front()
	return card_front


func _init_card_front() -> void:
	# Because we duplicate the card when adding to the viewport focus
	# It already has a CardBack node, so we don't want to replicate it
	# so we only add a CardBack node, if we know it's not a dupe focus

	# If it is a viewport focus dupe, we still need to setup the
	# card_back variable, as the .duplicate() method does not copy
	# internal variables.	
	
	if _card_front_container.get_children():
		card_front = _card_front_container.get_child(0)
	else:
		var card_front_instance = card_front_design.instance()
		_card_front_container.add_child(card_front_instance)
		card_front = card_front_instance



func _init_card_layout() -> void:
	_init_card_front()
	_init_card_back()



# Ensures that the canonical card name is set in all fields which use it.
#  var canonical_name, "Name" label and self.name should use the same string.
func _init_card_name() -> void:
	if not canonical_name:
		# The node name changes depending on how many other cards
		# with the same node name are siblings
		# We use this regex to discover the actual name
		var regex = RegEx.new()
		regex.compile("@{0,1}([\\w ]+)@{0,1}")
		var result = regex.search(name)
		var node_human_name = result.get_string(1)
		if (not node_human_name):
			regex.compile("([\\w ]+)-")
			result = regex.search(name)
			node_human_name = result.get_string(1)		
		set_card_name(node_human_name, false)
	else:
		# If the variable has been set, we ensure label and node name
		# are matching
		set_card_name(canonical_name, false)


func _class_specific_process(delta):
	if $Tween.is_active() and not cfc.ut: # Debug code for catch potential Tween deadlocks
		_tween_stuck_time += delta
		if _tween_stuck_time > 5 and int(fmod(_tween_stuck_time,3)) == 2 :
			print_debug("Tween Stuck for ",_tween_stuck_time,
					"seconds. Reports leftover runtime: ",$Tween.get_runtime ( ))
			$Tween.remove_all()
			_tween_stuck_time = 0
	else:
		_tween_stuck_time = 0
	_process_card_state()
	# Having to do all these checks due to godotengine/godot#16854
	if cfc._debug and not get_parent().is_in_group("piles"):
		var stateslist = [
			"IN_HAND",
			"FOCUSED_IN_HAND",
			"MOVING_TO_CONTAINER",
			"REORGANIZING",
			"PUSHED_ASIDE",
			"DRAGGED",
			"DROPPING_TO_BOARD",
			"ON_PLAY_BOARD",
			"FOCUSED_ON_BOARD",
			"IN_PILE",
			"VIEWED_IN_PILE",
			"IN_POPUP",
			"FOCUSED_IN_POPUP",
			"VIEWPORT_FOCUS",
			"PREVIEW",
			"DECKBUILDER_GRID",
			"MOVING_TO_SPAWN_DESTINATION",
		]
		$Debug.visible = true
		$Debug/id.text = "ID:  " + str(self)
		$Debug/state.text = "STATE: " + stateslist[state]
		$Debug/index.text = "INDEX: " + str(get_index())
		$Debug/parent.text = "PARENT: " + str(get_parent().name)
	else:
		$Debug.visible = false	

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta) -> void:
	_class_specific_process(delta)



# Triggers the focus-in effect on the card
func _on_Card_mouse_entered() -> void:
	gain_focus()

func gain_focus():
	# This triggers the focus-in effect on the card
	#print(state,":enter:",get_index(), ":", buttons._are_hovered()) # Debug
	#print($Control/Tokens/Drawer/VBoxContainer.rect_size) # debug	
	match state:
		CardState.IN_HAND, CardState.REORGANIZING, CardState.PUSHED_ASIDE:
			if not cfc.card_drag_ongoing:
				#print("focusing:",get_my_card_index()) # debug
				interruptTweening()
				set_state(CardState.FOCUSED_IN_HAND)
		CardState.ON_PLAY_BOARD:
			set_state(CardState.FOCUSED_ON_BOARD)
		# The only way to mouse over a card in a pile, is when
		# it's in a the grid popup
		CardState.IN_POPUP:
			set_state(CardState.FOCUSED_IN_POPUP)

func _class_specific_input(event) -> void:
	if event is InputEventMouseButton and not event.is_pressed():
		if targeting_arrow.is_targeting:
			if event.get_button_index() == 2: #todo have a cancel button on screen instead
				targeting_arrow.cancel_targeting()
			else:
				targeting_arrow.complete_targeting()
		if  event.get_button_index() == 1:
			# On depressed left mouse click anywhere on the board
			# We stop all attempts at dragging this card
			# We cannot do this in gui_input, because some thing
			# like the targetting arrow, will trigger dragging
			# because the click depress will not trigger on the card for some reason
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			$Control.set_default_cursor_shape(Input.CURSOR_ARROW)
			cfc.card_drag_ongoing = null
	

func _input(event) -> void:
	_class_specific_input(event)

func are_hovered_manipulation_buttons():
	if !buttons:
		return false
	return buttons.hovered()	

func set_manipulation_buttons_active(value):
	if !buttons:
		return false
	return buttons.set_active(value)

# A signal for whenever the player clicks on a card
func _on_Card_gui_input(event) -> void:
	cfc.add_ongoing_process(self)
	if event is InputEventMouseButton and cfc.NMAP.has("board"):
		# because of https://github.com/godotengine/godot/issues/44138
		# we need to double check that the card which is receiving the
		# gui input, is actually the one with the highest index.
		# We use our mouse pointer which is tracking this info.
		if cfc.NMAP.board.mouse_pointer.current_focused_card \
				and self != cfc.NMAP.board.mouse_pointer.current_focused_card:
			cfc.NMAP.board.mouse_pointer.current_focused_card._on_Card_gui_input(event)
		# If the player left clicks, we need to see if it's a double-click
		# or a long click
		elif event.is_pressed() \
				and event.get_button_index() == 1 \
				and not are_hovered_manipulation_buttons() \
				and not tokens.are_hovered():
			# If it's a double-click, then it's not a card drag
			# But rather it's script execution
			if event.doubleclick\
					and ((check_play_costs() != CFConst.CostsState.IMPOSSIBLE
					and get_state_exec() == "hand")
					or get_state_exec() == "board"):
				cfc.card_drag_ongoing = null
				execute_scripts()
			# If it's a long click it might be because
			# they want to drag the card
			else:
				if state in [CardState.FOCUSED_IN_HAND,
						CardState.FOCUSED_ON_BOARD,
						CardState.FOCUSED_IN_POPUP]:
					# But first we check if the player does a long-press.
					# We don't want to start dragging the card immediately.
					cfc.card_drag_ongoing = self
					# We need to wait a bit to make sure the other card has a chance
					# to go through their scripts
					yield(get_tree().create_timer(0.1), "timeout")
					# If this variable is still set to true,
					# it means the mouse-button is still pressed
					# We also check if another card is already selected for dragging,
					# to prevent from picking 2 cards at the same time.
					if cfc.card_drag_ongoing == self:
						if state == CardState.FOCUSED_IN_HAND\
								and  _has_targeting_cost_hand_script()\
								and check_play_costs() != CFConst.CostsState.IMPOSSIBLE:
							cfc.card_drag_ongoing = null
							var _sceng = execute_scripts()
						elif state == CardState.FOCUSED_IN_HAND\
								and (disable_dragging_from_hand
								or check_play_costs() == CFConst.CostsState.IMPOSSIBLE):
							cfc.card_drag_ongoing = null
						elif state == CardState.FOCUSED_ON_BOARD \
								and disable_dragging_from_board:
							cfc.card_drag_ongoing = null
						elif state == CardState.FOCUSED_IN_POPUP \
								and disable_dragging_from_pile:
							cfc.card_drag_ongoing = null
						else:
							# While the mouse is kept pressed, we tell the engine
							# that a card is being dragged
							_start_dragging(event.position)
		# If the mouse button was released we drop the dragged card
		# This also means a card clicked once won't try to immediately drag
		elif not event.is_pressed() and event.get_button_index() == 1:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			$Control.set_default_cursor_shape(Input.CURSOR_ARROW)
			cfc.card_drag_ongoing = null
			match state:
				CardState.DRAGGED:
					# if the card was being dragged, it's index is very high
					# to always draw above other objects
					# We need to reset it to the default
					z_index = CFConst.Z_INDEX_BOARD_CARDS_NORMAL
					for attachment in self.attachments:
						attachment.z_index = CFConst.Z_INDEX_BOARD_CARDS_NORMAL

					var destination = cfc.NMAP.board
					if potential_container:
						destination = potential_container
						potential_container.highlight.set_highlight(false)
					move_to(destination)
					_focus_completed = false
		else:
			_process_more_card_inputs(event)
	cfc.remove_ongoing_process(self)


# Overridable function to allow games to extend the _on_Card_gui_input() functionality
# We use this so that we know we caught the correct card based on its index
func _process_more_card_inputs(_event) -> void:
	pass




# Triggers the focus-out effect on the card
func _on_Card_mouse_exited() -> void:
	lose_focus()

func lose_focus():
	# On exiting this node, we wait a tiny bit to make sure the mouse didn't
	# just enter a child button
	# If it did, then that button will immediately set a variable to let us know
	# not to restart the focus
	#print(state,":exit:",get_index()) # debug
	#print(buttons.are_hovered()) # debug
	match state:
		CardState.FOCUSED_IN_HAND:
			#_focus_completed = false
			# To avoid errors during fast player actions
			if get_parent().is_in_group("hands"):
				for c in get_parent().get_all_cards():
					# We need to make sure afterwards all card will return
					# to their expected positions
					# Therefore we simply stop all tweens and reorganize the whole hand
					c.interruptTweening()
					# This will also set the state to IN_HAND afterwards
					c.reorganize_self()
		CardState.FOCUSED_ON_BOARD:
			set_state(CardState.ON_PLAY_BOARD)
		CardState.FOCUSED_IN_POPUP:
			set_state(CardState.IN_POPUP)

# This function handles filling up the card's labels according to its
# card definition dictionary entry.
func setup() -> void:
	# If the card properties have already been populated, we use them
	# This might happen in case the card is modified outside the game
	# For example, with legacy elements.
	var read_properties := properties.duplicate(true)
	# The name property will almost always exist, due to being set by _init_name()
	# Therefore we remove this property, to ensure the next check works properly
	# warning-ignore:return_value_discarded
	read_properties.erase('Name')
	# canonical_name needs to be setup before we call this function
	set_card_name(canonical_name)
	if state != CardState.VIEWPORT_FOCUS:
		if read_properties.empty():
			read_properties = cfc.card_definitions.get(canonical_id, {})
	else:
		# We set them again here for the viewport focus, in order to ensure
		# we capture the card_name in them
		read_properties = properties.duplicate(true)
	for property in read_properties.keys():
		# warning-ignore:return_value_discarded
		modify_property(
				property,
				read_properties[property],
				false,
				["Init"])
	


# Changes the property stored in the properties dictionary of this card
# and modified the card front labels so that they display the correct
# text
#
# If the property is a number, and the value is a string integer with the
# operator in front (e.g. "+4", "-1" etc), then instead of setting the property
# it will be instead modified by that amount.
func modify_property(
			property: String,
			value,
			check := false,
			tags := ["Manual"]) -> int:
	var retcode: int
	var is_init := false
	if "Init" in tags:
		is_init = true
	if not property in properties.keys() and not is_init:
		retcode = CFConst.ReturnCode.FAILED
	elif typeof(properties.get(property)) == typeof(value)\
			and properties.get(property) == value\
			and not is_init:
		retcode = CFConst.ReturnCode.OK
	elif typeof(properties.get(property)) != typeof(value)\
			and str(properties.get(property)) == str(value):
		retcode = CFConst.ReturnCode.OK
	# This checks if the player is trying to reduce a card property below 0
	# And if so, returns FAILED
	elif check\
			and property in CardConfig.PROPERTIES_NUMBERS\
			and typeof(value) == TYPE_STRING\
			and value.is_valid_integer()\
			and properties.get(property,0) + int(value) < 0:
		retcode = CFConst.ReturnCode.FAILED
	else:
		# We store the values to send with the signal
		var previous_value
		if not is_init:
			previous_value = properties[property]
		retcode = CFConst.ReturnCode.CHANGED
		if not check and property == "Name":
			set_card_name(value)
		elif not check:
			# We do this check because we allow strings specifying
			# numerical property modifications to be sent
			# In that case, the set of the property is based on calcualtion operations
			# that we do that later on.
			if properties.get(property) == null\
					or typeof(properties.get(property)) == typeof(value):
				properties[property] = value
				
			if ("emit_signal" in tags) or not is_init:
				scripting_bus.emit_signal(
						"card_properties_modified",
						self,
						{
							"property_name": property,
							"new_property_value": value,
							"previous_property_value": previous_value,
							"tags": tags
						}
				)			
			if not card_front.card_labels.has(property):
				if not property.begins_with("_"):
					#print_debug("Warning: ", property,
					#		" does not have a matching label!")
					var _tmp = 1
				#retcode = CFConst.ReturnCode.FAILED
			else:
				# These are int or float properties which need to be converted
				# to a string with some formatting.
				#
				# In this demo, the format is defined as: "labelname: value"
				if property in CardConfig.PROPERTIES_NUMBERS:
					# If the property is numerical but the value is a string
					# and that value has a +/- operator
					# The designer is attempting to modify the property
					# from its current value
					if typeof(value) == TYPE_STRING:
						if value.is_valid_integer():
							# We catch the designer by mistake putting a number
							# as an integer in the card definition
							# We also set directly as the value, if the current value of the card
							# if a string (.e.g 'X')
							if is_init or typeof(properties[property]) != TYPE_INT:
								properties[property] = int(value)
							# If this is not during init, then a +/- number in modify_property() args
							# signifies an operation on the existing number
							else:
								properties[property] += int(value)
						else:
							# We allow setting number properties as strings.
							# We assume the designer knows what they're doing
							properties[property] = value
				# If the property is an array, and the value is a string, we assume they want
				# to add this value to the array
				# If the value is prepended by -, we assume the want to remove the value.
				if property in CardConfig.PROPERTIES_ARRAYS and typeof(value) == TYPE_STRING:
					if value.begins_with('-'):
						properties[property].erase(value.lstrip('-'))
					else:
						properties[property].append(value)
			refresh_property_label(property)
	return(retcode)


func refresh_property_label(property: String) -> void:
	if not is_instance_valid(card_front) or not card_front.card_labels.has(property):
		return
	var label_node = card_front.card_labels[property]
	var value_for_label = str(properties[property])
	if property in CardConfig.PROPERTIES_NUMBERS:
		if typeof(properties[property]) == TYPE_INT and properties[property] < 0:
			value_for_label = '0'
		elif typeof(properties[property]) == TYPE_STRING and properties[property].is_valid_integer():
			value_for_label = str(int(properties[property]))
		if value_for_label =='0' and property in CardConfig.NUMBERS_HIDDEN_ON_0:
			card_front.set_label_text(label_node,"")
		elif property in CardConfig.NUMBER_WITH_LABEL:
			card_front.set_label_text(label_node,property
					+ ": " + value_for_label)
		else:
			card_front.set_label_text(label_node,value_for_label)
	# These are arrays of properties which are put in a label
	# with a simple join character
	elif property in CardConfig.PROPERTIES_ARRAYS:
		card_front.set_label_text(label_node,
				CFUtils.array_join(properties[property],
				CFConst.ARRAY_PROPERTY_JOIN))
	# These are standard properties which is simple a String to add to the
	# label.text field
	# Normally they should be defined in CardConfig.PROPERTIES_STRINGS
	# but this is also the fallback we use for
	# properties undefined in CardConfig
	elif card_front.card_labels[property] as RichTextLabel:
		card_front.set_rich_label_text(label_node, _get_formatted_text(properties[property]))
	else:
		card_front.set_label_text(label_node, _get_formatted_text(properties[property]))


func refresh_card_front() -> void:
	for property in properties:
		refresh_property_label(property)



# Retrieves the value of a property. This should always be used instead of
# properties.get() as it takes into account the temp_properties_modifiers var
# and also checks for alterant scripts
func get_property(property: String, default = null, force_alterant_check = false):
	if property =="scheme_crisis":
		var _tmp = 1
	if not (properties.has(property)) and not force_alterant_check:
		return default
	return(get_property_and_alterants(property, false, default).value)


# Discovers the modified value of the specified property based
# on temp_properties_modifiers and alterants (if it's a number).
#
# Returns a dictionary with the following keys:
# * value: The final value of this property after all modifications
# * alteration: The  full dictionary returned by
#	CFScriptUtils.get_altered_value() but including details about
#	temp_properties_modifiers
func get_property_and_alterants(property: String,
		use_global_temp_mods := false, default = null) -> Dictionary:

	if canonical_id == "01027" and property == "attack":
		var _tmp = 1
	var property_value = properties.get(property, default)
	var alteration = {
		"value_alteration": 0,
		"alterants_details": {}
	}
	var temp_modifiers = {
		"value_modification": 0,
		"modifier_details": {}
	}
	if property in CardConfig.PROPERTIES_NUMBERS and typeof(property_value) == TYPE_INT:
		var tmp_mods : Dictionary
		# The global card modifications record in cfc is not typically used
		# A game will have to be setup to explicitly request its use in this
		# method. This would be needed for example when calculating the
		# effect a temp_modifier would have on a card subject, before
		# a subject was selected.
		if use_global_temp_mods\
				and temp_properties_modifiers.empty()\
				and not cfc.card_temp_property_modifiers.empty():
			tmp_mods = cfc.card_temp_property_modifiers
		else:
			tmp_mods = temp_properties_modifiers
		for modifiers_dict in tmp_mods.values():
			temp_modifiers.value_modification += \
					modifiers_dict.modifier.get(property,0)
			# Each value in the modifier_details dictionary is another dictionary
			# Where the key is the card object which has added this modifier
			# And the value is the modifier this specific card added to the total
			temp_modifiers.modifier_details[modifiers_dict.requesting_object] =\
					modifiers_dict.modifier.get(property,0)
		property_value += temp_modifiers.value_modification
		# We use this flag to avoid an alteranty which alters get_property
		# by filtering the card's properties, causing an infinite loop.
		if not _is_property_being_altered:
			_is_property_being_altered = true
			alteration = CFScriptUtils.get_altered_value(
				self,
				"get_property",
				{SP.KEY_PROPERTY_NAME: property,},
				properties.get(property, default))
			if alteration is GDScriptFunctionState:
				alteration = yield(alteration, "completed")
			_is_property_being_altered = false
			# The first element is always the total modifier from all alterants
			property_value += alteration.value_alteration
		if property_value < 0:
			property_value = 0
	var return_dict := {
		"value": property_value,
		"alteration": alteration,
		"temp_modifiers": temp_modifiers
	}
	return(return_dict)


# Adjust all control nodes in this card's hierarchy so that they are
# scaled according to the requested scale, and then adjusted in position likewise
# This allows the card layout to scale without using the .scale property
# Which prevents the font from getting blurry
func resize_recursively(control_node: Node, requested_scale: float) -> void:
	if card_size != canonical_size * requested_scale:
		card_size = canonical_size * requested_scale
	if _original_layouts.has(control_node)\
			and CFUtils.compare_floats(requested_scale, _original_layouts[control_node].get('scale')):
		return
	if control_node as Control and not _original_layouts.has(control_node):
		_original_layouts[control_node] = {}
		_original_layouts[control_node]["size"] = control_node.rect_min_size
		_original_layouts[control_node]["position"] = control_node.rect_position
		if control_node as MarginContainer:
			for margin in ["top","bottom", "left", "right"]:
				_original_layouts[control_node]["margin_" + margin]\
						= control_node.get("custom_constants/margin_" + margin)
	for child in control_node.get_children():
		resize_recursively(child, requested_scale)
	if control_node as Control:
		control_node.rect_min_size = _original_layouts[control_node]["size"] * requested_scale
		control_node.call_deferred('set_size', control_node.rect_min_size)
		control_node.rect_position = _original_layouts[control_node]["position"] * requested_scale
		if control_node as MarginContainer:
			for margin in ["top","bottom", "left", "right"]:
				var current_margin = control_node.get("custom_constants/margin_" + margin)
				if not current_margin:
					current_margin = 0.0
				control_node.set("custom_constants/margin_" + margin,current_margin * requested_scale)
		_original_layouts[control_node]["scale"] = requested_scale

func display_debug(msg):
	pass

# Sets the card size and adjusts all nodes depending on it.
func set_card_size(value: Vector2, ignore_area = false) -> void:
	if (canonical_id == "01001b" or canonical_id =="01097"):
		display_debug(canonical_name + "set size to " + str(value.x) + "x" + str(value.y))
	card_size = value
	_control.rect_min_size = value
	# We set the card to always pivot from its center.
	_control.rect_pivot_offset = value/2
	_card_back_container.rect_min_size = value
	_card_front_container.rect_min_size = value
	# We set the card's Highlight to always extend 3 pixels over
	# Either side of the card. This way its border will appear
	# correctly when hovering over the card.
	for node in [highlight._left_right, highlight._top_bottom, highlight]:
		node.rect_min_size = value + Vector2(6, 6)
		# We cannot set the rect_size immediately after setting the min_size
		# As the engine won't allow it, as the min_size change has not happened yet
		node.call_deferred('set_size', node.rect_min_size)
	highlight.rect_position = Vector2(-3, -3)
	if not ignore_area:
		$CollisionShape2D.shape.extents = value / 2
		$CollisionShape2D.position = value / 2


# Setter for is_faceup
#
# Flips the card face-up/face-down
#
# * Returns CFConst.ReturnCode.CHANGED if the card actually changed rotation
# * Returns CFConst.ReturnCode.OK if the card was already in the correct rotation
func set_is_faceup(
			value: bool,
			instant := false,
			check := false,
			tags := ["Manual"]) -> int:
	var retcode: int
	if value == is_faceup:
		retcode = CFConst.ReturnCode.OK
	# We check if the parent is a valid instance
	# If it is not, this is a viewport dupe card that has not finished
	# its ready() process
	elif not check and is_instance_valid(get_parent()):
		tokens.set_is_drawer_open(false)
		# We make sure to remove other tweens of the same type to avoid a deadlock
		is_faceup = value
		# When we change faceup state, we reset the is_viewed to false
		if set_is_viewed(false) == CFConst.ReturnCode.FAILED:
			printerr("ERROR: Something went unexpectedly in set_is_faceup")
		if value:
			_flip_card(_card_back_container, _card_front_container,instant)
			# We need this check, as this node might not be ready
			# Yet when a viewport focus dupe is instancing
			if buttons:
				buttons.set_button_visible("View", false)
			if is_instance_valid(card_back):
				card_back.stop_card_back_animation()
		else:
			_flip_card(_card_front_container, _card_back_container,instant)
			if buttons:
				buttons.set_button_visible("View", true)
#			if get_parent() == cfc.NMAP.board:
			if is_instance_valid(card_back):
				card_back.start_card_back_animation()
		# When we flip, we also want to adjust the dupe card
		# in the focus viewport
		if state != CardState.VIEWED_IN_PILE\
				and cfc.NMAP.get("main", null)\
				and cfc.NMAP.main._previously_focused_cards.has(self):
			var dupe_card : Card = cfc.NMAP.main._previously_focused_cards[self]
# warning-ignore:return_value_discarded
			dupe_card.set_is_faceup(value, true)
		retcode = CFConst.ReturnCode.CHANGED
		# When the faceup has the instant switch, it's typically a built-in
		# action, which we don't want trigerring scripts
		if not instant:
			scripting_bus.emit_signal(
					"card_flipped",
					self,
					{
						"is_faceup": value,
						"tags": tags,
					})
	# If we're doing a check, then we just report CHANGED.
	else:
		retcode = CFConst.ReturnCode.CHANGED
	return retcode


# Getter for is_faceup
func get_is_faceup() -> bool:
	return is_faceup


# Setter for is_viewed
#
# (What does that do ?)
#
# * Returns CFConst.ReturnCode.CHANGED if the card actually changed view status
# * Returns CFConst.ReturnCode.OK if the card was already in the correct view status
# * Returns CFConst.ReturnCode.FAILED if changing the status is now allowed
func set_is_viewed(value: bool) -> int:
	var retcode: int
	if value == true:
		if is_faceup == true:
			# Players can already see faceup cards
			retcode = CFConst.ReturnCode.FAILED
		elif value == is_viewed:
			retcode = CFConst.ReturnCode.OK
		else:
			is_viewed = true
			if state != CardState.VIEWED_IN_PILE\
					and cfc.NMAP.get("main", null)\
					and cfc.NMAP.main._previously_focused_cards.has(self):
				var dupe_card : Card = cfc.NMAP.main._previously_focused_cards[self]
				# warning-ignore:return_value_discarded
				dupe_card.set_is_faceup(true, true)
			card_back.is_viewed_visible = true
			retcode = CFConst.ReturnCode.CHANGED
			# We only emit a signal when we view the card
			# not when we unview it as that happens naturally
			scripting_bus.emit_signal("card_viewed", self,  {"is_viewed": true})
	else:
		if value == is_viewed:
			retcode = CFConst.ReturnCode.OK
		elif is_faceup == true:
			retcode = CFConst.ReturnCode.CHANGED
			is_viewed = false
			card_back.is_viewed_visible = false
		else:
			# We don't allow players to unview cards
			retcode = CFConst.ReturnCode.FAILED

	return retcode


# Getter for is_faceup
func get_is_viewed() -> bool:
	return is_viewed


# Setter for canonical_name
# Also changes the card label and the node name
func set_card_name(value : String, set_label := true) -> void:
	# if the card_front.card_labels variable is not set it means ready() has not
	# run yet, so we just store the card name for later.
	if card_front:
		# We set all areas of the card to match the canonical name.
		var name_label = card_front.card_labels.get("Name", null)
		if set_label and name_label as RichTextLabel:
			card_front.set_rich_label_text(name_label,value)
		elif set_label:
			card_front.set_label_text(name_label,value)
	name = value + "-" + guidMaster.get_guid(self) #a unique identifier that will also work for network calls
	canonical_name = value
	properties["Name"] = value


# Getter for canonical_name
func get_card_name() -> String:
	return canonical_name


# Overwrites the built-in set name, so that it also sets canonical_name
#
# It's preferrable to set canonical_name instead.
func set_name(value : String) -> void:
	.set_name(value)
	if card_front:
		card_front.card_labels["Name"].text = value
	canonical_name = value


# Sets the card state and sends a signal.
func set_state(value: int) -> void:
	if state == CardState.DRAGGED:
		pass
	var prev_state = state
	state = value
	emit_signal("state_changed", self, prev_state, state)


# Setter for card_rotation.
#
# Rotates the card the specified number of degrees.
#
# If the caller specifies the degree the card already has,
# and they have enabled the toggle flag,
# then we just reset the card to 0 degrees.
#
# * Returns CFConst.ReturnCode.CHANGED if the card actually changed rotation.
# * Returns CFConst.ReturnCode.OK if the card was already in the correct rotation.
# * Returns CFConst.ReturnCode.FAILED if an invalid rotation was specified.
func set_card_rotation(
			value: int,
			toggle := false,
			start_tween := true,
			check := false,
			tags := ["Manual"]) -> int:
	var retcode
	
	# For cards we only allow orthogonal degrees of rotation
	# If it's not, we consider the request failed
	if not ("force" in tags) and not (value in [0,90,180,270]):
		retcode = CFConst.ReturnCode.FAILED
	# We only allow rotating card while they're on the board
	elif value != 0 and get_parent() != cfc.NMAP.board:
		retcode = CFConst.ReturnCode.FAILED
	# If the card is already in the specified rotation
	# and a toggle was not requested, we consider we did nothing
	elif value == card_rotation and not toggle:
		retcode = CFConst.ReturnCode.OK
		# We add this check because hand oval rotation
		# does not change the card_rotation property
		# so we ensure that the displayed rotation of a card
		# which is not in hand, matches our expectations
		if not state in [CardState.PREVIEW, CardState.DECKBUILDER_GRID]\
				and not get_parent().is_in_group("hands") \
				and cfc.game_settings.hand_use_oval_shape \
				and $Control.rect_rotation != 0.0 \
				and not $Tween.is_active():
			_add_tween_rotation($Control.rect_rotation,value)
			if start_tween:
				$Tween.start()
	else:
		# If the toggle was specified then if the card matches the requested
		# rotation, we reset it to 0 degrees
		if card_rotation == value and toggle:
			value = 0

		# We modify the card only if this is not a cost dry-run
		if not check:
			card_rotation = value
			# If the value is 0 but the card is in an oval hand, we ensure the actual
			# rotation we apply to the card will be their hand oval rotation
			if value == 0 \
					and get_parent().is_in_group("hands") \
					and cfc.game_settings.hand_use_oval_shape:
				value = int(_recalculate_rotation())
			$CollisionShape2D.rotation_degrees = value
			# We make sure to remove other tweens of the same type
			# to avoid a deadlock
			# There's no way to rotate the Area2D node,
			# so we just rotate the internal $Control. The results are the same.
			_add_tween_rotation($Control.rect_rotation,value)
			# We only start the animation if this flag is set to true
			# This allows us to set the card to rotate on the next
			# available tween, instead of immediately.
			if start_tween:
				$Tween.start()
			#$Control/Tokens.rotation_degrees = -value # need to figure this out
			# When the card actually changes orientation
			# We report that it changed.
			scripting_bus.emit_signal(
					"card_rotated", self,
					{
						"degrees": value,
						"tags": tags,
					}
			)

		retcode = CFConst.ReturnCode.CHANGED
	return retcode


# Getter for card_rotation
func get_card_rotation() -> int:
	return card_rotation


# Discovers if a grid placement slot is currently highlighted to be used
func get_potential_placement_slot() -> BoardPlacementSlot:
	var placement_slot: BoardPlacementSlot = null
	for ps in get_tree().get_nodes_in_group("placement_slot"):
		if ps.is_highlighted():
			placement_slot = ps
	return(placement_slot)

# Arranges so that the card enters the chosen container.
#
# Will take care of interpolation.
#
# If the target container is the board, the card will either be placed at the
# mouse position, or at the 'boardPosition' variable.
#
# If placed in a pile, the index determines the card's position
# among other card. If it's -1, card will be placed on the bottom of the pile
func move_to(targetHost: Node,
		index := -1,
		board_position = null,
		tags := ["Manual"]) -> void:
#	if cfc.game_settings.focus_style:
#		# We make to sure to clear the viewport focus because
#		# the mouse exited signal will not fire after drag&drop in a container
#		cfc.NMAP.main.unfocus()
	# We clear all caches every time the board state changes
	cfc.flush_cache()
	cfc.add_ongoing_process(self)
	# We need to store the parent, because we won't be able to know it later
	var parentHost = get_parent()
	# We want to keep the token drawer closed during movement
	tokens.set_is_drawer_open(false)
	# This checks ensure we don't change parent to the board,
	# if the placement to the board requested is invalid
	# depending on the board_placement variable
	targetHost = targetHost.get_final_placement_node(self)
	targetHost = common_pre_move_scripts(targetHost, parentHost, tags)
	if targetHost == cfc.NMAP.board and not board_position:
		match board_placement:
			BoardPlacement.NONE:
				targetHost = parentHost
			BoardPlacement.ANY_GRID:
				var slot = get_potential_placement_slot()
				if slot:
					board_position = slot
				else:
					targetHost = parentHost
					board_position = _placement_slot
			BoardPlacement.SPECIFIC_GRID, BoardPlacement.GRID_AUTOPLACEMENT:
				var slot = get_potential_placement_slot()
				if slot:
					if get_potential_placement_slot().get_grid_name() \
							== mandatory_grid_name:
						board_position = slot
					else:
						targetHost = parentHost
						board_position = _placement_slot
				elif board_placement == BoardPlacement.GRID_AUTOPLACEMENT \
						and not _placement_slot:
					var grid = cfc.NMAP.board.get_grid(mandatory_grid_name)
					if grid:
						slot = grid.find_available_slot()
						yield(get_tree().create_timer(0.1), "timeout")
						if slot:
							board_position = slot
						else:
							targetHost = parentHost
							board_position = _placement_slot
					else:
						targetHost = parentHost
						board_position = _placement_slot
				else:
					targetHost = parentHost
					board_position = _placement_slot
			# If we allow positioning anywhere, we check a slot it higlighted
			# if it is, we use it as target position
			_:
				var slot = get_potential_placement_slot()
				if slot:
					board_position = slot
	if targetHost != parentHost:
		# When changing parent, it resets the position of the child it seems
		# So we store it to know where the card used to be, before moving it
		var previous_pos = global_position
		var global_pos = global_position
		# If the parent and the target are on different scales, we want to
		# adjust the scale of the card before moving.
		# The MOVING_TO_CONTAINER state will adjust the scale with a tween automatically
		# which will make the card appear to be be resizing as it's moving
		var parent_scale: Vector2
		var target_scale: Vector2
		if parentHost as Control:
			parent_scale = parentHost.rect_scale
		else:
			parent_scale = parentHost.scale
		if targetHost as Control:
			target_scale = targetHost.rect_scale
		else:
			target_scale = targetHost.scale
		if parent_scale > target_scale:
			set_scale(parent_scale / target_scale)
		elif parent_scale < target_scale:
			set_scale(scale * parent_scale * target_scale)
		# We need to remove the current parent node before adding a different one
		parentHost.remove_child(self)
		targetHost.add_child(self)
		# The below is used when a specific card position is requested
		# It converts the requested card position, to absolute node position
		# between all nodes
		if index >= 0:
			targetHost.move_child(self,
					targetHost.translate_card_index_to_node_index(index))
		# Ensure card stays where it was before it changed parents
		global_position = previous_pos
		if targetHost.is_in_group("hands"):
#			_tween_interpolate_visibility(1,0.3)
			# We need to adjust the start position based on the global position
			# coordinates as they would be inside the hand control node
			# So we transform global coordinates to hand rect coordinates.
			previous_pos = targetHost.to_local(global_pos)
			# The end position is always the final position the card would be
			# inside the hand
			_set_target_position(recalculate_position())
			card_rotation = 0
			_set_target_rotation(_recalculate_rotation())
			set_state(CardState.MOVING_TO_CONTAINER)
			scripting_bus.emit_signal("card_moved_to_hand",
					self,
					 {
						"destination": targetHost.name,
						"source": parentHost.name,
						"tags": tags
					}
			)
			# We reorganize the left over cards in hand.
			for c in targetHost.get_all_cards():
				if c != self:
					c.interruptTweening()
					c.reorganize_self()
			if set_is_faceup(true) == CFConst.ReturnCode.FAILED:
				printerr("ERROR: Something went unexpectedly in set_is_faceup")
		elif targetHost.is_in_group("piles"):
			# The below checks if the pile we're moving is in a popup
			# If the card is also in a popup of the same pile
			# we assume we're moving back
			# to the same container, so we do nothing
			# The finite state machine  will reset the card to its position
			if "CardPopUpSlot" in parentHost.name \
					and parentHost.get_parent().get_parent().get_parent() == targetHost:
				if targetHost.get_node("ViewPopup").visible == true:
					pass
			else:
				# Added because sometimes it ended up stuck and a card remained
				# visible on top of deck
				$Tween.remove_all()
				# We need to adjust the end position based on the local rect inside
				# the container control node
				# So we transform global coordinates to container rect coordinates.
				previous_pos = targetHost.to_local(global_pos)
				# The target position is always the local coordinates
				# of the stack position the card would have
				# (this means how far up in the pile the card would appear)
				_set_target_position(targetHost.get_stack_position(self))
				_set_target_rotation(0.0)
				set_state(CardState.MOVING_TO_CONTAINER)
				scripting_bus.emit_signal("card_moved_to_pile",
						self,
						{
							"destination": targetHost.name,
							"source": parentHost.name,
							"tags": tags
						}
				)
				# We start the flipping animation here, even though it also
				# set in the card state, because we want to see it while the
				# card is moving to the CardContainer
				if set_is_faceup(targetHost.faceup_cards) == CFConst.ReturnCode.FAILED:
					printerr("ERROR: Something went unexpectedly in set_is_faceup")
				# If we have fancy movement, we need to wait for 2 tweens to finish
				# before we reorganize the stack.
				# One for the fancy move, and then the move to the final position.
				# If we don't then the card will appear to teleport
				# to the pile before starting animation
#				yield($Tween, "tween_all_completed")
#				if cfc.game_settings.fancy_movement:
#					yield($Tween, "tween_all_completed")
				targetHost.reorganize_stack()
		else:
			interruptTweening()
			_set_target_rotation( _recalculate_rotation())
			if potential_host:
				# The _potential_cards are always organized so that the card higher
				# in index that we were hovering over, is the last in the array.
					attach_to_host(potential_host)
			else:
				# The developer is allowed to pass a position override to the
				# card placement which also bypasses manual drop placement
				# restrictions
				if typeof(board_position) == TYPE_VECTOR2:
					_set_target_position(board_position)
				elif board_position as BoardPlacementSlot:
					_set_target_position(board_position.rect_global_position)
					board_position.set_occupying_card(self)
				elif board_position and board_position as String:
					var grid = cfc.NMAP.board.get_grid(board_position)
					var slot = grid.find_available_slot()
					# We need a small delay, to allow a potential new slot to instance
					#TODO this might cause issues with the stack
					#yield(get_tree().create_timer(0.05), "timeout")
					_set_target_position(slot.rect_global_position)
					slot.set_occupying_card(self)				
				else:
					_determine_target_position_from_mouse()
				raise()
			set_state(CardState.DROPPING_TO_BOARD)
			#force set is faceup to true when moving to board
			if "facedown" in tags:
				set_is_faceup(false)
			else:
				set_is_faceup(true)
			scripting_bus.emit_signal("card_moved_to_board",
					self,
					 {
						"destination": targetHost.name,
						"source": parentHost.name,
						"tags": tags
					}
			)
		if is_instance_valid(parentHost) and parentHost.is_in_group("hands"):
			# We also want to rearrange the hand when we take cards out of it
			for c in parentHost.get_all_cards():
				# But this time we don't want to rearrange ourselves, as we're
				# in a different container by now
				if c != self and c.state != CardState.DRAGGED:
					c.interruptTweening()
					c.reorganize_self()
		elif parentHost and parentHost == cfc.NMAP.board:
			# If the card was or had attachments and it is removed from the table,
			# all attachments status is cleared
			_clear_attachment_status()
			# If the card has tokens, and tokens_only_on_board is true
			# we remove all tokens
			# (The cfc._ut_tokens_only_on_board is there for unit testing)
			if CFConst.TOKENS_ONLY_ON_BOARD and cfc._ut_tokens_only_on_board:
				for token in tokens.get_all_tokens().values():
					print_debug(cfc._ut_tokens_only_on_board)
					token.queue_free()
			# If the card was hosted in a board placement grid
			# we clean the references.
			if _placement_slot:
					_placement_slot.remove_occupying_card(self)
	else:
		# Here we check what to do if the player just moved the card back
		# to the same container
		if parentHost and parentHost.is_in_group("hands"):
			set_state(CardState.IN_HAND)
			reorganize_self()
		elif parentHost == cfc.NMAP.board:
			# Checking if this is an attachment and we're looking for a new host
			if potential_host:
				attach_to_host(potential_host)
			# If we are an attachment and were moved elsewhere
			# We reset the position.
				set_state(CardState.ON_PLAY_BOARD)
			elif current_host_card:
				var attach_index = current_host_card.attachments.find(self)
				_set_target_position((current_host_card.global_position
						+ Vector2(
						(attach_index + 1) * card_size.x
						* CFConst.ATTACHMENT_OFFSET[attachment_offset].x,
						(attach_index + 1)* card_size.y
						* CFConst.ATTACHMENT_OFFSET[attachment_offset].y)))
				set_state(CardState.ON_PLAY_BOARD)
			else:
				# When we drop from board to board
				# We need to ensure the card respects its
				# board_placement variable. So we need to check
				# where the player is trying to drop the card
				# and revert the placement if it's invalid
				if board_position is BoardPlacementSlot:
					# This will trigger is the card can only be placed
					# in specific grids, and the player tried to drag it
					# Manually to a different grid
					if _placement_slot != board_position:
						if _placement_slot!= null:
							_placement_slot.remove_occupying_card(self)
						_set_target_position(board_position.rect_global_position)
						board_position.set_occupying_card(self)
						set_state(CardState.DROPPING_TO_BOARD)
					else:
						_set_target_position(board_position.rect_global_position)
						set_state(CardState.DROPPING_TO_BOARD)
				else:
					if typeof(board_position) == TYPE_VECTOR2:
						_set_target_position(board_position)
					else:
						_determine_target_position_from_mouse()
					set_state(CardState.ON_PLAY_BOARD)
					if _placement_slot:
							_placement_slot.remove_occupying_card(self)
				raise()
		elif parentHost == targetHost and index != get_my_card_index():
			parentHost.move_child(self,
					parentHost.translate_card_index_to_node_index(index))
		elif "CardPopUpSlot" in parentHost.name:
			set_state(CardState.IN_POPUP)
	common_post_move_scripts(targetHost.name, parentHost.name, tags)
	cfc.remove_ongoing_process(self)

func set_scale(value):		
	scale = value

#Return interrupt string to hijack manual run
#TODO right now this returns the first one, need to be more specific
func find_interrupt_script() -> String:
	var my_scripts = retrieve_all_scripts()	
	for _k in my_scripts.keys():
		var k:String = _k 
		if (k == "interrupt"):
			return k
	return ""
	

func retrieve_filtered_scripts(trigger_card,trigger, trigger_details):
	var card_scripts = retrieve_scripts(trigger)
	# I use this spot to add a breakpoint when testing script behaviour
	# especially on filters
	if _debugger_hook:
		pass

	# We check the trigger against the filter defined
	# If it does not match, then we don't pass any scripts for this trigger.
	if not SP.filter_trigger(
			card_scripts,
			trigger_card,
			self,
			trigger_details):
		card_scripts.clear()
	
	return card_scripts

func get_state_scripts(card_scripts, trigger_card, trigger_details):
	var state_scripts_dict = get_state_scripts_dict(card_scripts, trigger_card, trigger_details)
	return state_scripts_dict["state_scripts"]

func get_state_scripts_dict(card_scripts, trigger_card, trigger_details):
	var state_scripts = []
	var action_name = ""
	# We select which scripts to run from the card, based on it state
	var state_exec := get_state_exec()
	var any_state_scripts = card_scripts.get('all', [])
	state_scripts = card_scripts.get(state_exec, any_state_scripts)

	var rules = {}
	#If it's a multiple choice, filter down only to only the ones we can afford to pay
	if typeof(state_scripts) == TYPE_DICTIONARY:
		#special case if only one entry in a dictionary, this is a choice by the script writer,
		# we let it through and remove the
		#dictionary wrapper
		if state_scripts.has("_rules"):
			rules = state_scripts.get("_rules")
			state_scripts.erase("_rules")
			
		if state_scripts.size() == 1:
			var first_key = state_scripts.keys()[0]
			state_scripts = state_scripts[first_key]
			action_name = first_key
		else:	
			for entry_name in state_scripts.keys():
				if entry_name == "_rules":
					continue
				var state_script = state_scripts[entry_name]
				var sceng = cfc.scripting_engine.new(
					state_script,
					self,
					trigger_card,
					trigger_details)
				common_pre_run(sceng)	
				var func_return = sceng.execute(CFInt.RunType.BACKGROUND_COST_CHECK)
				while func_return is GDScriptFunctionState && func_return.is_valid():
					func_return = func_return.resume()
				if !sceng.can_all_costs_be_paid:
					state_scripts.erase(entry_name)
			#notably we keep the dictionary here even if there's only one entry remaining in manual mode,
			#so the user doesn't auto activate the only option by mistake
			if CFConst.AUTO_EXECUTE_ONE_ENTRY_MENU and state_scripts.size() == 1:
				if (CFConst.AUTO_EXECUTE_ONE_ENTRY_MENU == CFConst.AUTO_EXECUTE_MENU.MANUAL_INCLUDED) or trigger_details.get("trigger_type","") != "manual":
					var first_key = state_scripts.keys()[0]
					state_scripts = state_scripts[first_key]
					action_name = first_key
			if !state_scripts:
				state_scripts = []
				

	
	return { "action_name" : action_name, "state_scripts" : state_scripts, "rules": rules}

func is_dry_run(run_type):
	return ((run_type == CFInt.RunType.COST_CHECK) or
		 (run_type == CFInt.RunType.BACKGROUND_COST_CHECK))

func _set_target_position(new_target_position):
	_target_position = new_target_position

func _set_target_rotation(new_target_rotation):
	if self.canonical_name == "Charge":
			var _tmp =1
	_target_rotation = new_target_rotation

# Executes the tasks defined in the card's scripts in order.
#
# Returns a [ScriptingEngine] object but that it not statically typed
# As it causes the parser think there's a cyclic dependency.
func execute_scripts(
		trigger_card: Card = self,
		trigger: String = "manual",
		trigger_details: Dictionary = {},
		only_cost_check := false):
	if cfc.game_paused:
		return
	# Just in case the card is displayed outside the main game
	# and somehow its script is triggered.
	if not cfc.NMAP.has('board'):
		return
	common_pre_execution_scripts(trigger_card, trigger, trigger_details)
	var card_scripts = retrieve_scripts(trigger)
	# I use this spot to add a breakpoint when testing script behaviour
	# especially on filters
	if _debugger_hook:
		pass
	# We check the trigger against the filter defined
	# If it does not match, then we don't pass any scripts for this trigger.
	if not SP.filter_trigger(
			card_scripts,
			trigger_card,
			self,
			trigger_details):
		card_scripts.clear()
	var state_scripts = []
	# We select which scripts to run from the card, based on it state
	var state_exec := get_state_exec()
	var any_state_scripts = card_scripts.get('all', [])
	state_scripts = card_scripts.get(state_exec, any_state_scripts)
	# Here we check for confirmation of optional trigger effects
	# There should be an SP.KEY_IS_OPTIONAL definition per state
	# E.g. if board scripts are optional, but hand scripts are not
	# Then you'd include an "is_optional_board" key at the same level as "board"
	var confirm_return = cfc.ov_utils.confirm(
		card_scripts,
		canonical_name,
		trigger,
		state_exec)
	if confirm_return is GDScriptFunctionState: # Still working.
		confirm_return = yield(confirm_return, "completed")
		# If the player chooses not to play an optional cost
		# We consider the whole cost dry run unsuccesful
		if not confirm_return:
			state_scripts = []
	# If the state_scripts return a dictionary entry
	# it means it's a multiple choice between two scripts
	if typeof(state_scripts) == TYPE_DICTIONARY:
		var choices_menu = _CARD_CHOICES_SCENE.instance()
		choices_menu.prep(canonical_name,state_scripts)
		# We have to wait until the player has finished selecting an option
		yield(choices_menu,"id_pressed")
		# If the player just closed the pop-up without choosing
		# an option, we don't execute anything
		if choices_menu.id_selected:
			state_scripts = state_scripts[choices_menu.selected_key]
		else: state_scripts = []
		# Garbage cleanup
		choices_menu.queue_free()
	# To avoid unnecessary operations
	# we evoke the ScriptingEngine only if we have something to execute
	# We do not statically type it as this causes a circular reference
	var sceng = null
	if len(state_scripts):
		is_executing_scripts = true
		# This evocation of the ScriptingEngine, checks the card for
		# cost-defined tasks, and performs a dry-run on them
		# to ascertain whether they can all be paid,
		# before executing the card script.
		sceng = cfc.scripting_engine.new(
				state_scripts,
				self,
				trigger_card,
				trigger_details)
		common_pre_run(sceng)
		# In case the script involves targetting, we need to wait on further
		# execution until targetting has completed
		sceng.execute(CFInt.RunType.COST_CHECK)
		if not sceng.all_tasks_completed:
			yield(sceng,"tasks_completed")
		# If the dry-run of the ScriptingEngine returns that all
		# costs can be paid, then we proceed with the actual run
		if sceng.can_all_costs_be_paid and not only_cost_check:
			#print("DEBUG:" + str(state_scripts))
			# The ScriptingEngine is where we execute the scripts
			# We cannot use its class reference,
			# as it causes a cyclic reference error when parsing
			sceng.execute()
			if not sceng.all_tasks_completed:
				yield(sceng,"tasks_completed")
			# warning-ignore:void_assignment
			var func_return = common_post_execution_scripts(trigger)
			# We make sure this function does to return until all
			# custom post execution scripts have also finished
			if func_return is GDScriptFunctionState: # Still working.
				func_return = yield(func_return, "completed")
		# This will only trigger when costs could not be paid, and will
		# execute the "is_else" tasks
		elif not sceng.can_all_costs_be_paid and not only_cost_check:
			#print("DEBUG:" + str(state_scripts))
			sceng.execute(CFInt.RunType.ELSE)
			if not sceng.all_tasks_completed:
				yield(sceng,"tasks_completed")
		is_executing_scripts = false
		emit_signal("scripts_executed", self, sceng, trigger)
	return(sceng)

func get_instance_runtime_scripts(trigger:String = "", filters:={}) -> Dictionary:
	if scripts.empty():
		return {}
	match trigger:
		"":
			return scripts.duplicate(true)
		_:
			if not scripts.get(trigger,{}).empty():
				return scripts.get(trigger,{}).duplicate(true)
	#since scripts exist (but not for our trigger)
	#we return a dummy dictionary to override results
	return {
		"scripts_exist_but_not_for_your_use_case" : true
	}
	
# Retrieves the card scripts either from those defined on the card
# itself, or from those defined in the script definition files
#
# Returns a dictionary of card scripts for this specific card
# based on the current trigger.
func retrieve_scripts(trigger: String, filters := {}) -> Dictionary:
	var found_scripts: Dictionary
	# If scripts have been defined directly in this Card object
	# They take precedence over CardScriptDefinitions.gd
	#
	# This allows us to modify a card's scripts during runtime
	# in isolation from other cards of the same name
	found_scripts = get_instance_runtime_scripts(trigger, filters)
	if !found_scripts:
		# This retrieves all the script from the card, stored in cfc
		# The seeks in them the specific trigger we're using in this
		# execution
		found_scripts = cfc.set_scripts.get(canonical_id,{}).get(trigger,{}).duplicate(true)
	if (canonical_name == "Wakanda Forever!" and trigger == "manual"):
		var _tmp = 1
	return(found_scripts)

# Retrieves the card scripts either from those defined on the card
# itself, or from those defined in the script definition files
#
# Returns a dictionary of card scripts for this specific card
# (based on the current trigger.all triggers)
func retrieve_all_scripts() -> Dictionary:
	var found_scripts: Dictionary
	# If scripts have been defined directly in this Card object
	# They take precedence over CardScriptDefinitions.gd
	#
	# This allows us to modify a card's scripts during runtime
	# in isolation from other cards of the same name
	found_scripts = get_instance_runtime_scripts()
	if !found_scripts:
		# This retrieves all the script from the card, stored in cfc
		# The seeks in them the specific trigger we're using in this
		# execution
		found_scripts = cfc.set_scripts.get(canonical_id,{}).duplicate(true)
	return(found_scripts)


# Determines which play position (board, pile or hand)
# a script should look for to find card scripts
# based on the card's state.
#
# Returns either "board", "hand", "pile" or "NONE".
func get_state_exec() -> String:
	var state_exec := "NONE"
	# We don't check according to the parent name
	# as that can change.
	# Might consier checking on the parent class if this gets too complicated.
	match state:
		CardState.ON_PLAY_BOARD,\
				CardState.FOCUSED_ON_BOARD,\
				CardState.DROPPING_TO_BOARD:
			# We assume only faceup cards can execute scripts on the board
			if is_faceup:
				state_exec = "board"
		CardState.IN_HAND,\
				CardState.FOCUSED_IN_HAND,\
				CardState.REORGANIZING,\
				CardState.PUSHED_ASIDE:
			state_exec = "hand"
		CardState.IN_POPUP,\
				CardState.FOCUSED_IN_POPUP,\
				CardState.IN_PILE,\
				CardState.VIEWED_IN_PILE:
			state_exec = "pile"
		CardState.MOVING_TO_CONTAINER:
			if get_parent() and get_parent().is_in_group("hands"):
				state_exec = "hand"
			else:
				state_exec = "pile"
	return(state_exec)


# Handles the card becoming an attachment for a specified host Card object
func attach_to_host(
			host: Card,
			is_following_previous_host = false,
			tags := ["Manual"]) -> void:
	# First we check if the selected host is not the current host anyway.
	# If it is, we do nothing else
	if host != current_host_card:
		# If the card is not yet on the board, we move it there
		if get_parent() != cfc.NMAP.board:
			move_to(cfc.NMAP.board, -1, host.position, tags)
		# If we already had a host, we clear our state with it
		# I don't know why, but logic breaks if I don't use the is_following_previous_host flag
		# It should work without it, but it doesn't
		# The is_following_previous_host var signifies that this card
		# is being attached to this host, because its previous host
		# also became an attachment here.
		if current_host_card and not is_following_previous_host:
			current_host_card.remove_attachment(self)
			scripting_bus.emit_signal("card_unattached",
					self,
					{"host": current_host_card, "tags": tags})
		# If card was on a grid slot, we clear that occupation
		if _placement_slot:
			_placement_slot.remove_occupying_card(self)
		current_host_card = host
		# Once we selected the host, we don't need anything in the array anymore
		potential_host = null
		# We also clear the highlights on our new host
		current_host_card.highlight.set_highlight(false)
		# We set outselves as an attachment on the target host for easy iteration
		current_host_card.attachments.append(self)
		#print(current_host_card.attachments)
		# We make existing attachments reattach to the new host directly
		# Otherwise it becomes too complex to handle attachment indexes
		for card in attachments:
			card.attach_to_host(host,true)
		attachments.clear()
		# The position below the host is based on how many other attachments it has
		# We offset our position below the host based on a percentage of
		# the card size, times the index among other attachments
		var attach_index = current_host_card.attachments.find(self)
		_set_target_position((current_host_card.global_position
				+ Vector2(
				(attach_index + 1) * card_size.x
				* CFConst.ATTACHMENT_OFFSET[current_host_card.attachment_offset].x,
				(attach_index + 1)* card_size.y
				* CFConst.ATTACHMENT_OFFSET[current_host_card.attachment_offset].y)))
		var target_rotation = 0
		if CFConst.OPTIONS.get("enable_fuzzy_rotations", false):
			target_rotation = randi() % 13
		set_card_rotation(target_rotation, false, true, false, ["force"])
		_set_target_rotation(target_rotation)		
		scripting_bus.emit_signal("card_attached",
				self,
				{"host": host, "tags": tags})


# Overrides the built-in get_class to
# Returns "Card" instead of "Area2D"
func get_class(): return "Card"


# Ensures the card is placed in the right position in the hand
# In relation to the other cards in the hand
#
# It will also adjust the separation between cards depending on the amount
# of cards in-hand
func reorganize_self() ->void:
	# We clear the card as being in-focus if we're asking it to be reorganized
	_focus_completed = false
	match state:
		CardState.IN_HAND, CardState.FOCUSED_IN_HAND, CardState.PUSHED_ASIDE:
			_set_target_position(recalculate_position())
			_set_target_rotation( _recalculate_rotation())
			set_state(CardState.REORGANIZING)
	# This second match is  to prevent from changing the state
	# when we're doing fancy movement
	# and we're still in the first part (which is waiting on an animation yield).
	# Instead, we just change the target position transparently,
	# and when the second part of the animation begins
	# it will automatically pick up the right location.
	match state:
		CardState.MOVING_TO_CONTAINER:
			_set_target_position(recalculate_position())
			_set_target_rotation(_recalculate_rotation())


# Stops existing card animations then makes sure they're
# properly cleaned-up to allow future animations to play.
func interruptTweening() ->void:
	# This if-logic is there to avoid interrupting animations during fancy_movement,
	# as we want the first part to play always
	# Effectively we're saying if fancy movement is turned on, and you're
	# still doing the first part, don't interrupt
	# If you've finished the first part and are not still in the
	# move to another container movement, then you can interrupt.
	if not cfc.game_settings.fancy_movement or (cfc.game_settings.fancy_movement
			and (_fancy_move_second_part
			or state != CardState.MOVING_TO_CONTAINER)):
		$Tween.remove_all()
		set_state(CardState.IN_HAND)


func clear_highlight():
	if !highlight:
		return
	highlight.set_highlight(false)

# Changes card focus (highlighted and put on the focus viewport)
func set_focus(requestedFocus: bool, colour := CFConst.FOCUS_HOVER_COLOUR) -> void:
	# We use an if to avoid performing constant operations in _process
	# We only modify the highlight though, if the card is not being
	# highlighted by another effect (such as a targetting arrow etc)
	if highlight.visible != requestedFocus and \
			highlight.modulate in CFConst.CostsState.values():
		#highlight.set_highlight(requestedFocus,colour)
		var _tmp = 1
	# focus_style value 0 means only scaling focus
	# We also recheck that main exists, as sometimes GUT messes it up
	if not state in [CardState.PREVIEW, CardState.DECKBUILDER_GRID]\
			and cfc.game_settings.focus_style\
			and cfc.NMAP.has("main"):
		if requestedFocus:
			var show_preview := true
			if cfc.curr_scale < 0.8\
					or cfc.game_settings.focus_style == CFInt.FocusStyle.BOTH_INFO_PANELS_ONLY:
				show_preview = false
			cfc.NMAP.main.focus_card(self, show_preview)
		else:
			cfc.NMAP.main.unfocus(self)
	# Tokens drawer is an optional node, so we check if it exists
	# We also generally only have tokens on the table
	if state in [CardState.ON_PLAY_BOARD, CardState.FOCUSED_ON_BOARD]:
		if $Control.has_node("Tokens"):
			tokens.set_is_drawer_open(requestedFocus)
#		if name == "Card" and get_parent() == cfc.NMAP.board:
#			print(requestedFocus)


# Ensures the card's state is in idle mode.
#
# This is useful when the game is paused, but we don't want
# cards to stay focused
func set_to_idle() -> void:
	if not state in [
		CardState.VIEWPORT_FOCUS,
		CardState.PREVIEW,
		CardState.DECKBUILDER_GRID
	]:
		if state in [CardState.FOCUSED_IN_HAND, CardState.PUSHED_ASIDE]:
			reorganize_self()
		elif not state == CardState.REORGANIZING:
			_determine_idle_state()


# Tells us the focus-state of a card
#
# Returns true if card is currently in focus, else false
func get_focus() -> bool:
	var focusState = false
	match state:
		CardState.FOCUSED_IN_HAND, CardState.FOCUSED_ON_BOARD:
			focusState = true
	return(focusState)


# Returns the Card's index position among other card objects
func get_my_card_index() -> int:
	if get_parent().has_method('get_card_index'):
		return(get_parent().get_card_index(self))
	else:
		return(0)


# Changes the hosted Control nodes filters
#
# * When set to false, card cannot receive inputs anymore
#    (this is useful when card is in motion or in a pile)
# * When set to true, card can receive inputs again
func set_control_mouse_filters(value = true) -> void:
	var control_filter := 0
	if not value:
		control_filter = 2
	# We do a comparison first, to make sure we avoid unnecessary operations
	if $Control.mouse_filter != control_filter:
		$Control.mouse_filter = control_filter
	if monitorable != bool(value):
#		print_debug('monitorable')
		monitorable = value


# Get card position in hand by index
# if use oval shape, the card has a certain offset according to the angle
func recalculate_position(index_diff = null) -> Vector2:
	if cfc.game_settings.hand_use_oval_shape:
		return _recalculate_position_use_oval(index_diff)
	return _recalculate_position_use_rectangle(index_diff)


# Animates a card semi-randomly to make it looks like it's being shuffled
# Then it returns it to its original location
func animate_shuffle(anim_speed : float, style : int) -> void:
	var starting_card_position = position
	var csize : Vector2
	var random_x : float
	var random_y : float
	var random_rot : float
	var center_card_pop_position = starting_card_position+Vector2(random_x,random_y)
	var start_pos_anim
	var end_pos_anim
	var rot_anim
	var pos_speed := anim_speed
	var rot_speed := anim_speed
	# We create a mini-random generator so that we have a
	# randf_range function
	# We don't want to use the cfc rng, because that is only to preserve
	# the game state, and the below randomness is irrelevant
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	if style == CFConst.ShuffleStyle.CORGI:
		csize = card_size * 0.65
		random_x = rng.randf_range(- csize.x, csize.x)
		random_y = rng.randf_range(- csize.y, csize.y)
		random_rot = rng.randf_range(-20, 20)
		center_card_pop_position = starting_card_position \
				+ Vector2(random_x, random_y)
		start_pos_anim = Tween.TRANS_CIRC
		end_pos_anim = Tween.TRANS_CIRC
		rot_anim = Tween.TRANS_CIRC
	# 2 is splash
	elif style == CFConst.ShuffleStyle.SPLASH:
		csize = card_size * 0.85
		random_x = rng.randf_range(- csize.x, csize.x)
		random_y = rng.randf_range(- csize.y, csize.y)
		random_rot = rng.randf_range(-180, 180)
		center_card_pop_position = starting_card_position \
				+ Vector2(random_x, random_y)
		start_pos_anim = Tween.TRANS_ELASTIC
		end_pos_anim = Tween.TRANS_QUAD
		rot_anim = Tween.TRANS_CIRC
		pos_speed = pos_speed
	elif style == CFConst.ShuffleStyle.SNAP:
		csize = card_size
		center_card_pop_position.y = starting_card_position.y \
				+ card_size.y
		start_pos_anim = Tween.TRANS_ELASTIC
		end_pos_anim = Tween.TRANS_ELASTIC
		rot_anim = null
		pos_speed = pos_speed
	elif style == CFConst.ShuffleStyle.OVERHAND:
		csize = card_size * 1.1
		random_x = rng.randf_range(- csize.x/10, csize.x/10)
		random_y = rng.randf_range(- csize.y, - csize.y/2)
		random_rot = rng.randf_range(-10, 10)
		center_card_pop_position = starting_card_position \
				+ Vector2(random_x,random_y)
		start_pos_anim = Tween.TRANS_CIRC
		end_pos_anim = Tween.TRANS_SINE
		rot_anim = Tween.TRANS_ELASTIC
	_add_tween_position(starting_card_position,center_card_pop_position,
			pos_speed,start_pos_anim,Tween.EASE_OUT)
	if rot_anim:
		_add_tween_rotation(0,random_rot,rot_speed,rot_anim,Tween.EASE_OUT)
	_tween.start()
	yield(_tween, "tween_all_completed")
	_add_tween_position(center_card_pop_position,starting_card_position,
			pos_speed,end_pos_anim,Tween.EASE_IN)
	if rot_anim:
		_add_tween_rotation(random_rot,0,rot_speed,rot_anim,Tween.EASE_IN)
	_tween.start()


# This function can be overriden by any class extending Card, in order to provide
# a way of checking if a card can be played before dragging it out of the hand.
#
# This method will be called while the card is being focused by the player
# If it returns true, the card will be highlighted as normal and the player
# will be able to drag it out of the hand
#
# If it returns false, the card will be highlighted with a red tint, and the
# player will not be able to drag it out of the hand.
func check_play_costs(params:Dictionary = {}) -> Color:
	return(CFConst.CostsState.OK)


# This function can be overriden by any class extending Card, in order to provide
# a way of running scripts which might change where a card moves
#
# This method will be called before the card moves anywhere,
# but before board_placement is evaluted. This allows a card which has been
# setup to not allow moves to the board,
# (which would normally send it back to its origin container)
# to instead be redirected to a pile.
# warning-ignore:unused_argument
# warning-ignore:unused_argument
func common_pre_move_scripts(new_host: Node, old_host: Node, move_tags: Array) -> Node:
	return(new_host)

# This function can be overriden by any class extending Card, in order to provide
# a way of running scripts for a whole class of cards, based on where the card moves.
#
# This method will be called after the card moves anywhere, to a different
# container, or the same. new_host is where it moved to, and old_host
# is where it moved from. They can be the same, such as when a card changes
# places on the table.
# warning-ignore:unused_argument
# warning-ignore:unused_argument
# warning-ignore:unused_argument
func common_post_move_scripts(new_host: String, old_host: String, move_tags: Array) -> void:
	pass


# This function can be overriden by any class extending Card, in order to provide
# a way of running scripts for a whole class of cards, based on what the trigger was
# before all normal scripts have been executed
#
# This is useful for example, for paying the costs of one-use cards before executing them
func common_pre_execution_scripts(_trigger_card, _trigger: String, _trigger_details: Dictionary) -> void:
	pass


# This function can be overriden by any class extending Card, in order to provide
# a way of running special functions on an extended scripting engine.
#
# It is called after the scripting engine is initiated, but before it's run
# the first time
#
func common_pre_run(_sceng) -> void:
	pass


# This function can be overriden by any class extending Card, in order to provide
# a way of running scripts for a whole class of cards, based on what the trigger was
# after all normal scripts have been executed
#
# This is useful for example, for discarding one-use cards after playing them
func common_post_execution_scripts(_trigger: String) -> void:
	pass


# This function when we think the card is turned the right way, to ensure it's not stuck
# in a weird position
func ensure_proper() -> void:
	var to_visible = _card_front_container
	var to_invisible = _card_back_container
	if not is_faceup:
		to_visible = _card_back_container
		to_invisible = _card_front_container
	_flip_card(to_invisible, to_visible, true)

# Returns true is the card has hand_drag_starts_targeting set to true
# is currently in hand, and has a targetting task.
#
# This is used by the _on_Card_gui_input to determine if it should fire
# scripts on the card during an attempt to drag it from hand.
func _has_targeting_cost_hand_script() -> bool:
	var ret := false
	var hand_scripts = retrieve_scripts("manual").get("hand",[])
	# We don't check multiple choice cards
	if hand_drag_starts_targeting and typeof(hand_scripts) == TYPE_ARRAY:
		for task in hand_scripts:
			if task.get(SP.KEY_SUBJECT) == SP.KEY_SUBJECT_V_TARGET:
				ret = true
	return(ret)


# Overridable function for formatting card text
func _get_formatted_text(value) -> String:
	return(str(value))


# Makes attachments always move with their parent around the board
func _organize_attachments() -> void:
	# We only do this if the parent is still on the board
	if get_parent() == cfc.NMAP.board:
		for card in attachments:
			# We use the index of the attachment among other attachments
			# to figure out its index and placement
			var attach_index = attachments.find(card)

			# offset the attachment's position in the boards hierarchy
			# by the attachment offset
			if (card.attachment_mode == AttachmentMode.ATTACH_BEHIND and
				card.get_index() > (self.get_index()-attach_index)):
				get_parent().move_child(card, self.get_index()-attach_index)
			elif(card.attachment_mode == AttachmentMode.ATTACH_IN_FRONT and
				card.get_index() < (self.get_index()+attach_index)):
				get_parent().move_child(card, self.get_index()+attach_index)

			# We don't want to try and move it if it's still tweening.
			# But if it isn't, we make sure it always follows its parent
			if not card.get_node('Tween').is_active() and \
					card.state in \
					[CardState.ON_PLAY_BOARD,CardState.FOCUSED_ON_BOARD]:
				card._set_target_position(global_position + \
						Vector2(
						(attach_index + 1) * card_size.x
						* CFConst.ATTACHMENT_OFFSET[attachment_offset].x * cfc.screen_scale.x,
						(attach_index + 1) * card_size.y \
						* CFConst.ATTACHMENT_OFFSET[attachment_offset].y * cfc.screen_scale.y))

# Returns the global mouse position but ensures it does not exit the
# viewport limits when including the card rect
#
# Returns the adjusted global_mouse_position
func _determine_board_position_from_mouse() -> Vector2:
	var targetpos: Vector2 = cfc.NMAP.board.mouse_pointer.determine_global_mouse_pos() - (_drag_offset * scale)
	if targetpos.x + card_size.x * scale.x >= get_viewport().size.x:
		targetpos.x = get_viewport().size.x - card_size.x * scale.x
	if targetpos.x < 0:
		targetpos.x = 0
	if targetpos.y + card_size.y * scale.y >= get_viewport().size.y:
		targetpos.y = get_viewport().size.y - card_size.y * scale.y
	if targetpos.y < 0:
		targetpos.y = 0
	return targetpos


# This function figures out where on the table a card should be placed
# based on the mouse position
# It takes extra care not to drop the card outside viewport margins
func _determine_target_position_from_mouse() -> void:
	_set_target_position(_determine_board_position_from_mouse())

	# The below ensures the card doesn't leave the viewport dimentions
	if _target_position.x + card_size.x * play_area_scale \
			> get_viewport().size.x:
		_target_position.x = get_viewport().size.x \
				- card_size.x \
				* play_area_scale
	if _target_position.y + card_size.y * play_area_scale \
			> get_viewport().size.y:
		_target_position.y = get_viewport().size.y \
				- card_size.y \
				* play_area_scale


# Instructs the card to move aside for another card enterring focus
func _pushAside(targetpos: Vector2, target_rotation: float) -> void:
	interruptTweening()
	_set_target_position(targetpos)
	_set_target_rotation(target_rotation)
	set_state(CardState.PUSHED_ASIDE)


# Pick up a card to drag around with the mouse.
func _start_dragging(drag_offset: Vector2) -> void:
	_drag_offset = drag_offset
	# When dragging we want the dragged card and attachments to always be drawn above all else
	z_index = CFConst.Z_INDEX_HAND_CARDS_NORMAL + 1
	for attachment in self.attachments:
		attachment.z_index = CFConst.Z_INDEX_HAND_CARDS_NORMAL + 1
	# We have use parent viewport to calculate global_position
	# due to godotengine/godot#30215
	# This is caused because we're using a viewport node and scaling the game
	# in full-creen.
	# This is not supported in browsers.
	if not cfc.ut and not OS.has_feature("web"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)
#		if ProjectSettings.get("display/window/stretch/mode") != 'disabled':
#			get_tree().current_scene.get_viewport().warp_mouse(global_position + Vector2(5,5))
		# However the above messes things if we don't have stretch mode,
		# so we ignore it then
#		else:
#			get_viewport().warp_mouse(global_position + _drag_anchor)
	set_state(CardState.DRAGGED)
	# We check if the card was already overlapping with other card
	# before we started dragging. If so, we activate the code
	# which checks for potential hosts, on all these cards to make sure
	# we don't miss any.
#	for obj in get_overlapping_areas():
#		_on_Card_area_entered(obj)
	if get_parent().is_in_group("hands"):
		# While we're dragging the card from hand, we want the other cards
		# to move to their expected position in hand
		for c in get_parent().get_all_cards():
			if c != self:
				c.interruptTweening()
				c.reorganize_self()
	emit_signal("dragging_started", self)


# Determines the state a card should have,
# based on the card's container grouping.
#
# This is needed because some states are generic
# and don't always know the state the card should be afterwards
func _determine_idle_state() -> void:
	if get_parent().is_in_group("hands"):
		set_state(CardState.IN_HAND)
	# The extra if is in case the ViewPopup is currently active when the card
	# is being moved into the container
	elif get_parent().is_in_group("piles"):
		set_state(CardState.IN_PILE)
	elif "CardPopUpSlot" in get_parent().name:
		set_state(CardState.IN_POPUP)
	else:
		set_state(CardState.ON_PLAY_BOARD)


# Makes the card change visibility nicely
func _tween_interpolate_visibility(visibility: float, time: float) -> void:
	# We only want to do something if we're actually doing something
	if modulate[3] != visibility:
		$Tween.interpolate_property(self,'modulate',
				modulate, Color(1, 1, 1, visibility), time,
				Tween.TRANS_QUAD, Tween.EASE_OUT)


#what to do when I'm an attachement and my host is removed from the table
func host_is_gone(former_host):
	# Attachments typically follow their parents to the same container
	move_to(get_parent())

func remove_attachment(card):
	attachments.erase(card)

# Clears all attachment/hosting status.
# It is typically called when a card is removed from the table
func _clear_attachment_status(tags := ["Manual"]) -> void:
	cfc.add_ongoing_process(self)
	if current_host_card:
		scripting_bus.emit_signal("card_unattached",
				self,
				{"host": current_host_card, "tags": tags})
		current_host_card.remove_attachment(self)
		current_host_card = null
	for card in attachments:
		card.current_host_card = null
		card.host_is_gone(self)
		# We do a small wait to make the attachment drag look nicer
		yield(get_tree().create_timer(0.1), "timeout")
	attachments.clear()
	cfc.remove_ongoing_process(self)


# Detects when the mouse is still hovering over the card
#
# We need to detect this extra, for the same reasons as the targetting buttons
# In case the mouse was hovering over the tokens area and just exited
#
# Returns true if the mouse is hovering over the card, else false
func _is_card_hovered() -> bool:
	var ret = false
	if cfc.NMAP.board.mouse_pointer in get_overlapping_areas():
		ret = true
	#print(ret)
	return(ret)


# Flips the visible parts of the card control nodes
# so that the correct Panel (Card Back or Card Front) and children is visible
#
# It also pretends to flip the highlight, otherwise it looks fake.
func _flip_card(to_invisible: Control, to_visible: Control, instant := false) -> void:
	if instant:
		to_visible.visible = true
		to_visible.rect_scale.x = 1
		to_visible.rect_position.x = 0
		to_invisible.visible = false
		to_invisible.rect_scale.x = 0
		to_invisible.rect_position.x = to_visible.rect_size.x/2
		highlight.rect_scale = Vector2(1,1)
	# When dupe cards in focus viewport are created, they have parent == null
	# This causes them to raise an error trying to create a tween
	# So we skip that.
	elif get_parent() == null:
		pass
	else:
		# We clear existing tweens to avoid a deadlocks
		for n in [_card_front_container, _card_back_container, highlight]:
			_flip_tween.remove(n,'rect_scale')
			_flip_tween.remove(n,'rect_position')
		_flip_tween.interpolate_property(to_invisible,'rect_scale',
				to_invisible.rect_scale, Vector2(0,1), 0.4,
				Tween.TRANS_QUAD, Tween.EASE_IN)
		_flip_tween.interpolate_property(to_invisible,'rect_position',
				to_invisible.rect_position, Vector2(
				to_invisible.rect_size.x/2,0), 0.4,
				Tween.TRANS_QUAD, Tween.EASE_IN)
		_flip_tween.interpolate_property(highlight,'rect_scale',
				highlight.rect_scale, Vector2(0,1), 0.4,
				Tween.TRANS_QUAD, Tween.EASE_IN)
		# The highlight is larger than the card size, but also offset a bit
		# so that it's still centered. This way its borders only extend
		# over the card borders. We need to offest to the right location.
		_flip_tween.interpolate_property(highlight,'rect_position',
				highlight.rect_position, Vector2(
				(highlight.rect_size.x-3)/2,0), 0.4,
				Tween.TRANS_QUAD, Tween.EASE_IN)
		_flip_tween.start()
		yield(_flip_tween, "tween_all_completed")
		to_visible.visible = true
		to_invisible.visible = false
		_flip_tween.interpolate_property(to_visible,'rect_scale',
				to_visible.rect_scale, Vector2(1,1), 0.4,
				Tween.TRANS_QUAD, Tween.EASE_OUT)
		_flip_tween.interpolate_property(to_visible,'rect_position',
				to_visible.rect_position, Vector2(0,0), 0.4,
				Tween.TRANS_QUAD, Tween.EASE_OUT)
		_flip_tween.interpolate_property(highlight,'rect_scale',
				highlight.rect_scale, Vector2(1,1), 0.4,
				Tween.TRANS_QUAD, Tween.EASE_OUT)
		_flip_tween.interpolate_property(highlight,'rect_position',
				highlight.rect_position, Vector2(-3,-3), 0.4,
				Tween.TRANS_QUAD, Tween.EASE_OUT)
		_flip_tween.start()


# Card rotation animation
func _add_tween_rotation(
		expected_rotation: float,
		target_rotation: float,
		runtime := 0.3,
		trans_type = Tween.TRANS_BACK,
		ease_type = Tween.EASE_IN_OUT):
	$Tween.remove($Control,'rect_rotation')
	$Tween.interpolate_property($Control,'rect_rotation',
			expected_rotation, target_rotation, runtime,
			trans_type, ease_type)
	# We ensure the card_rotation value is also kept up to date
	# But onlf it it's one of the expected multiples
	if int(target_rotation) != card_rotation \
			and int(target_rotation) in [0,90,180,270]:
		card_rotation = int(target_rotation)


# Card position animation
func _add_tween_position(
		expected_position: Vector2,
		target_position: Vector2,
		runtime := 0.3,
		trans_type = Tween.TRANS_CUBIC,
		ease_type = Tween.EASE_OUT):
	$Tween.remove(self,'position')
	$Tween.interpolate_property(self,'position',
			expected_position, target_position, runtime,
			trans_type, ease_type)


# Card global position animation
func _add_tween_global_position(
		expected_position: Vector2,
		target_position: Vector2,
		runtime := 0.5,
		trans_type = Tween.TRANS_BACK,
		ease_type = Tween.EASE_IN_OUT):
	$Tween.remove(self,'global_position')
	$Tween.interpolate_property(self,'global_position',
			expected_position, target_position, runtime,
			trans_type, ease_type)


# Card scale animation
func _add_tween_scale(
		expected_scale: Vector2,
		target_scale: Vector2,
		runtime := 0.3,
		trans_type = Tween.TRANS_CUBIC,
		ease_type = Tween.EASE_OUT):
	$Tween.remove(self,'scale')
	$Tween.interpolate_property(self,'scale',
			expected_scale, target_scale, runtime,
			trans_type, ease_type)


# A rudimentary Finite State Engine for cards.
#
# Makes sure that when a card is in a specific state while
# its position, highlights, scaling and so on, stay as expected

func _process_card_state() -> void:
	match state:
		CardState.IN_HAND:
			z_index = CFConst.Z_INDEX_HAND_CARDS_NORMAL
			set_focus(false)
			set_control_mouse_filters(true)
			set_manipulation_buttons_active(false)
			# warning-ignore:return_value_discarded
			set_card_rotation(0)
			# warning-ignore:return_value_discarded
			# When we have an oval shape, we ensure the cards stay
			# in the rotation expected of their position
			if cfc.game_settings.hand_use_oval_shape:
				_set_target_rotation( _recalculate_rotation())
				if not $Tween.is_active() \
						and not CFUtils.compare_floats($Control.rect_rotation, _target_rotation):
					_add_tween_rotation($Control.rect_rotation,_target_rotation,
						in_hand_tween_duration)
					$Tween.start()
			if not scale.is_equal_approx(cfc.screen_scale):
				set_scale(cfc.screen_scale)

		CardState.FOCUSED_IN_HAND:
			# Used when card is focused on by the mouse hovering over it.
			# We increase the z_index to allow the focused card appear
			# always over its neighbours
			z_index = CFConst.Z_INDEX_HAND_CARDS_NORMAL + 10
#			print(global_position + _control.rect_size)
			set_focus(true,check_play_costs())
			set_control_mouse_filters(true)
			set_manipulation_buttons_active(false)
			# warning-ignore:return_value_discarded
			set_card_rotation(0,false,false)
			if not $Tween.is_active() and \
					not _focus_completed and \
					cfc.game_settings.focus_style != CFInt.FocusStyle.VIEWPORT:
				var expected_position: Vector2 = recalculate_position()
				var expected_rotation: float = _recalculate_rotation()
				# We figure out our neighbours by their index
				var neighbours := []
				for neighbour_index_diff in [-2,-1,1,2]:
					var hand_size: int = get_parent().get_card_count()
					var neighbour_index: int = \
							get_my_card_index() + neighbour_index_diff
					if neighbour_index >= 0 and neighbour_index <= hand_size - 1:
						var neighbour_card: Card = get_parent().get_card(neighbour_index)
						# Neighbouring cards are pushed to the side to allow
						# the focused card to not be overlapped
						# The amount they're pushed is relevant to
						# how close neighbours they are.
						# Closest neighbours (1 card away) are pushed more
						# than further neighbours.
						neighbour_card._pushAside(
								neighbour_card.recalculate_position(
									neighbour_index_diff),
								neighbour_card._recalculate_rotation(
									neighbour_index_diff))
						neighbours.append(neighbour_card)
				for c in get_parent().get_all_cards():
					if not c in neighbours and c != self:
						c.interruptTweening()
						c.reorganize_self()
				_set_target_position(expected_position \
						- Vector2(card_size.x \
						* 0.25,0))
				# Enough with the fancy calculations. I'm just brute-forcing
				# The card to stay at the fully within the viewport.
				if get_parent().placement == get_parent().Anchors.CONTROL:
					while  get_parent().get_parent().rect_global_position.y\
							+ get_parent().bottom_margin \
							+ _target_position.y \
							+ card_size.y * 1.5> get_viewport().size.y:
						_target_position.y -= 1
				else:
					while get_parent().position.y \
						+ get_parent().bottom_margin \
						+ _target_position.y \
						+ card_size.y > get_viewport().size.y:
						_target_position.y -= 1
				# We need to bump up the y postion a bit based on the rotation
				# We subtract 13 if there is no rotation
				_set_target_rotation(expected_rotation)
				# We make sure to remove other tweens of the same type
				# to avoid a deadlock
				_add_tween_position(expected_position, _target_position, focus_tween_duration)
				_add_tween_scale(scale, Vector2(1.5,1.5), focus_tween_duration)

				if cfc.game_settings.hand_use_oval_shape:
					_add_tween_rotation($Control.rect_rotation, 0, focus_tween_duration)
				else:
					# warning-ignore:return_value_discarded
					set_card_rotation(0)
				$Tween.start()
				_focus_completed = true
				# We don't change state yet, only when the focus is removed
				# from this card
#				resize_recursively(highlight, 1.0)


		CardState.MOVING_TO_CONTAINER:
			# Used when moving card between places
			# (i.e. deck to hand, hand to discard etc)
			z_index = CFConst.Z_INDEX_BOARD_CARDS_NORMAL
			set_focus(false)
			clear_highlight()
			set_control_mouse_filters(false)
			set_manipulation_buttons_active(false)
			# warning-ignore:return_value_discarded
			# set_card_rotation(0,false,false)
			if not $Tween.is_active():
				var intermediate_position: Vector2
				if not scale.is_equal_approx(Vector2(1,1)):
					_add_tween_scale(scale, Vector2(1,1),to_container_tween_duration)
				if cfc.game_settings.fancy_movement:
					# The below calculations figure out
					# the intermediate position as a spot,
					# offset towards the viewport center by an amount proportional
					# to distance from the viewport center.
					# (My math is not the best so there's probably a more elegant formula)
					var direction_x: int = -1
					var direction_y: int = -1
					if get_parent() != cfc.NMAP.board:
						# We determine its center position on the viewport
						var controlNode_center_position := \
								Vector2(global_position + card_size/2)
						# We then direct this position towards the viewport center
						# If we are to the left/top of viewport center,
						# we offset towards the right/bottom (+offset)
						# If we are to the right/bottom of viewport center,
						# we offset towards the left/top (-offset)
						if controlNode_center_position.x < get_viewport().size.x/2:
							direction_x = 1
						if controlNode_center_position.y < get_viewport().size.y/2:
							direction_y = 1
						# The offset amount if calculated by creating a multiplier
						# based on the distance of our target container
						# from the viewport center
						# The further away they are, the more the intermediate point
						# moves towards the screen center
						# We always offset by percentages of the card size to
						# be consistent in case the card size changes
						var offset_x = (abs(controlNode_center_position.x
								- get_viewport().size.x/2)) / 250 * card_size.x
						var offset_y = (abs(controlNode_center_position.y
								- get_viewport().size.y/2)) / 250 * card_size.y
						var inter_x = controlNode_center_position.x \
								+ direction_x * offset_x
						var inter_y = controlNode_center_position.y \
								+ direction_y * offset_y
						# We calculate the position we want the card to move
						# on the viewport
						# then we translate that position to the local coordinates
						# within the parent control node
						#intermediate_position = Vector2(inter_x,inter_y)
						intermediate_position = Vector2(inter_x,inter_y)
					# The board doesn't have a node2d host container.
					# Instead we use directly the viewport coords.
					else:
						intermediate_position = get_viewport().size/2
					_add_tween_global_position(global_position, intermediate_position,
						to_container_tween_duration)
					$Tween.start()
					yield($Tween, "tween_all_completed")
					_tween_stuck_time = 0
					_fancy_move_second_part = true
				# We need to check again, just in case it's been reorganized instead.
				if state == CardState.MOVING_TO_CONTAINER:
					_add_tween_position(position, _target_position,
						to_container_tween_duration, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
					_add_tween_rotation($Control.rect_rotation,_target_rotation,
						to_container_tween_duration)
					$Tween.start()
					yield($Tween, "tween_all_completed")
					_determine_idle_state()
				_fancy_move_second_part = false

		CardState.REORGANIZING:
			# Used when reorganizing the cards in the hand
			z_index = CFConst.Z_INDEX_HAND_CARDS_NORMAL
			set_focus(false)
			set_control_mouse_filters(true)
			set_manipulation_buttons_active(false)
			# warning-ignore:return_value_discarded
			set_card_rotation(0,false,false)
			if not $Tween.is_active():
				$Tween.remove(self,'position') #
				_add_tween_position(position, _target_position, reorganization_tween_duration)
				if not scale.is_equal_approx(cfc.screen_scale):
					_add_tween_scale(scale, cfc.screen_scale, reorganization_tween_duration)
				_add_tween_rotation($Control.rect_rotation,_target_rotation,
					reorganization_tween_duration)
				$Tween.start()
				set_state(CardState.IN_HAND)
	

		CardState.PUSHED_ASIDE:
			# Used when card is being pushed aside due to the focusing of a neighbour.
			z_index = CFConst.Z_INDEX_HAND_CARDS_NORMAL
			set_focus(false)
			set_control_mouse_filters(true)
			set_manipulation_buttons_active(false)
			# warning-ignore:return_value_discarded
			if not $Tween.is_active() and \
					not position.is_equal_approx(_target_position):
				_add_tween_position(position, _target_position,
					pushed_aside_tween_duration, Tween.TRANS_QUART, Tween.EASE_IN)
				_add_tween_rotation($Control.rect_rotation, _target_rotation,
					pushed_aside_tween_duration)
				if not scale.is_equal_approx(cfc.screen_scale):
					_add_tween_scale(scale, cfc.screen_scale, pushed_aside_tween_duration,
						Tween.TRANS_QUART, Tween.EASE_IN)
				$Tween.start()
				# We don't change state yet,
				# only when the focus is removed from the neighbour
	

		CardState.DRAGGED:
			# Used when the card is dragged around the game with the mouse
			set_focus(true)
			set_control_mouse_filters(true)
			set_manipulation_buttons_active(false)
			if (not $Tween.is_active() and
				not scale.is_equal_approx(CFConst.CARD_SCALE_WHILE_DRAGGING) and
				get_parent() != cfc.NMAP.board):
				_add_tween_scale(scale, CFConst.CARD_SCALE_WHILE_DRAGGING,
					dragged_tween_duration, Tween.TRANS_SINE, Tween.EASE_IN)
				$Tween.start()
			# We need to capture the mouse cursos in the window while dragging
			# because if the player drags the cursor outside the window and unclicks
			# The control will not receive the mouse input
			# and this will stay dragging forever
			$Control.set_default_cursor_shape(Input.CURSOR_CROSS)
			# We set the card to be centered on the mouse cursor to allow
			# the player to properly understand where it will go once dropped.
			global_position = _determine_board_position_from_mouse() - Vector2(5,5)
			_organize_attachments()
			# We want to keep the token drawer closed during movement
			tokens.set_is_drawer_open(false)

		CardState.ON_PLAY_BOARD:
			# Used when the card is idle on the board
			z_index = CFConst.Z_INDEX_BOARD_CARDS_NORMAL

			# if this card is an attachment and it's host is being dragged
			# then we want this card to be above everything like the host
			if current_host_card and current_host_card.state == CardState.DRAGGED:
				z_index = CFConst.Z_INDEX_HAND_CARDS_NORMAL + 1

			set_focus(false)
			set_control_mouse_filters(true)
			set_manipulation_buttons_active(false)
			#TODO this messes up attached components such as the targeting arrow
			var target_scale = play_area_scale
			if (_placement_slot):
				target_scale = _placement_slot.get_scale_modifier()
			if ( current_host_card and  current_host_card._placement_slot):
				target_scale =  current_host_card._placement_slot.get_scale_modifier()				
			if canonical_name =="The Break-In!":
				var _tmp = 1	
			if not $Tween.is_active():
				var need_tweening = false
				if not scale.is_equal_approx(Vector2(1,1) * target_scale):
					_add_tween_scale(scale, Vector2(1,1) * target_scale,
						on_board_tween_duration, Tween.TRANS_SINE, Tween.EASE_OUT)
					need_tweening = true
				if not position.is_equal_approx(_target_position):	
					_add_tween_position(position, _target_position, to_board_tween_duration)
					need_tweening = true
				if need_tweening:
					$Tween.start()
			_organize_attachments()

		CardState.DROPPING_TO_BOARD:
			z_index = CFConst.Z_INDEX_BOARD_CARDS_NORMAL
			set_control_mouse_filters(true)
			set_manipulation_buttons_active(false)
			# Used when dropping the cards to the table
			# When dragging the card, the card is slightly behind the mouse cursor
			# so we tween it to the right location
			if not $Tween.is_active():
				$Tween.remove(self,'position') # We make sure to remove other tweens of the same type to avoid a deadlock
#				_target_position = _determine_board_position_from_mouse()
#				# The below ensures the card doesn't leave the viewport dimentions
#				if _target_position.x + card_size.x * play_area_scale.x > get_viewport().size.x:
#					_target_position.x = get_viewport().size.x - card_size.x * play_area_scale.x
#				if _target_position.y + card_size.y * play_area_scale.y > get_viewport().size.y:
#					_target_position.y = get_viewport().size.y - card_size.y * play_area_scale.y
				_add_tween_position(position, _target_position, to_board_tween_duration)
				# The below ensures a card dropped from the hand will not
				# retain a slight rotation.
				# We check if the card already has been rotated to a different
				# card_cotation
				if _maintain_rotation_when_moving:
					_maintain_rotation_when_moving = false
				else:
					if not int($Control.rect_rotation) in [0,90,180,270]:
						_add_tween_rotation($Control.rect_rotation, _target_rotation, to_board_tween_duration)
				# We want cards on the board to be slightly smaller than in hand.
				if not scale.is_equal_approx(Vector2(1,1) * play_area_scale):
					_add_tween_scale(scale, Vector2(1,1) * play_area_scale, to_board_tween_duration,
							Tween.TRANS_BOUNCE, Tween.EASE_OUT)
				$Tween.start()
				set_state(CardState.ON_PLAY_BOARD)

		CardState.FOCUSED_ON_BOARD:
			z_index = CFConst.Z_INDEX_BOARD_CARDS_NORMAL
			# Used when card is focused on by the mouse hovering over it while it is on the board.
			set_focus(true)
			set_control_mouse_filters(true)
			set_manipulation_buttons_active(true)
			# We don't change state yet, only when the focus is removed from this card
			_organize_attachments()

		CardState.IN_PILE:
			z_index = CFConst.Z_INDEX_BOARD_CARDS_NORMAL
			set_focus(false)
			clear_highlight()
			set_control_mouse_filters(false)
			set_manipulation_buttons_active(false)
			# warning-ignore:return_value_discarded
			set_card_rotation(0)
			if scale != Vector2(1,1):
				set_scale(Vector2(1,1))
			if get_parent() in get_tree().get_nodes_in_group("piles"):
				if card_front.resizing_labels.size() and not get_parent().faceup_cards:
					return
				set_is_faceup(get_parent().faceup_cards, true)
				ensure_proper()

		CardState.VIEWED_IN_PILE:
			z_index = CFConst.Z_INDEX_BOARD_CARDS_NORMAL
			cfc.NMAP.main.focus_card(self)
			set_control_mouse_filters(false)
			set_manipulation_buttons_active(false)
			# warning-ignore:return_value_discarded
			set_card_rotation(0)
			if scale != Vector2(1,1):
				set_scale(Vector2(1,1))
			if get_parent() in get_tree().get_nodes_in_group("piles"):
				set_is_faceup(get_parent().faceup_cards, true)
				
				#TODO bugfix I've had cards staying in "VIEWED_IN_PILE" limbo...
				if get_parent().get_top_card() != self:
					self.set_state(CardState.IN_PILE)


		CardState.IN_POPUP:
			z_index = CFConst.Z_INDEX_BOARD_CARDS_NORMAL
			# We make sure that a card in a popup stays in its position
			# Unless moved
			set_focus(false)
			clear_highlight()
			set_control_mouse_filters(true)
			set_manipulation_buttons_active(false)
			# warning-ignore:return_value_discarded
			set_card_rotation(0)
			if modulate[3] != 1:
				modulate[3] = 1
			if scale != Vector2(0.75,0.75):
				set_scale(Vector2(0.75,0.75))
			if position != Vector2(0,0):
				position = Vector2(0,0)

		CardState.FOCUSED_IN_POPUP:
			z_index = CFConst.Z_INDEX_BOARD_CARDS_NORMAL
			# Used when the card is displayed in the popup grid container
			set_focus(true)
			# warning-ignore:return_value_discarded
			set_card_rotation(0)

		CardState.VIEWPORT_FOCUS:
			if gameData.is_ongoing_blocking_announce():
				self.modulate.a = 0			
			else:
				self.modulate.a = 1
			z_index = CFConst.Z_INDEX_TOP_MENU + 500	
			$Control.mouse_filter = Control.MOUSE_FILTER_IGNORE
			set_focus(false)
			set_control_mouse_filters(false)
			set_manipulation_buttons_active(false)
			# warning-ignore:return_value_discarded
			set_card_rotation(0)
			$Control.rect_rotation = 0
			targeting_arrow.cancel_targeting()
			$Control/Tokens.visible = true
			# We scale the card dupe to allow the player a better viewing experience
			if CFConst.VIEWPORT_FOCUS_ZOOM_TYPE == "scale":
				set_scale(Vector2(1,1) * focused_scale * cfc.curr_scale)
			else:
				# We need to reset its scale,
				# in case it was already scaled due to being on the table etc.
				set_scale(Vector2(1,1))
				resize_recursively(_control, focused_scale * cfc.curr_scale)
#				set_card_size(CFConst.CARD_SIZE * CFConst.FOCUSED_SCALE, true)
				get_card_front().scale_to(focused_scale * cfc.curr_scale )
				get_card_back().scale_to(focused_scale * cfc.curr_scale)
			# If the card has already been been viewed while down,
			# we allow the player hovering over it to see it
			if not is_faceup:
				if is_viewed:
					_flip_card(_card_back_container,_card_front_container, true)

		CardState.PREVIEW:
			$Control.mouse_filter = Control.MOUSE_FILTER_IGNORE
			set_focus(false)
			set_control_mouse_filters(false)
			set_manipulation_buttons_active(false)
			# warning-ignore:return_value_discarded
			set_card_rotation(0)
			$Control.rect_rotation = 0
			# We scale the card to allow the player a better viewing experience
			if CFConst.VIEWPORT_FOCUS_ZOOM_TYPE == "scale":
				set_scale(Vector2(1,1) * preview_scale * cfc.curr_scale)
			else:
#				set_card_size(CFConst.CARD_SIZE * CFConst.PREVIEW_SCALE)
				resize_recursively(_control, preview_scale * cfc.curr_scale)
				get_card_front().scale_to(preview_scale * cfc.curr_scale)

		CardState.DECKBUILDER_GRID:
			z_index = 1
			z_as_relative = true
			$Control.mouse_filter = Control.MOUSE_FILTER_IGNORE
			set_focus(false)
			self.tokens.set_is_drawer_open(false)
			set_control_mouse_filters(false)
			set_manipulation_buttons_active(false)
			# warning-ignore:return_value_discarded
			set_card_rotation(0)
			$Control.rect_rotation = 0
			# We scale the card to allow the player a better viewing experience
			if CFConst.VIEWPORT_FOCUS_ZOOM_TYPE == "scale":
				set_scale(Vector2(1,1) * thumbnail_scale * cfc.curr_scale)
			# Commenting this out because it is messing with RichTextLabel
			# Font resizing
			else:
#				set_card_size(CFConst.CARD_SIZE * thumbnail_scale)
				resize_recursively(_control, thumbnail_scale * cfc.curr_scale)
				get_card_front().scale_to(thumbnail_scale * cfc.curr_scale)

		CardState.MOVING_TO_SPAWN_DESTINATION:
			z_index = CFConst.Z_INDEX_HAND_CARDS_NORMAL + 1
			set_focus(false)
			set_control_mouse_filters(false)
			set_manipulation_buttons_active(false)
			if not _tween.is_active()\
					and not scale.is_equal_approx(Vector2(1,1)):
				_add_tween_scale(scale, Vector2(1,1),0.75)
				_add_tween_global_position(global_position, get_viewport().size/2 - CFConst.CARD_SIZE/2)
				_tween.start()
				yield(_tween, "tween_all_completed")
				_tween_stuck_time = 0
				move_to(spawn_destination)
				scripting_bus.emit_signal("card_spawned", self, {"tags": ["Scripted", "Spawned"]})
				spawn_destination = null

func is_animating():
	if _tween and _tween.is_active():
		return true
	if _flip_tween and _flip_tween.is_active():
		return true
	return false

# Get the angle on the ellipse
func _get_angle_by_index(index_diff = null) -> float:
	var index = get_my_card_index()
	var hand_size = get_parent().get_card_count()
	# This to prevent div/0 errors because the card will not be
	# reported when it's being dragged
	if hand_size == 0:
		hand_size = 1
	var half = (hand_size - 1) / 2.0
	var card_angle_max: float = 15
	var card_angle_min: float = 6.5
	# Angle between cards
	var card_angle = max(min(60 / hand_size, card_angle_max), card_angle_min)
	# When foucs hand, the card needs to be offset by a certain angle
	# The current practice is just to find a suitable expression function, if there is a better function, please replace this function: - sign(index_diff) * (1.95-0.3*index_diff*index_diff) * min(card_angle,5)
	if index_diff != null:
		return 90 + (half - index) * card_angle \
				- sign(index_diff) * (1.95 - 0.3 * index_diff * index_diff) \
				* min(card_angle, 5)
	else:
		return 90 + (half - index) * card_angle


# Get card angle in hand by index that use oval shape
# The angle of the normal on the ellipse
func _get_oval_angle_by_index(
		angle = null,
		index_diff = null,
		hor_rad = null,
		ver_rad = null) -> float:
	if not angle:
		# Get the angle from the point on the oval to the center of the oval
		angle = _get_angle_by_index(index_diff)
	var parent_control
	if not hor_rad:
		parent_control = get_parent().get_node('Control')
		hor_rad = parent_control.rect_size.x * 0.5 * 1.5
	if not ver_rad:
		parent_control = get_parent().get_node('Control')
		ver_rad = parent_control.rect_size.y * 1.5
	var card_angle
	if angle == 90:
		card_angle = 90
	# Convert oval angle to normal angle
	else:
		# To avoid div/0
		if hor_rad == 0:
			card_angle = 90
		else:
			card_angle = rad2deg(atan(- ver_rad / hor_rad / tan(deg2rad(angle))))
			card_angle = card_angle + 90
	return(card_angle)


# Calculate the position after the rotation has been calculated that use oval shape
func _recalculate_position_use_oval(index_diff = null)-> Vector2:
	var card_position_x: float = 0.0
	var card_position_y: float = 0.0
	var parent = get_parent()
	var parent_control = parent.get_node('Control')
	# Oval hor rad, rect_size.x*0.5*1.5 it’s an empirical formula,
	# that's been tested to feel good.
	var hor_rad: float = parent_control.rect_size.x * 0.5 * 1.5
	# Oval ver rad, rect_size.y * 1.5 it’s an empirical formula,
	# that's been tested to feel good.
	var ver_rad: float = parent_control.rect_size.y * 1.5
	# Get the angle from the point on the oval to the center of the oval
	var angle = _get_angle_by_index(index_diff)
	var rad_angle = deg2rad(angle)
	# Get the direction vector of a point on the oval
	var oval_angle_vector = Vector2(hor_rad * cos(rad_angle),
			- ver_rad * sin(rad_angle))
	# Take the center point of the card as the starting point, the coordinates
	# of the top left corner of the card
	var left_top = Vector2(- card_size.x/2, - card_size.y/2)
	# Place the top center of the card on the oval point
	var center_top = Vector2(0, - card_size.y/2)
	# Get the angle of the card, which is different from the oval angle,
	# the card angle is the normal angle of a certain point
	var card_angle = _get_oval_angle_by_index(angle, null, hor_rad,ver_rad)
	# Displacement offset due to card rotation
	var delta_vector = left_top - center_top.rotated(deg2rad(90 - card_angle))
	# Oval center x
	var center_x = parent_control.rect_size.x / 2 \
			+ parent_control.rect_position.x
	# Oval center y, - parent_control.rect_size.y * 0.25:This method ensures that the card is moved to the proper position
	var center_y = parent_control.rect_size.y * 1.5 \
			+ parent_control.rect_position.y \
			- parent_control.rect_size.y * 0.25
	card_position_x = (oval_angle_vector.x + center_x)
	card_position_y = (oval_angle_vector.y + center_y)
	return(Vector2(card_position_x, card_position_y) + delta_vector)


# Calculate the position that use rectangle
func _recalculate_position_use_rectangle(index_diff = null)-> Vector2:
	var card_position_x: float = 0.0
	var card_position_y: float = 0.0
	# The number of cards currently in hand
	var hand_size: int = get_parent().get_card_count()
	# The maximum of horizontal pixels we want the cards to take
	# We simply use the size of the parent control container we've defined in
	# the node settings
	var parent_control = get_parent().get_node('Control')
	var max_hand_size_width: float = parent_control.rect_size.x
	# The maximum distance between cards
	# We base it on the card width to allow it to work with any card-size.
	var card_gap_max: float = card_size.x * 1.1
	# The minimum distance between cards
	# (less than card width means they start overlapping)
	var card_gap_min: float = card_size.x/2
	# The current distance between cards.
	# It is inversely proportional to the amount of cards in hand
	var cards_gap: float = max(min((max_hand_size_width
			- card_size.x/2)
			/ hand_size, card_gap_max), card_gap_min)
	# The current width of all cards in hand together
	var hand_width: float = (cards_gap * (hand_size-1)) + card_size.x
	# The following just create the vector position to place this specific card
	# in the playspace.
	card_position_x = (max_hand_size_width/2
			- hand_width/2
			+ cards_gap
			* get_my_card_index())
	# Since our control container has the same size as the cards,we start from 0
	# and just offset the card if we want it higher or lower.
	card_position_y = 0
	if index_diff!=null:
		return(Vector2(card_position_x, card_position_y)
				+ Vector2(card_size.x / index_diff * CFConst.NEIGHBOUR_PUSH, 0))
	else:
		return(Vector2(card_position_x,card_position_y))


# Calculates the rotation the card should have based on its parent.
func _recalculate_rotation(index_diff = null)-> float:
	var calculated_rotation := float(card_rotation)
	if get_parent().is_in_group("hands") and cfc.game_settings.hand_use_oval_shape:
		calculated_rotation = 90.0 - _get_oval_angle_by_index(null, index_diff)
	return(calculated_rotation)


# Ensures that all filters requested by the script are respected
#
# Will set is_valid to false if any filter does not match reality
func _filter_signal_trigger(card_scripts, trigger_card: Card) -> bool:
	var is_valid = true
	# Here we check that the trigger matches the _request_ for trigger
	# A trigger which requires "another" card, should not trigger
	# when itself causes the effect.
	# For example, a card which rotates itself whenever another card
	# is rotated, should not automatically rotate when itself rotates.
	var trigger = card_scripts.get("trigger", "any")
	if trigger == "self" and trigger_card != self:
		is_valid = false
	if trigger == "another" and trigger_card == self:
		is_valid = false
	return(is_valid)


func _on_Back_resized() -> void:
	# This looks like a Godot bug. I'm leaving it here in case I can track it later
	# It only happens if "card.set_is_faceup(false,true)" in CGFBoard.tcsn
	# At the loop at line 91, is active
	if _card_back_container and _card_back_container.rect_size != canonical_size:
		pass
#		print_debug($Control/Back.rect_size) # Replace with function body.



func serialize_to_json():
	return {"TODO": "TODO"}
	
func copy_tokens_to(to_card, details:= {}):
	var exclude = details.get("exclude",[])
	var my_tokens = tokens.get_all_tokens()
	for token_name in my_tokens.keys():
		if (token_name in exclude):
			continue
		var count = tokens.get_token_count(token_name)
		to_card.tokens.mod_token(token_name, count, true)		


# Ensures proper cleanup when a card is queue_free() for any reason
func _on_tree_exiting():	
	if cfc.NMAP.has("main"):
		cfc.NMAP.main.unfocus(self)
	if _placement_slot:
		_placement_slot.remove_occupying_card(self)
		_placement_slot = null

#We remove all signals from the card
#once it's been scheduled for deletion
#this avoids trigerring its effects after we've decided to delete it 
func queue_free():
	var connections = self.get_incoming_connections()
	for conn in connections:
		var source = conn["source"]
		source.disconnect(conn["signal_name"],self , conn["method_name"])
	.queue_free()
	
var _duplicate = null
func get_duplicate(refresh_variables = true):
	if !_duplicate:
		_duplicate = get_duplicate_no_cache()
	elif refresh_variables:
		#duplicate already exists, we refresh it
		_duplicate.clear_highlight()
		var tokens_json = tokens.export_to_json()
		_duplicate.tokens.load_from_json(tokens_json)
	return _duplicate
	
func get_duplicate_no_cache():
	var dupe = self.duplicate(DUPLICATE_USE_INSTANCING)
	# This prevents the card from being scripted with the
	# signal propagator and other things going via groups
	dupe.remove_from_group("cards")
	dupe.canonical_name = canonical_name
	dupe.canonical_id = canonical_id
	dupe.properties = properties.duplicate()
	return dupe
