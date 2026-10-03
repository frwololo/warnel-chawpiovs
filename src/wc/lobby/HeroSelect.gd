extends VBoxContainer

onready var lobby = find_parent("TeamSelection")
onready var hero_picture: TextureButton = get_node("%HeroPicture")
onready var hero_name_label: Label = get_node("%HeroName")
#onready var playerName := $PlayerName
#onready var kick := $Kick
var hero_id
var grayscale_tex = null
var color_tex = null
var available = true

#animation
var target_container = null
var target_index = Vector2(0,0)
var id_in_container = 0
var total_objects_in_container = 0
var animate = false 
var use_shader = true
var shader_loaded = false
var shader_active = false
var shader_progress = 0.0

func _ready():
	if color_tex:
		hero_picture.texture_normal = color_tex
		resize()
		# warning-ignore:return_value_discarded
		get_viewport().connect("gui_focus_changed", self, "gui_focus_changed")
	# warning-ignore:return_value_discarded
	get_viewport().connect("size_changed", self, '_on_Menu_resized')
	cfc.connect("locale_changed", self, "_game_locale_changed")
	$Tween.connect("tween_all_completed", self, "_tween_completed")
	var animate_menu = cfc.get_setting("animate_menu")
	animate = true if animate_menu else false
	use_shader =  (animate_menu == 2)
	#animation
	if animate:

		if use_shader:
			self.modulate.a = 0
			var reverse_delay = id_in_container
			
			var delay = (randi() % ((int(total_objects_in_container* 2.5)) - (reverse_delay * 2))) 
			delay  = float(delay) * 0.01
			cfc.play_sfx("shuffle")
			yield(get_tree().create_timer(delay/2), "timeout")
			
			yield(get_tree().create_timer(delay/2), "timeout")
			#this uses https://github.com/cashew-olddew/Universal-Transition-Shader
			self.modulate.a = 1

			hero_picture.modulate = CFConst.TRANSITION_HIGHLIGHT_COLORS["default"]

			$Tween.interpolate_property(
					hero_picture,'modulate', hero_picture.modulate,
					Color(1.0,1.0,1.0,1.0),
					0.5, Tween.TRANS_LINEAR, Tween.EASE_OUT)
			$Tween.start()	

			var material = load(CFConst.PATH_CUSTOM + "shaders/transition.gdshader")
			hero_picture.material = ShaderMaterial.new()
			hero_picture.material.set("shader", material)
			var shader_settings = CFConst.TRANSITION_SHADER_PARAMS.get("team_selection")
			for setting in shader_settings:
				var value = shader_settings[setting]
				if typeof(value) == TYPE_DICTIONARY:
					continue
				hero_picture.material.set_shader_param(setting,value) 
			
			shader_progress = 1.0	
			hero_picture.material.set_shader_param("progress", shader_progress)					
			shader_loaded = true
			shader_active = true
			hero_name_label.modulate.a = 0
		else: 
			self.modulate.a = 0.01
			if target_container:
				self.set_global_position(Vector2(600 + randi()%200 , 100 + randi()%200))
				self.rect_scale = Vector2(6.0, 6.0)
				var size_offset = Vector2(3, -3)
				var target_position = Vector2(target_index.x * (self.rect_size.x + size_offset.x), target_index.y * (self.rect_size.y+ size_offset.y))
				var offset = target_container.rect_global_position
				
				target_position += offset
			
				$Tween.interpolate_property(
						self,'rect_scale', self.rect_scale,
						Vector2(1.0, 1.0),
						1, Tween.TRANS_BOUNCE, Tween.EASE_OUT)
				$Tween.interpolate_property(
						self,'rect_global_position', self.rect_global_position,
						target_position,
						1, Tween.TRANS_BOUNCE, Tween.EASE_OUT)
						
			$Tween.interpolate_property(
					self,'modulate', self.modulate,
					Color(1.0,1.0,1.0,1.0),
					1, Tween.TRANS_LINEAR, Tween.EASE_OUT)								
			$Tween.start()	

func _process(delta):
	if shader_active:
		hero_picture.material.set_shader_param("progress", shader_progress)
		shader_progress -= delta * 4.0

		hero_name_label.modulate.a = 1.0 - ((shader_progress + 1.0)/2.0)
		if shader_progress <= -1.0:
			end_shader()	

func end_shader():
	shader_active = false
	shader_progress = 0.0
	hero_picture.material = null
	hero_name_label.modulate.a = 1.0
	
