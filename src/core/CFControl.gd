# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED

# Card Gaming Framework Control Singleton
#
# Add it to your autoloads with the name 'cfc'
class_name CFControl
extends Node

# Sent when all CGF nodes have been added to the NMAP dictionary
signal all_nodes_mapped
# Sent any time the scripting engine cache is cleared
signal cache_cleared
# Sent when all Card definitions have finished loading the memory from file
signal card_definitions_loaded
# Sent when all Card scripts have finished loading the memory from file
signal scripts_loaded
# Sent when a new Card node is instanced
signal new_card_instanced(card)

var load_start_time := OS.get_ticks_msec()

#pointer to modal menu for potential cleanup
var modal_menus := [] 

var perf_monitors = {}
#which scripting bus signals the printed scripts of a card id listen to
#(CardTemplate.register_signals). Only depends on set_scripts: cleared
#whenever they change
var signal_registration_cache := {}
#Performance profiling. Off by default (the ticks cost a little themselves).
#Turn on with the "perf_profiling" setting (works in release builds too,
#to measure on older machines), or with PERF_PROFILING_IN_DEBUG in debug
#builds. The report is printed and saved to user://perf_report.txt
#(output_perf_monitors, called from the Debug button and at test suite end)
const PERF_PROFILING_IN_DEBUG = false
var perf_profiling := false
#nested calls of the same tick (e.g. alterants computing alterants) each
#get their own start time
var _perf_stopwatches := {}
#per frame counters, to find frames where everything gets recomputed
var _perf_frame_counts := {}
var _perf_frame_start_usec := 0
#per frame time budgets (usec) for work that can wait a few frames, such as
#the play highlight cost checks. Reset every frame
const FRAME_BUDGETS_USEC := {
	"cost_checks": 8000,
	"visual_alterants": 3000,
}
var _frame_budget_spent := {}
#-----------------------------------------------------------------------------
# BEGIN Unit Testing Variables
#-----------------------------------------------------------------------------

# Unit Testing flag
var ut := false
var _ut_tokens_only_on_board := CFConst.TOKENS_ONLY_ON_BOARD
var _ut_show_token_buttons := CFConst.SHOW_TOKEN_BUTTONS
# This is set to true when tests are running
var is_testing := false

#-----------------------------------------------------------------------------
# END Unit Testing Variables
#-----------------------------------------------------------------------------

# This variable stores all custom settings for each game.
# It is initiated by looking for [CFConst#SETTINGS_FILENAME], but if it
# doesn't exist, defaults to the values specified in CFConst, if applicable.
var game_settings := {}
# This variable stores the font and icon size for each string of text.
# based on the current card size. This allows us to avoid calculating fonts
# on the fly all the time and adding delay to card instancing.
var font_size_cache := {}
var cache_commit_timer: SceneTreeTimer
# If set to true, the player will be prevented from interacting with the game
var game_paused := false setget set_game_paused
# If this is false, all CardContainers will pause in their ready() scene
# until all other CardContainers have been mapped.
var are_all_nodes_mapped := false
# The games initial Random Number Generator seed.
# When this stays the same, the game randomness will always play the predictable.
var game_rng_seed = "CFC Random Seed" setget set_seed
# This will store all card properties which are placed in the card labels
var card_definitions := {}
# This will store all card scripts
var set_scripts := {}
# This will store all card scripts, including their format placeholders
var unmodified_set_scripts := {}
# A dictionary of all our container nodes for easy access
var NMAP: Dictionary
# The card actively being dragged
var card_drag_ongoing: Card = null
# Switch used for seeing debug info
var _debug := false
# Game random number generator
var game_rng := RandomNumberGenerator.new()
var rng_saved_state = game_rng.state
# We cannot preload the scripting engine as a const for the same reason
# We cannot refer to it via class name.
#
# If we do, it is parsed by the compiler who then considers it
# a cyclic reference as the scripting engine refers back to the Card class.
var scripting_engine = load(CFConst.PATH_SCRIPTING_ENGINE)
# We cannot preload the per script as a const for the same reason
# We cannot refer to it via class name.
#
# If we do, it is parsed by the compiler who then considers it
# a cyclic reference as the scripting engine refers back to the Card class.
var script_per = load(CFConst.PATH_SCRIPT_PER)
# We cannot preload the alterant engine as a const for the same reason
# We cannot refer to it via class name.
#
# If we do, it is parsed by the compiler who then considers it
# a cyclic reference as the scripting engine refers back to the Card class.
var alterant_engine = load(CFConst.PATH_ALTERANT_ENGINE)
# Stores the alterations returned for a specific card-script-value combination.
#
# As the Alterant Engine is scanning all cards in game for alterant scripts
# then those scripts can further scan cards in play and trigger other alterants
# this can be a quite heavy operations, when there's a few alterants in play.
#
# To avoid this, after each alterant operation, we store the results in this
# dictionary, and use them for the next time. This scripts which read properties
# or counters to be placed even in _process() while there's alterants in play.
var alterant_cache: Dictionary
# This is a copy of card.temp_property_modifiers
# We store it globally for games which want to have access to it,
# before subject cards are selected
#
# This dictionary is not used by default anywhere in the framework.
# A game need to explicitly make use of it.
var card_temp_property_modifiers = {}
var ov_utils = load(CFConst.PATH_OVERRIDABLE_UTILS).new()
var curr_scale: float

