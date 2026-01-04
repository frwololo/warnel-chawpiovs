# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:UNUSED_VARIABLE
# warning-ignore-all:RETURN_VALUE_DISCARDED

class_name Announcer
extends Node

var default_announcer_minimum_time: float= 2
var announcer_minimum_time: float= 2

#
#{
#	"announce",
#	"object"
#	"is_blocking",
#	"storage",
#	"current_delta"
#}
var ongoing_announces = []
var _skip_announcer := false
var right_screen_announces = 0

const _SIMPLE_ANNOUNCE_SCENE_FILE = CFConst.PATH_CUSTOM + "Announce.tscn"
const _SIMPLE_ANNOUNCE_SCENE = preload(_SIMPLE_ANNOUNCE_SCENE_FILE)

const _STACK_GENERIC_SCENE_FILE = CFConst.PATH_CUSTOM + "board/StackEventDisplay.tscn"
const _STACK_GENERIC_SCENE = preload(_STACK_GENERIC_SCENE_FILE)


const DEFAULT_TOP_COLOR:= Color8(50, 50, 50, 255)
const DEFAULT_BOTTOM_COLOR:= Color8(18, 18, 18, 255)
const DEFAULT_BG_COLOR = Color8(255,255,255,75)

const GENERIC_STACK_POSITION = Vector2(1500, 150)

const _script_name_to_function:={
	"receive_damage": "receive_damage",
	"phase_starts" : "simple_announce",
	"simple_announce" : "simple_announce",
	"generic_stack": "generic_stack",
	"choices_menu": "choices_menu",
	"black_cover" : "black_cover"
}

func add_child_to_board(child, details = {}):
	var container = cfc.NMAP.board

	if details.get("set_as_toplevel", false):
		container.add_child_to_top_layer(child)
	else:
		container.add_child(child)
		if "z_index" in child:
			child.z_index = CFConst.Z_INDEX_ANNOUNCER
	


func remove_child_from_board(child,details = {}):
	var container = cfc.NMAP.board
	container.remove_child_from_top_layer(child)

func _ready():
	gameData.theStack.connect("stack_interrupt", self, "_stack_interrupt")
	scripting_bus.connect("step_started", self, "_step_started")
	scripting_bus.connect("stack_event_deleted", self, "_stack_event_deleted")
	if CFConst.DISABLE_ANNOUNCER:
		skip_announcer()


func skip_announcer(value:bool=true):
	_skip_announcer = value

func _stack_event_deleted(event):
	for announce in ongoing_announces:
		var ongoing_announce_object = announce.get("object", null)
		if ongoing_announce_object == event:
			announce["object_deleted"] = true
				

func _step_started(_trigger_object, details:Dictionary):
	if (_skip_announcer):
		return
		
	var current_step = details["step"]
	var settings = {}
	match current_step:
		CFConst.PHASE_STEP.PLAYER_TURN:
			settings["text"] = "Player Phase"
			var my_heroes = gameData.get_my_heroes()
			var hero_to_display = my_heroes[0] if my_heroes else 1
			var hero_card = gameData.get_identity_card(hero_to_display)
			var filename = hero_card.get_art_filename()
			settings["top_texture_filename"] = filename
		CFConst.PHASE_STEP.VILLAIN_THREAT:
			settings["text"] = "Villain Phase"
			var villain_card = gameData.get_villain()
			var filename = villain_card.get_art_filename()
			settings["top_texture_filename"] = filename	
		CFConst.PHASE_STEP.VILLAIN_DEAL_ENCOUNTER:
			settings = {
					"top_text": "Reveal",
					"bottom_text" : "Encounters",
					"top_color": Color8(50,18,18,255),
					"bottom_color": Color8(50,18,18,255),
					"bg_color" : Color8(0,0,0,0),
					"scale": 0.6,
					"duration": 2,
					"animation_style": Announce.ANIMATION_STYLE.SPEED_OUT,
					"top_texture_filename": gameData.get_villain().get_art_filename(),
			}		
	if settings:
		var announce = {
			"announce" :"phase_starts",
			"object" : current_step,
			"is_blocking" : true, #false,
			"storage": {},
			"current_delta" : 0.0,
			"set_as_toplevel": true
		}
		ongoing_announces.append(announce)		
		var func_return = call("init_simple_announce", settings, announce)
		while func_return is GDScriptFunctionState && func_return.is_valid():
			func_return = func_return.resume()
	return

