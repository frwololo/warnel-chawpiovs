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

const _SIMPLE_ANNOUNCE_SCENE_FILE = CFConst.PATH_CUSTOM + "Announce.tscn"
const _SIMPLE_ANNOUNCE_SCENE = preload(_SIMPLE_ANNOUNCE_SCENE_FILE)

const DEFAULT_TOP_COLOR:= Color8(50, 50, 50, 255)
const DEFAULT_BOTTOM_COLOR:= Color8(18, 18, 18, 255)
const DEFAULT_BG_COLOR = Color8(255,255,255,75)

const _script_name_to_function:={
	"receive_damage": "receive_damage",
	"phase_starts" : "simple_announce",
	"simple_announce" : "simple_announce",
}

func _ready():
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
				

func _step_started(details:Dictionary):
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
			"is_blocking" : false,
			"storage": {},
			"current_delta" : 0.0
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

func init_receive_damage(script:ScriptTask, announce:Dictionary) -> bool:
	var storage = announce["storage"]
	storage["arrows"] = []
		
	var tags: Array = script.get_property(SP.KEY_TAGS) #TODO Maybe inaccurate?
	var amount = script.retrieve_integer_property("amount")
	var owner = script.owner
	var hero_id = owner.get_controller_hero_id()

	#if the owner of the damage is a player,
	#we want to skip this thing to avoid
	#making a long announce of an event the players initiated themselves
	if hero_id:
		return false
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

	cfc.NMAP.board.add_child(announce_scene)
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
	cfc.NMAP.board.remove_child(announce_scene)
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
	}	
	var func_return = call("init_simple_announce", settings, announce)
	while func_return is GDScriptFunctionState && func_return.is_valid():
		func_return = func_return.resume()
	ongoing_announces.append(announce)	
	return true