var script_load_thread : Thread
var scripts_loading := true

var cards_load_thread : Thread
var cards_loading := true

func _ready() -> void:
	var load_end_time = OS.get_ticks_msec()
	if OS.has_feature("debug") and not cfc.is_testing:
		print_debug("DEBUG INFO:CFControl: instance time = %sms" % [str(load_end_time - load_start_time)])
	
	# warning-ignore:return_value_discarded
	connect("all_nodes_mapped", self, "_on_all_nodes_mapped")
	# warning-ignore:return_value_discarded
	get_viewport().connect("size_changed", self, '_on_viewport_resized')
	_on_viewport_resized()
	_setup()

func _process(_delta:float):
	flush_cache_as_needed()
	_perf_end_frame()
	_frame_budget_spent = {}

#true if some of the budget is left in this frame (the first call of
#the frame always gets to run, whatever its duration)
func has_frame_budget(budget_name:String) -> bool:
	return _frame_budget_spent.get(budget_name, 0) < FRAME_BUDGETS_USEC.get(budget_name, 0)

func spend_frame_budget(budget_name:String, usec:int):
	_frame_budget_spent[budget_name] = _frame_budget_spent.get(budget_name, 0) + usec

func reset_settings_to_default():
	var dir = Directory.new()
	dir.remove(CFConst.SETTINGS_FILENAME)
	game_settings = {}
	init_settings_from_file()
	
func _setup() -> void:
	init_settings_from_file()
	init_font_cache()

	# We reset our node mapping variables every time
	# as they repopulate during unit testing many times.
	# warning-ignore:return_value_discarded
	flush_cache()
	# We need to reset these values for UNIT testing
	NMAP = {}
	are_all_nodes_mapped = false
	card_drag_ongoing = null
	# The below takes care that we adjust some settings when testing via Gut
	if is_testing:
		ut = true
		_debug = true
	else:
		# Initialize the game random seed
		set_seed(game_rng_seed)
	if !cfc.game_settings.get("load_cards_online", true):	
		load_cards_database()

func is_perf_profiling() -> bool:
	return perf_profiling or (PERF_PROFILING_IN_DEBUG and OS.is_debug_build())

func add_performance_call_count(var_name, count = 1):
	if !is_perf_profiling():
		return
	var count_name = var_name + " (count)"
	perf_monitors[count_name] = perf_monitors.get(count_name, 0) + count
	#how many times in the current frame, the max is kept in the report
	_perf_frame_counts[var_name] = _perf_frame_counts.get(var_name, 0) + count

func start_performance_tick(var_name):
	if !is_perf_profiling():
		return
	if !_perf_stopwatches.has(var_name):
		_perf_stopwatches[var_name] = []
	_perf_stopwatches[var_name].append(OS.get_ticks_usec())

