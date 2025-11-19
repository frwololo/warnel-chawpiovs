# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED

class_name WCCard
extends Card

# -1 uninitialized, 0 Villain, any positive value: hero
var _owner_hero_id  := -1
var _controller_hero_id  := -1 setget set_controller_hero_id, get_controller_hero_id

var _check_play_costs_cache: Dictionary = {}

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
var spinbox
#healthbar on top of characters, allies, villains, etc...
var healthbar

var activity_script

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
	update_hero_groups()
	_controller_hero_id = hero_id
	
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
	if canonical_name == "Highway Robbery":
		var _tmp = 1
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

func setup() -> void:
	.setup()
	_runtime_properties_setup()
	_init_groups()
	init_token_drawer()	
	set_card_art()
	position_ui_elements()
	_ready_load_from_json()
	
	gameData.connect("game_state_changed", self, "_game_state_changed")
	scripting_bus.connect("step_started", self, "_game_step_started")
	scripting_bus.connect("card_token_modified", self, "_card_token_modified")

	scripting_bus.connect("card_moved_to_hand", self, "_card_moved")
	scripting_bus.connect("card_moved_to_pile", self, "_card_moved")
	scripting_bus.connect("card_moved_to_board", self, "_card_moved")		
	
	attachment_mode = AttachmentMode.ATTACH_BEHIND
	
	#this prevents moving cards around. A bit annoying but avoids weird double click envents leading to a drag and drop
	disable_dragging_from_board = true	
	disable_dropping_to_cardcontainers = true

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
		display_health()
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
	if properties.get("_horizontal", 0):
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
	spinbox = $Control/SpinPanel/SpinBox
	healthbar = $Control/HealthPanel/healthbar	

func _ready():
	scripting_bus.connect("scripting_event_about_to_trigger", self, "execute_before_scripts")

func _class_specific_process(delta):
	._class_specific_process(delta)
		

func _process(delta) -> void:
	if (cfc.is_modal_event_ongoing()):
		return
	if (gameData.is_targeting_ongoing()):
		return
	var can_play = check_play_costs()
	if (can_play == CFConst.CostsState.OK):
		#if modal menu is displayed we don't want to mess up those cards highlights
		set_target_highlight(can_play)
	else:
		#pass
		clear_highlight()

func set_target_highlight(colour):
	highlight.set_target_highlight(colour)


#flush caches and states when game state changes
func _game_state_changed(_details:Dictionary):
	for i in gameData.get_team_size():
		var hero_id = i+1
		_check_play_costs_cache[hero_id] = CFConst.CostsState.CACHE_INVALID

#reset some variables at new turn
func _game_step_started(details:Dictionary):
	var current_step = details["step"]
	match current_step:
		CFConst.PHASE_STEP.PLAYER_TURN:
			_can_change_form = true
	return	
	

func get_card_back_code() -> String:
	return get_property("back_card_code")

func get_art_filename():
	var card_code = get_property("_code")
	return cfc.get_img_filename(card_code)		

func set_card_art():
	var filename = get_art_filename()
	if (filename):
		card_front.set_card_art(filename)

#adds our card to group names matching its type and hero owner
# e.g. "allies2" means allies belonging to hero 2
func update_hero_groups():
	var type_code = properties.get("type_code", "")
	
	var groups:Array = CFConst.TYPES_TO_GROUPS.get(type_code, [])
	
	for group in groups:
		for i in range (gameData.team.size() + 1):
			var hero_group = group + str(i)
			if self.get_controller_hero_id() == i:
				if !self.is_in_group(hero_group):
					self.add_to_group(hero_group)
			else:
				if self.is_in_group(hero_group):
					self.remove_from_group(hero_group)	

func _init_groups() -> void :
	var type_code = properties.get("type_code", "")
	
	var groups:Array = CFConst.TYPES_TO_GROUPS.get(type_code, [])
	
	for group in groups:
		self.add_to_group(group)
		
