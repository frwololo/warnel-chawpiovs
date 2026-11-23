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

var textures:= {}
var mode = Mode.PLAYER_TURN
var hero_id = 0

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

#runtime stages of the icon
#reset at beginning of turn
#set_active when it's the current one
#set completed when done
#set_inactive in all other cases

func reset():
	set_grayscale_all()
	hide_checkmark()
	
func set_completed():
	set_grayscale_all()	
	show_checkmark()

func set_active():
	set_color_all()
	hide_checkmark()

func set_inactive():
	set_grayscale_all()	
	

func setup(descriptor, _hero_id = 0):
	mode = descriptor
	hero_id = _hero_id

func post_setup():
	#the threat icon has no hero
	var hero_canonical_id = ""
	if hero_id:
		var hero_deck_data = gameData.get_team_member(hero_id)["hero_data"]
		hero_canonical_id = hero_deck_data.get_hero_id()
	
	match mode:
		Mode.PLAYER_TURN:
			load_texture1(hero_canonical_id)
			hide_texture2()
		Mode.THREAT:
			load_texture1("threat")
			hide_texture2()
			label.visible = true
			label.text = "???"			
		Mode.VILLAIN_ACTIVATES:
			load_texture1(hero_canonical_id)
			load_texture2("attack", -15, 15)
		Mode.ENCOUNTER:
			load_texture1(hero_canonical_id)
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
			var new_img = WCUtils.load_img("res://assets/card_backs/generic_back.png")
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
	switch_texture(texture, "grayscale")
	modulate = Color(0.5,0.5,0.5)
	
func set_color_texture(texture):
	switch_texture(texture, "color")
	modulate = Color(1.0,1.0,1.0)

