# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED

class_name WCCard
extends Card

const _SPINBOX_SCENE_FILE = CFConst.PATH_CUSTOM + "cards/SpinPanel.tscn"
const _SPINBOX_SCENE = preload(_SPINBOX_SCENE_FILE)

var has_focus = false

# -1 uninitialized, 0 Villain, any positive value: hero
var _owner_hero_id  := -1
var _controller_hero_id  := -1 setget set_controller_hero_id, get_controller_hero_id

var _check_play_costs_cache: Dictionary = {}
var _cache_resource_value: = {}
var _cache_refresh_needed:= false

var _on_ready_load_from_json:Dictionary = {}

#marvel champions specific variables
var _can_change_form := true
var _is_exhausted:= false
var _is_boost:=false

#an array of ManaCost variables representing everything that's been used to pay for this card
var _last_paid_with := []

var extra_scripts := {}
var extra_script_uid := 0

# The node with number manipulation box on this card
var spinbox = null
#healthbar on top of characters, allies, villains, etc...
var healthbar
var info_icon
var side_icons

var hints:= []

#activity script tied to a villain/minion attacking or scheming
#might be used for other stuff eventually
var activity_script
#status of this card as an encounter (see GameData)
var encounter_status = gameData.EncounterStatus.NONE

func hint (text, color, details = {}):
	var position = details.get("position", "")
	var pos_x = 50
	var pos_y = 50
	match position:
		"bottom_right":
			pos_x = 100
			pos_y = 200
		_:
			pos_x += (randi() % 100) - 50
			pos_y += (randi() % 100) - 50
		
	var _hint_label = Label.new()
	var _hint= Container.new()
	_hint_label.text = text
	var dynamic_font = cfc.get_font("res://fonts/Bangers-Regular.ttf", 32)	
	_hint_label.add_font_override("font", dynamic_font)	
	_hint_label.add_color_override("font_color", color)
	var dir_x = randf() * 10 
	var dir_y = randf() * 10
	
	var settings = {
		"hint_object": _hint,
		"lifetime": details.get("lifetime", 1.0),
		"direction": Vector2(dir_x, dir_y)
	}
	hints.append(settings)
	var _hint_label_shadow = _hint_label.duplicate(DUPLICATE_USE_INSTANCING)
	_hint_label_shadow.add_color_override("font_color", Color8(0,0,0,150))
	_hint.add_child(_hint_label_shadow)	
	_hint.add_child(_hint_label)
	_hint_label_shadow.rect_position = _hint_label.rect_position + Vector2(10, 10)
	$Control.add_child(_hint)
	_hint.rect_position = Vector2(pos_x, pos_y)

func add_extra_script(script_definition, allowed_hero_id = 0):
	extra_script_uid+= 1
	extra_scripts[extra_script_uid] = {
		"script_definition" : script_definition
	}
	if allowed_hero_id:
		extra_scripts[extra_script_uid]["controller_id"] = allowed_hero_id
		
	check_ghost_card()
	return extra_script_uid

func remove_extra_script(script_uid):
	extra_scripts.erase(script_uid)
	check_ghost_card()
	return extra_script_uid

func set_is_boost(value:=true):
	self._is_boost = value
	
	#removing the card from this group will prevent
	#triggering alterants
	if value and self.is_in_group("cards"):
		self.remove_from_group("cards") 
	if !value and !self.is_in_group("cards"):
		self.add_to_group("cards")
	
func is_boost():
	return self._is_boost

#what to do when I'm an attachement and my host is removed from the table
func host_is_gone(former_host):
	# Attachments typically go to their discard
	discard()

func init_owner_hero_id(hero_id:int):
	if _owner_hero_id >=0: #already initialized
		return
	if (hero_id == -1):
		var _error = 1		
	_owner_hero_id = hero_id
	
func get_owner_hero_id() -> int:
	return _owner_hero_id	

func set_controller_hero_id(hero_id:int):
	_controller_hero_id = hero_id		
	update_hero_groups()

func queue_refresh_cache():
	_cache_refresh_needed = true

#refresh cache for all data
func refresh_cache(forced=false):
	if !forced and ! _cache_refresh_needed:
		return
		
		
	for i in gameData.get_team_size():
		var hero_id = i+1
		_check_play_costs_cache[hero_id] = CFConst.CostsState.CACHE_INVALID
	check_death()
	_cache_resource_value = {}
	side_icons.update_state(true)
	_cache_refresh_needed = false

func is_character() -> bool:
	var type_code = get_property("type_code", "")
	return is_character_type(type_code)

static func is_character_type(type_code)-> bool:
	return type_code in ["villain", "hero", "alter_ego", "ally", "minion"]

func _stack_event_deleted(event):
	match event.get_first_task_name():
		"card_dies":
			var scripts = event.get_tasks()
			if scripts:
				var script = scripts[0]
				if script.subjects and script.subjects[0] == self:
					_died_signal_sent = false

var _died_signal_sent = false
func check_death(script = null) -> bool:
	if _died_signal_sent:
		return true
	#if no script is passed, this is an automated check (during _process), we only perform
	#it for character cards that are on the board, and with an empty stack to avoid a race condition
	if !script:
		if !is_character():
			return false
		if !is_onboard():
			return false
		if !gameData.theStack.is_idle():
			return false
		
	var total_damage:int =  tokens.get_token_count("damage")
	var health = get_property("health", 0)

	if total_damage < health:
		return false
	
	var tags = []
	var trigger_details = {}
	var trigger_card = self
		
	if script:
		tags = [script.script_name, "Scripted"] + script.get_property(SP.KEY_TAGS)	
		trigger_card = script.trigger_object
		trigger_details = script.trigger_details.duplicate(true)
		trigger_details["source"] = guidMaster.get_guid(script.owner)
	
		#if the damage comes from an "attack", ensure the source is properly categorized as
		#the hero (or villain) owner rather than the event card itself
		if ("attack" in tags):
			var owner = script.owner
			var type = owner.get_property("type_code", "")
			if !is_character_type(type):
				owner = WCScriptingEngine._get_identity_from_script(script)	
				trigger_details["source"] = guidMaster.get_guid(owner)

	var card_dies_definition = {
		"name": "card_dies",
		"tags": tags
	}
			
	var card_dies_script:ScriptTask = ScriptTask.new(self, card_dies_definition, trigger_card, trigger_details)
	card_dies_script.subjects = [self]
	var task_event = SimplifiedStackScript.new(card_dies_script)
	gameData.theStack.add_script(task_event)
	_died_signal_sent = true
	return true
	
func get_controller_hero_id() -> int:
	return _controller_hero_id	

func get_controller_hero_card():
	return gameData.get_identity_card(_controller_hero_id)	
	
func get_controller_player_network_id() -> int:
	var player_data:PlayerData = gameData.get_hero_owner(get_controller_hero_id())
	if (!player_data):
		return 0 #TODO error handling? This shouldn't happen
	return player_data.get_network_id()	
	
func get_controller_player_id() -> int:
	var player_data:PlayerData = gameData.get_hero_owner(get_controller_hero_id())
	if (!player_data):
		return 0 #TODO error handling? This shouldn't happen
	return player_data.get_id()		

func _runtime_properties_setup():
	_horizontal = self.get_property("_horizontal", false)
	
	var base_threat = self.get_property("base_threat",0)
	var base_threat_fixed = get_property("base_threat_fixed", true)
	if base_threat and !base_threat_fixed:
		base_threat *= gameData.team.size()
		properties["base_threat"] = base_threat

	var health = get_property("health",0)
	var health_per_hero = get_property("health_per_hero", false)
	if health and health_per_hero:
		health *= gameData.team.size()
		properties["health"] = health
		
	var threat = get_property("threat",0)
	var threat_fixed = get_property("threat_fixed", true)
	if threat and !threat_fixed:
		threat *= gameData.team.size()
		properties["threat"] = threat		

func get_display_name(force_canonical = false):
	if is_faceup:
		return canonical_name
	var shortname =  get_property("shortname", "---")
	return shortname

func setup() -> void:
	.setup()
	_runtime_properties_setup()
	update_groups()
	init_token_drawer()	
	position_ui_elements()
	_ready_load_from_json()
	
	gameData.connect("game_state_changed", self, "_game_state_changed")
	scripting_bus.connect("step_started", self, "_game_step_started")
	scripting_bus.connect("card_token_modified", self, "_card_token_modified")

	scripting_bus.connect("card_moved_to_hand", self, "_card_moved")
	scripting_bus.connect("card_moved_to_pile", self, "_card_moved")
	scripting_bus.connect("card_moved_to_board", self, "_card_moved")		
	scripting_bus.connect("card_properties_modified", self, "_card_properties_modified")		

	cfc.connect("cache_cleared", self, "_cfc_cache_cleared")
	scripting_bus.connect("stack_event_deleted", self, "_stack_event_deleted")
	
	attachment_mode = AttachmentMode.ATTACH_BEHIND
	
	#this prevents moving cards around. A bit annoying but avoids weird double click envents leading to a drag and drop
	disable_dragging_from_board = true	
	disable_dropping_to_cardcontainers = true

#		scripting_bus.emit_signal(
#				"card_properties_modified",
#				self,
#				{
#					"property_name": property,
#					"new_property_value": value,
#					"previous_property_value": previous_value,
#					"tags": tags
#				}
#		)	
func _card_properties_modified(owner_card, details):
	if owner_card == self and details.get("property_name", "") == "type_code":
		var previous_value = details.get("previous_property_value", "")
		var new_value = details.get("new_property_value", "")
		if new_value in ["villain", "minion"] and new_value != previous_value  and "emit_signal" in details["tags"]:
			scripts = SetScripts_All.get_enemy_scripts()
		update_groups()
		update_hero_groups()
	
#		scripting_bus.emit_signal(
#				"card_token_modified",
#				owner_card,
#				{SP.TRIGGER_TOKEN_NAME: token.get_token_name(),
#				SP.TRIGGER_PREV_COUNT: prev_value,
#				SP.TRIGGER_NEW_COUNT: new_value,
#				"tags": tags})
func _card_token_modified(owner_card, details):
	if owner_card != self:
		return
	if details[SP.TRIGGER_TOKEN_NAME] == "damage":
		#display_health()
		pass
	if details[SP.TRIGGER_TOKEN_NAME] == "threat":
		display_threat()

#("card_moved_to_hand",
#					self,
#					 {
#						"destination": targetHost.name,
#						"source": parentHost.name,
#						"tags": tags
#					}
#			)

func _card_moved(owner_card, details):
	if owner_card != self:
		return
	display_debug(canonical_name + " moved from " + details["source"] + " to " + details["destination"])

func display_threat():
	if !healthbar:
		return
	if get_state_exec() != "board":
		healthbar.set_visible(false)
		return

	var type_code = get_property("type_code", 0)
	if !(type_code in ["main_scheme"]):
		return

	var total_threat = get_property("threat", 0)
	if !total_threat:
		return
	var current_threat = self.tokens.get_token_count("threat")
	healthbar.set_threat(total_threat, current_threat)
	pass
	
