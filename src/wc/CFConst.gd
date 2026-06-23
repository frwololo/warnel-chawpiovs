# Card Gaming Framework global Behaviour Constants
#
# This class contains constants which handle how all the framework behaves.
#
# Tweak the values to match your game requirements.
class_name CFConst
extends Reference

# The possible return codes a function can return
#
# * OK is returned when the function did not end up doing any changes
# * CHANGE is returned when the function modified the card properties in some way
# * FAILED is returned when the function failed to modify the card for some reason
# * WAITING the function is waiting for something else to happen (in a different thread/coroutine, generally)
enum ReturnCode {
	OK,
	CHANGED,
	FAILED,
	WAITING
}

enum FLIP_STATUS {
	FACEUP,
	FACEDOWN,
	BOTH
}

enum CanInterrupt {
	NO,
	MAY,
	MUST	
}

enum USER_INTERACTION_STATUS {
	NOT_CHECKED_YET,
	DONE_INTERACTION_NOT_REQUIRED,
	DONE_NETWORK_PREPAID,
	NOK_UNAUTHORIZED_USER,
	DONE_AUTHORIZED_USER,
}

# Options for pile shuffle styles.
# * auto: Will choose a shuffle animation depending on the amount of
#	cards in the pile.
# * none: No shuffle animation for this pile.
# * random: Will choose a random shuffle style each time a shuffle is requested.
# * corgi: Looks better on a small amount of cards (0 to 30)
# * splash: Looks better on a moderate amount of cards (30+)
# * snap: For serious people with no time to waste.
# * overhand: Shuffles deck in 3 vertical raises. Best fit for massive amounts (60+)
enum ShuffleStyle {
	AUTO,
	NONE,
	RANDOM,
	CORGI,
	SPLASH,
	SNAP,
	OVERHAND,
}
# This is used to know when to refresh the font size cache, but you can use it
# for other purposes as well.
# If you never adjust this, the font cache might start growing too large.
const GAME_VERSION := "1.0.0"
# The card size you want your  cards to have.
# This will also adjust all CardContainers to match
# If you modify this property, you **must** adjust
# the min_rect of the various control nodes inside the card front and back scenes.
const CARD_SIZE := Vector2(200,280)
# This is the resolution the game was developed in. It is used to adjust the card sizes
# for smaller resolutions. Any lower resoluton will adjust its card sizes for previews/thumbnails
# based on the percentage of difference between the two resolutions in absolute pixel number.
const DESIGN_RESOLUTION := Vector2(1280, 720) #Vector2(1920,1080)
# Switch this off to disable fancy movement of cards during draw/discard
const FANCY_MOVEMENT := true
# The focus style selected for this game. See enum `FocusStyle`
const FOCUS_STYLE = CFInt.FocusStyle.BOTH
# Controls how the card will be magnified in the focus viewport.
# Set to either "resize" or "scale"
#
# If set to scale, will magnify the card during viewport focus
# using godot scaling. It doesn't require any extra configuration when your
# Card font layout is changed, but it doesn't look quite as nice.
#
# If set to resize, will resize the card's viewport dupe's dimentions.
# This prevent blurry text, but needs more setup in the
# card's front and card back scripts.
# 
# Generally if the standard card size is large, this can stay as 'scale'
# If the standard card size is small, then resize tends to work better.
const VIEWPORT_FOCUS_ZOOM_TYPE = "resize"
# If set to true, the hand will be presented in the form of an oval shape
# If set to false, the hand will be presented with all cards
# horizontally aligned
#
# If you allow the player to modify this with cfc.set_settings()
# Then that will always take priority
const HAND_USE_OVAL_SHAPE := true
# The below scales down cards down while being dragged.
#
# if you don't want this behaviour, change it to Vector2(1,1)
const CARD_SCALE_WHILE_DRAGGING := Vector2(0.4, 0.4)
# The location and name of the file into which to store game settings
const SETTINGS_FILENAME := "user://settings.json"
# The location and name of the file into which to store the font size cache
const FONT_SIZE_CACHE := "user://CGFFontCache.json"
# The location where this game will store deck files
const DECKS_PATH := "user://Decks/"
# The path where the Card Game Framework core files exist.
# (i.e. mandatory scenes and scripts)
const PATH_CORE := "res://src/core/"
# The path where scenes and scripts customized for this specific game exist
# (e.g. board, card back etc)
const PATH_CUSTOM := "res://src/wc/"
# The path where card template scenes exist.
# These is usually one scene per type of card in the game
const PATH_CARDS := PATH_CUSTOM
# The path where the set definitions exist.
# This includes Card definition and card script definitions.
const PATH_SETS := PATH_CUSTOM + "cards/sets/"
# The path where assets needed by this game are placed
# such as token images
const PATH_ASSETS := "res://assets/"
# The text which is prepended to files to signify the contain
# Card definitions for a specific set
const CARD_SET_NAME_PREPEND := "SetDefinition_"
# The text which is prepended to files to signify the contain
# script definitions for a specific set
const SCRIPT_SET_NAME_PREPEND := "SetScripts_"
# This specifies the location of your token images.
# Tokens are always going to be seeked at this location
const PATH_TOKENS := PATH_ASSETS + "tokens/"
# If you wish to extend the OVUtils, extend the class with your own
# script, then point to it with this const.
const PATH_OVERRIDABLE_UTILS := PATH_CUSTOM + "OVUtils.gd"
# This specifies the path to the Scripting Engine. If you wish to extend
# The scripting engine functionality with your own tasks,
# Point this to your own script file.
const PATH_SCRIPTING_ENGINE := PATH_CUSTOM + "ScriptingEngine/ScriptingEngine.gd"
# This specifies the path to the [ScriptPer] class file.
# We don't reference is by class name to avoid cyclic dependencies
# And this also allows other developers to extend its functionality
const PATH_SCRIPT_PER := PATH_CORE + "ScriptingEngine/ScriptPer.gd"
# This specifies the path to the Alterant Engine. If you wish to extend
# The alterant engine functionality with your own tasks,
# Point this to your own script file.
const PATH_ALTERANT_ENGINE := PATH_CUSTOM + "ScriptingEngine/AlterantEngine.gd"
# This specifies the path to the MousePointer. If you wish to extend
# The mouse pointer functionality with your own code,
# Point this to your own scene file with a scrip extending Mouse Pointer.
const PATH_MOUSE_POINTER := PATH_CORE + "MousePointer.tscn"
# The amount of distance neighboring cards are pushed during card focus
#
# It's based on the card width. Bigger percentage means larger push.
const NEIGHBOUR_PUSH := 0.75
# The scale of a card while on the play area
# You can adjust this for each different card type
const PLAY_AREA_SCALE := 0.65
# The default scale of a card while on a thumbnail area such as the deckbuilder
# You can adjust this for each different card type
const THUMBNAIL_SCALE := 0.85
# The scale of a card while on a larger preview following the mouse
# You can adjust this for each different card type
const PREVIEW_SCALE := 1.5
# The scale of a card while it's shown focused on the top right.
# You can adjust this for each different card type
const FOCUSED_SCALE := 1.5
# The margin towards the bottom of the viewport on which to draw the cards.
#
# More than 0 and the card will appear hidden under the display area.
#
# Less than 0 and it will float higher than the bottom of the viewport
const BOTTOM_MARGIN_MULTIPLIER := 0.5
# Here you can adjust the amount of offset towards a side of their host card
# that attachments are placed.
#
# This is a multiplier based on the card size.
#
# You define which placement offset an attachment uses by setting the
# "attachment_offset" exported variable on the card scene
const ATTACHMENT_OFFSET := [
	# TOP_LEFT
	Vector2(-0.2,-0.2),
	# TOP
	Vector2(0,-0.2),
	# TOP_RIGHT
	Vector2(0.2,-0.2),
	# RIGHT
	Vector2(0.2,0),
	# LEFT
	Vector2(-0.2,0),
	# BOTTOM_LEFT
	Vector2(-0.2,0.2),
	# BOTTOM
	Vector2(0,0.2),
	# BOTTOM_RIGHT
	Vector2(0.2,0.2),
]
const FOCUS_COLOUR_ACTIVE :=  Color(0, 0.5, 1) * 1.3 #Color(0.1, 0.1, 1) * 1.2
const FOCUS_CARD_MODULATE :=  Color(1, 1, 1) * 1.2
const FOCUS_COLOUR_INACTIVE := Color(1, 0, 0) * 1.2
# The colour to use when hovering over a card.
#
# Reduce the multiplier to reduce glow effect or stop it altogether
const FOCUS_HOVER_COLOUR := Color(1, 0.8, 0.8) * 1
# The colour to use when hovering over a card with an attachment to signify
# a valid host.
#
# We multiply it a bit to make it as bright as FOCUS_HOVER_COLOUR
# for the glow effect.
#
# Reduce the multiplier to reduce glow effect or stop it altogether
const HOST_HOVER_COLOUR := Color(1, 0.8, 0) * 1
# The colour to use when hovering over a card with an targetting arrow
# to signify a valid target.
#
# We multiply it a bit to make it about as bright
# as FOCUS_HOVER_COLOUR for the glow effect.
#
# Reduce the multiplier to reduce glow effect or stop it altogether.
const TARGET_HOVER_COLOUR := Color(0, 0.4, 1) * 1.3
# The colour to use when hovering over a card with an targetting arrow
# to signify a valid target
#
# We are using the same colour as the TARGET_HOVER_COLOUR since they
# they match purpose
#
# You can change the colour to something else if  you want however
const TARGETTING_ARROW_COLOUR := TARGET_HOVER_COLOUR
# The below const defines what string to put between these elements.
# Returns a color code to be used to mark the state of cost to pay for a card
# * IMPOSSIBLE: The cost of the card cannot be paid.
# * INCREASED: The cost of the card can be paid but is increased for some reason.
# * DECREASED: The cost of the card can be paid and is decreased for some reason.
# * OK: The cost of the card can be paid exactly.
# * CACHE_INVALID: value is not valid and needs to be recalculated
const CostsState := {
	"IMPOSSIBLE": Color(1, 0, 0, 0) * 1.3, #alpha zero
	"INCREASED": Color(1, 0.5, 0, 0) * 1.3, #alpha zero
	"DECREASED": Color(0.5, 1, 0,0 ) * 1.3, #alpha zero
	"OK": Color(0, 0.5, 1) * 1.3,
	"OK_NO_MOUSE": Color(0, 0, 1) * 1.2,	
	"OK_INTERRUPT": Color(0, 1, 0) * 1.3,	
	"CACHE_INVALID": Color(1, 1, 1, 0), #alpha zero
}
# This is used when filling in card property labels in [Card].setup()
# when the property is an array, the label will still display it as a string
# but will have to join its elements somehow.
const ARRAY_PROPERTY_JOIN := ' - '
# If this is set to false, tokens on cards
# will not be removed when they exit the board
const TOKENS_ONLY_ON_BOARD := true
# If true, each token will have a convenient +/- button when expanded
# to allow the player to add a remove more of the same
const SHOW_TOKEN_BUTTONS := false
# This dictionary contains your defined tokens for cards
#
# The key is the name of the token as it will appear in your scene and labels
# **Please use lowercase only for the key**
#
# The value is the filename which contains your token image. The full path will
# be constructed using the PATH_TOKENS variable
#
# This allows us to reuse a token image for more than 1 token type
# 'default' is required
const TOKENS_MAP := {
	'default': 'yellow.svg',
	'tough': 'blue.svg',
	'threat' : 'black.svg',
	'damage': 'red.svg',
	'stunned': 'green.svg',
#	'industry': 'grey.svg',
	'confused': 'purple.svg',
}

