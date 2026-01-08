# Handles drawing an Object's (primarily a card's) targeting arrow
# and specifying the final target
class_name TargetingArrow
extends Line2D

# Emitted whenever the object spawns a targeting arrow.
signal initiated_targeting
# Emitted whenever the object has selected a target.
signal target_selected(target)
# Emitted whenever the target arrow hovers over a valid target.
signal potential_target_found(target)
# We use this to track multiple potential target objects
# when our owner_card is about to target them.
var _potential_targets := []
# If true, the targeting arrow will be drawn towards the mouse cursor
var is_targeting := false
# Used to store a card succesfully targeted.
# It should be cleared from whichever effect requires a target.
# once it is used
var target_object : Node = null
# Stores a reference to the Card that is hosting this node
onready var owner_object = get_parent()
onready var z_index_owner_object = get_parent()
onready var label = $PanelContainer/Label

enum DISPLAY_MODE {
	NORMAL,
	SHADOW
}

var display_mode = DISPLAY_MODE.NORMAL

func set_display_mode(mode):
	display_mode = mode

var valid_targets: Array = []
var _stored_destination = null
var _show_arrow_head = true

func set_destination(_dest):
	_stored_destination = _dest

func get_stored_destination_position():
	if !_stored_destination:
		return Vector2(0,0)
		
	if (_stored_destination is Vector2):
		return _stored_destination
	#else it's an object.
	if !is_instance_valid(_stored_destination):
		return Vector2(0,0)
		
	if _stored_destination.has_method("get_global_center"):
		  return _stored_destination.get_global_center()
	
	return _stored_destination.get_global_position() + Vector2(40,40)

func reset_destination():
	set_destination(null)
	
func set_valid_targets (objects):
	valid_targets = objects

func get_valid_targets():
	return valid_targets

func _ready() -> void:
	# We set the targetting arrow modulation to match our config specification
	default_color = CFConst.TARGETTING_ARROW_COLOUR
	$ArrowHead.color = CFConst.TARGETTING_ARROW_COLOUR
	# warning-ignore:return_value_discarded
	$ArrowHead/Area2D.connect("area_entered", self, "_on_ArrowHead_area_entered")
	# warning-ignore:return_value_discarded
	$ArrowHead/Area2D.connect("area_exited", self, "_on_ArrowHead_area_exited")
	self.z_index = CFConst.Z_INDEX_BOARD_CARDS_ABOVE + 1

func show_arrow_head():
	_show_arrow_head = true
	
func hide_arrow_head():
	_show_arrow_head = false
	
func set_text(_text):
	label.text = _text
	var dynamic_font = cfc.get_font("res://fonts/Bangers-Regular.ttf", 32)	
	label.add_font_override("font", dynamic_font)	
	label.visible = true
	$PanelContainer.visible = true
	if !_text:
		$PanelContainer.visible = false
		label.visible = false

var _modulate_direction = 1
func _process(_delta: float) -> void:
	if is_targeting:
		var destination = get_stored_destination_position()
		var pointing_to = destination
		if !pointing_to:
			if gamepadHandler.is_mouse_input():
				pointing_to = cfc.NMAP.board.mouse_pointer.determine_global_mouse_pos()	
			else:
				pointing_to = gamepadHandler.get_approx_position()
		_draw_targeting_arrow(pointing_to)
		
	match display_mode:
		DISPLAY_MODE.SHADOW:
			$Highlight.width = 5
			
			var min_z_index = CFConst.Z_INDEX_BOARD_CARDS_ABOVE
			var owner_z_index = CFConst.Z_INDEX_ANNOUNCER
			if z_index_owner_object and is_instance_valid(z_index_owner_object) and "z_index" in z_index_owner_object:
				owner_z_index = z_index_owner_object.z_index
			
			var base_index = min(owner_z_index, min_z_index)
				
			self.z_as_relative = false
			self.z_index = base_index - 1

			if _stored_destination and is_instance_valid(_stored_destination):
				if "z_index" in _stored_destination:
					_stored_destination.z_as_relative = false
					_stored_destination.z_index = base_index
				else:
					var parent = _stored_destination.get_parent()
					if parent and  "z_index" in parent:
						parent.z_index = base_index

			$Highlight.z_as_relative = false
			$Highlight.z_index = self.z_index -1
			var modulate_modification = 1 + _delta * _modulate_direction
			var the_max = $Highlight.modulate.r
			if $Highlight.modulate.g > the_max:
				the_max = $Highlight.modulate.g 
			if $Highlight.modulate.b > the_max:
				the_max = $Highlight.modulate.b
			if the_max * modulate_modification < 0.5:
				_modulate_direction = 1	 
			elif the_max * modulate_modification > 2:
				_modulate_direction = -1
			else:	 					
				$Highlight.modulate *= modulate_modification
				$HighlightArrowHead.modulate *= modulate_modification

				if $Highlight.modulate.a > 1:
					$Highlight.modulate.a = 1
				if $HighlightArrowHead.modulate.a > 1:
					$HighlightArrowHead.modulate.a = 1														