func _process(delta: float):
	var to_cleanup = []	
	if (_skip_announcer):
		for announce in ongoing_announces:
			var ongoing_announce_object = announce["object"]
			if typeof(ongoing_announce_object) == TYPE_DICTIONARY and ongoing_announce_object.get("_forced", false):
				break
			else:			
				to_cleanup.append(announce)
		for announce in to_cleanup:		
			cleanup(announce)
		to_cleanup = []		
	
	for announce in ongoing_announces:
		announce["current_delta"] += delta
				
		var still_processing = call("process_" + _script_name_to_function[announce["announce"]], announce)
		if !still_processing:
			to_cleanup.append(announce)

	for announce in to_cleanup:		
		cleanup(announce)
			



func set_announcer_minimum_time(_time):
	announcer_minimum_time = _time

func get_blocking_announce():
	for announce in ongoing_announces:	
		var is_blocking = announce["is_blocking"]
		if is_blocking:
			return announce["announce"]
	return null

func is_announce_ongoing():
	if ongoing_announces:
		return true
	return false

func add_right_announce():
	right_screen_announces +=1
	
	#ask the focused card to move if it's in the way
	cfc.NMAP.main.reposition()

func remove_right_announce():
	right_screen_announces -=1
	
func is_right_side_announce_ongoing():
	return right_screen_announces

func cleanup(announce = null):
	#not passing anything means cleanup everything
	if !announce:
		for a in ongoing_announces:
			cleanup(a)
		return
	var ongoing_announce = announce["announce"]		
	var func_return = call("cleanup_" + _script_name_to_function[ongoing_announce], announce)
	while func_return is GDScriptFunctionState && func_return.is_valid():
		func_return = func_return.resume()

	announcer_minimum_time = default_announcer_minimum_time
	ongoing_announces.erase(announce)

func choices_menu(owner_card, origin_event, choices_menu, interacting_hero):
	var announce = {
		"announce" :"choices_menu",
		"object" : origin_event,
		"is_blocking" : false,
		"storage": {
			"owner_card": owner_card,
			"choices_menu": choices_menu,
			"interacting_hero": interacting_hero
		},
		"current_delta" : 0.0,
	}			
	var func_return = init_choices_menu(origin_event, announce)
	if (func_return):
		ongoing_announces.append(announce)					
		#set_announcer_minimum_time(3.0)
	return #exit after the first one	

func init_choices_menu(script, announce):
	var storage = announce["storage"]
	var announce_scene = _STACK_GENERIC_SCENE.instance()
	announce_scene.load_from_past_event(script, storage)
	
	#var announce_scene = StackEventDisplay.new(script)
	storage["scene"] = announce_scene
	add_child_to_board(announce_scene)
	announce_scene.set_target_position(GENERIC_STACK_POSITION * cfc.screen_scale)
	self.add_right_announce()	
	return true
	
#the process_* functions in Announcer return false if they are finished,
#true if they still have stuff to display		
func process_choices_menu(announce):		
	var storage = announce["storage"]
	if !cfc.get_modal_menu():
		return false
	return true

func cleanup_choices_menu(announce):
	var storage = announce["storage"]
	var announce_scene = storage["scene"]
	if !announce_scene or not is_instance_valid(announce_scene):
		return		
	announce_scene.force_close()	
	remove_child_from_board(announce_scene)	
	self.remove_right_announce()	
	announce_scene.queue_free()

func _stack_interrupt(stack_object, mode):
	if mode != GlobalScriptStack.InterruptMode.OPTIONAL_INTERRUPT_CHECK:
		return

	var announce = {
		"announce" :"generic_stack",
		"object" : stack_object,
		"is_blocking" : false,
		"storage": {},
		"current_delta" : 0.0,
	}			
	var func_return = init_generic_stack(stack_object, announce)
	if (func_return):
		ongoing_announces.append(announce)					
		#set_announcer_minimum_time(3.0)
	return #exit after the first one			

func announce_from_stack(script):
	if (_skip_announcer):
		return
			
	var tasks = script.get_tasks()
	for task in tasks:		
		if _script_name_to_function.has(task.script_name):
			var announce = {
				"announce" :task.script_name,
				"object" : script,
				"is_blocking" : false,
				"storage": {},
				"current_delta" : 0.0,
			}			
			var func_return = call("init_" + _script_name_to_function[task.script_name], task, announce)
			while func_return is GDScriptFunctionState && func_return.is_valid():
				func_return = func_return.resume()
			if (func_return):
				ongoing_announces.append(announce)					
				set_announcer_minimum_time(3.0)
			return #found one so we exit early	
			