func display_health():
	if !healthbar:
		return
	if get_state_exec() != "board":
		healthbar.set_visible(false)
		return

	var type_code = get_property("type_code", 0)
	if !(type_code in ["hero", "alter_ego", "villain"]):
		return

	var total_health = get_property("health", 0)
	if !total_health:
		return
	var total_damage = self.tokens.get_token_count("damage")
	var remaining_health = total_health-total_damage
	if remaining_health<0:
		remaining_health= 0
	healthbar.set_health(total_health, remaining_health)
	pass

func position_ui_elements():
	if _horizontal:
		#reposition the token drawer for horizontal cards
		tokens.set_is_horizontal()

func execute_before_scripts(
		trigger_card: Card = self,
		trigger: String = "manual",
		trigger_details: Dictionary = {},
		run_type := CFInt.RunType.NORMAL):
	return execute_scripts(trigger_card, "before_" + trigger, trigger_details, run_type) 

func _class_specific_ready():
	._class_specific_ready()
	healthbar = $Control/HealthPanel/healthbar
	info_icon = get_node("%info_icon")
	side_icons = get_node("%SideIcons")
	#deactivate collision support for performance
	if CFConst.PERFORMANCE_HACKS:
		self.monitoring = false
		remove_child($Debug)
		$Control.remove_child($Control/ManipulationButtons)
		buttons = null

func get_spinbox():
	if !spinbox:
		var spinbox_panel = _SPINBOX_SCENE.instance()
		$Control.add_child(spinbox_panel)
		spinbox = spinbox_panel.get_node("SpinBox")

	return spinbox		
		

func _ready():
	scripting_bus.connect("scripting_event_about_to_trigger", self, "execute_before_scripts")

#
# Keyboard/Gamepad focus related functions
#
func reorganize_attachments_focus_mode():
	var previous_control:Control = self.get_focus_control()
	previous_control.focus_neighbour_left = ""
	previous_control.focus_neighbour_right = ""
	previous_control.focus_neighbour_bottom = ""
	previous_control.focus_neighbour_top = ""		
	for card in attachments:
		var control = card.get_focus_control()
		control.focus_neighbour_left = ""
		control.focus_neighbour_right = ""
		control.focus_neighbour_bottom = ""
		control.focus_neighbour_top = ""		
		if previous_control:
			#attachments are slightly below, slightly to the right of each other
			control.focus_neighbour_left = previous_control.get_path()	
			control.focus_neighbour_top = control.focus_neighbour_left			
			previous_control.focus_neighbour_right = control.get_path()
			previous_control.focus_neighbour_bottom = previous_control.focus_neighbour_right
		previous_control = control

func _on_Control_focus_entered():	
	#doing the focus thing only for non mouse inputs
	if !gamepadHandler.is_mouse_input():
		gain_focus()
	
func _on_Control_focus_exited():
	lose_focus()

func grab_focus():
	_control.grab_focus()

func get_focus_control():
	return _control

func gain_focus():
	has_focus = true
	
	#TODO this is a lame attempt to make it clearer which card is being 
	#currently selected. Doesn"t work so well tbh..
	if !gamepadHandler.is_mouse_input():
		if get_state_exec()!= "hand":
			if card_front and card_front.art:
				card_front.art.self_modulate = CFConst.FOCUS_CARD_MODULATE
				card_front.art.self_modulate.a = 1.0
	.gain_focus()
	
func lose_focus():
	has_focus = false
#	if card_front and card_front.art:
#		card_front.art.set_material(null)
	if card_front and card_front.art:
		card_front.art.self_modulate = Color(1.0,1.0,1.0,1.0)
	.lose_focus()
	
func enable_focus_mode():
	_control.focus_mode = Control.FOCUS_ALL

func disable_focus_mode():
	_control.focus_mode = Control.FOCUS_NONE

#
# User Interface/Input functions
#

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
	elif event is InputEvent:
		if targeting_arrow.is_targeting:
			if gamepadHandler.is_ui_accept_pressed(event):
				targeting_arrow.complete_targeting()
			elif gamepadHandler.is_ui_cancel_pressed(event):
				targeting_arrow.cancel_targeting()		

	

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
	pass
		

func _process(delta) -> void:
	if cfc.game_paused:
		return

	refresh_cache()

	if info_icon and info_icon.visible:
		info_icon.modulate.a -= delta
		if info_icon.modulate.a < 0.01:
			info_icon.visible = false

	#hints
	var hints_to_erase = []
	var stop = false
	for _hint_data in hints:
		var hint_object = _hint_data.get("hint_object", null)
		if hint_object:
			hint_object.visible = false
		
	for _hint_data in hints:
		if stop:
			break
		var hint_object = _hint_data.get("hint_object", null)
		if hint_object:
			hint_object.visible = true
			hint_object.modulate.a -= delta / 3
			hint_object.rect_scale += Vector2(delta *3, delta *3)
			hint_object.rect_position+= _hint_data.get("direction") * delta
		if self._is_exhausted:
			hint_object.rect_rotation = -90
		var lifetime = _hint_data.get("lifetime", 0)
		lifetime -= delta
		if lifetime < 0.2 or hint_object.modulate.a <=0.2:
			stop = false
		else:
			stop = true
		if lifetime < 0 or hint_object.modulate.a <=0:
			hints_to_erase.append(_hint_data)
		_hint_data["lifetime"] = lifetime
	for data in hints_to_erase:
		$Control.remove_child(data["hint_object"])
		hints.erase(data)
	hints_to_erase = []
	
	
	if (cfc.is_modal_event_ongoing()):
		return
	if (gameData.is_targeting_ongoing()):
		return
		
	display_play_highlight()	


func display_play_highlight():
	var can_play = check_play_costs()
	if (can_play == CFConst.CostsState.OK):
		#if modal menu is displayed we don't want to mess up those cards highlights
		var colour = can_play
		if !gamepadHandler.is_mouse_input():
			colour = CFConst.CostsState.OK_NO_MOUSE
		if gameData.is_interrupt_mode():
			colour = CFConst.CostsState.OK_INTERRUPT
		set_target_highlight(colour)
		if has_focus and !gamepadHandler.is_mouse_input():
			set_target_highlight(CFConst.FOCUS_COLOUR_ACTIVE)			
	else:
		#pass
		clear_highlight()
		#card with focus overrides previous highlight color	
		if has_focus and !gamepadHandler.is_mouse_input():
			set_target_highlight(CFConst.FOCUS_COLOUR_INACTIVE)		

func set_target_highlight(colour):
	highlight.set_target_highlight(colour)


#flush caches and states when game state changes
func _game_state_changed(_details:Dictionary):
	queue_refresh_cache()	
	display_health()

func _cfc_cache_cleared():
	queue_refresh_cache()

#reset some variables at new turn
func _game_step_started(_trigger_object, details:Dictionary):
	var current_step = details["step"]
	match current_step:
		CFConst.PHASE_STEP.PLAYER_TURN:
			_can_change_form = true
	return	
	

func get_card_back_code() -> String:
	return get_property("back_card_code")

func get_art_filename(force_if_facedown: = true):
	if force_if_facedown or is_faceup:
		var card_code = get_property("_code")
		return cfc.get_img_filename(card_code)		

	return ("res://assets/card_backs/generic_back.png")

func get_art_texture(force_if_facedown: = true):
	return cfc.get_card_texture(self, force_if_facedown)

func get_cropped_art_texture():
	return cfc.get_cropped_card_texture(self)

func set_card_art(forced=false):
	if card_front.art_filename and !forced:
		return
	var filename = get_art_filename()
	card_front.set_card_art(filename)

# Determines which play position (board, pile or hand)
# a script should look for to find card scripts
# based on the card's state.
#
# Returns either "board", "hand", "pile" or "NONE".
var _state_exec_cache := ""

func set_state(value: int) -> void:
	if state == CardState.DRAGGED:
		pass
	var prev_state = state
	state = value
	if prev_state != state:
		emit_signal("state_changed", self, prev_state, state)
		
		_state_exec_cache = ""

func get_state_exec() -> String:
	#return get_state_exec_no_cache()
	
	# I can't cache CardState.MOVING_TO_CONTAINER:
	#I've seen cases where it keeps that state while moving between multiple places,
	#which makes the cached value stale
	
	if !_state_exec_cache or state == CardState.MOVING_TO_CONTAINER:
		 _state_exec_cache = get_state_exec_no_cache()
	return _state_exec_cache
	
func get_state_exec_no_cache() -> String:	
	var state_exec := "NONE"
	# We don't check according to the parent name
	# as that can change.
	# Might consier checking on the parent class if this gets too complicated.
	match state:
		CardState.ON_PLAY_BOARD,\
				CardState.FOCUSED_ON_BOARD,\
				CardState.DROPPING_TO_BOARD:
			# cards that have a type_code 'i.e faceup cards and facedown cards with modifiers)
			#are allowed to run scripts
			if get_property("type_code", ""):
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

#adds our card to group names matching its type and hero owner
# e.g. "allies2" means allies belonging to hero 2
# 0 is valid and represents the villain
func update_hero_groups():
	var type_code = properties.get("type_code", "")
	
	var all_groups:Array = CFConst.ALL_TYPE_GROUPS
	for group in all_groups:
		for i in range (gameData.team.size() + 1):
			var hero_group = group + str(i)
			if self.is_in_group(hero_group):
				self.remove_from_group(hero_group)	
	
	var groups:Array = CFConst.TYPES_TO_GROUPS.get(type_code, [])
	
	for group in groups:
		for i in range (gameData.team.size() + 1):
			var hero_group = group + str(i)
			if self.get_controller_hero_id() == i:
				self.add_to_group(hero_group)

func update_groups() -> void :
	var type_code = properties.get("type_code", "")

	var all_groups:Array = CFConst.ALL_TYPE_GROUPS
	for group in all_groups:
		if self.is_in_group(group):
			self.remove_from_group(group)	
			
	var groups:Array = CFConst.TYPES_TO_GROUPS.get(type_code, [])
	for group in groups:
		self.add_to_group(group)

func remove_attachment(card):
	attachments.erase(card)
	reorganize_attachments_focus_mode()

func attach_to_host(
			host: Card,
			is_following_previous_host = false,
			tags := ["Manual"]) -> void:
	.attach_to_host(host, is_following_previous_host, tags)
	host.reorganize_attachments_focus_mode()		
		