func _game_locale_changed(_new_locale):
	#invalidate pictures
	grayscale_tex = null
	color_tex = null
	reload_texture()

func start_migration_to(index, _id_in_container, _total_objects_in_container, container = null):
	target_container = container
	target_index = index
	id_in_container = _id_in_container
	total_objects_in_container = _total_objects_in_container
	animate = true

func _tween_completed():
	migration_finished()

func migration_finished():
	if !target_container:
		return
	var parent = get_parent()
	parent.remove_child(self)
	target_container.add_child(self)	
	pass

func resize():
#	var stretch_mode = cfc.get_screen_stretch_mode()
#	if stretch_mode != SceneTree.STRETCH_MODE_VIEWPORT:
#		return

	var screen_size = get_viewport().size/cfc.screen_scale
	var grid_width = 390
	if screen_size.x > CFConst.LARGE_SCREEN_WIDTH:
		grid_width = CFConst.TEAM_SELECTION_GUI["HEROES_LARGE_GRID_WIDTH"]
		var dynamic_font = cfc.get_font("res://fonts/ReggaeOne-Regular.ttf", 16)	
		hero_name_label.add_font_override("font", dynamic_font)	
		hero_name_label.add_color_override("font_color", Color8(220, 220,220))			
	
	var parent = target_container if target_container else get_parent()
	var columns = parent.columns
	var image_size = grid_width / columns
	
	hero_picture.rect_min_size = Vector2(image_size, image_size)

	
	hero_picture.rect_size = hero_picture.rect_min_size	
	$Panel/HorizontalHighlights.rect_min_size = hero_picture.rect_min_size
	$Panel/VerticalHighlights.rect_min_size = hero_picture.rect_min_size
	$Panel/HorizontalHighlights.rect_size = hero_picture.rect_size
	$Panel/VerticalHighlights.rect_size = hero_picture.rect_size			
func grab_focus():
	hero_picture.grab_focus()


func card_image_download_complete(card_id):
	if card_id != hero_id:
		return
	reload_texture()

func reload_texture():
	if !hero_id:
		return
		
	var texture = cfc.get_hero_portrait(hero_id)
	if (texture):
		color_tex = texture	
		hero_picture.texture_normal = color_tex
		grayscale_tex = WCUtils.to_grayscale(color_tex)	

func load_hero(_hero_id):
	hero_id = _hero_id
	var hero_name = WCUtils.get_translated_property(hero_id, "Name")
	var hero_unlocks = cfc.game_settings.get("heroes_used_for_unlocks", [])
	if !(hero_id in hero_unlocks) and cfc.get_locked_heroes():
		hero_name = "*"	+ hero_name
	get_node("%HeroName").set_text(hero_name)

	var texture = cfc.get_hero_portrait(hero_id, self)
	if (texture):
		color_tex = texture	
		grayscale_tex = WCUtils.to_grayscale(color_tex)	

func gui_focus_changed(control):
	if control == hero_picture:
		gain_focus()
	else:
		lose_focus()

func gain_focus():
	if !gamepadHandler.is_mouse_input():
		$Panel/VerticalHighlights.visible = true
		$Panel/HorizontalHighlights.visible = true
		$Panel/HorizontalHighlights.rect_size = hero_picture.rect_size
		#$HorizontalHighlights.rect_position = rect_position
		$Panel/VerticalHighlights.rect_size = hero_picture.rect_size	
	lobby.show_preview(hero_id)
	
func lose_focus():
	$Panel/VerticalHighlights.visible = false
	$Panel/HorizontalHighlights.visible = false
	lobby.hide_preview(hero_id)
	
func _on_HeroSelect_gui_input(event):
	if event is InputEventMouseButton: #TODO better way to handle Tablets and consoles
		if event.button_index == BUTTON_LEFT and event.pressed:
			#Tell the server I want this hero
			action()

func enable():
	hero_picture.texture_normal = color_tex
	available = true

func disable():
	hero_picture.texture_normal = grayscale_tex	
	available = false

func _on_HeroPicture_mouse_entered():
	gain_focus()



func _on_HeroPicture_mouse_exited():
	lose_focus()


func _on_HeroPicture_pressed():
	action()

func action():
	if available:
		lobby.request_hero_slot(hero_id)
	else:
		lobby.request_release_hero_slot(hero_id)

func _on_Menu_resized() -> void:
	resize()
