extends VBoxContainer

onready var lobby = find_parent("TeamSelection")
onready var the_picture: TextureButton = get_node("%ScenarioPicture")
onready var scenario_name: Label = get_node("%ScenarioName")
#onready var playerName := $PlayerName
#onready var kick := $Kick
var scenario_id
var _options:= []
var villain_id
var _rotation = 0

#animation
var target_container = null
var target_index = Vector2(0,0)
var id_in_container = 0
var total_scenarios = 0
var animate = false 
var use_shader = true
var shader_loaded = false
var shader_active = false
var shader_progress = 0.0

func _ready():

	attempt_load_texture()

	
	# warning-ignore:return_value_discarded
	get_viewport().connect("gui_focus_changed", self, "gui_focus_changed")
	cfc.connect("locale_changed", self, "_game_locale_changed")

	$Tween.connect("tween_all_completed", self, "_tween_completed")

	var animate_menu = cfc.get_setting("animate_menu")
	animate = true if animate_menu else false
	use_shader =  (animate_menu == 2)
	
	resize()
	#animation
	if animate:
		if use_shader:
			self.modulate.a = 0
			var reverse_delay = id_in_container
			var delay = (randi() % ((total_scenarios * 3) - (reverse_delay * 2))) 
			cfc.play_sfx("shuffle")
			yield(get_tree().create_timer(float(delay) * 0.01), "timeout")
			#this uses https://github.com/cashew-olddew/Universal-Transition-Shader
			self.modulate.a = 1
			the_picture.modulate = CFConst.TRANSITION_HIGHLIGHT_COLORS["villain"]

			$Tween.interpolate_property(
					the_picture,'modulate', the_picture.modulate,
					Color(1.0,1.0,1.0,1.0),
					0.5, Tween.TRANS_LINEAR, Tween.EASE_OUT)
			$Tween.start()				
			
			#this uses https://github.com/cashew-olddew/Universal-Transition-Shader
			var material = load(CFConst.PATH_CUSTOM + "shaders/transition.gdshader")
			the_picture.material = ShaderMaterial.new()
			the_picture.material.set("shader", material)
			var shader_settings = CFConst.TRANSITION_SHADER_PARAMS.get("team_selection")
			for setting in shader_settings:
				var value = shader_settings[setting]
				if typeof(value) == TYPE_DICTIONARY:
					continue
				the_picture.material.set_shader_param(setting,value) 
			
			shader_progress = 1.0	
			the_picture.material.set_shader_param("progress", shader_progress)					
			shader_loaded = true
			shader_active = true
			scenario_name.modulate.a = 0
		else:		
			self.modulate.a = 0.1
			
			if target_container:
				self.rect_scale = Vector2(6.0, 6.0)
				self.set_global_position(Vector2(800 + randi()%200, 100  + randi()%200))
				var size_offset = Vector2(3, 3)
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



func get_texture():
	if the_picture and the_picture.texture_normal:
		return the_picture.texture_normal
	return null

func get_text():
	if scenario_name and scenario_name.text:
		return scenario_name.text
	return ""

func gain_focus():
	if !gamepadHandler.is_mouse_input():
		$Panel/VerticalHighlights.visible = true
		$Panel/HorizontalHighlights.visible = true
	$Panel/HorizontalHighlights.rect_size = the_picture.rect_size
	#$HorizontalHighlights.rect_position = rect_position
	$Panel/VerticalHighlights.rect_size = the_picture.rect_size	
	lobby.show_preview(villain_id)
	
func lose_focus():
	$Panel/VerticalHighlights.visible = false
	$Panel/HorizontalHighlights.visible = false
	lobby.hide_preview(villain_id)
	

func set_display_name(display_name):
	var villain_unlocks = ScenarioDeckData._get_corrected_scenario_ids("villains_used_for_unlocks")
	if (!scenario_id in villain_unlocks) and ScenarioDeckData.get_locked_scenarios():
		display_name = "*" + display_name			
		
	scenario_name.set_text(display_name)	

func card_image_download_complete(_card_id):
	reload_texture()

func reload_texture():
	the_picture.texture_normal = null