func set_arrow_color(_color):
	default_color = _color
	$ArrowHead.color = _color
	$Line.default_color = _color
	#$Line.modulate = _color

	$Highlight.default_color = _color * 1.2 #Color(0.1, 0.5, 0.5) * 1.3  -> debug
	$Highlight.modulate = _color * 1.2
	$HighlightArrowHead.color = _color * 1.2
	$HighlightArrowHead.modulate = _color * 1.2
	
	
func show_me():
	$ArrowHead/Area2D.monitoring = true
	$Highlight.visible =  true
	match display_mode:
		DISPLAY_MODE.SHADOW:
			$Line.visible = false
			$ArrowHead.visible = false			
		_:
			$Line.visible = true	
			$ArrowHead.visible = _show_arrow_head			
	$HighlightArrowHead.visible = _show_arrow_head
		
func hide_me():
	$ArrowHead.visible = false
	$ArrowHead/Area2D.monitoring = false
	$Highlight.visible = false
	$Line.visible = false
	$HighlightArrowHead.visible = false
	label.visible = false
	$PanelContainer.visible = false

func clear_points():
	.clear_points()
	$Line.clear_points()
	$Highlight.clear_points()
	
func set_color_from_script(script_definition):
	set_arrow_color(CFConst.TARGETTING_ARROW_COLOUR)
	
	var s_name = script_definition.get("name", "")
	if CFConst.TARGET_ARROW_COLOR_BY_NAME.has(s_name):
		set_arrow_color(CFConst.TARGET_ARROW_COLOR_BY_NAME[s_name])
		return
		
	var tags = script_definition.get("tags", [])
	for tag in tags:
		if CFConst.TARGET_ARROW_COLOR_BY_TAG.has(tag):
			set_arrow_color(CFConst.TARGET_ARROW_COLOR_BY_TAG[tag])
			return


# Will generate a targeting arrow on the card which will follow the mouse cursor.
# The top card hovered over by the mouse cursor will be highlighted
# and will become the target when complete_targeting() is called
func initiate_targeting(_valid_targets, _script_definition:Dictionary = {}) -> void:
	set_valid_targets(_valid_targets)
	set_color_from_script(_script_definition)
	is_targeting = true
	show_me()
	emit_signal("initiated_targeting")
	scripting_bus.emit_signal("initiated_targeting", owner_object)


func cancel_targeting() -> void:
	#TODO send another signal
	if !is_targeting:
		return
	
	reset_destination()		
	is_targeting = false
	clear_points()
	hide_me()	
	emit_signal("target_selected",target_object)
	scripting_bus.emit_signal("target_selected", owner_object, {"target": target_object})		
# Will end the targeting process.
#
# The top targetable object which is hovered (if any) will become the target and inserted
# into the target_object property for future use.
func complete_targeting() -> void:
	if !is_targeting:
		return
		
	if !len(_potential_targets):
		return
		
	var tc = _potential_targets.back()
	if !(tc in valid_targets):
		return
		
	# We don't want to emit a signal, if the card is a dummy viewport card
	# or we already selected a target during dry-run
	if owner_object.get_parent() != null \
			and owner_object.get_parent().name != "Viewport":
		# We make the targeted card also emit a targeting signal for automation
		scripting_bus.emit_signal("card_targeted", tc,
				{"targeting_source": owner_object})
	target_object = tc
	reset_destination()	
	is_targeting = false
	clear_points()
	hide_me()
	emit_signal("target_selected",target_object)
	scripting_bus.emit_signal("target_selected", owner_object, {"target": target_object})	

#for internal testing
func force_select_target(target):
	_potential_targets.append(target)
	complete_targeting()