func common_post_move_scripts(new_host: String, _old_host: String, _move_tags: Array) -> void:
	#change controller as needed
	var new_grid = get_grid_name()
	var new_hero_id = 0
	if (new_grid):
		new_hero_id = gameData.get_grid_owner_hero_id(new_grid)
	else:
		#attempt for piles/containers
		new_hero_id = gameData.get_grid_owner_hero_id(new_host)
	
	if (new_hero_id or (self.get_controller_hero_id() < 0) ): #only change if we were able to establish an owner, or if uninitialized
		self.set_controller_hero_id(new_hero_id)
	
	
	#init owner once and only once, if not already done
	init_owner_hero_id(new_hero_id)	
	
	display_health()
	display_threat()
	
	#rest exhausted status
	if new_host.to_lower() != "board":
		_is_exhausted = false
		

#Tries to play the card assuming costs aren't impossible to pay
#Also used for automated tests
func attempt_to_play(user_click:bool = false):
	#don't try to activate the card if the click was the result of targeting
	if user_click:
		if gameData.is_targeting_ongoing() or gameData.targeting_happened_too_recently():
			return
		#we already sent a request and should be waiting for full resolution	
		if !gameData.theStack.is_player_allowed_to_click(self):
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
	execute_scripts()


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
	if canonical_name == "Cosmic Flight" and trigger_card.canonical_name == "Rhino - 1":
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


	if gameData.can_hero_play_this_ability(hero_id,self, card_scripts):
		if card_scripts.get("is_optional_" + get_state_exec()):
			#optional interrupts need to check costs
			if check_play_costs_no_cache(hero_id) == CFConst.CostsState.IMPOSSIBLE:
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
	

	var override_controller_id = trigger_details.get("override_controller_id", 0)
	var for_hero_id = trigger_details.get("for_hero_id", 0)

	if override_controller_id:
		if gameData.get_current_local_hero_id() != override_controller_id:
			return null
	else:
	#can only trigger if I'm the controller of the abilityor if enemy card (will send online to other clients)

		if for_hero_id:
			if !gameData.can_hero_play_this_ability(for_hero_id, self):
				return null
		else:
			if !gameData.can_i_play_this_ability(self):
				return null
		
	#enemy cards, multiple players can react except when they're the specific target
	if self.get_controller_hero_id() <= 0:
		var can_i_play_enemy_card = false
		if for_hero_id:
			if for_hero_id in gameData.get_currently_playing_hero_ids():
				can_i_play_enemy_card = true
		else:	
			for my_hero in (gameData.get_my_heroes()):
				if my_hero in (gameData.get_currently_playing_hero_ids()):
					can_i_play_enemy_card = true
		if !can_i_play_enemy_card:
			return null
	
	#last minute swap for hero vs alter ego reveals
	if trigger == "reveal":
		var hero_id_to_check = gameData.get_villain_current_hero_target()
		var identity_card = gameData.get_identity_card(hero_id_to_check)
		var specific_trigger = "reveal_alter_ego" if identity_card.is_alter_ego_form() else "reveal_hero"
		var specific_reveal = cfc.set_scripts.get(canonical_id,{}).get(specific_trigger,{})
		if specific_reveal:
			trigger = specific_trigger		
				
			
	return .execute_scripts(trigger_card, trigger, trigger_details, run_type)	

# A signal for whenever the player clicks on a card
func _on_Card_gui_input(event) -> void:
	cfc.add_ongoing_process(self, "_on_Card_gui_input_" + canonical_name)
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
				and not buttons.are_hovered() \
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
					z_index = 0
					for attachment in self.attachments:
						attachment.z_index = 0

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

func remove_threat(modification: int, script = null) -> int:
	
	#Crisis special case: can't remove threat from main scheme
	if "main_scheme" == properties.get("type_code", "false"):
		var all_schemes:Array = cfc.NMAP.board.get_all_cards_by_property("type_code", "side_scheme")
		for scheme in all_schemes:
			#we add all acceleration tokens	
			var crisis = scheme.get_property("scheme_crisis", 0)
			if crisis:
				return CFConst.ReturnCode.FAILED
	
	var token_name = "threat"
	var current_tokens = tokens.get_token_count(token_name)
	if current_tokens - modification < 0:
		modification = current_tokens
	var result = tokens.mod_token(token_name,-modification)
	
#	if "side_scheme" == properties.get("type_code", "false"):
#		if get_current_threat() == 0:
#			self.die(script)
			
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


