class_name BoardOrganizer
extends Reference

enum BOX_TYPES {
	HORIZONTAL,
	VERTICAL
}

var card_size := CFConst.CARD_SIZE
var card_play_scale := CFConst.PLAY_AREA_SCALE

var my_name
var box_type = BOX_TYPES.HORIZONTAL
var my_children:= []
var my_absolute_position: Vector2
var my_size: Vector2
var my_scale: float = 1

#to compute scale
var max_size: Vector2
var min_size: Vector2
# Declare member variables here. Examples:
# var a = 2
# var b = "text"

func string_to_box_type(string):
	if string.to_lower() == "vertical":
		return BOX_TYPES.VERTICAL
	return BOX_TYPES.HORIZONTAL

func set_absolute_position(position):
	my_absolute_position = position

func setup(def:Dictionary, hero_id, _scale = 0):
	my_name = def.get("name", "")
	my_scale = _scale if _scale else def.get("scale", 1)
	
	box_type = string_to_box_type(def.get("type", "horizontal"))
	var x = def.get("x", 0)
	var y = def.get("y", 0)
	my_absolute_position = Vector2(x, y)
	var hero_id_str = ""
	if hero_id:
		hero_id_str = str(hero_id)

	var width = def.get("width", 0)
	var height = def.get("height", 0)
	my_size = Vector2(width, height)

	var max_width = def.get("max_width", 0)
	var max_height = def.get("max_height", 0)
	max_size = Vector2(max_width, max_height)

	var min_width = def.get("min_width", 0)
	var min_height = def.get("min_height", 0)
	min_size = Vector2(min_width, min_height)
	
	var children = def.get("children", [])
	for child in children:
		var type = child.get("type", "")
		var new_child
		match type:
			"horizontal","vertical":
				new_child = new_instance()
				new_child.setup(child, hero_id, my_scale)
			"pile":
				new_child = cfc.NMAP[child.get("name", "") + hero_id_str]
			"grid":
				new_child = cfc.NMAP.board.get_grid(child.get("name", "") + hero_id_str)
			_:
				new_child = null
		var child_data = {
			"name": child.get("name", "") + hero_id_str,
			"absolute_position": Vector2(0, 0),			
			"position": Vector2(0, 0),
			"size": Vector2(0,0),
			"scale" : child.get("scale", 1),
			"cards_to_display": 0,
			"item" : new_child,
			"type" : type,
		}
		my_children.append(child_data)


func compute_spacer_size(child_data):
	var new_scale = my_scale * child_data["scale"] 
	#add a bit of spacing
	var spacing = Vector2(50, 50) 
	var size = CFConst.CARD_SIZE + spacing
	return new_scale * size 

func compute_pile_size(child_data):
	var child = child_data["item"]
	if !child as Pile:
		return Vector2(0,0)	
		
	var new_scale = my_scale * child_data["scale"] 

	#add a bit of spacing
	var spacing = Vector2(50, 50)

	var size = child.card_size + spacing


	return new_scale * size 

func compute_grid_size(child_data):
	var spacing = Vector2(50, 50)
	
	var child = child_data["item"]
	if !child as BoardPlacementGrid:
		return Vector2(0,0)
	
	var cards = child.get_all_cards()
	if !cards:
		return  my_scale * spacing
	
	#grids have this square shape
	var tmp = child.card_size
	var max_axis = max(tmp.x, tmp.y)
	var _card_size:Vector2 = Vector2(max_axis, max_axis)
	
	var new_scale = my_scale * child_data["scale"] * CFConst.PLAY_AREA_SCALE
	var x = new_scale * (_card_size.x * cards.size() + spacing.x)
	var y = new_scale * (_card_size.y + spacing.y) 
		
	return Vector2(x, y)



func compute_hbox_min_size() -> Vector2:
	var size = Vector2(0, 0)
	
	for child_data in my_children:
		child_data["position"] = Vector2(size.x, 0)
		var child = child_data["item"]
		if child as BoardPlacementGrid:
			var child_size = compute_grid_size(child_data)
			child_data["size"] = child_size
			size.y = child_size.y if size.y < child_size.y else size.y
			size.x += child_size.x
		elif child as Pile:
			var child_size = compute_pile_size(child_data)			
			child_data["size"] = child_size			
			size.y = child_size.y if size.y < child_size.y else size.y
			size.x += child_size.x
		elif child_data["type"] == "spacer":
			var child_size = compute_spacer_size(child_data)			
			child_data["size"] = child_size			
			size.y = child_size.y if size.y < child_size.y else size.y
			size.x += child_size.x		
		else: #this is a hbox/vbox entiry		
			var _min_size = child.compute_min_size()
			child_data["size"] = _min_size
			size.y = _min_size.y if _min_size.y > size.y else size.y
			size.x += _min_size.x
	return size
	
