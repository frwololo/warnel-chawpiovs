# Data that represents the available mana/energy for the player
class_name ManaPool
extends ManaCost



# Called when the node enters the scene tree for the first time.
func _init():
	pass


#Pays a Manacost and goes into negatives as needed, to understand what kind of Mana is still missing to pay the cost
func compute_missing(cost:ManaCost) :
	# We go from the most specific (Wild)  to the least specific (uncolor) and loop over all the others
	# We create a duplicate and pay from it in order to remove mana progressively
	var temp_pool:ManaPool = self.duplicate()
	
	#WILD Cost first 
	temp_pool.pool[Resource.WILD] -= cost[Resource.WILD]	
	
	#All Colored Mana/Energy
	for k in cost.pool.keys():
		#skip specific cases
		if (Resource.WILD == k) or (Resource.UNCOLOR == k):
			continue
		temp_pool.pool[k] -= cost[k]

	#UNCOLORED Cost last
	var remaining = cost[Resource.UNCOLOR]
	var i = Resource.WILD
	while (remaining and i >= Resource.UNCOLOR) :
		if (temp_pool.pool[i] >= remaining):
			temp_pool.pool[i] -= remaining
			remaining = 0
		elif (temp_pool.pool[i]>0): #we now have cases were some parts of the pool are even negative, can't use those to pay
			remaining -= temp_pool.pool[i]
			temp_pool.pool[i] = 0
		i-=1
		
	return temp_pool	
	
#Return true if this mana pool represents a cost deficit (at least one of its members is negative)	
func is_negative() :		
	for v in pool.values():
		if v < 0 :
			return true
	return false

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