func init_generic_stack(script, announce):
	var storage = announce["storage"]
	var announce_scene = _STACK_GENERIC_SCENE.instance()
	announce_scene.load_from_event(script)
	
	#var announce_scene = StackEventDisplay.new(script)
	storage["scene"] = announce_scene
	add_child_to_board(announce_scene)
	announce_scene.set_target_position(GENERIC_STACK_POSITION * cfc.screen_scale)
	self.add_right_announce()		
	return true
	
#the process_* functions in Announcer return false if they are finished,
#true if they still have stuff to display		
func process_generic_stack(announce):		
	var storage = announce["storage"]
	var announce_scene:StackEventDisplay = storage["scene"]
	if announce_scene.is_finished():
		return false
	
	return true

func cleanup_generic_stack(announce):
	var storage = announce["storage"]
	var announce_scene = storage["scene"]
	if !announce_scene or not is_instance_valid(announce_scene):
		return		
	remove_child_from_board(announce_scene)	
	self.remove_right_announce()
	announce_scene.queue_free()
	
func init_receive_damage(script:ScriptTask, announce:Dictionary) -> bool:
	var storage = announce["storage"]
	storage["arrows"] = []
		
	var tags: Array = script.get_property(SP.KEY_TAGS) #TODO Maybe inaccurate?

	var owner = script.owner
	var hero_id = owner.get_controller_hero_id()

	#if the owner of the damage is a player,
	#we want to skip this thing to avoid
	#making a long announce of an event the players initiated themselves
	if hero_id:
		return false	
	
	var amount = script.retrieve_integer_property("amount")

	#consolidate subjects. If the same subject is chosen multiple times, we'll multipy the damage
	# e.g. Spider man gets 3*1 damage = 3 damage
	var consolidated_subjects:= {}
	for card in script.subjects:
		if !consolidated_subjects.has(card):
			consolidated_subjects[card] = 0
		consolidated_subjects[card] += 1
	
	for card in consolidated_subjects.keys():
		var damage = amount * consolidated_subjects[card]
		
		var targeting_arrow = owner.targeting_arrow.duplicate(DUPLICATE_USE_INSTANCING)
		owner.add_child(targeting_arrow)
		storage["arrows"].append(targeting_arrow)
		targeting_arrow.set_text(str(damage) + " DAMAGE")
		targeting_arrow.show_me()
		targeting_arrow.set_destination(card)
		targeting_arrow._draw_targeting_arrow()

	announce["is_blocking"] = true
	return true
	
func process_receive_damage(announce) -> bool:
	var storage = announce["storage"]
	var arrows = storage["arrows"]
	for arrow in arrows:
		arrow._draw_targeting_arrow()
	
	var object_deleted = announce.get("object_deleted", false)
	if object_deleted:
		announce["is_blocking"] = false
		return false
	
#	is_blocking = true
#	if current_delta > 	announcer_minimum_time:
#		return false
#	return true
	var interrupt_mode = gameData.theStack.interrupt_mode
	match interrupt_mode:
		GlobalScriptStack.InterruptMode.NOBODY_IS_INTERRUPTING :		
			announce["is_blocking"] = true
			if announce["current_delta"] > 	announcer_minimum_time:
				return false
			return true
#		GlobalScriptStack.InterruptMode.HERO_IS_INTERRUPTING,\
#		GlobalScriptStack.InterruptMode.FORCED_INTERRUPT_CHECK,\
#		GlobalScriptStack.InterruptMode.OPTIONAL_INTERRUPT_CHECK:
		_:
			announce["is_blocking"] = false
			if !gameData.theStack.has_script(announce["object"]) and\
				 (announce["current_delta"]  > 	announcer_minimum_time):
				return false
			return true
#		_:
#			is_blocking = true
#			if current_delta > 	announcer_minimum_time:
#				return false
#
#			return true		
	
func cleanup_receive_damage(announce):
	var storage = announce["storage"]	
	var arrows = storage["arrows"]
	for arrow in arrows:
		if arrow and is_instance_valid(arrow):	
			arrow.get_parent().remove_child(arrow)
			arrow.queue_free()


