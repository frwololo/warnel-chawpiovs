extends Panel

# The time it takes to switch from one menu tab to another
const menu_switch_time = 0.35

onready var v_buttons := $MainMenu/VBox/Center/VButtons
onready var main_menu := $MainMenu
onready var v_folder_label := $MainMenu/VBox/Margin2/Label


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	for option_button in v_buttons.get_children():
		if option_button.has_signal('pressed'):
			option_button.connect('pressed', self, 'on_button_pressed', [option_button.name])
	# warning-ignore:return_value_discarded
	get_viewport().connect("size_changed", self, '_on_Menu_resized')
	v_folder_label.text = "user folder:" + ProjectSettings.globalize_path("user://")


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
	for tab in [main_menu]:
		if is_instance_valid(tab):
			tab.rect_size = get_viewport().size
			if tab.rect_position.x < 0.0:
					tab.rect_position.x = -get_viewport().size.x
			elif tab.rect_position.x > 0.0:
					tab.rect_position.x = get_viewport().size.x