func common_pre_execution_scripts(_trigger: String, _trigger_details: Dictionary) -> void:
	match _trigger:
		"enemy_attack":
			gameData.compute_potential_defenders(gameData.get_villain_current_hero_target())

func can_defend(hero_id = 0):
	if is_exhausted() : return false

	var type_code = properties.type_code
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
	scripting_bus.emit_signal("card_defeated", self, trigger_details)
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
			
	return CFConst.ReturnCode.OK		


func _process_card_state() -> void:
	._process_card_state()

	#TODO bug?
	#sometimes the card reports being "faceup" while actually showing the back
	#this is a fix for that
	if get_node('Control/Back').visible == is_faceup:
		is_faceup = !is_faceup
		set_is_faceup(!is_faceup, true)
	match state:
		CardState.ON_PLAY_BOARD:
			#horizontal cards are always forced to horizontal
			#does that need to change eventually ?	
			#note: setting tweening to false otherwise it causes issues with
			#tweening never ending
			if get_property("_horizontal", false):
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
func check_play_costs_no_cache(hero_id)-> Color:
	_check_play_costs_cache[hero_id] = CFConst.CostsState.CACHE_INVALID
	return check_play_costs({"hero_id" : hero_id})

	
func check_play_costs(params:Dictionary = {}) -> Color:
	#return .check_play_costs();
	var hero_id = params.get("hero_id", gameData.get_current_local_hero_id())

	
	if (_check_play_costs_cache.get(hero_id,CFConst.CostsState.CACHE_INVALID) != CFConst.CostsState.CACHE_INVALID):
		return _check_play_costs_cache[hero_id]
	
	_check_play_costs_cache[hero_id] = CFConst.CostsState.IMPOSSIBLE

	#skip if card is not in hand and not on board. TODO: will have to take into account cards than can be played from other places
	var state_exec = get_state_exec()
	
	if !(state_exec in ["hand", "board"]):
		return _check_play_costs_cache[hero_id]
	

	if (canonical_name == "Jessica Jones"):
		var _tmp = 1
		
	var sceng = execute_scripts(self,"manual",{"for_hero_id": hero_id},CFInt.RunType.BACKGROUND_COST_CHECK)

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
func common_pre_run(_sceng) -> void:
	var trigger_details = _sceng.trigger_details
	
	var controller_hero_id = trigger_details.get("override_controller_id", self.get_controller_hero_id())
	
	var scripts_queue: Array = _sceng.scripts_queue
	var new_queue: Array = []

	var temp_queue: Array = []
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
				for v in ["hand", "encounters_facedown","deck" ,"discard","enemies","identity","allies","upgrade_support"]:
					new_script_definition = WCUtils.search_and_replace(new_script_definition, v, v+str(hero_id), true)	

				var new_script = ScriptTask.new(script.owner, new_script_definition, script.trigger_object, script.trigger_details)
				scripts.append(new_script)
		for _script in scripts:
			temp_queue.append(_script)
	
	scripts_queue = temp_queue	
	var zones = ["hand"] + CFConst.HERO_GRID_SETUP.keys()
	
	for task in scripts_queue:
		var script: ScriptTask = task
		var script_definition = script.script_definition			
		
		for v in zones:
		#first player explcitely mentioned
			script_definition = WCUtils.search_and_replace(script_definition, v + "_first_player", v+str(gameData.first_player_hero_id()), true)	

		
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
				script_definition = WCUtils.search_and_replace(script_definition, v, v+str(controller_hero_id), true)	


				#any_discard, etc gets replaced with ["discard1","discard2"] 
				var team_size = gameData.get_team_size()
				var any_container_def = []
				for i in range (team_size):
					any_container_def.append(v + str(i+1))
				if any_container_def.size() == 1:
					any_container_def = any_container_def[0]
				script_definition = WCUtils.search_and_replace(script_definition, "any_" + v, any_container_def, true)	
		
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
			_:
				new_queue.append(task)
	_sceng.scripts_queue = new_queue	

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
				SP.KEY_SELECTION_OPTIONAL: true,
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

#Marvel Champions Specific functionality
func can_change_form() -> bool:
	return _can_change_form

