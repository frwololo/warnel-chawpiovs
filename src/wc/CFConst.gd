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
const DESIGN_RESOLUTION := Vector2(1920,1080)
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
	'default': 'blue.svg',
	'threat' : 'black.svg',
	'damage': 'red.svg',
	'stunned': 'green.svg',
#	'industry': 'grey.svg',
	'confused': 'purple.svg',
#	'blood': 'red.svg',
#	'gold coin': 'yellow.svg',
#	'void': 'black.svg',
}

const Z_INDEX_MOUSE_POINTER := 4050
const Z_INDEX_TOP_MENU := 2000
const Z_INDEX_BOARD_CARDS_ABOVE := 100
const Z_INDEX_BOARD_CARDS_NORMAL := 0
const Z_INDEX_ANNOUNCER := 1000
const Z_INDEX_HAND_CARDS_NORMAL :=200
	


const TYPES_TO_GROUPS := {
	"main_scheme" : ["group_schemes"],
	"player_scheme" : ["group_schemes"],
	"side_scheme" : ["group_schemes"],
	"minion" : ["group_enemies", "group_characters"],
	"villain" : ["group_enemies", "group_villains", "group_characters"],
	"hero" : ["group_identities", "group_characters", "group_friendly", "group_allies_and_heroes"],
	"alter_ego" : ["group_identities", "group_characters", "group_friendly"],
	"ally" : ["group_allies", "group_characters", "group_friendly", "group_allies_and_heroes"],
}

const ALL_TYPE_GROUPS: = [
	"group_schemes",
	"group_enemies",
	"group_characters",
	"group_villains",
	"group_identities",
	"group_friendly",
	"group_allies_and_heroes",
]
	

const FORCE_HORIZONTAL_CARDS := {
	"main_scheme" : true,
	"player_scheme" : true,
	"side_scheme" : true,
}

const DEFAULT_PROPERTIES_BY_TYPE:= {
	"hero": {
		"ally_limit" : 3,
		"max_hand_size": 0,
	},
	"alter_ego": {
		"ally_limit" : 3,
		"max_hand_size": 0,
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
	"environment" : "villain_misc"
}

const GRID_SETUP := {
	"deck_villain" :{
		"x" : 0,
		"y" : 20,
		"type" : "pile",
		"scale" : 0.5			
	},
	"discard_villain" :{
		"x" : 150,
		"y" : 20,
		"type" : "pile",
		"faceup" : true,
		"scale" : 0.5			
	},		
	"villain" : {
		"x" : 300,
		"y" : 20,
		"auto_extend": false,
	},
	"schemes" : {
		"x" : 500,
		"y" : 20,
	},
	"villain_misc" : {
		"x" : 1500,
		"y" : 20,
	},
	"set_aside" :{
		"x" : -300,
		"y" : -300,
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

const TOKENS_ONLY_ON_BOARD_EXCEPTIONS:= [
	"encounters_facedown",
	"encounters_reveal"	
]

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

const DEFAULT_TOKEN_MAX_VALUE := {
	"tough" : 1,
	"stunned" : 1,
	"confused" : 1
}

const AUTO_KEYWORDS := {
	"alliance" : "bool",
	"assault" : "bool",
	"form" : "bool",
	"guard" : "bool",
	"hinder" : "int",
	"incite" : "int",
	"linked" : "string",
	"overkill" : "int",
	"patrol" : "bool",
	"peril" : "bool",
	"permanent" : "bool",
	"piercing" : "bool",
	"quickstrike" : "bool",
	"ranged" : "bool",
	"requirement" : "string",
	"restricted" : "bool",
	"retaliate" : "int",
	"setup" : "bool",
	"stalwart" : "bool",
	"steady" : "bool",
	"surge" : "bool",
	"team-up" : "bool",
	"teamwork" : "string",
	"temporary" : "bool",
	"toughness" : "bool",
	"uses" : "string",
	"victory" : "int",
	"villainous" : "bool",	
	
#additional ones not officially in the game

	"invincible": "int",
					
}

const MAX_TEAM_SIZE:int = 4

enum PHASE {
	PLAYER,
	VILLAIN
}

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
	"deal_damage" : Color(0.5, 0.1, 0.1)
}

const DEACTIVATE_SLOTS_HIGHLIGHT := true
const DISABLE_MANUAL_ATTACHMENTS : = true
const HIDE_GRID_BACKGROUND:= true
const HIDE_PILE_DETAILS:= true

#this overrides the manipulation buttons in Piles
const FACEUP_PILE_VIEW_ON_CLICK := true
#set to true to fetch card datasets online and download images
const LOAD_CARDS_ONLINE := true


const DEFAULT_SETTINGS:= {
	'glow_intensity' : 0.01,
	'images_base_url': "https://marvelcdb.com",
	"decks_base_url": "https://marvelcdb.com/api/public/decklist/",
	'database': {
		"core": "https://marvelcdb.com/api/public/cards/core.json"
	},
	'lobby_server': {
		'server': 'https://wololo.net/',
		'create_room_url': 'wc/lobby.php?mode=create_room',
		'list_rooms_url': 'wc/lobby.php?mode=list_rooms',
		'join_room_url': 'wc/lobby.php?mode=join_room&room_name=__ROOM_NAME__',
	}
	
}

#if a menu only has one entry, it will auto execute it whenever possible

enum AUTO_EXECUTE_MENU {
	OFF,
	SCRIPTED_ONLY,
	MANUAL_INCLUDED,
}

#TODO other values than OFF break some tests and multiplayer interaction
const AUTO_EXECUTE_ONE_ENTRY_MENU = AUTO_EXECUTE_MENU.OFF # SCRIPTED_ONLY

#
# Debugging options
#
#set to true to help with breakpoints and debug
const DISABLE_THREADS:= true 
#this disables the announcer messages. Usually not recommended, but might help with speeding up tests
const DISABLE_ANNOUNCER:= false
#useful only for tests to accelerate the loading of the game and get to gameplay faster
const SKIP_MULLIGAN:= false
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

const DEBUG_AUTO_START_MULTIPLAYER = false

const DEBUG_ENABLE_NETWORK_TEST = false
#set to 0 to deactivate fake delay. Otherwise, random delay between 0 and this value will be added
#to rpc calls on the stack (only activated if DEBUG_ENABLE_NETWORK_TEST is true)
const DEBUG_SIMULATE_NETWORK_DELAY = 1.5
const DEBUG_NETWORK_DELAY_RANDOM = false
const DEBUG_SIMULATE_NETWORK_PACKET_DROP = false

const SCRIPT_BREAKPOINT_CARD_NAME := "Whirlwind"
const SCRIPT_BREAKPOINT_TRIGGER_NAME := "enemy_attack"

const LARGE_SCREEN_WIDTH:= 1600
