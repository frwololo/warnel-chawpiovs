extends Counters

# * The `counters_container` has to point to the scene path, relative to your
#	counters scene, where each counter will be placed.
# * value_node specified the name of the label which holds
#	the value of the counter as displayed to the player
# * The needed_counters dictionary has one key per counter used in your game
#	Each value hold a dictionary with details about this counter.
#	* The key matching `value_node` will be used to set the starting
#		value of this counter
#	* All other keys specified have to match a label node name in the counter scene
#		and their value will be set as that label's text.
# * spawn_needed_counters() has to be called at the end, to actually
#	add the specified counters to your counters scene.
func _ready() -> void:
	counters_container = $VBC
	value_node = "Value"
	needed_counters = {
	}
	
	#TODO Manapool is currently connected to this display, need something more advanced
	var manapool:ManaPool = gameData.get_current_team_member()["manapool"]
	for v in ManaCost.Resource.values() :
		needed_counters[ManaCost.RESOURCE_TEXT[v]] = {"CounterTitle": ManaCost.RESOURCE_TEXT[v], "Value": manapool.pool[v]}
	# warning-ignore:return_value_discarded
	spawn_needed_counters()
	
	#Signals
	scripting_bus.connect("current_playing_hero_changed", self, "_refresh")
	scripting_bus.connect("manapool_modified", self, "_refresh")
	
func _refresh (trigger_details: Dictionary = {}):
	var manapool:ManaPool = gameData.get_current_team_member()["manapool"]
	for v in ManaCost.Resource.values() :
		mod_counter(ManaCost.RESOURCE_TEXT[v],manapool.pool[v], true) 

# We add counters dynamically at runtime as requested, even if they didn't exist in the game definition
# We do this before calling the parent which actually needs the counter to exist
func mod_counter(counter_name: String,
		value: int,
		set_to_mod := false,
		check := false,
		requesting_object = null,
		tags := ["Manual"]) -> int:
	if (not needed_counters.has(counter_name)):
		add_new_counter(counter_name, {"CounterTitle": counter_name, "Value" : 0} )
		
	var result = .mod_counter(counter_name, value, set_to_mod, check, requesting_object, tags)
	return result