const Z_INDEX_MOUSE_POINTER := 4050
const Z_INDEX_TOP_MENU := 2000
const Z_INDEX_BOARD_CARDS_ABOVE := 100
const Z_INDEX_BOARD_CARDS_NORMAL := 0
const Z_INDEX_ANNOUNCER := 1000
const Z_INDEX_HAND_CARDS_NORMAL :=200
	
#signals that will be sent only if cards register for them
#this is an optimization to avoid calling the stack constantly for games that don't need it
#DO NOT put signals in there that are needed by the core engine
# In particular DO NOT ADD:
# enemy_initiates*
# enemy_*_happened
# basic_defense_happened,
# basic_attack_happened,
# basic_thwart_happened,
const OPTIONAL_SIGNALS:= [
	"about_to_reveal",
	"ally_played",
		
	"boost_card_resolved",
	"bypass_guard_happened", 
	"bypass_crisis_happened",
	"bypass_patrol_happened",

	"card_exhausted",
	"card_leaves_play",
	"card_readied",

	"event_played",

	"identity_changed_form",
	
	"paid_as_resource",
	"pile_emptied",
	"player_side_scheme_played",
	
	"script_executed",
	"support_played",

	"upgrade_played",
		
	"villain_unique_card_conflict",
]
#unless a card registers an interrupt, these signals will
#be emitted directly without being added to the stack
#this is an optimization to avoid calling the stack constantly for games that don't need it
const NO_STACK_BY_DEFAULT_SIGNALS:= [
	"card_damaged",	
	"card_moved_to_board",
	"card_moved_to_hand",	
	"card_moved_to_pile",
	"card_played",
		
	"step_about_to_end",		
	"step_about_to_start",
	"step_ended",	
	"step_started",	
]

