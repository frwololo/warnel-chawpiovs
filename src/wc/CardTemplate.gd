# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED

class_name WCCard
extends Card

# -1 uninitialized, 0 Villain, any positive value: hero
var _owner_hero_id  := -1 setget set_owner_hero_id, get_owner_hero_id
var _controller_hero_id  := -1 setget set_controller_hero_id, get_controller_hero_id

var _check_play_costs_cache: Color = CFConst.CostsState.CACHE_INVALID

var _on_ready_load_from_json:Dictionary = {}

#marvel champions specific variables
var _can_change_form := true
var is_boost:=false

func set_owner_hero_id(hero_id:int):
	if (hero_id == -1):
		var _error = 1
	_owner_hero_id = hero_id
	
func get_owner_hero_id() -> int:
	return _owner_hero_id	

func set_controller_hero_id(hero_id:int):
	_controller_hero_id = hero_id
	
func get_controller_hero_id() -> int:
	return _controller_hero_id	
	
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


func setup() -> void:
	.setup()
	_init_groups()
	init_default_max_tokens()	
	set_card_art()
	_ready_load_from_json()
	
	gameData.connect("game_state_changed", self, "_game_state_changed")
	scripting_bus.connect("step_started", self, "_game_step_started")


func _process(delta) -> void:
	._process(delta)
	var can_play = check_play_costs()
	if (can_play == CFConst.CostsState.OK and not cfc.modal_menu):
		#if modal menu is displayed we don't want to mess up those cards highlights
		set_target_highlight(can_play)
	else:
		highlight.deactivate_glow()

func set_target_highlight(colour):
	highlight.set_target_highlight(colour)


#flush caches and states when game state changes
func _game_state_changed(_details:Dictionary):
	_check_play_costs_cache = CFConst.CostsState.CACHE_INVALID

#reset some variables at new turn
func _game_step_started(details:Dictionary):
	var current_step = details["step"]
	match current_step:
		CFConst.PHASE_STEP.PLAYER_TURN:
			_can_change_form = true
	return	
	

func get_card_back_code() -> String:
	return get_property("back_card_code")
	

func set_card_art():
	var card_code = get_property("_code")
	var filename = cfc.get_img_filename(card_code)
	if (filename):
		card_front.set_card_art(filename)


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
	self.set_controller_hero_id(new_hero_id)
	
	#init owner once and only once, if not already done
	if (not self.get_owner_hero_id()):
		self.set_owner_hero_id(new_hero_id)		
		

#Tries to play the card assuming costs aren't impossible to pay
#Also used for automated tests
func attempt_to_play():
	var state_exec = get_state_exec()
	
	if !state_exec in ["hand", "board"]:
		return false
	
	match state_exec:
		"hand":
			if check_play_costs() == CFConst.CostsState.IMPOSSIBLE:
				return false
			#unique rule
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
	
	#select valid scripts that match the current trigger
	var card_scripts = retrieve_filtered_scripts(trigger_card, "interrupt", trigger_details)
	
	if (!card_scripts):
		return CFConst.CanInterrupt.NO	
	
	var state_scripts = get_state_scripts(card_scripts)
	
	if (!state_scripts):
		return CFConst.CanInterrupt.NO
	
	#card has potential interrupts. Last we check if I'm the player who can play them
	var may_interrupt =  CFConst.CanInterrupt.NO

	if gameData.can_hero_play_this_ability(hero_id,self, card_scripts):
		if card_scripts.get("is_optional_" + get_state_exec()):
			may_interrupt =  CFConst.CanInterrupt.MAY
		else:
			return  CFConst.CanInterrupt.MUST
	
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
		
	return .execute_scripts(trigger_card, trigger, trigger_details, run_type)	


# A signal for whenever the player clicks on a card
func _on_Card_gui_input(event) -> void:
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
			# If it's a double-click, then it's not a card drag
			# But rather it's script execution
			if event.doubleclick:
				attempt_to_play()
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
						attempt_to_play()
					else :	
						move_to(destination)
					_focus_completed = false
		else:
			_process_more_card_inputs(event)
		

# Game specific code and/or shortcuts
func readyme(toggle := false,
			start_tween := true,
			check := false,
			tags := ["Manual"]) :
	var retcode = set_card_rotation(0, toggle, start_tween, check, tags)
	return retcode
	
func exhaustme(toggle := false,
			start_tween := true,
			check := false,
			tags := ["Manual"]) :
	var retcode = set_card_rotation(90, toggle, start_tween, check, tags)
	return retcode	

func is_ready() :
	return get_card_rotation() == 0

