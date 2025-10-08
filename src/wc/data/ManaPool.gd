# Data that represents the available mana/energy for the player
class_name ManaPool
extends ManaCost



# Called when the node enters the scene tree for the first time.
func _init():
	pool[Resource.UNCOLOR] = 1 #TODO Temp for tests



### 
### Parent Overrides
###
func reset() :
	var temp_pool:ManaCost = ManaCost.new()
	temp_pool.set_cost(self.pool)
	.reset()
	var diff:ManaCost = compute_diff(temp_pool)
	if not diff.is_zero():
		scripting_bus.emit_signal("manapool_modified",  {}) #TODO Requesting object - better to have a card here?


func add_resource(type, amount) :
	.add_resource(type, amount)
	scripting_bus.emit_signal("manapool_modified",  {}) #TODO Requesting object - better to have a card here?


#computes raw diff between two mana costs without any clever logic	
func compute_diff(cost:ManaCost) -> ManaCost:
	var result:ManaCost = ManaCost.new()
	for k in cost.pool.keys():
		result.pool[k] = self.pool[k] - cost.pool[k]
	return result	

#Pays a Manacost and goes into negatives as needed, to understand what kind of Mana is still missing to pay the cost
func compute_missing(cost:ManaCost) -> ManaCost: 
	# We go from the most specific (Wild)  to the least specific (uncolor) and loop over all the others
	# We create a duplicate and pay from it in order to remove mana progressively
	var temp_pool:ManaCost = ManaCost.new()
	temp_pool.set_cost(self.pool)
	
	#WILD Cost first 
	temp_pool.pool[Resource.WILD] -= cost.pool[Resource.WILD]	
	
	#All Colored Mana/Energy
	for k in cost.pool.keys():
		#skip specific cases
		if (Resource.WILD == k) or (Resource.UNCOLOR == k):
			continue
		temp_pool.pool[k] -= cost.pool[k]

	#UNCOLORED Cost last
	var remaining = cost.pool[Resource.UNCOLOR]
	var i = Resource.WILD
	while (remaining and i > Resource.UNCOLOR) :
		if (temp_pool.pool[i] >= remaining):
			temp_pool.pool[i] -= remaining
			remaining = 0
		elif (temp_pool.pool[i]>0): #we now have cases were some parts of the pool are even negative, can't use those to pay
			remaining -= temp_pool.pool[i]
			temp_pool.pool[i] = 0
		i-=1
	
	temp_pool.pool[Resource.UNCOLOR] -= remaining
		
	return temp_pool	
	


#Returns null if the cost can't be paid, or a new manapool object post payment if cost can be paid	
func can_pay_total_cost(cost:ManaCost) :
	var temp_pool = compute_missing(cost)
	if (temp_pool.is_negative()):
		return null
	return temp_pool
				
	
func pay_total_cost(cost:ManaCost) :
	var temp_pool = can_pay_total_cost(cost)
	if not (temp_pool) :
		return CFConst.ReturnCode.FAILED
	
	#Apply change
	self.pool = temp_pool.pool	
	return CFConst.ReturnCode.CHANGED		


func _on_manapool_modified(_trigger_card: Card, _trigger: String, _details: Dictionary):
	for v in ManaCost.Resource.values() :
			var _retcode: int = cfc.NMAP.board.counters.mod_counter(
			ManaCost.RESOURCE_TEXT[v],
			pool[v],
			true)

func savestate_to_json() -> Dictionary:
	var export_dict:Dictionary = {}
	for v in ManaCost.Resource.values() :
		export_dict[v] = pool[v]	
	
	var json_data:Dictionary = {
		"manapool": export_dict
	}
	return json_data
	
func loadstate_from_json(json:Dictionary):
	.reset() #Init data even if we don't get aything from the json
	var json_data = json.get("manapool", null)
	if (null == json_data):
		return #TODO Error msg
	set_cost(json_data)