func stop_performance_tick(var_name):
	if !is_perf_profiling():
		return	
	var stop = OS.get_ticks_usec()	
	var watches = _perf_stopwatches.get(var_name, [])
	if !watches:
		return
	var elapsed = stop - watches.pop_back()

	add_performance_call_count(var_name)
	var total_time_name = var_name + " (total usec)"
	var max_time_name = var_name + " (max usec)"
	perf_monitors[total_time_name] = perf_monitors.get(total_time_name, 0) + elapsed
	perf_monitors[max_time_name] = max(perf_monitors.get(max_time_name, 0), elapsed)
	perf_monitors[var_name + " (avg per call usec)"] = perf_monitors[total_time_name] / perf_monitors[var_name + " (count)"]

#called once per frame (CFControl._process): frame time histogram and
#the max per frame of every counter
func _perf_end_frame():
	if !is_perf_profiling():
		_perf_frame_counts = {}
		return
	var now = OS.get_ticks_usec()
	if _perf_frame_start_usec:
		var frame_ms = (now - _perf_frame_start_usec) / 1000.0
		perf_monitors["frames (count)"] = perf_monitors.get("frames (count)", 0) + 1
		perf_monitors["frame (max ms)"] = max(perf_monitors.get("frame (max ms)", 0), frame_ms)
		for limit in [33, 50, 100, 250]:
			if frame_ms > limit:
				var key = "frames over " + str(limit) + "ms (count)"
				perf_monitors[key] = perf_monitors.get(key, 0) + 1
	_perf_frame_start_usec = now
	for key in _perf_frame_counts:
		var max_key = key + " (max per frame)"
		perf_monitors[max_key] = max(perf_monitors.get(max_key, 0), _perf_frame_counts[key])
		if _perf_frame_counts[key]:
			var frames_key = key + " (frames with calls)"
			perf_monitors[frames_key] = perf_monitors.get(frames_key, 0) + 1
	_perf_frame_counts = {}

func reset_perf_monitors():
	perf_monitors = {}
	_perf_stopwatches = {}
	_perf_frame_counts = {}
	_perf_frame_start_usec = 0

func output_perf_monitors():
	var report = get_perf_report()
	print_debug("Performance checks:")
	print_debug(report)
	print_debug("END - Performance checks:")
	var file = File.new()
	if file.open("user://perf_report.txt", File.WRITE) == OK:
		file.store_string(report + "\n")
		file.close()

#sorted report: one line per measure, grouped by name
func get_perf_report() -> String:
	if !perf_monitors:
		return "no performance data (turn on the perf_profiling setting)"
	var keys = perf_monitors.keys()
	keys.sort()
	var lines = []
	for key in keys:
		lines.append(key + ": " + str(perf_monitors[key]))
	return PoolStringArray(lines).join("\n")

func load_scripts():
	# Removed threading since I optimized this loading function
#	load_script_definitions()
	# We're loading the script definitions in a thread to avoid delaying game load too much
	
	if CFConst.DISABLE_THREADS or OS.get_name() == "HTML5":
		load_script_definitions()
	else:
		load_script_definitions()
#		script_load_thread = Thread.new()
#		var result = script_load_thread.start(self, "load_script_definitions")
#		if result != OK:
#			var _error = 1
	var scripts_load_end_time = OS.get_ticks_msec()
	if OS.has_feature("debug") and not cfc.is_testing:
		print_debug("DEBUG INFO:CFControl: card scripts load time = %sms" % [str(scripts_load_end_time - load_start_time)])	

func play_sfx(string):
	pass	


func get_build_number():
	return CFConst.GAME_VERSION + "." + CFConst.BUILD_NUMBER

func load_cards_database():
	if CFConst.DISABLE_THREADS or OS.get_name() == "HTML5":
		load_card_definitions()
	else:	
		cards_load_thread = Thread.new()
		cards_load_thread.start(self, "load_card_definitions")
		while cards_load_thread.is_alive():
			yield(get_tree().create_timer(0.1), "timeout")
		cards_load_thread.wait_to_finish()		
	var defs_load_end_time = OS.get_ticks_msec()
	if OS.has_feature("debug") and not cfc.is_testing:
		print_debug("DEBUG INFO:CFControl: card definitions load time = %sms" % [str(defs_load_end_time - load_start_time)])	

	load_scripts()

