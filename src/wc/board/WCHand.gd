extends Hand

# set_placement_groups and reset_location moved from src/core CardContainer modifications
func set_placement_groups():
	match placement:
		Anchors.NONE:
			pass
		Anchors.TOP_LEFT, Anchors.LEFT_MIDDLE, Anchors.BOTTOM_LEFT:
			add_to_group("left")
		Anchors.TOP_RIGHT, Anchors.RIGHT_MIDDLE, Anchors.BOTTOM_RIGHT:
			add_to_group("right")
	match placement:
		Anchors.TOP_LEFT, Anchors.TOP_MIDDLE, Anchors.TOP_RIGHT:
			add_to_group("top")
		Anchors.BOTTOM_LEFT, Anchors.BOTTOM_MIDDLE, Anchors.BOTTOM_RIGHT:
			add_to_group("bottom")

func reset_location():
	var place := Vector2(0,0)
	if (self.visible):
		# Here we match the adjust the default position based on the anchor
		# First we adjust the x position
		set_placement_groups()
		match placement:
			Anchors.NONE:
				place = position
			# Left position always start from x == 0,
			# which means left side of the viewport
			Anchors.TOP_LEFT, Anchors.LEFT_MIDDLE, Anchors.BOTTOM_LEFT:
				place.x = 0
			# Right position always start from the right-side of the viewport
			# minus the width of the container
			Anchors.TOP_RIGHT, Anchors.RIGHT_MIDDLE, Anchors.BOTTOM_RIGHT:
				place.x = get_viewport().size.x - (card_size.x * scale.x)
			# Middle placement is the middle of the viewport width,
			# minues half the height of the container
			Anchors.TOP_MIDDLE, Anchors.BOTTOM_MIDDLE:
				place.x = get_viewport().size.x / 2 - (card_size.x / 2 * scale.x)
		# Now we adjust the y position. Same logic for
		match placement:
			# Top position always start from y == 0,
			# which means top of the viewport
			Anchors.TOP_LEFT, Anchors.TOP_MIDDLE, Anchors.TOP_RIGHT:
				place.y = 0
			# Bottom position always start from the bottom of the viewport
			# minus the height of the container
			Anchors.BOTTOM_LEFT, Anchors.BOTTOM_MIDDLE, Anchors.BOTTOM_RIGHT:
				place.y = get_viewport().size.y - (card_size.y * scale.y)
			# Middle placement is the middle of the viewport height
			# minus half the height of the container
			Anchors.RIGHT_MIDDLE, Anchors.LEFT_MIDDLE:
				place.y = get_viewport().size.y / 2 - (card_size.y / 2 * scale.y)
		# Now we try to discover if more than one CardContainer share
		# the same anchor and the figure out which to displace.
		var duplicate_anchors := {}
		# All CardContainer belong to the "card_containers" group
		# So we gather them in a list
		for container in get_tree().get_nodes_in_group("card_containers"):
			# I could have made this code a bit more optimal
			# but Godot didn't like that sort of logic
			# So I just ensure each anchor is a key, and contains
			# an empty list
			if (container.visible):
				if not duplicate_anchors.get(container.placement):
					duplicate_anchors[container.placement] = []
				# For each anchor, I add to the list all the CardContainers
				# which are placed in that anchor
				duplicate_anchors[container.placement].append(container)
		# Hook for the debugger
		if _debugger_hook:
			pass
		for anchor in duplicate_anchors:
			# I only iterate on the anchor that this CardContainer is set
			# And only if there's more than one CardContainer using it.
			if anchor == placement and duplicate_anchors[anchor].size() > 1:
				# This variable will hold all the CardContainers which share it
				var cc_array =  duplicate_anchors[anchor]
				# This function sorts the CardContainers sharing the same anchor
				# based on their preferred index to push.
				# If they're set to push the "lowest" index, then the
				# containers with thew lower index will be pushed to the
				# back of the array.
				# Otherwise the containers with the highest index will be at
				# The back of the array.
				# This allows us to control which node will be "pushed".
				cc_array.sort_custom(CFUtils,"sort_by_shift_priority")
				# We reset this variable every time
				accumulated_shift = Vector2(0,0)
				# Now we start going through the sorted array of CardContainers
				# Since the array is sorted from not-moved, to move-the-furthest
				# We will adjust the amount we move by the amount of others
				# Which we have passed through
				for cc in cc_array:
					# if we find self, then we stop. If self is the first
					# container in the array, this means it won't move at all
					if cc == self:
						place += accumulated_shift
						break
					# If we didn't find self, then we increase the amount
					# This container will move, by the combined size of
					# other containers in the array before it.
					match overlap_shift_direction:
						CFInt.OverlapShiftDirection.UP:
							accumulated_shift.y -= cc.control.rect_size.y
						CFInt.OverlapShiftDirection.DOWN:
							accumulated_shift.y += cc.control.rect_size.y
						CFInt.OverlapShiftDirection.LEFT:
							accumulated_shift.x -= cc.control.rect_size.x
						CFInt.OverlapShiftDirection.RIGHT:
							accumulated_shift.x += cc.control.rect_size.x
	# Finally, we move to the right location.
	position = place
	call_deferred("_init_control_size")