#signals that will always be added to the top of the stack when they're emitted
const FORCE_INTERRUPT_SIGNALS:= [
	"paid_as_resource"
]

const TYPES_TO_GROUPS := {
	"upgrade": ["group_upgrade_support", "play_area"],
	"support": ["group_upgrade_support", "play_area"],
	"main_scheme" : ["group_schemes", "play_area"],
	"player_side_scheme" : ["group_schemes", "play_area"],
	"side_scheme" : ["group_schemes", "group_side_schemes", "play_area"],
	"minion" : ["group_enemies", "group_characters", "play_area"],
	"villain" : ["group_enemies", "group_villains", "group_characters", "play_area"],
	"hero" : ["group_identities", "group_characters", "group_friendly", "group_allies_and_heroes", "play_area"],
	"alter_ego" : ["group_identities", "group_characters", "group_friendly", "play_area"],
	"ally" : ["group_allies", "group_characters", "group_friendly", "group_allies_and_heroes", "play_area"],
	"environment": ["group_environments", "play_area"]
}

const ALL_TYPE_GROUPS: = [
	"group_upgrade_support",
	"group_schemes",
	"group_enemies",
	"group_characters",
	"group_villains",
	"group_identities",
	"group_friendly",
	"group_allies_and_heroes",
	"group_allies",
	"group_environments",
	"play_area",
]

#list of hardcoded entries for which we will update
#scripts at runtime to append player info
#e.g. "__player_token" will become "__player_token1"
const PER_PLAYER_MODIFIABLE_KEYS:= [
	"__player_token"
]	

const ENCOUNTER_CARD_TYPES:= [
	"main_scheme", 
	"side_scheme", 
	"environment", 
	"attachment", 
	"villain", 
	"minion", 
	"obligation", 
	"treachery"
]

const PLAYER_CARD_TYPES:= [
	"ally", 
	"event", 
	"hero", 
	"alter_ego", 
	"resource", 
	"support", 
	"upgrade",
	"player_side_scheme", 
]
const FORCE_HORIZONTAL_CARDS := {
	"main_scheme" : true,
	"player_side_scheme" : true,
	"side_scheme" : true,
}