func common_post_move_scripts(new_host: String, old_host: String, _move_tags: Array) -> void:
	#change controller as needed
	var new_grid = get_grid_name()
	var new_hero_id = 0
	if (new_grid):
		new_hero_id = gameData.get_grid_controller_hero_id(new_grid)
	else:
		#attempt for piles/containers
		new_hero_id = gameData.get_grid_controller_hero_id(new_host)
	
	if (new_hero_id or (self.get_controller_hero_id() < 0) ): #only change if we were able to establish an owner, or if uninitialized
		self.set_controller_hero_id(new_hero_id)
	
	
	#init owner once and only once, if not already done
	init_owner_hero_id(new_hero_id)	
	
	#display_health()
	display_threat()
	
	#cached data and flag updates for new zone
	match new_host.to_lower():
		"board":
			if !is_faceup:
				get_card_back().start_card_back_animation()
		_:
			_is_exhausted = false
			#reset some cache data
			_died_signal_sent = false

	
	#determine if this card can be selected with a controller	
	cfc.NMAP.board.update_card_focus(self, {"new_host" : new_host, "old_host": old_host} )
		

#Tries to play the card assuming costs aren't impossible to pay
#Also used for automated tests
func attempt_to_play(user_click:bool = false, origin_event = null):
	#don't try to activate the card if the click was the result of targeting
	if user_click:
		if gameData.is_targeting_ongoing() or gameData.targeting_happened_too_recently():
			return
		#we already sent a request and should be waiting for full resolution	

		var interaction_authority:UserInteractionAuthority = UserInteractionAuthority.new(self)
		var interaction_authorized = interaction_authority.interaction_authorized()			
		
		if !interaction_authorized or !gameData.theStack.is_player_allowed_to_click(self):
			network_request_rejected()
			return
		
		#gamedata is running some automated clicks from a previous request	
		if gameData.scripted_play_sequence:
			return	
		
	var state_exec = get_state_exec()
	
	if !state_exec in ["hand", "board"]:
		return false
	
	match state_exec:
		"hand":
			if check_play_costs() == CFConst.CostsState.IMPOSSIBLE:
				return false
			#unique rule - Move to check costs ?
			if get_property("is_unique", false):
				var already_in_play = cfc.NMAP.board.unique_card_in_play(self)
				if already_in_play:
					return false	


	cfc.card_drag_ongoing = null
	var details = {}
	if origin_event:
		details["origin_event"] = origin_event
	execute_scripts(self,"manual",details)


func network_request_rejected():
	if info_icon:
		info_icon.visible = true
		info_icon.modulate = Color(1,1,1,1)

#returns true if this card has some ability that can interrupt
#the current action (and if hero_id is the one who can play it)
func can_interrupt(
		hero_id,
		trigger_card: WCCard = self,
		trigger_details: Dictionary = {}) -> int:
	if cfc.game_paused:
		return CFConst.CanInterrupt.NO
	# Just in case the card is displayed outside the main game
	# and somehow its script is triggered.
	if not cfc.NMAP.has('board'):
		return CFConst.CanInterrupt.NO
	
	var _debug = false
	if canonical_name == "Black Knight - Dane Whitman" and trigger_card:
		if trigger_details["event_name"] == "receive_damage":
			_debug = true

	if (_debug):
		display_debug("{interrupt} Hero:" + str(hero_id) + " Checks for " + canonical_name + " vs " + trigger_details.get("event_name") + " - " + trigger_card.canonical_name)		

	#select valid scripts that match the current trigger
	var card_scripts = retrieve_filtered_scripts(trigger_card, "interrupt", trigger_details)
	if (_debug):
		display_debug("card_scripts: " + to_json(card_scripts))
	if (!card_scripts):
		if (_debug):
			display_debug("no filtered scripts found")
		return CFConst.CanInterrupt.NO	
	
	var state_scripts = get_state_scripts(card_scripts, trigger_card, trigger_details)
	if (_debug):
		display_debug("state_scripts: " + to_json(state_scripts))	
	if (!state_scripts):
		if (_debug):
			display_debug("no state scripts found")
		return CFConst.CanInterrupt.NO
	
	#card has potential interrupts. Last we check if I'm the player who can play them
	var may_interrupt =  CFConst.CanInterrupt.NO


	if gameData.can_hero_play_this_ability(hero_id,self):
		if card_scripts.get("is_optional_" + get_state_exec()):
			#optional interrupts need to check costs
			if check_play_costs_no_cache(hero_id, _debug) == CFConst.CostsState.IMPOSSIBLE:
				if (_debug):
					display_debug("allowed to interrupt but can't pay cost")
				return CFConst.CanInterrupt.NO			
			may_interrupt =  CFConst.CanInterrupt.MAY
		else:
			may_interrupt =  CFConst.CanInterrupt.MUST
	else:
		if (_debug):
			display_debug("not allowed to inbterrupt according to can_hero_play_this_ability")
		pass
	if (may_interrupt != CFConst.CanInterrupt.NO and canonical_name == "Spider-Man"):
		display_debug("can interrupt " + trigger_card.canonical_name + ". Details: " + to_json(trigger_details))

	if (_debug):
		display_debug("{interrupt} END OF CHECKS for " + canonical_name + " vs " + trigger_details.get("event_name") + " - " + trigger_card.canonical_name)		


	return may_interrupt

func execute_scripts_no_stack(
		trigger_card: Card = self,
		trigger: String = "manual",
		trigger_details: Dictionary = {},
		run_type := CFInt.RunType.NORMAL):
	var new_trigger_details = trigger_details
	new_trigger_details["use_stack"] = false
	return execute_scripts(trigger_card, trigger, new_trigger_details, run_type)	


func retrieve_filtered_scripts(trigger_card,trigger, trigger_details):
	# I use this spot to add a breakpoint when testing script behaviour
	# especially on filters
	if _debugger_hook:
		pass
	if trigger == CFConst.SCRIPT_BREAKPOINT_TRIGGER_NAME and canonical_name == CFConst.SCRIPT_BREAKPOINT_CARD_NAME:
		pass	
	var card_scripts = retrieve_scripts(trigger)		
	# We check the trigger against the filter defined
	# If it does not match, then we don't pass any scripts for this trigger.
	if not SP.filter_trigger(
			card_scripts,
			trigger_card,
			self,
			trigger_details):
		card_scripts.clear()
	
	#additional filter check for interrupts/responses
	if not cfc.ov_utils.filter_trigger(
			trigger,
			card_scripts,
			trigger_card,
			self,
			trigger_details):
		card_scripts.clear()
	
	var to_erase = []
#					"condition":{
#						"func_name": "current_activation_status",
#						"func_params": {
#							"undefended": true
#						}
#					},	
	for key in card_scripts:
		if card_scripts.has("condition_" + key):
			var condition = card_scripts["condition_" + key]
			var func_name = condition.get("func_name", "")
			if !func_name:
				continue
			var func_params = condition.get("func_params", {})
			var check = cfc.ov_utils.func_name_run(self, func_name, func_params, null)
			if !check:
				to_erase.append(key)
				to_erase.append("condition_" + key)		
	for key in to_erase:
		card_scripts.erase(key)
		
	return card_scripts


#a quick check fnction for performance to return early in execute_scripts
func has_potential_scripts(trigger_card, trigger):
	var card_scripts = retrieve_scripts(trigger)
	if !card_scripts:
		return false
	var state_exec := get_state_exec()
	var any_state_scripts = card_scripts.get('all', [])
	var state_scripts = card_scripts.get(state_exec, any_state_scripts)
	return state_scripts
	
# Executes the tasks defined in the card's scripts in order.
#
# Returns a [ScriptingEngine] object but that it not statically typed
# As it causes the parser think there's a cyclic dependency.

	# there is a bug in the original engine that will create duplicate card
	# in selectionWindow.gd. These cards should get triggered but they do
	# There has to be a better way to fix this (see their attempted fix in ScriptingBus)
	# but I'm not sure for now
func execute_scripts(
		trigger_card: Card = self,
		trigger: String = "manual",
		trigger_details: Dictionary = {},
		run_type := CFInt.RunType.NORMAL):

	if cfc.game_paused:
		return
	# Just in case the card is displayed outside the main game
	# and somehow its script is triggered.
	if not cfc.NMAP.has('board'):
		return

	if (trigger == CFConst.SCRIPT_BREAKPOINT_TRIGGER_NAME and canonical_name == CFConst.SCRIPT_BREAKPOINT_CARD_NAME ):
		var _tmp = 1
	
	var _debug = trigger_details.get("_debug", false)
			
	#temporary bug fix: prevent uninitalized cards from running scripts
	#these cards are duplicates that shouldn't exist?
	if (get_owner_hero_id() == -1):
		return null
	
	var can_i_run = can_execute_scripts()
	if typeof(can_i_run) == TYPE_BOOL:
		if !can_i_run:
			return null
	else:
		if !(trigger in (can_i_run)):
			return null	

	#Force execute some previously selected scripts, bypassing the rest of the process
	var exec_config = trigger_details.get("exec_config", {})
	var state_scripts_dict = trigger_details.get("state_scripts_dict", {})
	if state_scripts_dict:
		return choose_and_execute_scripts(state_scripts_dict, trigger_card, trigger, trigger_details, run_type, exec_config)

	#last minute swap for hero vs alter ego reveals
	if trigger == "reveal":
		var hero_id_to_check = gameData.get_villain_current_hero_target()
		var identity_card = gameData.get_identity_card(hero_id_to_check)
		var specific_trigger = "reveal_alter_ego" if identity_card.is_alter_ego_form() else "reveal_hero"
		var specific_reveal = cfc.set_scripts.get(canonical_id,{}).get(specific_trigger,{})
		if specific_reveal:
			trigger = specific_trigger		
				
	if _debug:
		display_debug("executing scripts :" +trigger_card.canonical_name + "-'"+ to_json(trigger_details))	


	
	#if set to false we'll skip the (potential) optional confirmation
	#this is useful e.g. in interrupt mode where we have a better UI
	var show_optional_confirmation_menu = true

	var force_user_interaction_required = false
	if trigger == "manual":
		force_user_interaction_required = true
		if gameData.is_forced_interrupt_mode():
			force_user_interaction_required = false

	trigger_details["trigger_type"] = trigger
	
	#we're playing a card manually but in interrupt mode.
	#What we want to do here is play the optional triggered effect instead
	if (trigger == "manual" and gameData.is_interrupt_mode()):
		#TODO very flaky code, how to fix?
		if (canonical_name == CFConst.SCRIPT_BREAKPOINT_CARD_NAME):
			var _tmp =1
			
		trigger = find_interrupt_script()
		if (!trigger):
			return
		trigger_details.merge(gameData.theStack.get_current_interrupted_event(), true)
		if (!trigger_details):
			return
		trigger_card = trigger_details["event_object"].owner #this is geting gross, how to clear that?
		if (!trigger_card):
			return
		#skip optional confirmation menu for interrupts,
		#we have a different gui signal	
		show_optional_confirmation_menu = false	

	if ! has_potential_scripts(trigger_card, trigger):
		return null

	var checksum = trigger
	if trigger_card:
		checksum += " - " + trigger_card.canonical_name
	if _debug:
		cfc.LOG("reached step 1 for: " + checksum  )	
	#var only_cost_check = is_dry_run(run_type)
		