func _setup_testing() -> void:
	flush_cache()
	NMAP = {}
	are_all_nodes_mapped = false
	card_drag_ongoing = null
	ut = true
	_debug = true
	game_paused = false
	
# Run when all necessary nodes (Board, CardContainers etc) for the game
# have been initialized. Allows them to proceed with their ready() functions.
func _on_all_nodes_mapped() -> void:
	if get_tree().get_root().has_node('Main'):
		# When Unit Testing, we want to always have both scaling options possible
		if ut:
			game_settings['focus_style'] = CFInt.FocusStyle.BOTH
	else:
		# If we're not using the main viewport scene, we need to fallback
		# to the basic focus
		game_settings['focus_style'] = CFInt.FocusStyle.SCALED
		# To prevent accidental switching this option when there's no other
		# viewports active
		if NMAP.board and NMAP.board.has_node("ScalingFocusOptions"): # Needed for UT
			NMAP.board.get_node("ScalingFocusOptions").disabled = true


# The below code allows us to quickly refer to nodes meant to host cards
# (i.e. parents) using an human-readable name.
#
# Since the fully mapped NMAP variable is critical for the good functioning
# of the framework, all CardContainers will wait in their ready() process
# for NMAP to be completed.
func map_node(node) -> void:
#	print_debug("Map Node %s Start: %sms" % [node.name, str(OS.get_ticks_msec() - load_start_time)])
	# The nmap always stores lowercase keys. Each key is a node name
	var node_name: String = node.name.to_lower()
	# I don't know why but suring UT sometimes I get duplicate board nodes.
	# I guess the queue_free is not as fast before the next test
	if 'board' in node_name:
		node_name = 'board'
	NMAP[node_name] = node
	var add_main = 0
	# Since we allow the game to run directly from the board scene,
	# we need to check if a viewport called Main is being used.
	if get_tree().get_root().has_node('Main'):
		add_main = 1
	# The below variable counts how many nodes we're expecting to map inside
	# NMAP. We calculate this by using node groups. For this, the piles
	# and hands have to be added to group from the editor (i.e. not only
	# via code in the ready() method).
	# The amount we're looking for is the sum of all CardContainers
	# +1 for the board, +1 if we're using a focus viewport
	var all_nodes : int = get_tree().get_nodes_in_group("hands").size() \
			+ get_tree().get_nodes_in_group("piles").size() + 1  + add_main
	# If the amount of node maps we have is equal to all nodes in gr
	if NMAP.size() == all_nodes:
		are_all_nodes_mapped = true
		# Once all nodes have been mapped, we emit a signal so that
		# all nodes waiting to complete their ready()  method, can continue.
		emit_signal("all_nodes_mapped")
#	print_debug("Map Node %s End: %sms" % [node.name, str(OS.get_ticks_msec() - load_start_time)])

func unmap_node(node) -> void:
	var node_name: String = node.name.to_lower()
	NMAP.erase(node_name)
	
# Setter for the random seed.
func set_seed(_seed, state = 0) -> void:
	game_rng_seed = str(_seed)
	game_rng.set_seed(hash(game_rng_seed))
	if state:
		game_rng.state = state


func restore_rng_state() -> void:
	game_rng.state = rng_saved_state

# Instances and returns a Card object, based on its name.
func _instance_card(card_id: String) -> Card:
	# We discover the template from the "Type"  property defined
	# in each card. Any property can be used
	var template = load(CFConst.PATH_CARDS
			+ card_definitions[card_id][CardConfig.SCENE_PROPERTY] + ".tscn")
	var card = template.instance()
	# We set the card_name variable so that it's able to be used later
	card.canonical_name = card_definitions[card_id]["Name"]
	card.canonical_id = card_id
	emit_signal("new_card_instanced", card)
	return(card)


