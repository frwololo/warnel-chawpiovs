# warning-ignore-all:RETURN_VALUE_DISCARDED
class_name StackEventDisplay
extends Node2D


# Declare member variables here. Examples:
# var a = 2
# var b = "text"

#singals defined in scriptingbus
#signal stack_event_display_finished(details) 

const _TARGETING_SCENE_FILE = CFConst.PATH_CORE + "Card/TargetingArrow.tscn"
const _TARGETING_SCENE = preload(_TARGETING_SCENE_FILE)
const SCALE = 1.7

enum ANIMATION_STATUS {
	NONE,
	STARTING,
	RUNNING,
	STOPPING,
	STOPPED,
}

var stack_event: StackObject = null
var owner_card
var subjects:= []
var status = ANIMATION_STATUS.NONE
var initialized = false
var arrows_initialized = false
var arrows := []
var rect_size = Vector2(200, 200)
var rect_position = Vector2(0, 0)
var target_position = Vector2(0,0)

onready var card_texture:TextureRect = get_node("%Card")
onready var control:Control= get_node("%Control")
onready var display_text:RichTextLabel = get_node("%DisplayText")
onready var shadow:ColorRect = get_node("%Shadow")
onready var tween:Tween = get_node("Tween")
onready var ok_checkbox:CheckBox = get_node("%OKCheckBox")
onready var ok_button = get_node("%OKButton")
var show_ok = false

# Called when the node enters the scene tree for the first time.
func _ready():
	scripting_bus.connect("stack_event_deleted", self, "_stack_event_deleted")	
	gameData.theStack.connect("script_executed_from_stack", self, "_script_executed_from_stack")

	start_animation()
	pass # Replace with function body.


#there is an issue where the theme of this control
#isn't the sam between godot 3.6 (default theme) and godot 3.5 (darktheme)
#possibly this ? https://github.com/godotengine/godot/pull/61588
#this leads to size issues on 3.5 at runtime
func handle_size_bug():
	if tween.is_active():
		return
	var bottom_right = control.rect_size * control.rect_scale + control.rect_position
	if bottom_right.y > get_viewport().size.y:
		display_text.rect_min_size = Vector2(display_text.rect_min_size.x + 10,0)
		display_text.rect_size = Vector2(display_text.rect_min_size.x, display_text.rect_min_size.y)

	control.rect_min_size = Vector2(control.rect_min_size.x, 0)
	control.rect_size = control.rect_min_size
	if bottom_right.x > get_viewport().size.x:
		if get_node("%Button").text !="<":
			control.rect_position.x -= 100	
			set_target_position(control.rect_position)	

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	if control:
		handle_size_bug()
		if shadow:
			shadow.rect_min_size = control.rect_min_size
			shadow.rect_size = control.rect_size
			shadow.rect_position = control.rect_position + (Vector2(10, 10) * SCALE)

		rect_size = control.rect_size
		rect_position = control.rect_position
	init_display()
	show_arrows()

	_dispay_ok_button()

	for arrow in arrows:
		arrow.owner_object = control
		arrow.set_global_position(control.get_global_position())
		arrow._draw_targeting_arrow()
	
	match status:
		ANIMATION_STATUS.STOPPED:		
			self.visible = false
		ANIMATION_STATUS.STARTING:
			status = ANIMATION_STATUS.RUNNING
		ANIMATION_STATUS.STOPPING:
			status = ANIMATION_STATUS.STOPPED
			force_close()
	pass

func force_close():
	for arrow in arrows:
		var container = self  #cfc.NMAP.board
		container.remove_child(arrow)
		arrow.queue_free()
	arrows = []
	scripting_bus.emit_signal("stack_event_display_finished", {"object" : self, "event": stack_event})


func init_display(forced = false):
	#abort if not ready
	if !owner_card or !card_texture or !display_text:
		return

	#abort if already initialized		
	if !forced and initialized:
		return
	
	control.rect_position = owner_card.global_position

	move_to_target_position()	
	
	initialized = load_card_texture()
	load_text()
	init_arrows()
	$Control.rect_scale = Vector2(SCALE,SCALE) * cfc.screen_scale
	$Shadow.rect_scale = Vector2(SCALE,SCALE) * cfc.screen_scale

func move_to_target_position():
	if tween.is_active():
		# warning-ignore:return_value_discarded
		tween.remove_all()
	# warning-ignore:return_value_discarded
	tween.interpolate_property(control, "rect_position",
			control.rect_position, target_position, 0.2,
			Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)
	# warning-ignore:return_value_discarded		
	tween.interpolate_property(self, "modulate",
			Color(1,1,1,0), Color(1,1,1,1), 0.2,
			Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)	
	# warning-ignore:return_value_discarded			
	tween.start()	