func compute_vbox_min_size() -> Vector2:
	var size = Vector2(0, 0)
	
	for child_data in my_children:
		var child = child_data["item"]
		child_data["position"] = Vector2(0, size.y)
		if child as BoardPlacementGrid:
			var child_size = compute_grid_size(child_data)
			child_data["size"] = child_size
			size.y += child_size.y
			size.x = child_size.x if child_size.x > size.x else size.x
		elif child as Pile:
			var child_size = compute_pile_size(child_data)			
			child_data["size"] = child_size	
			size.y +=child_size.y
			size.x = child_size.x if size.x < child_size.x else size.x
		elif child_data["type"] == "spacer":
			var child_size = compute_spacer_size(child_data)			
			child_data["size"] = child_size	
			size.y +=child_size.y
			size.x = child_size.x if size.x < child_size.x else size.x						
		else: #this is a hbox/vbox entiry
			var _min_size = child.compute_min_size()
			child_data["size"] = _min_size
			size.x = _min_size.x if _min_size.x > size.x else size.x
			size.y += _min_size.y
	return size
	
func compute_min_size() -> Vector2:
	match box_type:
		BOX_TYPES.HORIZONTAL:
			my_size = compute_hbox_min_size()
			return my_size
		BOX_TYPES.VERTICAL:
			my_size = compute_vbox_min_size()
			return my_size	
		_:
			#error
			return Vector2(0,0)

func compute_allowed_scale():
	#we assume min_size has been computed before this!!!
	var final_scale = 1
	
	var _min_size = min_size #* my_scale
	var _max_size = max_size #* my_scale
	
	if _min_size:
		var min_scale_x = _min_size.x / my_size.x
		var min_scale_y = _min_size.y / my_size.y	
		var min_scale = max(min_scale_x, min_scale_y)
		
		if min_scale > 1 and (min_scale > final_scale):
			final_scale = min_scale
	if _max_size:
		var max_scale_x = _max_size.x / my_size.x
		var max_scale_y = _max_size.y / my_size.y	
		var max_scale = min(max_scale_x, max_scale_y)	

		if max_scale < 1 or (max_scale > final_scale):
			final_scale = max_scale
	
	return final_scale	

#we assume min_size has been computed before this!!!
func rescale():
	var scale = compute_allowed_scale()
	for child_data in my_children:
		var child = child_data["item"]
		if child as BoardPlacementGrid:
			if child.get_all_cards():
				child_data["rescale"] = scale	
			pass
		elif child as Pile:
			#TODO
			pass
		elif child_data["type"] == "spacer":
			#TODO
			pass					
		else: #this is a hbox/vbox entiry
			child.rescale()	

#assumes that sizes have been computed for children
func reposition_children():		
	var current_position = my_absolute_position
		
	for child_data in my_children:
		child_data["absolute_position"] = current_position 
		var child = child_data["item"]
		if child as BoardPlacementGrid:
			pass
		elif child as Pile:			
			pass
		elif child_data["type"] == "spacer":
			pass
		else: #this is a hbox/vbox entiry		
			child.my_absolute_position = child_data["absolute_position"] 
			child.reposition_children()
		match box_type:
			BOX_TYPES.HORIZONTAL:
				current_position.x = child_data["absolute_position"].x + child_data["size"].x * child_data.get("rescale", 1)
			_:
				current_position.y = child_data["absolute_position"].y + child_data["size"].y * child_data.get("rescale", 1)		
					
	
#assums positions have been computed	
func display_new_positions():		
	for child_data in my_children:
		var child = child_data["item"]
		var new_position = child_data["absolute_position"]
		var rescale = child_data.get("rescale", 1)
		if child as BoardPlacementGrid:
			child.reposition(new_position)
			var new_scale = my_scale * rescale * child_data["scale"] * CFConst.PLAY_AREA_SCALE
			child.rescale(new_scale)
		elif child as Pile:
			child.set_position(new_position)
			child.set_global_position(new_position)
			var new_scale =  my_scale * rescale * child_data["scale"]
			child.scale = Vector2(new_scale, new_scale)				
		elif child_data["type"] == "spacer":
			pass			
		else: #this is a hbox/vbox entiry
			child.display_new_positions()
			
func organize():

	if cfc.NMAP.board.are_cards_still_animating():
		return
#	var previous_data = to_json(retrieve_all_children_data())	
	
	compute_min_size()
	rescale()
	reposition_children()
	display_new_positions()

#	var new_data = to_json(retrieve_all_children_data())	
#	if new_data != previous_data:
#		cfc.LOG_DICT({"positions" : retrieve_all_children_data()})

func retrieve_all_children_data():
	var children = []
	for child_data in my_children:
		var result = child_data.duplicate()
		var child = child_data["item"]
		if child as BoardPlacementGrid:
			children.append(result)
		elif child as Pile:
			children.append(result)
		elif child_data["type"] == "spacer":
			children.append(result)			
		else: #this is a hbox/vbox entiry
			result["children"] = child.retrieve_all_children_data() 
			children.append(result)	
	return children
			
# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


func new_instance():
	# var obj = MyRef.new() # this would result in a circular reference
	var obj = load(get_script().resource_path).new() # at runtime, the script is already loaded
	return obj

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