# disable and enable moved from src/core Hand modifications
func disable():
	visible = false
	$CollisionShape2D.disabled = true

func enable():
	visible = true
	$CollisionShape2D.disabled = false

func _ready() -> void:
	# warning-ignore:return_value_discarded
	$Control/ManipulationButtons/DiscardRandom.connect("pressed",self,'_on_DiscardRandom_Button_pressed')
	excess_cards = ExcessCardsBehaviour.ALLOW

func _process(_delta: float) -> void:
	var hero_id = get_my_hero_id()
	var hero = gameData.get_identity_card(hero_id)
	if hero:
		self.hand_size = hero.get_max_hand_size()

func set_control_size(x, y):
	$Control.rect_min_size = Vector2(x,y)
	$Control.rect_size = $Control.rect_min_size

func calculate_others_offset()-> Vector2:
	var result = Vector2(0,0)
	for group in ["top","bottom", "left", "right"]:
		var my_groups = get_groups()
		if group in my_groups:
			# We check how many other containers are in the same row/column
			for other in get_tree().get_nodes_in_group(group):
				if !other.visible:
					continue
				if other == self:
					continue
				if other.position.x + other.control.rect_size.x > result.x:
						result.x = other.position.x + other.control.rect_size.x

	return result

# Overrides the re_place() function of [CardContainer] in order
# to also resize the hand rect, according to how many other
# CardContainers exist in the same row/column
func re_place() -> void:
	if self.name.to_lower().begins_with("ghost"):
		var my_cards = get_all_cards()
		if !my_cards or get_my_hero_id() != gameData.get_current_local_hero_id():
			self.visible = false
			self.disable()
		else:
			self.visible = true
			self.enable()

	if !self.visible:
		return


	reset_location()

	#$Control.rect_size.y = card_size.y


	if self.name.to_lower().begins_with("ghost"):
		#ghosthand has an absolute position
		var total_cards = get_all_cards().size()
		var expected_size_x = total_cards * card_size.x
		if expected_size_x:
			expected_size_x = max(expected_size_x, get_viewport().size.x/3)
		expected_size_x = min (get_viewport().size.x/2, expected_size_x)
		set_control_size(expected_size_x, card_size.y)
		position.x = 100

	else:
		#hand's position depends on ghosthand
		var offset = calculate_others_offset()
		var offset_right = Vector2(200,0)
		var control_size = get_viewport().size - offset_right  - offset
		position.x = offset.x
		set_control_size(control_size.x, card_size.y)

	# If the hand is supposed to be shifted slightly outside the viewport
	# we do it now.
	if placement == Anchors.CONTROL:
		# When the hand is adjusted by the parent control, its default position should always be 0
		position.y = bottom_margin
	else:
		# When the hand is adjusted by its anchor
		# we need to move adjust it according to the margin
		position.y += bottom_margin
	# Finally we make sure the cards organize according to the new
	# hand-size.

	var _tmp = self.name
	_adjust_collision_area()

	if not cfc.ut:
		yield(get_tree(), "idle_frame")
	for c in get_all_cards():
		c.interruptTweening()
		c.reorganize_self()

func _adjust_collision_area() -> void:
	if ($CollisionShape2D.disabled):
		return
	#$CollisionShape2D.disabled = true

	var control_size = $Control.rect_size
	var _position = self.position
	var _extents = $CollisionShape2D.shape.extents
	var new_extents = Vector2(round(control_size.x/2), round(control_size.y/2))

	$CollisionShape2D.shape.extents =  new_extents #control_size / 2
	$CollisionShape2D.position = control_size / 2
	highlight.rect_size = control_size



	if self.name.to_lower().begins_with("ghost"):
		pass
	else:
		pass

func get_my_hero_id():
	var hero_id = self.name.substr(self.name.length()-1)
	return int(hero_id)

func reorganize_hands():
	if self.name.to_lower().begins_with("ghost"):
		self.re_place()
		cfc.NMAP["hand" + str(get_my_hero_id())].re_place()

func add_child(node:Node, legible_unique_name:bool=false):
	.add_child(node, legible_unique_name)
	reorganize_hands()


func remove_child(node:Node):
	.remove_child(node)
	reorganize_hands()

func retrieve_ghostable_scripts(card):
	var state_exec = card.get_state_exec()

	if (state_exec != "pile"):
		return null

	var parent = card.get_parent()
	if !parent:
		return null

	if !parent.is_in_group("player_discard"):
		return	null

	var card_scripts = card.retrieve_scripts("manual", {"requesting_hero_id" :  get_my_hero_id()})
	if !card_scripts:
		return null

	var state_scripts = []
	# We select which scripts to run from the card, based on it state
	var any_state_scripts = card_scripts.get('all', [])
	state_scripts = card_scripts.get(state_exec, any_state_scripts)
	return state_scripts

func check_ghost_card(card):
	var has_card = null
	for c in self.get_all_cards():
		if c.get_real_card() == card:
			has_card = c
			break

	var scripts = retrieve_ghostable_scripts(card)
	if (scripts):
		if (!has_card):
			has_card = cfc.instance_ghost_card(card, get_my_hero_id())
			add_child(has_card)
	else:
		if (has_card):
			remove_child(has_card)
			has_card.queue_free()