#	var cost_check_mode = \
#		CFInt.RunType.BACKGROUND_COST_CHECK if run_type == CFInt.RunType.BACKGROUND_COST_CHECK \
#		else CFInt.RunType.COST_CHECK
	
	common_pre_execution_scripts(trigger_card, trigger, trigger_details)
	
	#select valid scripts that match the current trigger
	var card_scripts = retrieve_filtered_scripts(trigger_card, trigger, trigger_details)
	
	# We select which scripts to run from the card, based on it state	
	state_scripts_dict = get_state_scripts_dict(card_scripts, trigger_card, trigger_details)
	show_optional_confirmation_menu = show_optional_confirmation_menu and card_scripts.get("is_optional_" + get_state_exec(), false)

	exec_config = {
		"show_optional_confirmation_menu" : show_optional_confirmation_menu,
		"checksum": checksum,
		"force_user_interaction_required": force_user_interaction_required
	}
	
	var rules = state_scripts_dict.get("rules", {})

	var sceng = null
	if rules.get("for_each_player", false):
		rules.erase("for_each_player")
		for i in gameData.get_team_size():
			var hero_id = i+1
			var hero_triggers = trigger_details.duplicate()
			hero_triggers["override_hero_id"] = hero_id
			hero_triggers["state_scripts_dict"] = state_scripts_dict
			hero_triggers["exec_config"] = exec_config
			gameData.add_script_to_execute(self, trigger_card, trigger, hero_triggers, run_type)
		#kickstart the process to return a sceng object if possible
		gameData.execute_priority_scripts()	
	else:	
		sceng = choose_and_execute_scripts(state_scripts_dict, trigger_card, trigger, trigger_details, run_type, exec_config)
		if sceng is GDScriptFunctionState: # Still working.
			sceng = yield(sceng, "completed")
	return sceng
	
func choose_and_execute_scripts(state_scripts_dict, trigger_card, trigger, trigger_details, run_type, exec_config = {}):	
	var state_scripts = state_scripts_dict["state_scripts"]

	var rules = state_scripts_dict.get("rules", {})

	var show_optional_confirmation_menu = exec_config.get("show_optional_confirmation_menu", false)
	var checksum = exec_config.get("checksum", "")
	var force_user_interaction_required = exec_config.get("force_user_interaction_required", false)	
	#Check if this script is exected from remote (another online player has been paying for the cost)
	var is_network_call = trigger_details.has("network_prepaid") #TODO MOVE OUTSIDE OF Core
	var origin_event = trigger_details.get("origin_event", null)
	
	#semaphores
	cfc.add_ongoing_process(self, "core_execute_scripts")
	
	var action_name = state_scripts_dict["action_name"]


	var _debug = trigger_details.get("_debug", false)

	var interaction_authority:UserInteractionAuthority = UserInteractionAuthority.new(self, trigger_card, trigger, trigger_details, run_type)
	var interaction_authorized = interaction_authority.interaction_authorized()	
	var interacting_hero = interaction_authority.authorized_hero_id()
	if _debug:
		cfc.LOG("reached step 2 for: " + checksum + ". InteractionAuthority says " + to_json(interaction_authority.compute_authority())  )
	

	# Here we check for confirmation of optional trigger effects
	# There should be an SP.KEY_IS_OPTIONAL definition per state
	# E.g. if board scripts are optional, but hand scripts are not
	# Then you'd include an "is_optional_board" key at the same level as "board"
	# Here we check for confirmation of optional trigger effects
	# There should be an SP.KEY_IS_OPTIONAL definition per state
	# E.g. if board scripts are optional, but hand scripts are not
	# Then you'd include an "is_optional_board" key at the same level as "board"

	if show_optional_confirmation_menu:
		if typeof(state_scripts) == TYPE_ARRAY:
			for script in state_scripts:
				#if the script is targeted, we have an option to cancel there
				if script.get("subject") in ["target", "boardseek"]:
					show_optional_confirmation_menu = false
	if show_optional_confirmation_menu and !is_network_call:
		if !interaction_authorized:
			cfc.remove_ongoing_process(self, "core_execute_scripts")
			gameData.theStack.set_pending_network_interaction(interaction_authority, checksum, "pending interaction because of optional dialog")		
			return null

		gameData.select_current_playing_hero(interacting_hero)
		force_user_interaction_required = true	
		var confirm_return = cfc.ov_utils.confirm(
			self,
			{"is_optional_" + get_state_exec() : true},
			canonical_name,
			trigger,
			get_state_exec())
		if confirm_return is GDScriptFunctionState: # Still working.
			confirm_return = yield(confirm_return, "completed")
			# If the player chooses not to play an optional cost
			# We consider the whole cost dry run unsuccesful
			if not confirm_return:
				gameData.theStack.resume_operations_to_all(checksum)
				state_scripts = []
	
	# If the state_scripts return a dictionary entry
	# it means it's a multiple choice between two scripts
	if typeof(state_scripts) == TYPE_DICTIONARY:	
		var selected_key = ""
		if run_type == CFInt.RunType.BACKGROUND_COST_CHECK:
			selected_key = state_scripts.keys()[0]
			#TODO need to help check costs here as well?
		else:
			if !interaction_authorized:
				gameData.theStack.set_pending_network_interaction(interaction_authority, checksum, "not authorized to multiple choice " + to_json(state_scripts))
				cfc.remove_ongoing_process(self, "core_execute_scripts")
				return null	
			force_user_interaction_required = true				
			gameData.select_current_playing_hero(interacting_hero)
			var choices_menu = _CARD_CHOICES_SCENE.instance()
			cfc.add_modal_menu(choices_menu)
			choices_menu.prep(canonical_name,state_scripts, rules)
			if trigger != "manual":
				gameData.theAnnouncer.choices_menu(self, origin_event, choices_menu, interacting_hero)			
			# We have to wait until the player has finished selecting an option
			yield(choices_menu,"id_pressed")
			# If the player just closed the pop-up without choosing
			# an option, we don't execute anything
			selected_key = choices_menu.selected_key if choices_menu.id_selected else ""
			# Garbage cleanup
			cfc.remove_modal_menu(choices_menu)
			choices_menu.queue_free()
			if !selected_key:
				gameData.theStack.resume_operations_to_all(checksum)
		if selected_key:
			state_scripts = state_scripts[selected_key]
			action_name = selected_key
		else: 
			state_scripts = []

	# To avoid unnecessary operations
	# we evoke the ScriptingEngine only if we have something to execute
	# We do not statically type it as this causes a circular reference
	var sceng = null
	if len(state_scripts):
		if action_name:
			action_name = canonical_name + "(" + action_name + ")"
		else:
			action_name = canonical_name
		action_name = action_name + " - " + trigger
		action_name =  trigger_details.get("_display_name", action_name) #override		
		
		var next_step_config = {
			"trigger": trigger,
			"checksum": checksum,
			"rules": rules,
			"action_name": action_name,
			"force_user_interaction_required": force_user_interaction_required,
			"interaction_authority": interaction_authority,
		}
		sceng = execute_chosen_script(state_scripts, trigger_card, trigger_details, run_type, next_step_config)
		if sceng is GDScriptFunctionState && sceng.is_valid():		
			yield(sceng,"completed")
		
	cfc.remove_ongoing_process(self, "core_execute_scripts")	
	emit_signal("scripts_executed", self, sceng, trigger)
	return(sceng)

func execute_chosen_script(state_scripts, trigger_card,  trigger_details, run_type, exec_config: = {} ):
	var sceng = null
	is_executing_scripts = true

	var rules= exec_config.get("rules",{})
	var trigger = exec_config.get("trigger", "")
	var checksum = exec_config.get("checksum", "")
	var action_name = exec_config.get("action_name", "")
	var force_user_interaction_required = exec_config.get("force_user_interaction_required", false)
	var interaction_authority = exec_config.get("interaction_authority", null)
	
	var cost_check_mode = \
		CFInt.RunType.BACKGROUND_COST_CHECK if run_type == CFInt.RunType.BACKGROUND_COST_CHECK \
		else CFInt.RunType.COST_CHECK

	#Check if this script is exected from remote (another online player has been paying for the cost)
	var is_network_call = trigger_details.has("network_prepaid") #TODO MOVE OUTSIDE OF Core

	var only_cost_check = is_dry_run(run_type)

	#if optional tags are passed, merge them with this invocation
	if trigger_details.has("additional_tags"):
		var tags = trigger_details["additional_tags"]
		for t in state_scripts:
			t["tags"] = t.get("tags", []) + tags

	if trigger_details.has("additional_script_definition"):
		var additional_def = trigger_details["additional_script_definition"]
		for t in state_scripts:
			for def in additional_def:
				t[def] = additional_def[def]
			
	# This evocation of the ScriptingEngine, checks the card for
	# cost-defined tasks, and performs a dry-run on them
	# to ascertain whether they can all be paid,
	# before executing the card script.
	sceng = cfc.scripting_engine.new(
			state_scripts,
			self,
			trigger_card,
			trigger_details)

	sceng.add_rules(rules)				
			
	common_pre_run(sceng)
	
	# 1) Client A selects payments for ability locally
	# In case the script involves targetting, we need to wait on further
	# execution until targetting has completed
	var sceng_return = sceng.execute(cost_check_mode)
	#if not sceng.all_tasks_completed:
	if sceng_return is GDScriptFunctionState && sceng_return.is_valid():		
		yield(sceng_return,"completed")
	
	# If the dry-run of the ScriptingEngine returns that all
	# costs can be paid, then we proceed with the actual run
	# we add the script to the server stack for execution
	if (!is_network_call and not only_cost_check):
		if sceng.user_interaction_status == CFConst.USER_INTERACTION_STATUS.NOK_UNAUTHORIZED_USER:
			gameData.theStack.set_pending_network_interaction(interaction_authority,  checksum, "not authorized to pay cost")
			cfc.remove_ongoing_process(self, "core_execute_scripts")
			return sceng			
		if (sceng.can_all_costs_be_paid or sceng.has_else_condition()):
			#1.5) We run the script in "prime" mode again to choose targets
			# for all tasks that aren't costs but still need targets
			# (is_cost = false and needs_subject = false)
			sceng_return = sceng.execute(CFInt.RunType.PRIME_ONLY)
			#if not sceng.all_tasks_completed:
			if sceng_return is GDScriptFunctionState && sceng_return.is_valid():				
				yield(sceng_return,"completed")
			
			if sceng.user_interaction_status == CFConst.USER_INTERACTION_STATUS.NOK_UNAUTHORIZED_USER:
				gameData.theStack.set_pending_network_interaction(interaction_authority, checksum, "not authorized to prime")
				cfc.remove_ongoing_process(self, "core_execute_scripts")
				return sceng
			if sceng.user_interaction_status == CFConst.USER_INTERACTION_STATUS.DONE_INTERACTION_NOT_REQUIRED:
				if force_user_interaction_required:
					sceng.user_interaction_status = CFConst.USER_INTERACTION_STATUS.DONE_AUTHORIZED_USER
			
			if sceng.user_interaction_status == CFConst.USER_INTERACTION_STATUS.DONE_AUTHORIZED_USER:
				if trigger != "manual":		
					gameData.theStack.set_pending_network_interaction(interaction_authority, checksum, "authorized user ready to interact")
			
			# 2) Once done with payment, Client A sends ability + payment information to all clients (including itself)
			# 3) That data is added to all clients stacks

			if trigger_details.get("use_stack", true):
				var func_return = add_script_to_stack(sceng, run_type, trigger, trigger_details, action_name, checksum)
				while func_return is GDScriptFunctionState && func_return.is_valid():
					func_return = func_return.resume()
			else:
				sceng_return = sceng.execute(run_type)
				while sceng_return is GDScriptFunctionState && sceng_return.is_valid():
					sceng_return = sceng_return.resume()	

			
	is_executing_scripts = false
	return sceng