# Triggers when a targetting arrow hovers over another card while being dragged
#
# It takes care to highlight potential cards which can serve as targets.
func _on_ArrowHead_area_entered(area: Area2D) -> void:
	
	#Code for targeting Top card of Piles
	var area_class = area.get_class()
	if area_class == "CardContainer" and area.has_method("get_top_card"):
		var top_card = area.get_top_card()
		if top_card:
			area = top_card
			
	if !(area in valid_targets):
		return
			
	if area.get_class() == 'Card' and not area in _potential_targets:

		_potential_targets.append(area)
		if 'highlight' in owner_object:
			owner_object.highlight.highlight_potential_card(
					CFConst.TARGET_HOVER_COLOUR, _potential_targets)
		emit_signal("potential_target_found", area)


# Triggers when a targetting arrow stops hovering over a card
#
# It clears potential highlights and adjusts potential cards as targets
func _on_ArrowHead_area_exited(area: Area2D) -> void:
	#Code for targeting Top card of Piles
	var area_class = area.get_class()
	if area_class == "CardContainer" and area.has_method("get_top_card"):
		var top_card = area.get_top_card()
		if top_card:
			area = top_card
				
	if area.get_class() == 'Card' and area in _potential_targets:
		# We remove the card we stopped hovering from the _potential_targets
		_potential_targets.erase(area)
		# And we explicitly hide its cards focus since we don't care about it anymore
		if 'highlight' in area:
			area.highlight.set_highlight(false)
		# Finally, we make sure we highlight any other cards we're still hovering
		if not _potential_targets.empty() and 'highlight' in owner_object:
			owner_object.highlight.highlight_potential_card(
				CFConst.TARGET_HOVER_COLOUR,
				_potential_targets)


# Draws a curved arrow, from the center of a card, to the mouse pointer
func _draw_targeting_arrow(destination = null) -> void:
	if (!destination):
		destination = get_stored_destination_position()
	# This variable calculates the card center's position on the whole board
	var card_half_size
	if "rect_size" in owner_object:
		card_half_size = owner_object.rect_size/2 * owner_object.rect_scale * cfc.screen_scale
	else: 
		card_half_size = owner_object.card_size/2 * owner_object.scale * cfc.screen_scale
	var centerpos = global_position + card_half_size #* scale
	# We want the line to be drawn anew every frame
	clear_points()
	# The final position is the mouse position,
	# but we offset it by the position of the card center on the map
	var final_point =  destination \
			- (position + card_half_size)
	var curve = Curve2D.new()
#		var middle_point = centerpos + (get_global_mouse_position() - centerpos)/2
#		var middle_dir_to_vpcenter = middle_point.direction_to(get_viewport().size/2)
#		var offmid = middle_point + middle_dir_to_vpcenter * 50
	# Our starting point has to be translated to the local position of the Line2D node
	# The out control point is the direction to the screen center,
	# with a magnitude that I found via trial and error to look good
	curve.add_point(to_local(centerpos),
			Vector2(0,0),
			centerpos.direction_to(get_viewport().size/2) * 75)
#		curve.add_point($TargetLine.to_local(offmid), Vector2(0,0), Vector2(0,0))
	# Our end point also has to be translated to the local position of the Line2D node
	# The in control point is likewise the direction to the screen center
	# with a magnitude that I found via trial and error to look good
	curve.add_point(to_local(position +
			card_half_size + final_point),
			Vector2(0, 0), Vector2(0, 0))
	# Finally we use the Curve2D object to get the points which will be drawn
	# by our lined2D
	var curve_points = curve.get_baked_points()
	#set_points(curve_points)
	$Highlight.set_points(curve_points)
	$Line.set_points(curve_points)
	
	# We place the arrowhead to start from the last point in the line2D
	$ArrowHead.position = $Highlight.get_point_position(
			$Highlight.get_point_count( ) - 1)
	# We delete the last 3 Line2D points, because the arrowhead will
	# be covering those areas
	for _del in range(1,4):
		$Line.remove_point($Line.get_point_count( ) - 1)
		$Highlight.remove_point($Highlight.get_point_count( ) - 1)
	# We setup the angle the arrowhead is pointing by finding the angle of
	# the last point on the line towards the mouse position
	$ArrowHead.rotation = $Highlight.get_point_position(
				$Highlight.get_point_count( ) - 1).direction_to(
				to_local(position + card_half_size + final_point)).angle()

	$HighlightArrowHead.position = $ArrowHead.position
	$HighlightArrowHead.rotation =  $ArrowHead.rotation
	$PanelContainer.rect_position = $ArrowHead.position + Vector2(15, -15)
