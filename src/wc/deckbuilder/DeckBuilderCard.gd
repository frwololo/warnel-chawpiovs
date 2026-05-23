class_name DeckBuilderCard
extends WCCard

const _QUANTITY_SCENE_FILE = CFConst.PATH_CUSTOM + "deckbuilder/CardQuantity.tscn"
const _QUANTITY_SCENE = preload(_QUANTITY_SCENE_FILE)

signal quantity_changed(card, before, after)

var main_scene
var quantity_scene = null
var quantity = 0
var deck_edit_hero_id = ""
var enforce_rules = true


const QTY_DISPLAY_POS = Vector2(130, 30)	
const QTY_EDIT_POS = Vector2(10, 30)

func enforce_deckbuilding_rules(value):
	enforce_rules = value
	if quantity_scene:
		quantity_scene.refresh()

func set_deck_hero_id(hero_id):
	deck_edit_hero_id = hero_id

func set_main_scene(object):
	main_scene = object

func get_quantity():
	return quantity

func activate_quantity_editor():
	init_quantity_scene()
	quantity_scene.edit_mode()
	quantity_scene.rect_position = QTY_EDIT_POS 

func deactivate_quantity_editor():
	if !quantity_scene:
		return
	
	if quantity < 2:
		quantity_scene.queue_free()
		quantity_scene = null
		return
		
	quantity_scene.display_mode()
	quantity_scene.rect_position = QTY_DISPLAY_POS
	
func set_target_position(next_position):
	_set_target_position(next_position)
	_add_tween_position(position, _target_position,
						to_container_tween_duration, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	$Tween.start()

func can_add_card_to_deck():
	return main_scene.can_add_card(self)	
	
func set_quantity(new_quantity):
	var before = quantity
	quantity = new_quantity
	if quantity > 1:
		init_quantity_scene()
	if before != quantity:
		emit_signal("quantity_changed", self , before, quantity)

func init_quantity_scene():
	if not quantity_scene:
		quantity_scene = _QUANTITY_SCENE.instance()
		add_child(quantity_scene)
		quantity_scene.rect_position = QTY_DISPLAY_POS	
		quantity_scene.rect_scale = Vector2(0.7, 0.7)
	quantity_scene.set_quantity(quantity)		
	

func gain_focus():
	main_scene.show_preview(self)
	
func lose_focus():
	main_scene.hide_preview(self)

func get_property(property: String, default = null, _force_alterant_check = false):
	return properties.get(property, default)

func _class_specific_ready():
	._class_specific_ready()
	for container in [self, self._control]:
		for child in container.get_children():
			if child as TargetingArrow:
				child.queue_free()
				targeting_arrow = null
			elif child as TokenDrawer:
				child.queue_free()
				tokens = null
			elif child as SideIcons:
				child.queue_free()
				side_icons = null				

func _on_Card_gui_input(event) -> void:
	if event is InputEventMouseButton:	
		# because of https://github.com/godotengine/godot/issues/44138
		# we need to double check that the card which is receiving the
		# gui input, is actually the one with the highest index.
		# We use our mouse pointer which is tracking this info.
#		if main_scene.mouse_pointer.current_focused_card \
#				and self != main_scene.mouse_pointer.current_focused_card:
#			main_scene.mouse_pointer.current_focused_card._on_Card_gui_input(event)
#			return
		
		# If the player left clicks, we need to see if it's a double-click
		# or a long click
		if event.is_pressed() and event.get_button_index() == 1 :
			main_scene.card_clicked(self)	
			