const DEFAULT_PROPERTIES_BY_TYPE:= {
	"hero": {
		"ally_limit" : 3,
		"restricted_limit" : 2,		
		"max_hand_size": 0,
		"max_tokens_tough": 1,
	},
	"alter_ego": {
		"ally_limit" : 3,
		"restricted_limit" : 2,			
		"max_hand_size": 0,
		"max_tokens_tough": 1,
	},
	"villain" : {
		"boost_cards_per_attack":1,
		"boost_cards_per_scheme": 1,
	}
} 

const TYPECODE_TO_PILE := {
	"event" : "discard",
	"treachery": "discard_villain"
}

const TYPECODE_TO_GRID := {
	"ally" : "allies",
	"upgrade" : "upgrade_support",
	"support" : "upgrade_support",
	"minion" : "enemies",
	"side_scheme" : "schemes",
	"player_side_scheme" : "schemes",
	"main_scheme": "schemes",
	"environment" : "villain_misc"
}

const GRID_SETUP := {
	"discard_villain" :{
		"x" : 0,
		"y" : 20,
		"type" : "pile",
		"faceup" : true,
		"scale" : 0.5			
	},	
	"deck_villain" :{
		"x" : 150,
		"y" : 20,
		"type" : "pile",
		"scale" : 0.5			
	},		
	"villain" : {
		"x" : 250,
		"y" : 20,
		"auto_extend": false,
	},
	"schemes" : {
		"x" : 600,
		"y" : 20,
	},
	"villain_misc" : {
		"x" : 1500,
		"y" : 20,
		"columns": 1,
	},
	"victory_display" :{
		"x" : 1800,
		"y" : 250,
		"type" : "pile",
		"faceup" : true,
		"scale" : 0.5,
		"focusable": false
	},	
	"set_aside" :{
		"x" : 3000,
		"y" : 500,
		"type" : "pile",
		"faceup" : true,
		"scale" : 0.5,
		"focusable": false
	},
	"removed_from_game" :{
		"x" : 3000,
		"y" : 700,
		"type" : "pile",
		"faceup" : true,
		"scale" : 0.5,
		"focusable": false
	},	
	"tmp_pile1" :{
		"x" : 3000,
		"y" : 0,
		"type" : "pile",
		"faceup" : true,
		"scale" : 0.5,
		"focusable": false
	},	
	"tmp_pile2" :{
		"x" : 3000,
		"y" : 150,
		"type" : "pile",
		"faceup" : true,
		"scale" : 0.5,
		"focusable": false
	},	
	"tmp_pile3" :{
		"x" : 3000,
		"y" : 300,
		"type" : "pile",
		"faceup" : true,
		"scale" : 0.5,
		"focusable": false
	},					
}
const HERO_GRID_SETUP := {
	"encounters_facedown" :{
		"x" : 0,
		"y" : 0,
		"type" : "pile",
		"scale" : 0.5		
	},
	"encounters_reveal" :{
		"x" : 150,
		"y" : 0,
		"type" : "pile",
		"faceup": true,
		"scale" : 0.5			
	},	
	"deck" :{
		"x" : 150,
		"y" : 440,
		"type" : "pile",
		"scale" : 0.5			
	},
	"discard" :{
		"x" : 0,
		"y" : 440,
		"type" : "pile",
		"faceup" : true,
		"groups" : ["player_discard"],
		"scale" : 0.5			
	},	
	"enemies" : {
		"x" : 350,
		"y" : 00,
	},
	"identity" : {
		"x" : 000,
		"y" : 220,
		"auto_extend": false,
	},
	"allies" : {
		"x" : 350,
		"y" : 220,
	},
	"upgrade_support" : {
		"x" : 350,
		"y" : 440,
	},	
								
}

const HERO_GRID_LAYOUT := {
	"type": "horizontal",
	"x" : 500,
	"y": 220,
	"children" : [
		{
		"name": "left",
		"type": "vertical",
		"children": [
			{
				"name": "encounters",
				"type": "horizontal",
				"children": [
					{
						"name": "encounters_facedown",
						"type": "pile",
						"scale": 0.5,				
					},
# Example of spacer usage					
#					{
#						"name": "test",
#						"type": "spacer",
#						"scale": 0.5,				
#					},					
					{
						"name": "encounters_reveal",
						"type": "pile",
						"scale": 0.5,									
					}					
				]
			},
			{
				"name": "identity",
				"type": "grid"				
			},
			{
				"name": "hero_piles",
				"type": "horizontal",
				"children": [
					{
						"name": "discard",
						"type": "pile",
						"scale": 0.5,											
					},
					{
						"name": "deck",
						"type": "pile",
						"scale": 0.5,											
					}					
				]				
			}
		]
		},
		{
			"name": "middle",
			"type" : "vertical",		
			"children": [
				{
					"name": "optional_discard_a",
					"type": "pile",
					"scale": 0.5,											
				},
				{
					"name": "optional_deck_a",
					"type": "pile",
					"scale": 0.5,											
				}					
			]					
		},
		{
		"name": "right",
		"type": "vertical",
		"max_width" : 1000,
		"max_height": 600,
		"children": [
		
			{
				"name": "enemies",
				"type": "grid"				
			},
			{
				"name": "allies",
				"type": "grid"				
			},
			{
				"name": "upgrade_support",
				"type": "grid"				
			}
		]
		}		
	]
}