func attempt_load_texture():
	if the_picture and !the_picture.texture_normal:
		var display_name = tr(ScenarioDeckData.get_scenario_display_name(scenario_id))
		var villain = ScenarioDeckData.get_first_villain_from_scheme(scenario_id)
		var picture_card_id = scenario_id
		var texture
		if (villain):
			var my_villain_id = villain["_code"]
			if !display_name:
				display_name = WCUtils.get_translated_property(my_villain_id, "shortname")
			
			picture_card_id = my_villain_id
			texture = cfc.get_villain_portrait(picture_card_id, self)
			_rotation = 0
		else:
			texture = cfc.get_scheme_portrait(picture_card_id)
			_rotation = 90

		if !display_name:
			display_name = WCUtils.get_translated_property(scenario_id, "shortname")
		set_display_name(display_name)
		 
		if (texture):
			the_picture.texture_normal = texture
		resize()	
			
func _process(delta:float):
	attempt_load_texture()
	
	if shader_active:
		the_picture.material.set_shader_param("progress", shader_progress)
		shader_progress -= delta * 4.0

		scenario_name.modulate.a = 1.0 - ((shader_progress + 1.0)/2.0)
		if shader_progress <= -1.0:
			end_shader()	

func end_shader():
	shader_active = false
	shader_progress = 0.0
	the_picture.material = null
	scenario_name.modulate.a = 1.0

func start_migration_to( index, _id_in_container, _total_scenarios, container = null):
	target_container = container
	target_index = index
	total_scenarios = _total_scenarios
	id_in_container = _id_in_container
	animate = true

func _tween_completed():
	migration_finished()

func migration_finished():
	if !target_container:
		return
	var parent = get_parent()
	parent.remove_child(self)
	target_container.add_child(self)	


func resize():

	var screen_size = get_viewport().size/cfc.screen_scale
	var grid_width = 450
	var grid_height = 220
	if screen_size.x > CFConst.LARGE_SCREEN_WIDTH:
		grid_width = CFConst.TEAM_SELECTION_GUI["SCENARIO_LARGE_GRID_WIDTH"]
		grid_height = CFConst.TEAM_SELECTION_GUI["SCENARIO_LARGE_GRID_HEIGHT"]
		var dynamic_font = cfc.get_font("res://fonts/ReggaeOne-Regular.ttf", 16)	
		scenario_name.add_font_override("font", dynamic_font)	
		scenario_name.add_color_override("font_color", Color8(220, 220,220))			
		
	var parent = target_container if target_container else get_parent()
	var columns = parent.columns
	
	var rows = int(ceil(float(float(total_scenarios) /float(columns))))
	var image_width = grid_width / columns
	var image_height = grid_height / rows
	var image_size = min(image_width, image_height)
	
	the_picture.rect_min_size = Vector2(image_size, image_size)

	
	the_picture.rect_size = the_picture.rect_min_size	

	scenario_name.rect_size.x = the_picture.rect_min_size.x		
	
	$Panel/HorizontalHighlights.rect_min_size = the_picture.rect_min_size
	$Panel/VerticalHighlights.rect_min_size = the_picture.rect_min_size
	$Panel/HorizontalHighlights.rect_size = the_picture.rect_size
	$Panel/VerticalHighlights.rect_size = the_picture.rect_size
	
	$Panel.rect_min_size = the_picture.rect_min_size
	$Panel.rect_size = the_picture.rect_size

	rect_min_size = the_picture.rect_min_size
	rect_size = the_picture.rect_size	
	var _tmp = 1


	
func _game_locale_changed(_new_locale):
	reload_texture()
	
func gui_focus_changed(control):
	if control == the_picture:
		gain_focus()
	else:
		lose_focus()	

func grab_focus():
	the_picture.grab_focus()

func load_scenario(_scenario_id) -> bool:
	scenario_id = _scenario_id
	var villain = ScenarioDeckData.get_first_villain_from_scheme(scenario_id)
	if (!villain):
		cfc.LOG("no villain defined for scenario id:" + _scenario_id)
		return false
	
	villain_id = villain["_code"]
		
	return true
	

func _on_ScenarioSelect_gui_input(event):		
	if event is InputEventMouseButton: #TODO better way to handle Tablets and consoles
		if event.button_index == BUTTON_LEFT and event.pressed:
			#Tell the server I want this hero
			action()

func action():
	if (not cfc.is_game_master()):
		return	
			
	lobby.scenario_select(scenario_id)

func _on_ScenarioPicture_mouse_entered():
	lobby.show_preview(villain_id)


func _on_ScenarioPicture_mouse_exited():
	lobby.hide_preview(villain_id)


func _on_ScenarioPicture_pressed():
	action()