func is_exhausted():
	return (not is_ready())	
	
func add_threat(threat : int):
	tokens.mod_token("threat",threat)	

func get_current_threat():
	return tokens.get_token_count("threat")

func remove_threat(modification: int) -> int:
	
	#Crisis special case: can't remove threat from main scheme
	if "main_scheme" == properties.get("type_code", "false"):
		var all_schemes:Array = cfc.NMAP.board.get_grid("schemes").get_all_cards()
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
	
	if "side_scheme" == properties.get("type_code", "false"):
		if get_current_threat() == 0:
			self.discard()
			
	return result

func discard():
	var hero_owner_id = get_owner_hero_id()
	if (!hero_owner_id):
		self.move_to(cfc.NMAP["discard_villain"])
	else:
		var destination = "discard" + str(hero_owner_id)
		self.move_to(cfc.NMAP[destination])

func heal(value):
	var current_damage = tokens.get_token_count("damage")
	var heal_value = min(value, current_damage)
	tokens.mod_token("damage",-heal_value)

func common_pre_execution_scripts(_trigger: String, _trigger_details: Dictionary) -> void:
	match _trigger:
		"enemy_attack":
			gameData.compute_potential_defenders()

func can_defend():
	if is_exhausted() : return false

	var type_code = properties.type_code
	if type_code != "hero" and type_code != "ally": return false
	
	return true


func die():
	var type_code = properties.get("type_code", "")
	match type_code:
		"hero", "alter_ego":
			gameData.hero_died(self)
		"ally":
			move_to(cfc.NMAP["discard1"]) #TODO per hero
		"minion":
			move_to(cfc.NMAP["discard_villain"])	
		"villain":
			gameData.villain_died(self)
			
	return CFConst.ReturnCode.OK		

func commit_scheme():
	#TODO special case villain needs to receive a boost card
	var scheme_amount = self.get_property("scheme", 0)
	if (!scheme_amount):
		return
	
	var main_scheme:WCCard = gameData.find_main_scheme()
	if (!main_scheme):
		return

	#reveal boost cards
	for boost_card in attachments:
		if (!boost_card.is_boost):
			continue
		boost_card.set_is_faceup(true)
		scheme_amount = scheme_amount + boost_card.get_property("boost",0)
		#add an event on the stack to discard this card.
		#Note that the discard will happen *after* receive_damage below 
		#because we add it to the stack first
		var discard_event = cfc.scripting_engine.simple_discard_task(boost_card)
		gameData.theStack.add_script(discard_event)
	
	main_scheme.add_threat(scheme_amount)

func _process_card_state() -> void:
	._process_card_state()
	
	#TODO bug?
	#sometimes the card reports being "faceup" while actually showing the back
	#this is a fix for that
	if get_node('Control/Back').visible == is_faceup:
		is_faceup = !is_faceup
		set_is_faceup(!is_faceup, true)

# This function can be overriden by any class extending Card, in order to provide
# a way of checking if a card can be played before dragging it out of the hand.
#
# This method will be called while the card is being focused by the player
# If it returns true, the card will be highlighted as normal and the player
# will be able to drag it out of the hand
#
# If it returns false, the card will be highlighted with a red tint, and the
# player will not be able to drag it out of the hand.
func check_play_costs() -> Color:
	#return .check_play_costs();
	
	if (_check_play_costs_cache != CFConst.CostsState.CACHE_INVALID):
		return _check_play_costs_cache
	
	_check_play_costs_cache = CFConst.CostsState.IMPOSSIBLE

	#skip if card is not in hand and not on board. TODO: will have to take into account cards than can be played from other places
	if ((get_state_exec() != "hand")
		and get_state_exec() != "board"):
			return _check_play_costs_cache
		
	var sceng = execute_scripts(self,"manual",{},CFInt.RunType.BACKGROUND_COST_CHECK)

	if (!sceng): #TODO is this an error?
		_check_play_costs_cache = CFConst.CostsState.IMPOSSIBLE	
		return _check_play_costs_cache
		
	while sceng is GDScriptFunctionState && sceng.is_valid(): # Still working.
		sceng = sceng.resume()
		#sceng = yield(sceng, "completed")

	if (!sceng): #TODO is this an error?
		_check_play_costs_cache = CFConst.CostsState.IMPOSSIBLE	
		return _check_play_costs_cache
	
	if (sceng.can_all_costs_be_paid):
		_check_play_costs_cache = CFConst.CostsState.OK


	return _check_play_costs_cache