func init_simple_announce(settings:Dictionary, announce):
	var top_color:Color = settings.get("top_color", DEFAULT_TOP_COLOR)
	var bottom_color:Color = settings.get("bottom_color", DEFAULT_BOTTOM_COLOR)
	var bg_color:Color = settings.get("bg_color", DEFAULT_BG_COLOR)
	
	
	announce["is_blocking"] = true
	var storage = announce["storage"]
	var announce_scene = _SIMPLE_ANNOUNCE_SCENE.instance()
	if (settings.has("text")):
		 announce_scene .set_text(settings["text"])

	if (settings.has("bottom_text")):
		 announce_scene .set_text_bottom(settings["bottom_text"])	

	if (settings.has("top_text")):
		 announce_scene .set_text_top(settings["top_text"])	
	
	if (settings.has("animation_style")):
		announce_scene .set_animation_style(settings["animation_style"])
		
	announce_scene.set_bg_colors(top_color, bottom_color)
	announce_scene.set_bg_color(bg_color)	
	
	if settings.has("top_texture_filename"):
		announce_scene.set_top_texture(settings["top_texture_filename"])
	if settings.has("bottom_texture_filename"):
		announce_scene.set_bottom_texture(settings["bottom_texture_filename"])		

	if settings.has("duration"):
		 announce_scene.set_duration(settings["duration"])

	if settings.has("scale"):
		announce_scene.set_scale(settings["scale"])

	add_child_to_board(announce_scene, announce)
	storage["announce"] = announce_scene
	
func process_simple_announce(announce) -> bool:
	var storage=announce["storage"]
#	var tmp = 1
	if !storage["announce"].ongoing:
		return false
	return true
	
func cleanup_simple_announce(announce):
	var storage=announce["storage"]	
	var announce_scene = storage["announce"]
	if !announce_scene or not is_instance_valid(announce_scene):
		return	
	remove_child_from_board(announce_scene)
	announce_scene.queue_free()
	pass

func simple_announce (settings:Dictionary, force:bool = false):
	if is_announce_ongoing():
		if (force):
			cleanup()
		else:
			return false
	var announce = {
		"announce" :"simple_announce",
		"object" : settings,
		"is_blocking" : false,
		"storage": {},
		"current_delta" : 0.0,
		"set_as_toplevel": true
	}	
	var func_return = call("init_simple_announce", settings, announce)
	while func_return is GDScriptFunctionState && func_return.is_valid():
		func_return = func_return.resume()
	ongoing_announces.append(announce)	
	return true


func init_black_cover(top_object, announce):
	var storage = announce["storage"]
	
	var announce_scene = ColorRect.new()
	announce_scene.self_modulate = Color(0,0,0,0.4)
	var screen_size = get_viewport().size
	announce_scene.rect_size = screen_size
	announce_scene.rect_position = Vector2(0, 0)

	add_child_to_board(announce_scene, announce)
	storage["z_index"] = top_object.z_index
	top_object.z_index = cfc.NMAP.board.get_options_menu_z_index() + 10
	storage["announce"] = announce_scene
	storage["is_ongoing"] = true
	
func process_black_cover(announce) -> bool:
	var storage=announce["storage"]
	if storage["is_ongoing"]:
		return true
	return false
	
func cleanup_black_cover(announce):
	var storage=announce["storage"]	
	var announce_scene = storage["announce"]
	if !announce_scene or not is_instance_valid(announce_scene):
		return
	remove_child_from_board(announce_scene)
	announce_scene.queue_free()
	var top_object = announce["object"]
	top_object.z_index = storage["z_index"]

func black_cover (top_object, force:bool = false):
	var announce = {
		"announce" :"black_cover",
		"object" : top_object,
		"is_blocking" : false,
		"storage": {},
		"current_delta" : 0.0,
		"set_as_toplevel": true
	}	
	var func_return = call("init_black_cover", top_object, announce)
	while func_return is GDScriptFunctionState && func_return.is_valid():
		func_return = func_return.resume()
	ongoing_announces.append(announce)	
	return true

func stop_black_cover():
	for announce in ongoing_announces:
		if announce["announce"] == "black_cover":
			announce["storage"]["is_ongoing"] = false
		
func reset():
	for announce in ongoing_announces:
		cleanup(announce)
	ongoing_announces = []
	right_screen_announces = 0	
	