func change_form(voluntary = true) -> bool:
	#players have one voluntary change form per turn
	#we check for that
	if (voluntary):
		if !can_change_form():
			return false
		self._can_change_form = false

	var before = "alter_ego" if self.is_alter_ego_form() else "hero"
	var new_card = cfc.NMAP.board.flip_doublesided_card(self)
	if !new_card:
		var _error = 1
		return false
		
	#hopefully after and before are actually different...
	var after = "alter_ego" if new_card.is_alter_ego_form() else "hero"		
	scripting_bus.emit_signal("identity_changed_form", new_card, {"before": before , "after" : after } )
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

var _hidden_properties = {}
func set_is_faceup(
			value: bool,
			instant := false,
			check := false,
			tags := ["Manual"]) -> int:
	var retcode = .set_is_faceup(value, instant, check, tags)
	
	#we remove all of the card's properties as long as it's facedown,
	#to avoid triggering any weird things
#	if !check:
#		if is_faceup:
#			if _hidden_properties and !properties:
#				properties = _hidden_properties
#				_hidden_properties = {}
#		else:
#			if properties and !_hidden_properties:
#				_hidden_properties = properties
#				properties = {}
	
	return retcode	
		
	
func copy_modifiers_to(to_card:WCCard):
	var modifiers = export_modifiers()
	to_card.import_modifiers(modifiers)

func draw_boost_cards(action_type):
	var villain_deck:Pile = cfc.NMAP["deck_villain"]
	var amount = self.get_property("boost_cards_per_" + action_type, 0)
	for i in amount:
		var boost_card:Card = villain_deck.get_top_card()
		if boost_card:
			boost_card.set_is_boost(true)
			boost_card.attach_to_host(self) #,false, ["facedown"])
			boost_card.set_is_faceup(false)
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

#returns true if this card has a given trait
func has_trait(params) -> bool:
	var trait = ""
	match typeof(params):
		TYPE_DICTIONARY:
			trait = params.get("trait", "")
		TYPE_STRING:
			trait = params
		_:
			return false

	if !trait:
		return false
	
	trait = "trait_" + trait
	if get_property(trait, 0, true):
		return true
	return false

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

func get_script_bool_property(params, script:ScriptTask = null) -> bool:
	var property = params.get("property", "")
	if !property:
		return false
	return script.get_property(property, false)

func identity_has_trait(params, script:ScriptTask = null) -> bool:
	var hero = get_controller_hero_card()
	return hero.has_trait(params)	

func card_is_in_play(params, script:ScriptTask = null) -> bool:
	var card_name = params.get("card_name", "")
	if !card_name:
		return false
	var card = cfc.NMAP.board.find_card_by_name(card_name)
	if !card:
		return false
	return true

func current_activation_status(params:Dictionary, _script:ScriptTask = null) -> bool:
	var script = get_current_activation_details()
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
	for subject in subjects:
		var printed_resource = subject.get_printed_resource_value_as_mana()
		mana.add_manacost(printed_resource)
	var count = 0
	if params.has("resource_type"):
		count = mana.get_resource(params["resource_type"])
	else:
		count = mana.converted_mana_cost()
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
		var subjects = SP.retrieve_subject(params.get("subject"), script)
		if !subjects:
			return 0
		subject = subjects[0]
	return subject.tokens.get_token_count("damage")
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
	var exe_sceng = self.execute_scripts(self, "resource", {})				
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
				return result_mana			
	
	#if the compute didn't get through, we return the regular printed value
	if (my_state) == "hand":
		if (canonical_name == "The Power of Justice" and get_state_exec() == "hand"):
			var _tmp = 1		
		return get_printed_resource_value_as_mana(script)
		
	return null

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


func get_remaining_damage():
	var current_damage = self.tokens.get_token_count("damage")
	var health = self.get_property("health", 0)
	var diff = health - current_damage
	if diff <= 0:
		return 0
	return diff	

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

	
	#we don't handle the attachment/host content here, it is don by the board loading, after all cards are loaded
	
	return self

func is_hero_form() -> bool:
	if "hero" == properties.get("type_code", ""):
		return true
	return false
	
func is_alter_ego_form() -> bool:
	if "alter_ego" == properties.get("type_code", ""):
		return true
	return false

func serialize_to_json():
	return export_to_json()