const TRANSITION_HIGHLIGHT_COLORS:= {
	"default": Color(0, 0.5, 1) * 10,	
	"villain": Color(1, 0.1, 1) * 10,

}

const TRANSITION_SHADER_PARAMS:= {
	"default": {
		"transition_type": 2,	
		"position": Vector2(0.5,0.5),
		"grid_size":Vector2(0.5, 50.0),	
		"edges": 3,
		"shape_feather": 0.0,		
	},
	"villain": {
		"transition_type": 2,	
		"position": Vector2(0.5,0.5),	
		"grid_size":Vector2(50.0, 50.0),	
		"edges": 3,	
		"flip_frequency": Vector2(2.0, 1.0)		
	}

}

const TOKENS_ONLY_ON_BOARD_EXCEPTIONS:= [
	"encounters_facedown",
	"encounters_reveal"	
]

#list of non board zones that can have alterants (performance: piles not in this list will be excluded from the alterants loop)
#exception: cards that explicitly add a script with the "add_script" script will be taken into account no matter what

#leave empty == all cards will be considered for alterants
const ALTERANTS_ALLOWED_PILES:= [
	"hand",
]

#list of non board zones that can have interrupts (performance: piles not in this list will be excluded from the alterants loop)
#leave empty == all cards will be considered for interrupts
const INTERRUPT_ALLOWED_PILES:= [
	"hand"
]

const TOKENS_INCREASE_PREVENTION_PROPERTIES:= {
	"stunned": ["stalwart", "cannot_be_stunned"],
	"confused": ["stalwart", "cannot_be_confused"],
}


const DEFAULT_TOKEN_MAX_VALUE := {
	"tough" : 1,
	"stunned" : 1,
	"confused" : 1,
	"__can_change_form": 1,
}

const AUTO_KEYWORDS := {
	"alliance" : "int",
	"assault" : "bool",
	"form" : "bool",
	"guard" : "int",
	"hinder" : "int",
	"incite" : "int",
	"linked" : "string",
	"max 1 per player": "int",
	"max 1 per phase": "int",	
	"max 1 per round": "int",	
	"overkill" : "int",
	"patrol" : "int",
	"peril" : "bool",
	"permanent" : "int",
	"piercing" : "bool",
	"quickstrike" : "bool",
	"ranged" : "bool",
	"requirement" : "string",
	"restricted" : "int",
	"retaliate" : "int",
	"setup" : "bool",
	"stalwart" : "int",
	"steady" : "int",
	"surge" : "bool",
	"team-up" : "bool",
	"teamwork" : "string",
	"temporary" : "bool",
	"toughness" : "bool",
	"uses" : "string",
	"victory" : "int_no_alterant", #victory 0 is different from no Victory, so we don't want to init it at 0
	"villainous" : "int",
		
#additional keywords not officially in the game, for alterants
	"attack_indirect_damage": "int",
	"blank_abilities": "int",
	"blank_printed_trigger_abilities": "int",

	"bypass_crisis": "int",
	"bypass_guard": "int",
	"bypass_patrol": "int",


	"cannot_be_blocked": "int",
	"cannot_be_canceled": "int",
	"cannot_be_confused": "int",
	"cannot_be_healed_by_player_cards": "int",	
	"cannot_be_stunned": "int",	
	"cannot_be_thwarted": "int",	
	"cannot_change_form": "int",
	"cannot_change_to_alter_ego": "int",	
	"cannot_have_attachments": "int",	
	"cannot_have_player_card_attachments": "int",	
	"cannot_have_upgrade_attachments": "int",				
	"cannot_leave_play": "int",	
	"cannot_remove_threat": "int",
	"cannot_ready": "int",
	"cannot_ready_by_player_card": "int",
	"cannot_thwart_side_scheme": "int",

	"excess_damage_boost": "int", #Rocket Raccoon's Follow Through card
	"exclude_from_ally_limit": "int",

	"force_confused": "int",
	"force_stunned": "int",
	
	"guard_all": "int",
	
	"ignore_external_acceleration": "int",		
	"invincible": "int",		
}

const INTERRUPT_SECTION_KEYWORDS:= [
	"forced interrupt", 
	"interrupt",
	"hero interrupt",
	"alter-ego interrupt",
	"forced response", 
	"response",
	"hero response",
	"alter-ego response",	
]