func find_slot_in_grid(grid_name):
	if !grid_name:
		return null
	var grid: BoardPlacementGrid = cfc.NMAP.board.get_grid(grid_name)
	var slot: BoardPlacementSlot
	if grid:
		slot = grid.find_available_slot()
		if slot:
			return slot
	return null

func get_all_cards_from_containers(container_names) -> Array:
	if !NMAP.has('board'):
		return []
		
	var all_cards = []
	if !container_names:
		var _error = 1
		print_debug("missing parameter in get_all_cards_from_containers")
		return all_cards

	if (typeof(container_names) != TYPE_ARRAY):
		container_names = [container_names]
				
	for container_name in container_names:
		var container = NMAP.get(container_name, null)
		if !container:
			container = NMAP.board.get_grid(container_name)
		if is_instance_valid(container):
			all_cards += container.get_all_cards()
	
	return all_cards

# Returns a Dictionary with the combined Card definitions of all set files
func load_card_definitions() -> Dictionary:
	cards_loading = true
	var loaded_definitions : Array = []

	var set_files = CFUtils.list_files_in_directory(
			CFConst.PATH_SETS, CFConst.CARD_SET_NAME_PREPEND)
	for set_file in set_files:
		loaded_definitions.append(load(CFConst.PATH_SETS + set_file))
	var combined_sets := {}
	for set_def in loaded_definitions:
		for card_name in set_def.CARDS:
			combined_sets[card_name] = set_def.CARDS[card_name]

	card_definitions = combined_sets
	cards_loading = false
	emit_signal("card_definitions_loaded")	
	return(combined_sets)


# Returns a Dictionary with the combined Script definitions of all set files
func load_script_definitions() -> void:
	var loaded_script_definitions := []

	var script_definition_files := CFUtils.list_files_in_directory(
				CFConst.PATH_SETS, CFConst.SCRIPT_SET_NAME_PREPEND)
	for script_file in script_definition_files:
		loaded_script_definitions.append(load(CFConst.PATH_SETS + script_file).new())
		
	var combined_scripts := {}
	for card_name in card_definitions.keys():
		for scripts_obj in loaded_script_definitions:
			if combined_scripts.get(card_name):
				break
			var card_script = scripts_obj.get_scripts(card_name)
			var unmodified_card_script = scripts_obj.get_scripts(card_name, false)
#			print(unmodified_card_script)
			if not card_script.empty():
				combined_scripts[card_name] = card_script
				signal_registration_cache.erase(card_name)
				set_scripts[card_name] = card_script
				unmodified_set_scripts[card_name] = unmodified_card_script
	emit_signal("scripts_loaded")
	scripts_loading = false

func pile_or_grid(object_name, grid_def = null):
	if !grid_def:
		if gameData.scenario and gameData.scenario.grid_setup:
			grid_def = gameData.scenario.grid_setup
		else:
			grid_def = CFConst.GRID_SETUP
		
	if CFConst.HERO_GRID_SETUP.has(object_name):
		var type = CFConst.HERO_GRID_SETUP[object_name].get("type", "grid")
		return type 
	if grid_def.has(object_name):
		var type = grid_def[object_name].get("type", "grid")
		return type 		
	if object_name.begins_with("hand"):
		return "pile"
	for zone in CFConst.HERO_GRID_SETUP.keys():
		if object_name.begins_with(zone):
			var type = CFConst.HERO_GRID_SETUP[zone].get("type", "grid")
			return type 		
	return "grid"

# Setter for game_paused
func set_game_paused(value: bool) -> void:
	if NMAP.has("board") and is_instance_valid(NMAP.board) and NMAP.board.mouse_pointer:
		NMAP.board.mouse_pointer.is_disabled = value
	game_paused = value


func save_settings():
	var file = File.new()
	file.open(CFConst.SETTINGS_FILENAME, File.WRITE)
	file.store_string(JSON.print(game_settings, '\t'))
	file.close()	
# Whenever a setting is changed via this function, it also stores it
# permanently on-disk.
func set_setting(setting_name: String, value) -> void:
	if "/" in setting_name:
		var settings = setting_name.split("/")
		if settings.size() > 1:
			set_child_setting(settings[0], settings[1], value)
			return
	game_settings[setting_name] = value
	save_settings()

