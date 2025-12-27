# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED

extends Panel

# The time it takes to switch from one menu tab to another
const menu_switch_time = 0.35

onready var v_buttons := $CenterContainer/VBox/VButtons
onready var main_menu := $CenterContainer
onready var v_folder_label := $CenterContainer/VBox/HBoxContainer/FolderLabel


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	for option_button in v_buttons.get_children():
		if option_button.has_signal('pressed'):
			option_button.connect('pressed', self, 'on_button_pressed', [option_button.name])
			option_button.connect('mouse_entered', option_button, 'grab_focus')
	cfc.default_button_focus(v_buttons)
	# warning-ignore:return_value_discarded
	get_viewport().connect("size_changed", self, '_on_Menu_resized')
	v_folder_label.text = "user folder:" + ProjectSettings.globalize_path("user://")
	resize()


func on_button_pressed(_button_name : String) -> void:
	match _button_name:
		"Host":
			# warning-ignore:return_value_discarded
			get_tree().change_scene(CFConst.PATH_CUSTOM + 'lobby/MultiplayerLobby.tscn')
		"Join":
			get_tree().change_scene(CFConst.PATH_CUSTOM + 'menus/MultiplayerJoin.tscn')
		"Cancel":
			get_tree().change_scene(CFConst.PATH_CUSTOM + 'MainMenu.tscn')

	
func _on_Menu_resized() -> void:
	resize()


func resize():
	var stretch_mode = cfc.get_screen_stretch_mode()
	if stretch_mode != SceneTree.STRETCH_MODE_VIEWPORT:
		return	
	var target_size = get_viewport().size

	self.margin_right = target_size.x
	self.margin_bottom = target_size.y
	self.rect_size = target_size
	$CenterContainer.rect_size = target_size