#list of events for which we don't show a GUI announce to the user by default
#(interrupts override this)
const SKIP_ANNOUNCE_CHOICE_MENU:= {
	"trigger": {
		"manual": true,
		"mulligan": true,
		"end_phase_discard": true,
		#we already show the damage with an arrow
		"enemy_attack_damage": true,			
	}
}
const NOOB_SKIP_ANNOUNCE_STACK_EVENTS:= {
	"trigger": {
		"manual": true,
		"mulligan": true,
		#we already show the damage with an arrow
		"enemy_attack_damage": true,	
		
	},
	"script_name": {
		"move_to_player_zone": true		
	}
}
const SKIP_ANNOUNCE_STACK_EVENTS:= {
	"trigger": {
		"manual": true,
		"mulligan": true,		
		"self_moved_to_board" : true, 
		"about_to_reveal" : true,
		"end_phase_discard" : true,
		
		#we already have reveal_encounter which is redundant with those
		"reveal": true,
		"reveal_hero": true,
		"reveal_alter_ego": true	,	
		
		#we already show the damage with an arrow
		"enemy_attack_damage": true,	
		
		"card_dies": true,
		"character_died": true,	
	},
	"boost": {
		"discard": true,
	},
	"script_name": {
		"move_to_player_zone": true,
		"pre_receive_damage": true,		
	}	
}


const MAX_TEAM_SIZE:int = 4

enum PHASE {
	PLAYER,
	VILLAIN
}

# the sceng variable copies its trigger details to all children subscripts
# this has led to issues where some scripts react to multiple
# subscripts
# this variable forces not passing specific variables
# to childrend when duplicating the trigger_details variable from sceng
const SCENG_TRIGGER_DETAILS_ERASE_FROM_CHILDREN_SCRIPTS := [
	"is_interrupt_or_response"
]

#damages get split into multiple scripts (pre_receive_damage, receive_damage, etc...)
#they need to transfer some of their properties to the children scripts
const DAMAGE_TRANSFER_SCRIPT_PROPERTIES:= [
	"if_damage",
	"if_no_damage",
	"increase_amount",	
	"overkill"
]

enum PHASE_STEP {
	GAME_NOT_STARTED,
	PLAYER_MULLIGAN,
	MULLIGAN_DONE,
	IDENTITY_SETUP,
	GAME_READY, #an additional step to make sure nothing runs before game is loaded	 
	PLAYER_TURN, #turn loops here
	PLAYER_DISCARD,
	PLAYER_DRAW,
	PLAYER_READY,
	PLAYER_END,
	VILLAIN_THREAT,
	VILLAIN_ACTIVATES,
	VILLAIN_DEAL_ENCOUNTER,
	VILLAIN_REVEAL_ENCOUNTER,
	VILLAIN_PASS_PLAYER_TOKEN,
	VILLAIN_END,
	ROUND_END,
	SYSTEMS_CHECK		
}

const CAN_PRECOMPUTE : = [
	"add_resource"
]

const ASPECTS:= ["aggression", "justice", "leadership", "protection"]

const STATS_URI := "http://127.0.0.1"
const STATS_PORT := 8000

const MULTIPLAYER_PORT:= 7777

const OPTIONS := {
	"replace_targetting_with_selection": false,
	"enable_fuzzy_rotations": true,
}

const TARGET_ARROW_COLOR_BY_TAG: = {
	"attack" : Color(0.7, 0.1, 0.1) ,
	"thwart" : Color(0, 0.5, 0.7) 	
}

const TARGET_ARROW_COLOR_BY_NAME: = {
	"attack" : Color(0.7, 0.1, 0.1) ,	
	"deal_damage" : Color(0.7, 0.1, 0.1),
	"receive_damage" : Color(0.7, 0.1, 0.1)	
}

const ALLOWED_PCK_NAMES:= [
	"music",
	"cycle1",
	"cycle2",
	"cycle3",
	"cycle4",
	"cycle5",
	"cycle6",
	"cycle7",
	"cycle8",
	"cycle9",
	"cycle10",
	"cycle11",
	"cycle12",
	"cycle13",												
]

const DEACTIVATE_SLOTS_HIGHLIGHT := true
const DISABLE_MANUAL_ATTACHMENTS : = true
const HIDE_GRID_BACKGROUND:= true
const HIDE_PILE_DETAILS:= true

#this overrides the manipulation buttons in Piles
const FACEUP_PILE_VIEW_ON_CLICK := true
const ATTEMPT_TO_GUESS_IMAGE_URL := true

#default settings that will be merged into config file at first startup
#order matters, most relevant at the top. e.g. if a device is both mobile AND Android,
#and both entries have a shared key, the one at the top will take precedence
const OS_DEFAULT_SETTINGS := {
	"Android": {
		"can_toggle_fullscreen": false,
		"gui_bigger_buttons": true,		
		"gui_card_focused_scale": 3,

	},
	"pc": {
		"can_toggle_fullscreen": true,
		"gui_card_focused_scale": 2
	},		
	"mobile":{
		"can_toggle_fullscreen": false,
		"gui_bigger_buttons": true,			
		"gui_card_focused_scale": 3
	},					
}