func add_script_to_stack(sceng, run_type, trigger, trigger_details, action_name, checksum):
	gameData.theStack.create_and_add_script(sceng, run_type, trigger, trigger_details, action_name, checksum) 
	
	return


# A signal for whenever the player clicks on a card
func _on_Card_gui_input(event) -> void:
	if !cfc.NMAP.has("board"):
		return
		
	cfc.add_ongoing_process(self, "_on_Card_gui_input_" + canonical_name)

	if event is InputEventMouseButton:	
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

			if event.doubleclick and (get_state_exec() == "hand"):
				attempt_to_play(true)
			# If it's a long click it might be because
			# they want to drag the card

			if state in [CardState.FOCUSED_IN_HAND]:
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
					# We need to reset it to the default of 0
					z_index = CFConst.Z_INDEX_BOARD_CARDS_NORMAL
					for attachment in self.attachments:
						attachment.z_index = CFConst.Z_INDEX_BOARD_CARDS_NORMAL

					var destination = cfc.NMAP.board
					if potential_container:
						destination = potential_container
						potential_container.highlight.set_highlight(false)

					#TODO
					#NOTE ERWAN
					#Modified here so that drag to board mimics the effect of a double click	
					var parentHost = get_parent()
					if (destination == cfc.NMAP.board) and (parentHost.is_in_group("hands")):
						move_to(parentHost)
						attempt_to_play(true)
					else :	
						move_to(destination)
					_focus_completed = false
				_:
					if state != CardState.FOCUSED_IN_HAND:
						attempt_to_play(true)
		else:
			_process_more_card_inputs(event)
	elif event is InputEvent:
		if event.is_action_pressed("ui_accept"):
			attempt_to_play(true)
	else:
		var _tmp = 1
	cfc.remove_ongoing_process(self, "_on_Card_gui_input_"  + canonical_name)	

# Game specific code and/or shortcuts
func readyme(toggle := false,
			start_tween := true,
			check := false,
			tags := ["Manual"]) :
	
	var rot = 0
	if CFConst.OPTIONS.get("enable_fuzzy_rotations", false):
		if (is_exhausted()):			
			rot = randi() % 11 - 5
			tags = tags + ["force"]
			
	var retcode = set_card_rotation(rot, toggle, start_tween, check, tags)
	if !check and retcode != CFConst.ReturnCode.FAILED:
		_is_exhausted = false
	return retcode
	
func exhaustme(toggle := false,
			start_tween := true,
			check := false,
			tags := ["Manual"]) :
				
	var rot = 90	
	if CFConst.OPTIONS.get("enable_fuzzy_rotations",false):
		if (!is_exhausted()):			
			rot = randi() % 16 + 80
			tags = tags + ["force"]
			
	if 	is_exhausted()	and not toggle:
		return CFConst.ReturnCode.OK		
					
	var retcode = set_card_rotation(rot, toggle, start_tween, check, tags)
	if !check and retcode != CFConst.ReturnCode.FAILED:
		_is_exhausted = true
	return retcode	

func is_ready() :
	return !_is_exhausted

func is_exhausted():
	return _is_exhausted
	
func add_threat(threat : int):
	tokens.mod_token("threat",threat)	

func get_current_threat():
	return tokens.get_token_count("threat")

func check_scheme_defeat(script):
	if get_current_threat() <= 0:
	#card.die(script)
		if get_property("cannot_leave_play", 0):
			return
			
		var card_dies_definition = {
			"name": "card_dies",
			"tags": ["remove_threat", "Scripted"] + script.get_property(SP.KEY_TAGS)
		}
		var trigger_details = script.trigger_details.duplicate(true)
		trigger_details["source"] = guidMaster.get_guid(script.owner)

		var card_dies_script:ScriptTask = ScriptTask.new(self, card_dies_definition, script.trigger_object, trigger_details)
		card_dies_script.subjects = [self]

		var task_event = SimplifiedStackScript.new( card_dies_script)
		gameData.theStack.add_script(task_event)


func remove_threat(modification: int, script = null) -> int:
	
	#Crisis special case: can't remove threat from main scheme
	if script and script.has_tag("bypass_crisis"):
		pass
	else:
		if "main_scheme" == properties.get("type_code", "false"):
			var all_schemes:Array = cfc.NMAP.board.get_all_cards_by_property("type_code", "side_scheme")
			all_schemes.append(self) #some main schemes such as countdown to oblivion give themselves crisis
			for scheme in all_schemes:
				#we add all acceleration tokens	
				var crisis = scheme.get_property("scheme_crisis", 0, true)
				if crisis:
					scheme.hint("Crisis!", Color8(200, 50, 50))
					self.hint("Crisis!", Color8(200, 50, 50))
					return CFConst.ReturnCode.FAILED
					
	var token_name = "threat"
	var current_tokens = tokens.get_token_count(token_name)
	if current_tokens - modification < 0:
		modification = current_tokens
	var result = tokens.mod_token(token_name,-modification)
			
	return result

func discard():
	#cleanup some variables
	set_is_boost(false)
	
	#move to correct pile
	var hero_owner_id = get_owner_hero_id()
	if (!hero_owner_id):
		self.move_to(cfc.NMAP["discard_villain"])
	else:
		var destination = "discard" + str(hero_owner_id)
		self.move_to(cfc.NMAP[destination])

#returns the amount of healing that could happen for a given heal value
func can_heal(value):
	var current_damage = tokens.get_token_count("damage")
	return min(value, current_damage)	

func heal(value):
	var current_damage = tokens.get_token_count("damage")
	var heal_value = min(value, current_damage)
	return tokens.mod_token("damage",-heal_value)


func common_pre_execution_scripts(_trigger_card, _trigger: String, _trigger_details: Dictionary) -> void:
	match _trigger:
		"enemy_attack":
			gameData.compute_potential_defenders(gameData.get_current_activity_hero_target(), _trigger_card)

func can_defend(hero_id = 0):
	if is_exhausted() : return false

	var type_code = get_property("type_code", "")
	if type_code != "hero" and type_code != "ally": return false
	
	if hero_id:
		if get_controller_hero_id() != hero_id:
			return false
	
	return true


func die(script):
	var type_code = properties.get("type_code", "")
	var trigger_details = {}
	if script:
		trigger_details = script.trigger_details
	match type_code:
		"hero", "alter_ego":
			gameData.hero_died(self, script)
		"ally", "minion":
			gameData.character_died(self, script)
		"side_scheme":
			move_to(cfc.NMAP["discard_villain"])	
		"villain":
			gameData.villain_died(self, script)
		_:
			self.discard()
			
	scripting_bus.emit_signal("card_defeated", self, trigger_details)			
	return CFConst.ReturnCode.OK		

var _cached_state = -1
func _process_card_state() -> void:
	
	#if state hasn't changed and we're on a low fps machine,
	#reduce calls to this function
	if _cached_state == state:
		if cfc.throttle_process_for_performance():
			return

	_cached_state = state	
	._process_card_state()

	#TODO bug?
	#sometimes the card reports being "faceup" while actually showing the back
	#this is a fix for that
	if _card_back_container.visible == is_faceup:
		is_faceup = !is_faceup
		set_is_faceup(!is_faceup, true)
	match state:
		CardState.ON_PLAY_BOARD:
			#horizontal cards are always forced to horizontal
			#does that need to change eventually ?	
			#note: setting tweening to false otherwise it causes issues with
			#tweening never ending
			if _horizontal and not _is_boost:
				set_card_rotation(90, false, false)




#checks executable scripts for cards in discard pile,
#and attempts to create a "ghost" card in hand if needed
func check_ghost_card():
	for i in range(gameData.get_team_size()):
		cfc.NMAP["ghosthand" + str(i+1)].check_ghost_card(self)
	
# This function can be overriden by any class extending Card, in order to provide
# a way of checking if a card can be played before dragging it out of the hand.
#
# This method will be called while the card is being focused by the player
# If it returns true, the card will be highlighted as normal and the player
# will be able to drag it out of the hand
#
# If it returns false, the card will be highlighted with a red tint, and the
# player will not be able to drag it out of the hand.
func check_play_costs_no_cache(hero_id, _debug = false)-> Color:
	_check_play_costs_cache[hero_id] = CFConst.CostsState.CACHE_INVALID
	return check_play_costs({"hero_id" : hero_id}, _debug)

	
func check_play_costs(params:Dictionary = {}, _debug = false) -> Color:
	#return .check_play_costs();
	var hero_id = params.get("hero_id", gameData.get_current_local_hero_id())

	
	if (_check_play_costs_cache.get(hero_id,CFConst.CostsState.CACHE_INVALID) != CFConst.CostsState.CACHE_INVALID):
		return _check_play_costs_cache[hero_id]
	
	_check_play_costs_cache[hero_id] = CFConst.CostsState.IMPOSSIBLE

	#skip if card is not in hand and not on board. TODO: will have to take into account cards than can be played from other places
	var state_exec = get_state_exec()

	if !(state_exec in ["hand", "board"]):
		return _check_play_costs_cache[hero_id]
	


	
	var trigger_details = {
		"for_hero_id": hero_id,
		"_debug": _debug
	}
		
	var sceng = execute_scripts(self,"manual",trigger_details,CFInt.RunType.BACKGROUND_COST_CHECK)

	if (!sceng): #TODO is this an error?
		_check_play_costs_cache[hero_id] = CFConst.CostsState.IMPOSSIBLE	
		return _check_play_costs_cache[hero_id]
		
	while sceng is GDScriptFunctionState && sceng.is_valid(): # Still working.
		sceng = sceng.resume()
		#sceng = yield(sceng, "completed")

	if (!sceng): #TODO is this an error?
		_check_play_costs_cache[hero_id] = CFConst.CostsState.IMPOSSIBLE	
		return _check_play_costs_cache[hero_id]
	
	if (sceng.can_all_costs_be_paid):
		_check_play_costs_cache[hero_id] = CFConst.CostsState.OK


	return _check_play_costs_cache[hero_id]


