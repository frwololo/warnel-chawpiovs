extends VBoxContainer

onready var main_screen = find_parent("DeckManagement")
onready var deck_picture: TextureButton = get_node("%DeckPicture")
onready var deck_label: Label = get_node("%DeckName")
onready var aspects_container = get_node("%AspectsContainer")
#onready var playerName := $PlayerName
#onready var kick := $Kick
var deck_id = 0
var hero_id = 0
var deck_data:= {}
var color_tex: Texture = null


const ASPECT_TO_ICON = {
	"aggression":"aspect_red.png",
	"leadership": "aspect_blue.png",
	"protection": "aspect_green.png",
	"justice": "aspect_yellow.png"
		
}

func _ready():
	resize()
	# warning-ignore:return_value_discarded
	get_viewport().connect("gui_focus_changed", self, "gui_focus_changed")
	# warning-ignore:return_value_discarded
	get_viewport().connect("size_changed", self, '_on_Menu_resized')
	deck_picture.connect("gui_input", self, "_on_gui_input")
	#var hero_name = cfc.get_card_name_by_id(hero_id)
	if deck_data:
		deck_label.set_text(simplified_deck_name())

	if color_tex:
		deck_picture.texture_normal = color_tex
	
		
func get_texture():
	return deck_picture.texture_normal

var _simplified_deck_name = ""
func simplified_deck_name():
	if _simplified_deck_name:
		return _simplified_deck_name
		
	if !deck_data:
		_simplified_deck_name = "--"
		return _simplified_deck_name
	
	var deck_name = deck_data["name"]
	var hero_name = cfc.get_card_name_by_id(hero_id)
	deck_name = deck_name.replacen(hero_name, "").trim_prefix(" ")
	deck_name = deck_name.trim_prefix("- ")
	_simplified_deck_name = deck_name
	return _simplified_deck_name


func get_display_name():
	return simplified_deck_name()
	
func resize():
	var stretch_mode = cfc.get_screen_stretch_mode()
	if stretch_mode != SceneTree.STRETCH_MODE_VIEWPORT:
		return

	var screen_size = get_viewport().size
	var grid_width = screen_size.x * 0.9
	if screen_size.x > CFConst.LARGE_SCREEN_WIDTH:
		pass
	var columns = get_parent().columns
	var image_size = grid_width / columns
	
	deck_picture.rect_min_size = Vector2(image_size, image_size / 2)

	
	deck_picture.rect_size = deck_picture.rect_min_size	
	$Panel/HorizontalHighlights.rect_min_size = deck_picture.rect_min_size
	$Panel/VerticalHighlights.rect_min_size = deck_picture.rect_min_size
	$Panel/HorizontalHighlights.rect_size = deck_picture.rect_size
	$Panel/VerticalHighlights.rect_size = deck_picture.rect_size			
func grab_focus():
	deck_picture.grab_focus()

func get_deck_picture(callback_owner = null) -> Texture:
	var area = 	Rect2 ( 60, 70, 170, 100 )
	if !deck_data:
		return cfc.fallback_hero_portrait(deck_id, area)
	var my_hero_id = deck_data["hero_code"]	
	var result = cfc.get_sub_texture(my_hero_id, area)
	if result:
		return result
	#if we failed, assume we need to download the picture
	#then callback the caller
	if callback_owner:
		gameData.urgent_image_download(hero_id, callback_owner)
	return cfc.fallback_hero_portrait(hero_id, area)

func card_image_download_complete(card_id):
	if card_id != hero_id:
		return
	reload_texture()

func reload_texture():
	if !deck_data:
		return

	var texture = get_deck_picture()
	if (texture):
		color_tex = texture
		deck_picture.texture_normal = color_tex

func load_deck(_deck_data):
	deck_data = _deck_data.duplicate()
	hero_id = deck_data["hero_code"]
	deck_id = deck_data["id"]


	var texture = get_deck_picture(self)
	if (texture):
		color_tex = texture

func _process(_delta):
	refresh_display()