const DEFAULT_SETTINGS:= {
	'music_volume': 5,
	'sfx_volume': 10,
	'glow_intensity' : 0.01,
	'load_cards_online' : true,
	'images_base_url': "https://marvelcdb.com",
	"decks_base_url": "https://marvelcdb.com/api/public/decklist/",
	"decks_base_url_backup": "https://marvelcdb.com/api/public/deck/",
	'dont_show_msg': {},
	'database': {
#cycle 1	
		"core": "https://marvelcdb.com/api/public/cards/core.json", #Core Box
#		"gob": "https://marvelcdb.com/api/public/cards/gob.json", #Green Goblin Scenario Pack	
#		"twc": "https://marvelcdb.com/api/public/cards/twc.json", #The Wrecking Crew Scenario Pack
		"cap" : "https://marvelcdb.com/api/public/cards/cap.json", #Captain America Hero Pack
		"msm" : "https://marvelcdb.com/api/public/cards/msm.json", #Ms Marvel Hero Pack
		"thor" : "https://marvelcdb.com/api/public/cards/thor.json", #Thor Hero Pack
		"bkw" : "https://marvelcdb.com/api/public/cards/bkw.json", #Black Widow Hero Pack		
		"drs" : "https://marvelcdb.com/api/public/cards/drs.json", #Doctor Strange Hero Pack
		"hlk" : "https://marvelcdb.com/api/public/cards/hlk.json", #Hulk Hero Pack
#cycle 2
		"trors" : "https://marvelcdb.com/api/public/cards/trors.json", #The Rise of Red Skull Expansion Box
#		"toafk": "https://marvelcdb.com/api/public/cards/toafk.json", #The Once and Future Kang Scenario Pack
		"ant" : "https://marvelcdb.com/api/public/cards/ant.json", #Ant-Man Hero Pack
		"wsp" : "https://marvelcdb.com/api/public/cards/wsp.json", #Wasp Hero Pack
		"qsv" : "https://marvelcdb.com/api/public/cards/qsv.json", #Quicksilver Hero Pack						
		"scw": "https://marvelcdb.com/api/public/cards/scw.json", #Scarlet Witch Hero Pack
#cycle 3		
		"gmw" : "https://marvelcdb.com/api/public/cards/gmw.json", #Galaxy's Most Wanted Expansion Box				
		"stld" : "https://marvelcdb.com/api/public/cards/stld.json", #Star-Lord Hero Pack
		"gam": "https://marvelcdb.com/api/public/cards/gam.json", #Gamora Hero Pack	
		"drax": "https://marvelcdb.com/api/public/cards/drax.json", #Drax Hero Pack	
		"vnm": "https://marvelcdb.com/api/public/cards/vnm.json", #Venom Hero Pack
#cycle 4
		"mts" : "https://marvelcdb.com/api/public/cards/mts.json", #Mad Titan's Shadow Expansion Box
		"nebu": "https://marvelcdb.com/api/public/cards/nebu.json", #Nebula Hero Pack	
		"warm" : "https://marvelcdb.com/api/public/cards/warm.json", #War Machine Hero Pack
#		"hood": "https://marvelcdb.com/api/public/cards/hood.json", #The Hood scenario pack	
#		"valk": "https://marvelcdb.com/api/public/cards/valk.json", #Valkyrie Hero Pack	
#		"vision": "https://marvelcdb.com/api/public/cards/vision.json", #Vision Hero Pack	
#cycle 5
		"sm" : "https://marvelcdb.com/api/public/cards/sm.json", #Sinister Motives Expansion Box				
#		"nova": "https://marvelcdb.com/api/public/cards/nova.json", #Nova Hero Pack	
#		"ironheart": "https://marvelcdb.com/api/public/cards/ironheart.json", #Ironheart Hero Pack	
#		"spiderham": "https://marvelcdb.com/api/public/cards/spiderham.json", #Spiderham Hero Pack	
#		"spdr": "https://marvelcdb.com/api/public/cards/spdr.json", #SP//DR Hero Pack	
#cycle 6
		"mut_gen": "https://marvelcdb.com/api/public/cards/mut_gen.json", #Mutant Genesis Expansion Box	
#		"cyclops": "https://marvelcdb.com/api/public/cards/cyclops.json", #Cyclops Hero Pack
#		"phoenix": "https://marvelcdb.com/api/public/cards/phoenix.json", #Phoenix Hero Pack	
		"wolv": "https://marvelcdb.com/api/public/cards/wolv.json", #Wolverine Hero Pack	
#		"storm": "https://marvelcdb.com/api/public/cards/storm.json", #Storm Hero Pack	
#		"gambit": "https://marvelcdb.com/api/public/cards/gambit.json", #Gambit Hero Pack	
#		"rogue": "https://marvelcdb.com/api/public/cards/rogue.json", #Rogue Hero Pack
#		"mojo": "https://marvelcdb.com/api/public/cards/mojo.json",  #Mojo Scenario Pack	
#cycle 7
#		"next_evol": "https://marvelcdb.com/api/public/cards/next_evol.json", #Next Evolution  Expansion Box	
#		"psylocke": "https://marvelcdb.com/api/public/cards/psylocke.json", #Psylocke Hero Pack		
#		"angel": "https://marvelcdb.com/api/public/cards/angel.json", #Angel Hero Pack	
#		"x23": "https://marvelcdb.com/api/public/cards/x23.json", #X-23 Hero Pack	
#		"deadpool": "https://marvelcdb.com/api/public/cards/deadpool.json", #Deadpool Hero Pack		
#cycle 8
#		"aoa": "https://marvelcdb.com/api/public/cards/aoa.json", #Age of Apocalypse Expansion Box	
#		"iceman": "https://marvelcdb.com/api/public/cards/iceman.json", #Iceman Hero Pack	
#		"jubilee": "https://marvelcdb.com/api/public/cards/jubilee.json", #Jubilee Hero Pack	
		"ncrawler": "https://marvelcdb.com/api/public/cards/ncrawler.json", #NightCrawler Hero Pack	
#		"magneto": "https://marvelcdb.com/api/public/cards/magneto.json", #Magneto Hero Pack	
#cycle 9
#		"aos": "https://marvelcdb.com/api/public/cards/aos.json", #Agents of Shield Expansion
#		"bp": "https://marvelcdb.com/api/public/cards/bp.json", #Black Panther Hero Pack	
#		"silk": "https://marvelcdb.com/api/public/cards/silk.json", #Silk Hero Pack	
#		"falcon": "https://marvelcdb.com/api/public/cards/falcon.json", #Falcon Hero Pack	
		"winter": "https://marvelcdb.com/api/public/cards/winter.json", #Winter Soldier Hero Pack	
#		"tt": "https://marvelcdb.com/api/public/cards/tt.json", #Trickster Takeover Scenario Pack
#cycle 10
#		"": "https://marvelcdb.com/api/public/cards/.json", #
#		"": "https://marvelcdb.com/api/public/cards/.json", #
#		"": "https://marvelcdb.com/api/public/cards/.json", #
#		"": "https://marvelcdb.com/api/public/cards/.json", #
#cycle 11
#		"": "https://marvelcdb.com/api/public/cards/.json", #
#		"": "https://marvelcdb.com/api/public/cards/.json", #
#		"": "https://marvelcdb.com/api/public/cards/.json", #
#		"": "https://marvelcdb.com/api/public/cards/.json", #
#		"": "https://marvelcdb.com/api/public/cards/.json", #
#		"": "https://marvelcdb.com/api/public/cards/.json", #

	},
	'enable_ingame_debug_textedit': false,
	'lobby_server': {
		'server': 'https://wololo.net/',
		'create_room_url': 'wc/lobby.php?mode=create_room',
		'list_rooms_url': 'wc/lobby.php?mode=list_rooms',
		'join_room_url': 'wc/lobby.php?mode=join_room&room_name=__ROOM_NAME__',
	},
	'notifications_level': 'normal',
	'adventure_mode': true,
	'unlocked_heroes': ["01001a"], #default unlocked character
	'unlocked_villains': ["01097"], #default unlocked villain
	
}

