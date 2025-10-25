# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:UNUSED_VARIABLE

class_name Announcer
extends Node

const default_announcer_minimum_time:= 2
var announcer_minimum_time:= 2

var ongoing_announce_object = null
var ongoing_announce:= ""
var storage: Dictionary = {}
var current_delta := 0.0
var _skip_announcer := false

const _SIMPLE_ANNOUNCE_SCENE_FILE = CFConst.PATH_CUSTOM + "Announce.tscn"
const _SIMPLE_ANNOUNCE_SCENE = preload(_SIMPLE_ANNOUNCE_SCENE_FILE)


const _script_name_to_function:={
	"receive_damage": "receive_damage",
	"phase_starts" : "phase_starts",
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
		var func_return = call("init_phase_starts", text)
		while func_return is GDScriptFunctionState && func_return.is_valid():
			func_return = func_return.resume()
	return #found one so we exit early

func _process(delta: float):
	if (_skip_announcer):
		return
				
	if ongoing_announce:
		call("process_" + _script_name_to_function[ongoing_announce])	
	#force showing this for a while
	if (ongoing_announce and current_delta < announcer_minimum_time):
		current_delta += delta
		return
	else:
		current_delta = 0
		
	find_event_to_announce()
	
			



func set_announcer_minimum_time(_time):
	announcer_minimum_time = _time

func is_announce_ongoing():
	if ongoing_announce:
		return true
	return false
	
#we are showing an announce and want to wait a bit before proceeding to the next	
func wait_for_timer():
	return ongoing_announce and (current_delta < announcer_minimum_time)

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
	
func find_event_to_announce():
	var theStack:GlobalScriptStack = gameData.theStack
	if !theStack:
		cleanup()
		return
	
	var current_script = theStack.find_last_event()
	if !current_script:
		cleanup()
		return
	
	if current_script == ongoing_announce_object:
		return
	else:
		cleanup()
		var tasks = current_script.get_tasks()
		for task in tasks:		
			if _script_name_to_function.has(task.script_name):
				ongoing_announce = task.script_name
				ongoing_announce_object = current_script
				var func_return = call("init_" + _script_name_to_function[task.script_name], task)
				while func_return is GDScriptFunctionState && func_return.is_valid():
					func_return = func_return.resume()
				return #found one so we exit early


func init_receive_damage(script:ScriptTask):
	storage["arrows"] = []
		
	var tags: Array = script.get_property(SP.KEY_TAGS) #TODO Maybe inaccurate?
	var amount = script.script_definition["amount"]
	var owner = script.owner
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

	return
	
func process_receive_damage():
	var arrows = storage["arrows"]
	for arrow in arrows:
		arrow._draw_targeting_arrow()
	
func cleanup_receive_damage():	
	var arrows = storage["arrows"]
	for arrow in arrows:
		arrow.get_parent().remove_child(arrow)
		arrow.queue_free()


func init_phase_starts(text):
	var announce = _SIMPLE_ANNOUNCE_SCENE.instance()
	announce.set_text(text)
	cfc.NMAP.board.add_child(announce)
	storage["announce"] = announce
	
func process_phase_starts():
	current_delta = 0
	if !storage["announce"].ongoing:
		current_delta = announcer_minimum_time
		cleanup()
	pass
	
func cleanup_phase_starts():
	var announce = storage["announce"]
	cfc.NMAP.board.remove_child(announce)
	announce.queue_free()
	pass