func show_arrows():
	if arrows_initialized:
		return
	

	if !control or control.rect_size.y < 100:
		control.visible = false
		control.call_deferred("set_visible", true)
		return
		
	rect_size = control.rect_size
	rect_position = control.rect_position		
	self.visible = true
	self.z_index = CFConst.Z_INDEX_BOARD_CARDS_ABOVE
	
	arrows_initialized = true	

func is_finished() -> bool:
	return (status == ANIMATION_STATUS.STOPPED)

func init_arrows():
	if !owner_card:
		return
	
	
	if arrows:
		return
		
	init_one_arrow(owner_card, Color(1, 1, 0,1) * 1.3 )
	
	for subject in subjects:
		init_one_arrow(subject, Color(0.7, 0.5, 0,1) * 1.3 )
	
func init_one_arrow(object, color):		
	var owner_arrow = _TARGETING_SCENE.instance()
#	var container = cfc.NMAP.board
	self.add_child(owner_arrow)
	owner_arrow.set_display_mode(TargetingArrow.DISPLAY_MODE.SHADOW)	
	owner_arrow.hide_arrow_head()
	owner_arrow.set_arrow_color(color)
	owner_arrow.set_destination(object)
	owner_arrow.show_me()
	arrows.append(owner_arrow)



func load_card_texture() -> bool:
	if !owner_card:
		return false

	if !card_texture:
		return false
		
	card_texture.texture =  owner_card.get_cropped_art_texture()

	#card_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	# In case the generic art has been modulated, we switch it back to normal colour
	card_texture.self_modulate = Color(1,1,1)
	return true

func load_text():
	if !display_text:
		return

			
	if stack_event:
		display_text.bbcode_text = stack_event.get_display_text()
	else:
		if owner_card:
			display_text.bbcode_text = owner_card.get_printed_text()
		else:
			display_text.bbcode_text = "---"

		

func load_from_event(event):
	stack_event = event
	owner_card = stack_event.get_owner_card()
	subjects = stack_event.get_subjects()

func load_from_past_event(event, storage):
	stack_event = event
	if stack_event:
		owner_card = stack_event.get_owner_card()
	else:
		owner_card = storage.get("owner_card", null)
	
	if !owner_card:
		return
		
	var hero_id = storage.get("interacting_hero", 0)
	if hero_id:
		subjects.append(gameData.get_identity_card(hero_id))

	var choices_menu = storage.get("choices_menu", null)
	if choices_menu:
		subjects.append(choices_menu)

func start_animation():
	status = ANIMATION_STATUS.STARTING

func terminate():
	status = ANIMATION_STATUS.STOPPING


func _stack_event_deleted(event):
	if event != stack_event:
		return	
	terminate()
	
func _script_executed_from_stack(event):
	if event != stack_event:
		return		
	terminate()




func set_rect_position(pos):
	$Control.set_global_position(pos)
	$Control.rect_position = pos
	rect_position = pos

func get_global_position():
	return rect_position

func set_target_position(pos):
	target_position = pos

func _on_Button_pressed():
	var button = get_node("%Button")
	
	var hidden_position = Vector2(1870 * cfc.screen_scale.x, target_position.y)
	var before = target_position
	var after = hidden_position
	match button.text:
		">":
			button.text = "<"
		"<":
			before = hidden_position
			after = target_position			
			button.text= ">"
			
	tween.interpolate_property(control, "rect_position",
			before, after, 0.2,
			Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)
	tween.start()				
	pass # Replace with function body.

func show_ok_button():
	show_ok = true

func _dispay_ok_button():
	if !show_ok:
		return
	show_ok = false
	ok_button.visible = true
	ok_button.flat = false	
	ok_button.text = "OK"
	ok_button.disabled = false
	ok_checkbox.visible = true
	var tooltip_data = gameData.theAnnouncer.get_ignore_list_path(owner_card, stack_event)
	
	var separator = ""
	var tooltip = ""
	for key in tooltip_data:
		if key in ["trigger", "cards"]:
			continue
		tooltip+= separator + key 
		separator = "/"
	ok_checkbox.hint_tooltip = tooltip
	
	z_index = 0
	
func _on_OKButton_pressed():
	if ok_checkbox.pressed:
		gameData.theAnnouncer.add_event_to_ignore_list(owner_card, stack_event)
	terminate()