const RESOURCES_URL = "https://wololo.net/wc/resources/"


#if a menu only has one entry, it will auto execute it whenever possible

enum AUTO_EXECUTE_MENU {
	OFF,
	SCRIPTED_ONLY,
	MANUAL_INCLUDED,
}

#TODO other values than OFF break some tests and multiplayer interaction
const AUTO_EXECUTE_ONE_ENTRY_MENU = AUTO_EXECUTE_MENU.OFF # SCRIPTED_ONLY

const ABORT_EARLY_ON_COST_FAILURE = true 

const LARGE_SCREEN_WIDTH:= 1600
const LOCAL_DECK_ID_OFFSET = 1000000000

#
# Bug Workarounds
#

#Card container sorting started reporting a broken sorting function
#not sure what broke it but also I'm not really using that,
#so this const disables the sorting
const BUG_PATCH_IGNORE_CONTAINER_SORT := true

#
# Debugging options
#
#set to true to help with breakpoints and debug
const DISABLE_THREADS:= true 
#this disables the announcer messages. Should be set to false unless you want to speed up debugging sessions
const DISABLE_ANNOUNCER:= false
#useful only for debuggingto accelerate the loading of the game and get to gameplay faster
const SKIP_MULLIGAN:= false
#enables various performance tweaks for lowend platforms such as the Nintendo Switch. Disable only for debugging
const PERFORMANCE_HACKS = true

#if set to true, the system checks will only send hashed instead of 
#full dictionaries. Probably better for bandwidth
#set to false when debugging a network/desync issue
const SYSTEMS_CHECK_HASH_ONLY:= true
#set to true to force writing to log files even if cfc.debug is false
const FORCE_LOGS:= false
#seconds until we trigger a desync warning when the stack is blocked
#set to 0 for infinite waiting time (debug)
const DESYNC_TIMEOUT:= 5
const DISPLAY_DEBUG_MSG = false

const DEBUG_DISABLE_SCRIPT_DATABASE_CACHE = false
const DEBUG_AUTO_START_MULTIPLAYER = false

const DEBUG_ENABLE_NETWORK_TEST = false
#set to 0 to deactivate fake delay. Otherwise, random delay between 0 and this value will be added
#to rpc calls on the stack (only activated if DEBUG_ENABLE_NETWORK_TEST is true)
const DEBUG_SIMULATE_NETWORK_DELAY = 1.5
const DEBUG_NETWORK_DELAY_RANDOM = false
const DEBUG_SIMULATE_NETWORK_PACKET_DROP = false

const SCRIPT_BREAKPOINT_CARD_NAME := "Gamora"
const SCRIPT_BREAKPOINT_TRIGGER_NAME := "card_played"

const VERSION := "1.4.1"
const VERSION_CHECK_URL := "https://api.github.com/repos/frwololo/warnel-chawpiovs/releases"
const GITHUB_URL := "https://github.com/frwololo/warnel-chawpiovs/releases"



