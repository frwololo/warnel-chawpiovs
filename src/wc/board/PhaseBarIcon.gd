class_name PhaseBarIcon
#a Control (not a Node2D): it goes in the phase bar's HBoxContainers, which
#only lay out Controls
extends Control

enum Mode {
	PLAYER_TURN,
	THREAT,
	VILLAIN_ACTIVATES,
	ENCOUNTER
}

onready var texture1:TextureRect = get_node("%Texture1")
onready var texture2:TextureRect = get_node("%Texture2")
onready var checkmark:TextureRect = get_node("%Checkmark")
onready var label:Label = get_node("%Label")
var is_active = false

var textures:= {}
var mode = Mode.PLAYER_TURN
var hero_id = 0
var desc_text = ""
#what the hero textures currently show (see refresh_identity)
var _shown_identity_id = ""
var _shown_alter_ego = false
#whether the textures are in color or grayscale (set_color/grayscale_texture)
var _colored = false

# Called when the node enters the scene tree for the first time.
func _ready():
	label.visible = false
	checkmark.visible = false
	post_setup()
	

func load_texture1(descriptor, position_x = 0, position_y = 0):
	load_texture(texture1, descriptor, position_x, position_y)
	
func load_texture2(descriptor, position_x = 0, position_y = 0):
	load_texture(texture2, descriptor, position_x, position_y)
	
func set_grayscale_texture1():
	set_grayscale_texture(texture1)
	
func set_grayscale_texture2():
	set_grayscale_texture(texture2)

func set_grayscale_all():
	set_grayscale_texture(texture1)
	set_grayscale_texture(texture2)
	
func set_color_texture1():
	set_color_texture(texture1)
	
func set_color_texture2():
	set_color_texture(texture2)		
	
func set_color_all():
	set_color_texture(texture1)
	set_color_texture(texture2)	
	
func hide_texture2():
	texture2.visible = false		

func show_texture2():
	texture2.visible = true	

func hide_checkmark():
	checkmark.visible = false		

func show_checkmark():
	checkmark.visible = true	

func get_desc_text():
	if !desc_text:
		#the threat icon has no hero
		var hero_canonical_id = ""
		var hero_name = ""
		if hero_id:
			var hero_deck_data = gameData.get_team_member(hero_id)["hero_data"]
			hero_canonical_id = hero_deck_data.get_hero_id()
			hero_name = gameData.get_hero_name(hero_id)
	
		match mode:
			Mode.PLAYER_TURN:
				desc_text = "Player Turn (" + hero_name + ")" 
			Mode.THREAT:
				desc_text = "Villain adds threat on the main scheme" 			
			Mode.VILLAIN_ACTIVATES:
				desc_text = "Villain and minions activate against " + hero_name
			Mode.ENCOUNTER:
				desc_text = hero_name + " reveals encounter(s)"
			_:
				#unsupported
				desc_text = ""
	
	return desc_text

#runtime stages of the icon
#reset at beginning of turn
#set_active when it's the current one
#set completed when done
#set_inactive in all other cases

func reset():
	is_active = false
	set_grayscale_all()
	hide_checkmark()
	
func set_completed():
	is_active = false
	set_grayscale_all()	
	show_checkmark()

func set_active():
	is_active = true
	set_color_all()
	hide_checkmark()

func set_inactive():
	is_active = false
	set_grayscale_all()	
	

func setup(descriptor, _hero_id = 0):
	mode = descriptor
	hero_id = _hero_id

#card id of the hero's current form: the identity card's (hero or alter-ego),
#or the hero's id before the identity card is on the board
func _get_identity_id() -> String:
	if !hero_id:
		return ""
	var identity = gameData.get_identity_card(hero_id)
	if is_instance_valid(identity):
		var code = identity.properties.get("_code", "")
		if code:
			return code
	var hero_deck_data = gameData.get_team_member(hero_id)["hero_data"]
	return hero_deck_data.get_hero_id()

func _is_alter_ego() -> bool:
	if !hero_id:
		return false
	var identity = gameData.get_identity_card(hero_id)
	return is_instance_valid(identity) and identity.is_alter_ego_form()

#the portrait of the hero's current form and, for the villain's activation,
#attack (hero form) or thwart (alter-ego form)
func _load_identity_textures():
	_shown_identity_id = _get_identity_id()
	_shown_alter_ego = _is_alter_ego()
	load_texture1(_shown_identity_id)
	if mode == Mode.VILLAIN_ACTIVATES:
		load_texture2("thwart" if _shown_alter_ego else "attack", -15, 15)

#after the hero changed form: reloads the textures if what they show changed
func refresh_identity():
	if !hero_id or !texture1:
		return
	if _get_identity_id() == _shown_identity_id and _is_alter_ego() == _shown_alter_ego:
		return
	_load_identity_textures()
	#the name can change too
	desc_text = ""
	#load_texture shows the color textures: back to the current look
	if _colored:
		set_color_all()
	else:
		set_grayscale_all()

func post_setup():
	match mode:
		Mode.PLAYER_TURN:
			_load_identity_textures()
			hide_texture2()
		Mode.THREAT:
			load_texture1("threat")
			hide_texture2()
			label.visible = true
			label.text = "???"			
		Mode.VILLAIN_ACTIVATES:
			_load_identity_textures()
		Mode.ENCOUNTER:
			_load_identity_textures()
			load_texture2("card_back", -15, 15)
		_:
			#unsupported
			pass
	reset()
	
func load_texture(texture:TextureRect, descriptor, position_x, position_y):
	var prefix = texture.name.to_lower()
	var color_tex = null
	var grayscale_tex = null
	
	match descriptor:
		"card_back":
			var new_img = WCUtils.load_img("user://Gfx/card_back.png")
			if not new_img:
				new_img = WCUtils.load_img("res://assets/card_backs/generic_back.png")
			if not new_img:
				return null	
			color_tex = ImageTexture.new()
			color_tex.create_from_image(new_img)
		"attack", "thwart", "threat":
			var new_img = WCUtils.load_img("res://assets/icons/" + descriptor + ".png")
			if not new_img:
				return null	
			color_tex = ImageTexture.new()
			color_tex.create_from_image(new_img)				
		_:
			#other use cases are hero ids
			color_tex = cfc.get_hero_portrait(descriptor)

	if color_tex:
		grayscale_tex = WCUtils.to_grayscale(color_tex)
		texture.texture = color_tex
		texture.rect_position = Vector2(position_x, position_y)
		#texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		
		textures[prefix + "_color"] = color_tex
		textures[prefix + "_grayscale"] = grayscale_tex		
	
	pass
	
func switch_texture(texture_rect, descriptor):
	var prefix = texture_rect.name.to_lower()
	var texture = textures.get(prefix + "_" + descriptor, null)
	if texture:
		texture_rect.texture = texture
	pass
	
func set_grayscale_texture(texture):
	_colored = false
	switch_texture(texture, "grayscale")
	modulate = Color(0.5,0.5,0.5)
	
func set_color_texture(texture):
	_colored = true
	switch_texture(texture, "color")
	modulate = Color(1.0,1.0,1.0)

