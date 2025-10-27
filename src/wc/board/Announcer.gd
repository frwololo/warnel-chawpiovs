# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:UNUSED_VARIABLE

class_name Announcer
extends Node

const default_announcer_minimum_time:= 2
var announcer_minimum_time:= 2

var ongoing_announce_object = null
var ongoing_announce:= ""
var is_blocking:= false
var storage: Dictionary = {}
var current_delta := 0.0
var _skip_announcer := false

const _SIMPLE_ANNOUNCE_SCENE_FILE = CFConst.PATH_CUSTOM + "Announce.tscn"
const _SIMPLE_ANNOUNCE_SCENE = preload(_SIMPLE_ANNOUNCE_SCENE_FILE)

const DEFAULT_TOP_COLOR:= Color8(50, 50, 50, 255)
const DEFAULT_BOTTOM_COLOR:= Color8(18, 18, 18, 255)

const _script_name_to_function:={
	"receive_damage": "receive_damage",
	"phase_starts" : "simple_announce",
	"simple_announce" : "simple_announce",
}

func _ready():
	scripting_bus.connect("step_started", self, "_step_started")


func skip_announcer(value:bool=true):
	_skip_announcer = value

func _step_started(details:Dictionary):
	if (_skip_announcer):
		return
		
	var current_step = details["step"]
	var text = ""
	match current_step:
		CFConst.PHASE_STEP.PLAYER_TURN:
			text = "Player Phase"
		CFConst.PHASE_STEP.VILLAIN_THREAT:
			text = "Villain Phase"
	if text:
		ongoing_announce = "phase_starts"
		ongoing_announce_object = current_step
		var func_return = call("init_simple_announce", text)
		while func_return is GDScriptFunctionState && func_return.is_valid():
			func_return = func_return.resume()
	return #found one so we exit early

func _process(delta: float):
	if (_skip_announcer):
		return
	
	current_delta += delta
				
	if ongoing_announce:
		var still_processing = call("process_" + _script_name_to_function[ongoing_announce])
		if !still_processing:
			cleanup()
	else:
		current_delta = 0
		find_event_to_announce()
	
			



func set_announcer_minimum_time(_time):
	announcer_minimum_time = _time

func get_blocking_announce():
	if ongoing_announce and is_blocking:
		return ongoing_announce
	return null

func is_announce_ongoing():
	if ongoing_announce:
		return true
	return false

func cleanup():
	if !ongoing_announce:
		return
	var func_return = call("cleanup_" + _script_name_to_function[ongoing_announce])
	while func_return is GDScriptFunctionState && func_return.is_valid():
		func_return = func_return.resume()
	storage = {}
	ongoing_announce = ""
	ongoing_announce_object = null
	announcer_minimum_time = default_announcer_minimum_time
	current_delta = 0
	is_blocking = false
	
func find_event_to_announce():
	var theStack:GlobalScriptStack = gameData.theStack
	if !theStack:
		cleanup()
		return
	
	var current_script = theStack.find_last_event()
	if !current_script:
		cleanup()
		return
	
	#only start an event from stack if it isn't in motion
	if !theStack.interrupt_mode in [GlobalScriptStack.InterruptMode.NOBODY_IS_INTERRUPTING, GlobalScriptStack.InterruptMode.HERO_IS_INTERRUPTING] :
		cleanup()
		return
	
	if current_script == ongoing_announce_object:
		return
	else:
		cleanup()
		var tasks = current_script.get_tasks()
		for task in tasks:		
			if _script_name_to_function.has(task.script_name):
				var func_return = call("init_" + _script_name_to_function[task.script_name], task)
				while func_return is GDScriptFunctionState && func_return.is_valid():
					func_return = func_return.resume()
				if (func_return):
					ongoing_announce = task.script_name
					ongoing_announce_object = current_script
				return #found one so we exit early


func init_receive_damage(script:ScriptTask) -> bool:
	storage["arrows"] = []
		
	var tags: Array = script.get_property(SP.KEY_TAGS) #TODO Maybe inaccurate?
	var amount = script.script_definition["amount"]
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
		targeting_arrow.set_destination(card.global_position)
		targeting_arrow._draw_targeting_arrow()

	is_blocking = true
	return true
	
func process_receive_damage() -> bool:
	var arrows = storage["arrows"]
	for arrow in arrows:
		arrow._draw_targeting_arrow()
	
	if gameData.theStack.interrupt_mode ==\
			GlobalScriptStack.InterruptMode.NOBODY_IS_INTERRUPTING:		
		is_blocking = true
		if current_delta > 	announcer_minimum_time:
			return false

	if gameData.theStack.interrupt_mode ==\
			GlobalScriptStack.InterruptMode.HERO_IS_INTERRUPTING:
		is_blocking = false
	return true
	
func cleanup_receive_damage():	
	var arrows = storage["arrows"]
	for arrow in arrows:
		arrow.get_parent().remove_child(arrow)
		arrow.queue_free()


func init_simple_announce(text, top_color:Color = DEFAULT_TOP_COLOR, bottom_color:Color = DEFAULT_BOTTOM_COLOR):
	is_blocking = true
	var announce = _SIMPLE_ANNOUNCE_SCENE.instance()
	announce.set_text(text)
	announce.set_bg_colors(top_color, bottom_color)
	cfc.NMAP.board.add_child(announce)
	storage["announce"] = announce
	
func process_simple_announce() -> bool:
	if !storage["announce"].ongoing:
		return false
	return true
	
func cleanup_simple_announce():
	var announce = storage["announce"]
	cfc.NMAP.board.remove_child(announce)
	announce.queue_free()
	pass

func simple_announce (text, top_color:Color = DEFAULT_TOP_COLOR, bottom_color:Color = DEFAULT_BOTTOM_COLOR):
	if ongoing_announce:
		return false
	if text:
		ongoing_announce = "simple_announce"
		ongoing_announce_object = text
		var func_return = call("init_simple_announce", text, top_color, bottom_color)
		while func_return is GDScriptFunctionState && func_return.is_valid():
			func_return = func_return.resume()
	return true