func set_child_setting(key: String, setting_name: String, value) -> void:
	if not game_settings.has(key):
		game_settings[key] = {}
	game_settings[key][setting_name] = value
	save_settings()

func get_setting(setting_name: String):
	if "/" in setting_name:
		var settings = setting_name.split("/")
		if settings.size() > 1:
			return get_child_setting(settings[0], settings[1])
	return game_settings.get(setting_name, "")

	
func get_child_setting(key: String, setting_name: String):
	if not game_settings.has(key):
		return ""
	return game_settings[key].get(setting_name, "")	

# Initiates game_settings from the contents of CFConst.SETTINGS_FILENAME
func init_settings_from_file() -> void:
	var file = File.new()
	if file.file_exists(CFConst.SETTINGS_FILENAME):
		file.open(CFConst.SETTINGS_FILENAME, File.READ)
		var data = parse_json(file.get_as_text())
		file.close()
		if typeof(data) == TYPE_DICTIONARY:
			game_settings = data.duplicate()

	if not game_settings.has('fancy_movement'):
		game_settings['fancy_movement'] = CFConst.FANCY_MOVEMENT
	if not game_settings.has('focus_style'):
		game_settings['focus_style'] = CFConst.FOCUS_STYLE
	if not game_settings.has('hand_use_oval_shape'):
		game_settings['hand_use_oval_shape'] = CFConst.HAND_USE_OVAL_SHAPE
	#performance profiling: add "perf_profiling": true to the settings file
	perf_profiling = bool(game_settings.get("perf_profiling", false))


func set_font_cache() -> void:
#	var timer = Timer.new()
#	timer.connect("timeout", self, "_commit_font_cache", [timer])
#	timer.wait_time = 1
#	timer.start()
	if not cache_commit_timer:
		cache_commit_timer = get_tree().create_timer(1.0)
		# warning-ignore:return_value_discarded
		cache_commit_timer.connect("timeout", self, "_commit_font_cache")


# Whenever a setting is changed via this function, it also stores it
# permanently on-disk.
func _commit_font_cache() -> void:
#	timer.disconnect("timeout", self, "_commit_font_cache")
#	timer.queue_free()
	var file = File.new()
	file.open(CFConst.FONT_SIZE_CACHE, File.WRITE)
	file.store_string(JSON.print(font_size_cache, '\t'))
	file.close()
	cache_commit_timer = null


# Initiates game_settings from the contents of CFConst.SETTINGS_FILENAME
func init_font_cache() -> void:
	var file = File.new()
	if file.file_exists(CFConst.FONT_SIZE_CACHE):
		file.open(CFConst.FONT_SIZE_CACHE, File.READ)
		var data = parse_json(file.get_as_text())
		file.close()
		if typeof(data) == TYPE_DICTIONARY:
			if font_size_cache.get('version') == CFConst.GAME_VERSION:
				font_size_cache = data.duplicate()
			else:
				# If the version of the game has increased, we wipe the
				# font size cache and a new one will start being populated
				font_size_cache['version'] = CFConst.GAME_VERSION


# This function resets the game to the same state as when
# the board loads for the first time. Only works when you're running
# off of the Main scene.
func reset_game() -> void:
	var main = cfc.NMAP.main
	clear()
	yield(get_tree().create_timer(0.1), "timeout")
	main._ready()


# This function clears out the usual game nodes
# and prepares to either quit the game or reset.
func clear() -> void:
	flush_cache()
	are_all_nodes_mapped = false
	card_drag_ongoing = null
	if cfc.NMAP.has("board"):
		cfc.NMAP.board.queue_free()
	cleanup_modal_menu()
	# We need to give Godot time to deinstance all nodes.
	yield(get_tree().create_timer(0.1), "timeout")
	NMAP.clear()



# This function exits the card-game part of the framework
# for example as preparation for returning to the main menu.
func quit_game() -> void:
	var main = null
	if cfc.NMAP.has("main"):
		main = cfc.NMAP.main
	clear()
	if main:
		main.queue_free()

func count_players():
	return 1