var _needs_refresh = true
func refresh_display():
	if !_needs_refresh:
		return
	
	for c in aspects_container.get_children():
		aspects_container.remove_child(c)
	
	var aspects = compute_aspects()
	for aspect in aspects:
		var img_name = ASPECT_TO_ICON[aspect] 

		var textrect : TextureRect = TextureRect.new()
		var new_texture = ImageTexture.new();
		var tex = load(CFConst.PATH_ASSETS + "icons/" + img_name)
		var image = tex.get_data()
		new_texture.create_from_image(image)
		textrect.texture = new_texture
		aspects_container.add_child(textrect)	
		textrect.rect_min_size = Vector2(20,20)	
		textrect.expand = true
	_needs_refresh = false

var _max_aspect_cache = []	
func compute_aspects():
	if _max_aspect_cache:
		return _max_aspect_cache
			
	var slots = deck_data.get("slots", {})
	var slots_by_aspect = {}
	
	for card_id in slots:
		var card_data = cfc.get_card_by_id(card_id)
		var aspect = card_data["faction_code"].to_lower()
		if !aspect in ASPECT_TO_ICON.keys():
			continue
		var quantity = slots[card_id]
			
		if !slots_by_aspect.has(aspect):
			slots_by_aspect[aspect] = 0
		
		slots_by_aspect[aspect] +=quantity

	var sorting_list := []
	for s in slots_by_aspect:
		sorting_list.append({
					"type": s,
					"value": -slots_by_aspect[s]
				})
	sorting_list.sort_custom(CFUtils,'sort_by_card_field')
	
	_max_aspect_cache = []
	for i in sorting_list.size():
		if sorting_list[i]["type"]:
			_max_aspect_cache.append(sorting_list[i]["type"])
			
	return _max_aspect_cache			

func gui_focus_changed(control):
	if control == deck_picture:
		gain_focus()
	else:
		lose_focus()

func gain_focus():
	pass
#	if !gamepadHandler.is_mouse_input():
#		show_highlights()

func show_highlights():
	$Panel/VerticalHighlights.visible = true
	$Panel/HorizontalHighlights.visible = true
	$Panel/HorizontalHighlights.rect_size = deck_picture.rect_size
	#$HorizontalHighlights.rect_position = rect_position
	$Panel/VerticalHighlights.rect_size = deck_picture.rect_size	
	
func lose_focus():
	pass
#	hide_highlights()

func hide_highlights():
	$Panel/VerticalHighlights.visible = false
	$Panel/HorizontalHighlights.visible = false
	
func _on_gui_input(event):
	if event is InputEventMouseButton: #TODO better way to handle Tablets and consoles
		if event.button_index == BUTTON_LEFT:
			if event.doubleclick:
				main_screen.edit_deck(deck_data)				
			elif !event.pressed:
				yield(get_tree().create_timer(0.1), "timeout") #prevent confusing with double click
				action()
			

func _on_HeroPicture_mouse_entered():
	pass
	#gain_focus()



func _on_HeroPicture_mouse_exited():
	pass
	#lose_focus()


func action():
	main_screen.deck_selected(deck_id)
	show_highlights()
	

func _on_Menu_resized() -> void:
	resize()

func export_for_mcdb():		
	var slots = deck_data.get("slots", {})
	var slots_by_type = {}
	var hero_data = cfc.get_card_by_id(deck_data.get("hero_code", ""))
	
	for card_id in slots:
		var card_data = cfc.get_card_by_id(card_id)
		var type = card_data["type_code"].to_lower()

		if type in ["hero"]:
			continue

		var quantity = slots[card_id]
			
		if !slots_by_type.has(type):
			slots_by_type[type] = []
		
		var fullname = card_data["shortname"]
#		if card_data.get("subname", ""):
#			fullname += ": " + card_data["subname"]
		slots_by_type[type].append(str(quantity) +"x " +  fullname + " (" + card_data["pack_name"]  + ")")

	var result = ""
	result += hero_data["Name"] + " ("+ hero_data["pack_name"] + ")" + "\n"
	for type in slots_by_type:
		result+= "\n" + type.capitalize() +"\n"
		for slot in slots_by_type[type]:
			result+= slot + "\n"
		
	return result