# This function can be overriden by any class extending Card, in order to provide
# a way of running special functions on an extended scripting engine.
#
# It is called after the scripting engine is initiated, but before it's run
# the first time
#
# Used to hijack the scripts at runtime if needed
# Current use case: check manapool before asking to pay for cards
func common_pre_run(_sceng) -> void:
	var owner_hero_id = self.get_owner_hero_id()
		
	var scripts_queue: Array = _sceng.scripts_queue
	var new_queue: Array = []
	for task in scripts_queue:
		var script: ScriptTask = task
		var script_definition = script.script_definition
		
		if (owner_hero_id <=0 ):
			cfc.LOG("error owner hero id is not set" )
		else:
			#var current_hero_id = gameData.get_current_hero_id()
			for v in ["hand", "encounters_facedown","deck" ,"discard","enemies","identity","allies","upgrade_support"]:
				#TODO move to const
				WCUtils.search_and_replace(script_definition, v, v+str(owner_hero_id), true)	
		
		match script_definition["name"]:
			# To pay for cards: We check if the manapool has some mana
			# If so, use that in "priority" and reduce the actual cost of the card
			# We then replace the "pay" trigger with a combination of
			# 1) discard the appropriate number of cards from hand (minored by what's available in manapool)
			# 2) empty the manapool
			"pay_regular_cost":
				var additional_task := ScriptTask.new(
					script.owner,
					{"name": "pay_from_manapool"}, #TODO more advanced
					script.trigger_object,
					script.trigger_details)
				new_queue.append(additional_task)
					
				var new_script = pay_regular_cost_replacement(script_definition)
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

func pay_regular_cost_replacement(script_definition: Dictionary) -> Dictionary:	
	var owner_hero_id = self.get_owner_hero_id()	
	var manapool:ManaPool = gameData.get_team_member(owner_hero_id)["manapool"]
	var manacost:ManaCost = ManaCost.new()
	var cost = script_definition["cost"]
	if cost == "card_cost":
		cost = self.get_property("cost")
	manacost.init_from_expression(cost) #TODO better name?
	var missing_mana:ManaCost = manapool.compute_missing(manacost)
	
	var result = {}
	#Manapool not enough, need to discard cards
	if missing_mana.is_negative() :
		# var current_hero_id = gameData.get_current_hero_id()
		#Replace the script with a move condition
		result ={
				"name": "move_card_to_container",
				"is_cost": true,
				"subject": "index",
				"subject_count": "all",
				"subject_index": "top",
				SP.KEY_NEEDS_SELECTION: true,
				SP.KEY_SELECTION_COUNT: -missing_mana.pool[ManaCost.Resource.UNCOLOR], #TODO put real missing cost here
				SP.KEY_SELECTION_TYPE: "equal",
				SP.KEY_SELECTION_OPTIONAL: false,
				SP.KEY_SELECTION_IGNORE_SELF: true,
				"selection_what_to_count": "resource_value",
				"src_container": "hand" + str(owner_hero_id),
				"dest_container": "discard" + str(owner_hero_id),
			}		

	return result	

func get_grid_name():
	if (_placement_slot):
		return _placement_slot.get_grid_name()
	return null	

#Marvel Champions Specific functionality
func can_change_form() -> bool:
	return _can_change_form

#a way to copy all modifications of this card to another card
#used e.g. when flipping card 	
func copy_modifiers_to(to_card:WCCard):
	#TODO status cards
	#TODO attachments
	#tokens (including damage)
	var my_tokens = tokens.get_all_tokens()
	for token_name in my_tokens.keys():
		var count = tokens.get_token_count(token_name)
		to_card.tokens.mod_token(token_name, count, true)
	#state (exhausted)
	to_card.set_card_rotation(self.card_rotation)
	#change form
	to_card._can_change_form = self._can_change_form

func draw_boost_card():
	var villain_deck:Pile = cfc.NMAP["deck_villain"]
	var boost_card:Card = villain_deck.get_top_card()
	if boost_card:
		boost_card.is_boost = true
		boost_card.attachment_mode = AttachmentMode.ATTACH_BEHIND
		boost_card.attach_to_host(self)
	#TODO if pile empty...need to reshuffle ?

func get_resource_value(script):
	var total = 0
	for resource_name in ManaCost.RESOURCE_TEXT:
		var lc_name = resource_name.to_lower()
		total += get_property("resource_" + lc_name, 0)
	return total
	
func get_max_hand_size():
	return get_property("hand_size", 0)

func init_default_max_tokens():
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
		"owner_hero_id": owner_hero_id
	}
	if (tokens_to_json):
		card_description["tokens"] = tokens_to_json
	
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
	
	return self