func clear_group(group_name):
	var nodes = get_tree().get_nodes_in_group(group_name)
	for node in nodes:
		node.remove_from_group(group_name)

# Empties the alterants cache (only thing cached for now) which will cause
# all the alterants engine fire anew for all requests.
#
# This is called after most game-state changes, but there's one notable exception:
# if you add an alterant to a card's `scripts` variable manually, then you need
# to flush the cache afterwards using this function.
var _flush_cache_requested = false
func flush_cache(force = false) -> void:
	_flush_cache_requested = true
	if force:
		flush_cache_as_needed()

func flush_cache_as_needed() -> void:
	if !_flush_cache_requested:
		return
	add_performance_call_count("cache: flush (alterant cache cleared, all cards refresh)")
	alterant_cache.clear()
	emit_signal("cache_cleared")
	_flush_cache_requested = false


func hide_all_previews() -> void:
	for card_preview_node in cfc.get_tree().get_nodes_in_group("card_preview"):
		card_preview_node.hide_preview_card()
	for card_preview_node in cfc.get_tree().get_nodes_in_group("info_popup"):
		card_preview_node.hide()


func _on_viewport_resized() -> void:
	var pix = CFConst.DESIGN_RESOLUTION.x * CFConst.DESIGN_RESOLUTION.y
#	var curr_pix = get_viewport().size.x * get_viewport().size.y

	var width = ProjectSettings.get("display/window/size/width")
	var height = ProjectSettings.get("display/window/size/height")		
	var curr_pix = width * height	
	curr_scale = curr_pix / pix
	if curr_scale > 1:
		curr_scale = 1


func _exit_tree():
	save_settings()
	
	if script_load_thread:
		script_load_thread.wait_to_finish()

	if cards_load_thread and cards_load_thread.is_active():
		cards_load_thread.wait_to_finish()	

#A function to override as needed
func enrich_window_title(selectionWindow, script, title:String) -> String:
	return title

func add_modal_menu(object):
	if not object in modal_menus:
		modal_menus.append(object)
	NMAP.board.disable_focus_mode()

func remove_modal_menu(object):
	modal_menus.erase(object)
	if !modal_menus:
		NMAP.board.enable_focus_mode()

func get_modal_menu():
	if modal_menus:
		return modal_menus.back()
	return null	
	
func cleanup_modal_menu():
	if (modal_menus):
		for modal_menu in modal_menus:
			if modal_menu.has_method("force_cancel"):
				modal_menu.force_cancel()
		modal_menus = []
	return


#safer way than asking objects to serialize themselves in case of error
func serialize_object(object):
	if !(object and is_instance_valid(object)):
		return null
		
	return object.serialize_to_json()

func _input(event):
	if event.is_action_pressed("toggle_fullscreen"):
		
		#skip if we're editing stuff
		var current_scene = get_tree().current_scene
		if current_scene and current_scene.has_method("get_focus_owner"):
			var focus_owner = current_scene.get_focus_owner()
			if focus_owner: 
				if focus_owner as LineEdit:
					return
				if focus_owner as TextEdit:
					return
					
		set_fullscreen(!OS.window_fullscreen)
		get_tree().set_input_as_handled()	

func os_has_feature(tag_name) -> bool:
	if _is_steam_deck():
		if tag_name == "mobile":
			return true
	elif  _is_mobile_web():
		if tag_name == "mobile":
			return true
			
	return OS.has_feature(tag_name)

func set_fullscreen(value):
	game_settings["fullscreen"] = value
	OS.set_window_fullscreen(value)

func _is_steam_deck() -> bool:
	if "AMD CUSTOM APU 0405" in OS.get_processor_name():
		return true
	else:
		return false

var _mobile_web_data: = {}
func _is_mobile_web()-> bool:
	
	if _mobile_web_data.has("is_mobile"):
		return 	_mobile_web_data["is_mobile"]
		
	if OS.get_name() != "HTML5":
		_mobile_web_data["is_mobile"] = false
		return false
		
	var is_mobile = JavaScript.eval("/Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent)", true)
	_mobile_web_data["is_mobile"] = is_mobile
	return is_mobile
