# warning-ignore-all:UNUSED_ARGUMENT
# warning-ignore-all:RETURN_VALUE_DISCARDED

extends Panel

# The time it takes to switch from one menu tab to another
const menu_switch_time = 0.35

onready var v_buttons := $CenterContainer/VBox/VButtons
onready var main_menu := $CenterContainer
onready var v_folder_label := $CenterContainer/VBox/HBoxContainer/FolderLabel

const credits := [
	"Warnel Chawpiovs, by Wololo ([url]https://wololo.net[/url])",
	"== Credits ==",
	"* Uses the [url=https://godotengine.org/]Godot Engine[/url]",
	"* [url=https://github.com/Homebrodot]Godot Switch port[/url] thanks in particular to fhidalgosola/utnad, Stary2001, cpasjuste, halotroop2288",
	"* Uses a heavyly modified version of [url=https://github.com/db0/godot-card-game-framework]Card Game Framework[/url]",
	"[cards_info]",
	"== Disclaimer ==",
	"This is free, fan-created work and is not affiliated with, endorsed by, or sponsored by Fantasy Flight Games. All characters, settings, and related elements are the property of their respective owners."
]

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	for option_button in v_buttons.get_children():
		if option_button.has_signal('pressed'):
			option_button.connect('pressed', self, 'on_button_pressed', [option_button.name])
			option_button.connect('mouse_entered', option_button, 'grab_focus')
	cfc.default_button_focus(v_buttons)
	# warning-ignore:return_value_discarded
	get_viewport().connect("size_changed", self, '_on_Menu_resized')
	if cfc.game_settings.get("hide_folder_label", false):
		v_folder_label.text = " "
	else:
		v_folder_label.text = "user folder:" + ProjectSettings.globalize_path("user://")
	fill_credits_text()
	resize()
	
func fill_credits_text():
	var label = get_node("%RichTextLabel")
	label.bbcode_text = ""
	var sep = ""
	for credit in credits:
		match credit:
			"[cards_info]":
				var image_credits = gameData.cardImageDownloader.get_server_credits()
				if image_credits:
					var separator = " "
					credit = "* Database and images thanks to the terrific work of "
					for image_credit in image_credits:
						credit+= separator + "[url=" + image_credits[image_credit]+"]"+image_credit + "[/url]"
						separator = ", "
				else:
					credit = ""
		if credit.begins_with("=="):
			credit = "\n" + credit
		label.bbcode_text += sep + credit 
		sep = "\n"

func on_button_pressed(_button_name : String) -> void:
	match _button_name:
		"Back":
			get_tree().change_scene(CFConst.PATH_CUSTOM + 'MainMenu.tscn')

	
func _on_Menu_resized() -> void:
	resize()


func resize():
#	var stretch_mode = cfc.get_screen_stretch_mode()
#	if stretch_mode != SceneTree.STRETCH_MODE_VIEWPORT:
#		return	
	var target_size = get_viewport().size/cfc.screen_scale

	self.margin_right = target_size.x
	self.margin_bottom = target_size.y
	self.rect_size = target_size
	$CenterContainer.rect_size = target_size
	if cfc.screen_resolution.x < CFConst.LARGE_SCREEN_WIDTH:
		var dynamic_font = cfc.get_font("res://fonts/Bangers-Regular.ttf", 50)	
		get_node("%Label").add_font_override("font", dynamic_font)	
		get_node("%VBox").add_constant_override("separation", 4)
		get_node("%RichTextLabel").bbcode_text = get_node("%RichTextLabel").bbcode_text.replace("\n\n", "\n")
	
func _on_RichTextLabel_meta_clicked(meta):
	# `meta` is of Variant type, so convert it to a String to avoid script errors at run-time.
	OS.shell_open(str(meta))