# This function can be overriden by any class extending Card, in order to provide
# a way of running special functions on an extended scripting engine.
#
# It is called after the scripting engine is initiated, but before it's run
# the first time
#
# Used to hijack the scripts at runtime if needed
# Current use case: check manapool before asking to pay for cards
func common_pre_run(sceng) -> void:
	var trigger_details = sceng.trigger_details
	
	var controller_hero_id = trigger_details.get("override_controller_id", self.get_controller_hero_id())
	
	var scripts_queue: Array = sceng.scripts_queue
	var new_queue: Array = []
	var temp_queue: Array = []
	
	var zones = ["hand"] + CFConst.HERO_GRID_SETUP.keys()
		
#	if sceng.additional_rules.has("for_each_player"):
#		for i in gameData.get_team_size():
#			var hero_queue = scripts_queue.duplicate()
#			var hero_id = i+1
#			for task in hero_queue:
#				var script: ScriptTask = task
#				var script_definition = script.script_definition
#				var new_script_definition = script_definition.duplicate(true)
#				new_script_definition.erase("for_each_player")
#				for v in zones: # ["hand", "encounters_facedown","deck" ,"discard","enemies","identity","allies","upgrade_support"]:
#					new_script_definition = WCUtils.search_and_replace(new_script_definition, v, v+str(hero_id), true)	
#
#				new_script_definition = WCUtils.search_and_replace(new_script_definition, "their_identity", "identity_" + str(hero_id), true)	
#
#				var new_script = ScriptTask.new(script.owner, new_script_definition, script.trigger_object, script.trigger_details)
#				new_queue.append(new_script)
#		scripts_queue = new_queue
#		new_queue = []
				
	for task in scripts_queue:
		var script: ScriptTask = task
		var script_definition = script.script_definition
		var scripts = [script]
		if script_definition.get("for_each_player", false):	
			scripts = []
			for i in gameData.get_team_size():
				var hero_id = i+1
				var new_script_definition = script_definition.duplicate(true)
				new_script_definition.erase("for_each_player")
				for v in zones: #["hand", "encounters_facedown","deck" ,"discard","enemies","identity","allies","upgrade_support"]:
					new_script_definition = WCUtils.search_and_replace(new_script_definition, v, v+str(hero_id), true)	

				var new_script = ScriptTask.new(script.owner, new_script_definition, script.trigger_object, script.trigger_details)
				scripts.append(new_script)
		for _script in scripts:
			temp_queue.append(_script)
	
	scripts_queue = temp_queue	

	
	for task in scripts_queue:
		var script: ScriptTask = task
		var script_definition = script.script_definition			
		var replacements = {}
		for v in zones:
			replacements[v + "_first_player"] = v+str(gameData.first_player_hero_id())
		#first player explcitely mentioned
		script_definition = WCUtils.search_and_replace_multi(script_definition, replacements , true)	
		replacements = {}
		
		if (controller_hero_id <=0 ):
			var card_type = task.owner.get_property("type_code")
			if card_type in ["scheme", "main_scheme", "minion", "side_scheme", "treachery"]:
				pass
			else:
				cfc.LOG("error controller hero id is not set for script:" + task.script_name )
		else:
			#var current_hero_id = gameData.get_current_hero_id()
			for v in zones:
				#TODO move to const
				replacements[v] = v+str(controller_hero_id)


				#any_discard, etc gets replaced with ["discard1","discard2"] 
				var team_size = gameData.get_team_size()
				var any_container_def = []
				for i in range (team_size):
					any_container_def.append(v + str(i+1))
				if any_container_def.size() == 1:
					any_container_def = any_container_def[0]
				replacements["any_" + v] = any_container_def	
			script_definition = WCUtils.search_and_replace_multi(script_definition, replacements , true)	
	
		#put back the modified script			
		script.script_definition = script_definition
				
		match script_definition["name"]:
			# To pay for cards: We check if the manapool has some mana
			# If so, use that in "priority" and reduce the actual cost of the card
			# We then replace the "pay" trigger with a combination of
			# 1) discard the appropriate number of cards from hand (minored by what's available in manapool)
			# 2) empty the manapool
			"pay_cost",\
			"pay_regular_cost":
				var new_script = pay_regular_cost_replacement(script_definition, trigger_details)
				if (new_script) :
					script.script_definition = new_script
					script.script_name = script.get_property("name") #TODO something cleaner? Maybe part of the script itself?
					new_queue.append(script)
			"end_phase_discard":
				#end phase discard is either optional, or forced if we're above max_hand_size
				var hero = script.owner
				var max_hand_size = hero.get_max_hand_size()
				var hero_id = hero.get_controller_hero_id()
				var hand:Hand = cfc.NMAP["hand" + str(hero_id)]
				var current_hand_size = hand.get_card_count()
				var min_to_discard = 0
				if (current_hand_size > max_hand_size):
					min_to_discard = current_hand_size - max_hand_size
				script.script_name = "move_card_to_container"
				script.script_definition["name"] = script.script_name
				if (min_to_discard > 0):
					script.script_definition["selection_optional"] = false
					script.script_definition["selection_count"] = min_to_discard

				new_queue.append(script)
			"enemy_attack":
				var attacker = script.owner
				var modifiers = attacker.retrieve_scripts("modifiers")
				var defense_selection_modifier = modifiers.get("defense_selection", "")
				match defense_selection_modifier:
					#TODO this is split with GameData.compute_defenders(), need a cleaner, centralized place
					"my_allies_if_able":
						var defenders = cfc.get_tree().get_nodes_in_group("group_defenders")
						var found_ally = false
						for c in defenders:
							if c.get_property("type_code") == "ally":
								found_ally = true
								break
						if found_ally:
							script.script_definition[SP.KEY_SELECTION_TYPE] = "equal"
							script.script_definition[SP.KEY_SELECTION_OPTIONAL] = false
				new_queue.append(script)							
			_:
				new_queue.append(task)
	sceng.scripts_queue = new_queue	

#TODO cleanup, probably doesn't need to be a replacement
func pay_regular_cost_replacement(script_definition: Dictionary, trigger_details) -> Dictionary:	
	var owner_hero_id = trigger_details.get("override_controller_id", self.get_owner_hero_id())

	# For cards owned by the Villain, owner_hero_id is zero.
	# we set it to the current playing hero, meaning the currently active user
	# can pay the cost
	#TODO how does it work in Multiplayer?
	if (!owner_hero_id):
		owner_hero_id = gameData.get_current_local_hero_id()
			
	var manacost:ManaCost = ManaCost.new()
	var cost = script_definition["cost"]
	var is_optional = script_definition.get(SP.KEY_SELECTION_OPTIONAL, true)
	#precompute cost replacement macros
	if (typeof(cost) == TYPE_STRING):
		if cost == "card_cost":
			cost = self.get_property("cost")

	var selection_additional_constraints = null
	if (typeof(cost) == TYPE_DICTIONARY):
		manacost.init_from_dictionary(cost)
		selection_additional_constraints = {
			"func_name": "can_pay_as_resource",
			"using": "all_selection",
			"func_params": cost 
		}
	else:
		manacost.init_from_expression(cost) #TODO better name?
	
	var resource_container_names = ["hand", "identity","allies","upgrade_support"]
	var resource_containers = []
	for v in resource_container_names:
		resource_containers.append(v + str(owner_hero_id) )
		
	var result  ={
				"name": "pay_as_resource",
				"is_cost": true,
				"subject": "index",
				"subject_count": "all",
				"subject_index": "top",
				SP.KEY_NEEDS_SELECTION: true,
				SP.KEY_SELECTION_COUNT: manacost.converted_mana_cost(), #TODO put real missing cost here
				SP.KEY_SELECTION_TYPE: "min",
				SP.KEY_SELECTION_OPTIONAL: is_optional,
				SP.KEY_SELECTION_IGNORE_SELF: true,
				"selection_what_to_count": "get_resource_value_as_int",
				"selection_additional_constraints": selection_additional_constraints,
				"src_container": resource_containers
			}		

	return result	

func get_grid_name():
	if (_placement_slot):
		return _placement_slot.get_grid_name()
	return null	

#
#Marvel Champions Specific functionality
#

#easy access functions for tokens that are either 1 or 0
func is_token_set(token_name):
	return tokens.get_token_count(token_name) > 0

func enable_token(token_name, value:bool):
	if value:
		tokens.mod_token(token_name, 1, true)
	else:
		tokens.mod_token(token_name, 0, true)	

func is_stunned() -> bool:
	return is_token_set("stunned")

func set_stunned(value:bool = true):
	enable_token("stunned", value)

func remove_stun():
	set_stunned(false)

func is_confused() -> bool:
	return is_token_set("confused")

func set_confused(value:bool = true):
	enable_token("confused", value)

func disable_confused():
	set_confused(false)

func can_change_form() -> bool:
	return _can_change_form

func changed_form(details):
	var before = details.get("before")
	#hopefully after and before are actually different...
	var after = "alter_ego" if self.is_alter_ego_form() else "hero"		
	var stackEvent:SignalStackScript = SignalStackScript.new("identity_changed_form", self, {"before": before , "after" : after })
	gameData.theStack.add_script(stackEvent)		
#	scripting_bus.emit_signal("identity_changed_form", new_card, {"before": before , "after" : after } )
	

func change_form(voluntary = true) -> bool:
	#players have one voluntary change form per turn
	#we check for that
	if (voluntary):
		if !can_change_form():
			return false
		self._can_change_form = false


	var new_card = cfc.NMAP.board.flip_doublesided_card(self)
	if !new_card:
		var _error = 1
		return false
		
	return true

#a way to copy all modifications of this card to another card
#used e.g. when flipping card
func export_modifiers():
	var result = {
		"tokens" : tokens.export_to_json(),
		"exhausted" : self.is_exhausted(),
		"can_change_form": self._can_change_form
	}
	return result

#changes data of the card based on a dictionary
#this is different from loading from json because
# 1) it only impacts some variables, not all,
# 2) it doesn't reset to a default value if the modifier isn't set
func import_modifiers(modifiers:Dictionary):
	var token_data = modifiers.get("tokens", {})
	if token_data:
		tokens.load_from_json(token_data)
	
	if modifiers.has("exhausted"):
		if modifiers["exhausted"]:
			exhaustme()
		else:
			readyme()
			
	self._can_change_form = modifiers.get("can_change_form", self._can_change_form)	

func is_onboard():
	return state in [
		CardState.ON_PLAY_BOARD,
		CardState.FOCUSED_ON_BOARD, 
		CardState.DROPPING_TO_BOARD
	]
	
func is_onboard_facedown():
	return !is_faceup and is_onboard()

var _hidden_properties = {}
func set_is_faceup(
			value: bool,
			instant := false,
			check := false,
			tags := ["Manual"]) -> int:
	var _before = is_faceup			
	var retcode = .set_is_faceup(value, instant, check, tags)
	var _after = is_faceup
	
	if check:
		return retcode
	
	if value:
		#initiate the card art if it's the first time we're setting this faceup
		set_card_art()
			
	#we remove all of the card's properties as long as it's facedown on the board,
	#to avoid triggering any weird things
	if is_onboard_facedown():
		if !_hidden_properties:
			_hidden_properties = properties
			properties = {}
			#a few variables we still need to avoid a crash:
			for property in ["_code", "code"]:
				properties[property] = _hidden_properties.get(property, "")
	else:
		if _hidden_properties:
			var temp_properties = properties
			properties = _hidden_properties
			
			for property in temp_properties:
				if property in ["_code", "code"]:
					continue
				scripting_bus.emit_signal(
						"card_properties_modified",
						self,
						{
							"property_name": property,
							"new_property_value": properties.get(property),
							"previous_property_value": temp_properties[property],
							"tags": ["Scripted", "set_is_faceup"]
						}
				)				
			if scripts:
				cfc.LOG("removing extra scripts from card " + canonical_name + " as we turn it faceup")
				scripts = {}				
			
			_hidden_properties = {}
	
	return retcode	
		
	
func copy_modifiers_to(to_card:WCCard):
	var modifiers = export_modifiers()
	to_card.import_modifiers(modifiers)

func draw_boost_card():
	var villain_deck:Pile = cfc.NMAP["deck_villain"]	
	var boost_card:Card = villain_deck.get_top_card()
	if boost_card:
		boost_card.set_is_boost(true)
		boost_card.attach_to_host(self) #,false, ["facedown"])
		boost_card.set_is_faceup(false)

func draw_boost_cards(action_type):
	var amount = self.get_property("boost_cards_per_" + action_type, 0)
	for i in amount:
		draw_boost_card()
	#TODO if pile empty...need to reshuffle ?

#returns an array of allowed triggers,
# or "true" if all scripts allowed
func can_execute_scripts():
	#checks for cases where we don't want to execute scripts on this card	
	if self.is_boost():
		return ['boost']
	return true

func get_boost_cards(flip_status:int = CFConst.FLIP_STATUS.BOTH):
	var results = []
	for card in self.attachments:
		if (!card.is_boost()):
			continue
		if (card.is_faceup and flip_status == CFConst.FLIP_STATUS.FACEDOWN):
			continue
		if (!card.is_faceup and flip_status == CFConst.FLIP_STATUS.FACEUP):
			continue			
		results.append(card)

	return results	 

func next_boost_card_to_reveal():
	var boost_card = null
	for card in self.attachments:
		if (!card.is_boost()):
			continue
		if (card.is_faceup):
			continue
		boost_card = card
		break
	return boost_card

#returns scripts specific to this instance
func get_instance_runtime_scripts(trigger:String = "", filters:={}) -> Dictionary:
	#if we have no extra scripts we stick with parent behavior
	if !extra_scripts:
		return .get_instance_runtime_scripts(trigger)
		
	#if we have extra scripts, we'll do a merge of extra scripts
	#with the cards script, then retrieve from the merged dictionary
	var merged_scripts:Dictionary = .get_instance_runtime_scripts()
	if !merged_scripts:
		merged_scripts = cfc.set_scripts.get(canonical_id,{}).duplicate(true)
	
	#additional scripts to merge with what we found
	var requesting_hero_id = filters.get("requesting_hero_id", 0) 
	for key in extra_scripts:
		var extra_script = extra_scripts[key]["script_definition"]
		var controller_id = extra_scripts[key].get("controller_id", 0)
		if requesting_hero_id and controller_id and (requesting_hero_id != controller_id):
			continue
		merged_scripts = WCUtils.merge_dict(merged_scripts, extra_script, true)

	var found_scripts = {}
	match trigger:
		"":
			found_scripts = merged_scripts.duplicate(true)
		_:
			found_scripts = merged_scripts.get(trigger,{}).duplicate(true)
	
	return found_scripts



func set_activity_script(script):
	activity_script = script
	if script:
		gameData.set_latest_activity_script(script)

# For boost cards to know who's calling them
var _current_activation_details = null
func set_current_activation(script):
	if _current_activation_details:
		var _error = 1
	_current_activation_details = script

func get_current_activation_details():
	return _current_activation_details
	
func remove_current_activation(script):	
	if _current_activation_details != script:
		var _error = 1
	_current_activation_details = null

#
#FUNCTIONS USED DIRECTLY BY JSON SCRIPTS
#

func count_attachments(params = {}, script:ScriptTask = null) -> int:
	var subjects = [self]

	if script:
		subjects = script._local_find_subjects(0, CFInt.RunType.NORMAL, params)
					
	if !subjects:
		return 0	
	
	var ret := 0
	
	if params.get("filter_state_attachment", []):
		for card in subjects:
			for attachment in card.attachments:
				var script_owner = self
				if script:
					script_owner = script.owner 
				if SP.check_validity(attachment, params, "attachment", script_owner):
					ret+= 1
	else:
		for card in subjects:
			ret += card.attachments.size()
	return(ret)

func is_hero_form(params = {}, script:ScriptTask = null) -> bool:
	var subject = self

	if script:
		subject = null
		var subjects = script._local_find_subjects(0, CFInt.RunType.NORMAL, params)
		if subjects:
			subject = subjects[0]
					
	if !subject:
		return false	
	
	if "hero" == subject.properties.get("type_code", ""):
		return true
	return false
	
func is_alter_ego_form(params = {}, script:ScriptTask = null) -> bool:
	var subject = self

	if script:
		subject = null
		var subjects = script._local_find_subjects(0, CFInt.RunType.NORMAL, params)
		if subjects:
			subject = subjects[0]
			
	if !subject:
		return false
		
	if "alter_ego" == subject.properties.get("type_code", ""):
		return true
	return false

func get_script_bool_property(params, script:ScriptTask = null) -> bool:
	var property = params.get("property", "")
	if !property:
		return false
	return script.get_property(property, false)
	
func get_subject_int_property(params, script:ScriptTask = null) -> int:
	var subject = self
	if script:
		subject = null
		var subjects = script._local_find_subjects(0, CFInt.RunType.NORMAL, params)
		if subjects:
			subject = subjects[0]
	if !subject:
		return 0
	
	var property = params.get("property", "")
	if !property:
		return 0
	return subject.get_property(property, 0)	

func count_tokens(params, script:ScriptTask = null) -> int:
	var subjects = [self]
	var token_names = params.get("token_name", [])
	if typeof(token_names) == TYPE_STRING:
		token_names = [token_names]
	
	if script:
		subjects = script._local_find_subjects(0, CFInt.RunType.NORMAL, params)
			
	if !subjects:
		return 0
	
	var count = 0
	for subject in subjects:
		for token_name in token_names:
			count+= subject.tokens.get_token_count(token_name)
	
	return count

#returns true if this card (or script subject) has a given trait
func has_trait(params, script:ScriptTask = null) -> bool:
	var subject = self
	
	var and_or = "or"
	
	if script:
		subject = null
		var subjects = script._local_find_subjects(0, CFInt.RunType.NORMAL, params)
		if subjects:
			subject = subjects[0]
			
	var traits = []
	match typeof(params):
		TYPE_DICTIONARY:
			and_or = params.get("and_or", and_or)
			traits = params.get("trait", "")
		TYPE_STRING:
			traits = params
		_:
			return false

	if typeof(traits) == TYPE_STRING:
		traits = [traits]

	if !traits:
		return false
	for trait in traits:
		trait = "trait_" + trait
		if and_or =="or":
			if subject.get_property(trait, 0, true):
				return true
		else:
			if !subject.get_property(trait, 0, true):
				return false
	if and_or =="or":
		return false
	return true

func identity_has_trait(params, script:ScriptTask = null) -> bool:
	var hero = get_controller_hero_card()
	return hero.has_trait(params)	

func get_hero_id(params, script:ScriptTask = null) -> int:
	var hero_name = params.get("name")
	if !hero_name:
		return 1 #default to avoid crashes

	var hero_card = cfc.NMAP.board.find_card_by_name(hero_name, true)
	if !hero_card:
		return 1 #default to avoid crashes
	
	return hero_card.get_controller_hero_id()	

func get_aspect(params, script:ScriptTask = null) -> String:
	var subject = self
	
	if script:
		subject = null
		var subjects = script._local_find_subjects(0, CFInt.RunType.NORMAL, params)
		if subjects:
			subject = subjects[0]
			
	if !subject:
		return ""
	
	var aspect = subject.get_property("faction_code", "")
	if aspect == "basic":
		aspect = ""
	return aspect

func card_is_in_play(params, script:ScriptTask = null) -> bool:
	var card_name = params.get("card_name", "")
	if !card_name:
		return false
	var card = cfc.NMAP.board.find_card_by_name(card_name)
	if !card:
		return false
	return true

func current_activation_status(params:Dictionary, _script:ScriptTask = null) -> bool:
#	var script = get_current_activation_details()
	var script = gameData.get_latest_activity_script()
	if !script:
		return false
	var expected_activation_type = params.get("type", "")	
	var undefended = params.get("undefended", null)
	if null != undefended:
		expected_activation_type = "attack"
	
	match expected_activation_type:
		"attack":
			if not script.script_name in ["enemy_attack", "undefend"]:
				return false
		"scheme":
			if not script.script_name in ["commit_scheme"]:
				return false
		"":
			pass			
		_:
			return false	
	
	if null != undefended:
		if undefended and script.subjects:
			if !script.has_tag("undefended"):
				return false
		if !undefended and !scripts.subjects:
			return false
			
	return true				 	

#returns true if this card was paid for with (at least) resources described by params
#e.g if you paid 3 physical plus 1 mental for a card, 
#it would say true to {"mental": 1}, to {"physical" : 2}, or to {"mental" :1, "physical": 1}
#but false to {"mental": 2}, or {"mental": 1, "wild": 1} 
func paid_with_includes(params:Dictionary, script:ScriptTask = null) -> bool:
	var paid_with = ManaPool.new()
	for resource in _last_paid_with:
		paid_with.add_manacost(resource)

	var compared_to = ManaCost.new()
	compared_to.init_from_dictionary(params)
	
	return paid_with.can_pay_total_cost(compared_to)

func count_printed_resources(params:Dictionary, script) -> int:
	var mana = ManaCost.new()
	var subjects = script._local_find_subjects(0, CFInt.RunType.NORMAL, params)	

	while subjects is GDScriptFunctionState && subjects.is_valid():
		subjects = subjects.resume()	
	if !subjects:
		cfc.LOG("error retrieving subjects for " + to_json(params))
		return 0
		
	for subject in subjects:
		var printed_resource = subject.get_printed_resource_value_as_mana()
		mana.add_manacost(printed_resource)
	var count = 0
	if params.has("resource_type"):
		count = mana.get_resource(params["resource_type"])
	else:
		count = mana.converted_mana_cost()
	return count
	
func count_boost_icons(params:Dictionary, script) -> int:
	var subjects = script._local_find_subjects(0, CFInt.RunType.NORMAL, params)	
	var count = 0
	
	while subjects is GDScriptFunctionState && subjects.is_valid():
		subjects = subjects.resume()	
	if !subjects:
		cfc.LOG("error retrieving subjects for " + to_json(params))
		return 0
		
	for subject in subjects:
		var boost_icons = subject.get_property("boost", 0)
		count+= boost_icons

	return count	

func count_resource_types(params:Dictionary, script) -> int:
	var mana = ManaCost.new()
	var subjects = script._local_find_subjects(0, CFInt.RunType.NORMAL, params)	
	for subject in subjects:
		var printed_resource = subject.get_printed_resource_value_as_mana()
		mana.add_manacost(printed_resource)
	var count = mana.count_resource_types()
	return count
	
func get_sustained_damage(params:Dictionary = {}, script = null) -> int:
	var subject = self
	if params and script and params.has("subject"):
		var subjects = SP.retrieve_subjects(params.get("subject"), script)
		if !subjects:
			return 0
		subject = subjects[0]
	return subject.tokens.get_token_count("damage")

func get_remaining_damage(params:Dictionary = {}, script = null) -> int:
	var subject = self
	if params and script and params.has("subject"):
		var subjects = SP.retrieve_subjects(params.get("subject"), script)
		if !subjects:
			return 0
		subject = subjects[0]
	
	var current_damage = subject.tokens.get_token_count("damage")
	var health = subject.get_property("health", 0)
	var diff = health - current_damage
	if diff <= 0:
		return 0
	return diff	

#
# RESOURCE FUNCTIONS
#

func set_last_paid_with(manacost_array:Array):
	_last_paid_with = manacost_array

func pay_as_resource(script):
	cfc.add_ongoing_process(self, "pay_as_resource")

	#generate a summary of resources generated
	var result_mana = get_resource_value_as_mana(script)


	#reload and re_run the script from scratch, up to execution
	#var exe_sceng = self.execute_scripts(self, "resource", {})	
	#below is a convoluted way to force execute the sript locally without going through the network stack,
	#specifically for payments
	#two reasons for that:
	#1) spare a network trip
	#2) because of the Network delay, I suspect I've seen bugs where the payment is processed
	# after the card is played, leading to desync between the players
	var delegate = {}
	var hero_id = 0
	var owner_card = script.owner
	if owner_card:
		hero_id = owner_card.get_controller_hero_id()
	if hero_id:
		delegate = {"for_hero_id" : hero_id}
	var exe_sceng = self.execute_scripts_no_stack(self, "resource", delegate)				
	while exe_sceng is GDScriptFunctionState && exe_sceng.is_valid():
		exe_sceng  = exe_sceng.resume()	

	if (get_state_exec()) == "hand":
		self.discard()
	cfc.remove_ongoing_process(self, "pay_as_resource")
	return result_mana

func _get_resource_sceng(script):
	#var my_state = _state if _state else get_state_exec()
	var trigger_card = script.owner
	var trigger_details = {}
	var card_scripts = retrieve_filtered_scripts(trigger_card, "resource", trigger_details)	
	var state_scripts = get_state_scripts(card_scripts, trigger_card, trigger_details)
	
	if !state_scripts:
		return null
	
	var sceng = cfc.scripting_engine.new(
		state_scripts,
			self,
			trigger_card,
			trigger_details)	
	
	return sceng


#computes how much resources this card would generate as part of a payment
#this uses its "resource" script in priority (for card that have either special resource abilities,
#or cards that modify their resource based on some scripted conditions - e.g. The Power of Justice
func get_resource_value_as_mana(script):
	var cache_key = {
		"owner": script.owner
	}.hash()
	
	if _cache_resource_value.has(cache_key):
		return _cache_resource_value[cache_key]

		
	var my_state = get_state_exec()
	var sceng = _get_resource_sceng(script)
	var result_mana:ManaCost = ManaCost.new()
	
	if sceng:
		common_pre_run(sceng)
		
		var func_return = sceng.execute(CFInt.RunType.BACKGROUND_COST_CHECK)
		while func_return is GDScriptFunctionState && func_return.is_valid():
			func_return = func_return.resume()
		
		if (sceng.can_all_costs_be_paid):
			# run in precompute mode to try and calculate how much resources this would give us
			func_return = sceng.execute(CFInt.RunType.PRECOMPUTE)
			while func_return is GDScriptFunctionState && func_return.is_valid():
				func_return = func_return.resume()
				
			var results = sceng.get_precompute_objects()
			if (results):
				for result in results:
					if result as ManaCost:
						result_mana.add_manacost(result)
				_cache_resource_value[cache_key] = result_mana		
				return _cache_resource_value[cache_key]			
	
	#if the compute didn't get through, we return the regular printed value
	if (my_state) == "hand":
		if (canonical_name == "The Power of Justice" and get_state_exec() == "hand"):
			var _tmp = 1	
		_cache_resource_value[cache_key]  = get_printed_resource_value_as_mana(script)	
		return _cache_resource_value[cache_key]
	
	_cache_resource_value[cache_key] = null
	return _cache_resource_value[cache_key]

func get_resource_value_as_int(script):
	if (canonical_name == "The Power of Justice" and get_state_exec() == "hand"):
		var _tmp = 1
	var result_mana:ManaCost = get_resource_value_as_mana(script)
	
	if !result_mana:		
		return 0
	
	return result_mana.converted_mana_cost()
		

func get_printed_resource_value_as_mana(_script= null):
	var resource_dict = {}
	for resource_name in ManaCost.RESOURCE_TEXT:
		var lc_name = resource_name.to_lower()
		var value = get_property("resource_" + lc_name, 0)
		if value:
			resource_dict[lc_name] = value
	var resource_mana = ManaCost.new()
	resource_mana.init_from_dictionary(resource_dict)
	return resource_mana

func get_printed_resource_value_as_int(script):
	var total = 0
	for resource_name in ManaCost.RESOURCE_TEXT:
		var lc_name = resource_name.to_lower()
		total += get_property("resource_" + lc_name, 0)
	return total

#
# OTHER FUNCTIONS
#

func display_debug(msg):
	gameData.display_debug("(WCCard - " + canonical_name +") " + msg)



func get_remaining_threat():
	var current_threat = self.tokens.get_token_count("threat")
	return current_threat

#used for some scripts
func get_remaining_indirect_damage():
	return get_remaining_damage()
	
func get_max_hand_size():
	var max_hand_size = get_property("max_hand_size", 0)
	var hand_size =  get_property("hand_size", 0)

	if max_hand_size:
		hand_size = min(max_hand_size, hand_size)
		
	return hand_size

func init_token_drawer():
	#set token drawer to disable manipulation buttons
	tokens.show_manipulation_buttons = false
	#tokens with a max value
	for token_name in CFConst.DEFAULT_TOKEN_MAX_VALUE.keys():
		var value = CFConst.DEFAULT_TOKEN_MAX_VALUE[token_name]
		tokens.set_max(token_name, value)

func get_keywords () -> Dictionary:
	return get_property("keywords", {})

func get_keyword(name):
	var keywords:Dictionary = get_keywords ()
	return keywords.get(name.to_lower(), false)
	
func get_unique_name() -> String:
	var subname = get_property("subname")
	if !subname:
		subname = ""		
	return canonical_name + " - " + subname

#used for save/load	
func export_to_json():
	var owner_hero_id = self.get_owner_hero_id()
	var card_id = self.properties.get("_code")
	var tokens_to_json = self.tokens.export_to_json()
	var card_description = {
		"card" : card_id,
		"owner_hero_id": owner_hero_id,
		"exhausted": is_exhausted(),
		"can_change_form": _can_change_form,
	}
	if (tokens_to_json):
		card_description["tokens"] = tokens_to_json
	
	if (self.current_host_card):
		card_description["host"] = current_host_card.properties.get("_code")
		
	if self.encounter_status != gameData.EncounterStatus.NONE:
		card_description["encounter_status"] = self.encounter_status

	if is_onboard_facedown():
		card_description["facedown_properties"] = self.properties
	
	return card_description

func load_from_json(card_description):
	if (tokens):
		_ready_load_from_json(card_description)
	else:
		_on_ready_load_from_json = card_description
	return self

func _ready_load_from_json(card_description: Dictionary = {}):
	if (!card_description):
		card_description = _on_ready_load_from_json
	if !card_description:
		return self

	#owner_id and card_id should already be done or this card wouldn't exist
	var tokens_to_json = card_description.get("tokens", {})
	if (tokens_to_json):
		tokens.load_from_json(tokens_to_json)


	var exhausted = card_description.get("exhausted", false)
	if exhausted:
		exhaustme()
	else:
		readyme()
			
	self._can_change_form = card_description.get("can_change_form", true)	

	self.encounter_status = int(card_description.get("encounter_status", gameData.EncounterStatus.NONE))

	var facedown_properties = card_description.get("facedown_properties", {})
	if facedown_properties:
		set_is_faceup(false, true)
		for property in facedown_properties:
			if property in ["code", "_code"]:
				continue
			self.modify_property(
					property,
					facedown_properties[property],
					false,
					["Init", "emit_signal"])
		cfc.flush_cache()
	else:
		if state in[CardState.ON_PLAY_BOARD, CardState.IN_HAND]:
			set_is_faceup(true, true)

	#we don't handle the attachment/host content here, it is don by the board loading, after all cards are loaded

	return self



func get_global_center():
	var xy = get_global_position()
	var card_scale = scale
	var real_card_size = card_size
	if state in [CardState.IN_PILE, CardState.VIEWED_IN_PILE]:
		var parent = get_parent()
		if parent:
			card_scale = parent.scale
			real_card_size = parent.card_size
	if _placement_slot:
		card_scale = _placement_slot.get_scale_modifier()
	var center = (xy + real_card_size/2 * card_scale)
	return center

func serialize_to_json():
	return export_to_json()

var _cached_printed_text = {}
func get_printed_text(section = ""):
	if !section:
		return get_property("text","")
	if _cached_printed_text.has(section):
		return _cached_printed_text[section]
	
	var result = ""
	var full_text:String = get_property("text", "")
	var searching:String = "[b]" + section.to_lower() + "[/b]:"
	var position = full_text.findn(searching)
	if position == -1:
		result = ""
	else:
		var substring = full_text.substr(position + searching.length())
		var end = substring.find('\n')
		if end == -1:
			result = substring
		else:
			result = substring.substr(0, end)
	_cached_printed_text[section] = result
	return result	

