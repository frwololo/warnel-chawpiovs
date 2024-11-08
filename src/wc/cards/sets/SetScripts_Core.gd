# See README.md
extends Reference

const scripts := {
	"Test Card 1": {
		"manual": {
			"board": [
				{
					"name": "rotate_card",
					"subject": "self",
					"degrees": 90,
				}
			],
			"hand": [
				{
					"name": "spawn_card",
					"card_name": "Spawn Card",
					"board_position": Vector2(500,200),
				}
			]
		},
	},
	"Test Card 2": {
		"manual": {
			"board": [
				{
					"name": "move_card_to_container",
					"subject": "target",
					"dest_container": "discard",
				},
				{
					"name": "move_card_to_container",
					"subject": "self",
					"dest_container": "discard",
				}
			],
			"hand": [
				{
					"name": "custom_script",
				}
			]
		},
	},
	"Shaking Card": {
		"manual": {
			"hand": [
				{
					"name": "mod_counter",
					"modification": 5,
					"counter_name":  "research"
				},
#					{
#						"name": "move_card_to_container",
#						"subject": "self",
#						"dest_container": "discard",
#					},
				{
					"name": "nested_script",
					"nested_tasks": [
						{
							"name": "move_card_to_container",
							"is_cost": true,
							"subject": "index",
							"subject_count": "all",
							"subject_index": "top",
							SP.KEY_NEEDS_SELECTION: true,
							SP.KEY_SELECTION_COUNT: 2,
							SP.KEY_SELECTION_TYPE: "equal",
							SP.KEY_SELECTION_OPTIONAL: true,
							SP.KEY_SELECTION_IGNORE_SELF: true,
							"src_container": "hand",
							"dest_container": "discard",
						},
						{
							"name": "mod_counter",
							"modification": 3,
							"counter_name":  "research"
						},
					]
				},
			],
		},
	},
}

# This fuction returns all the scripts of the specified card name.
#
# It also merges with default rules for the game (rules that apply to all cards)
func get_scripts(card_name: String, get_modified = true) -> Dictionary:
	# find hardcoded scripts that match the card name and trigger
	# TODO load from external file
	var card = cfc.card_definitions[card_name]
	var	cost = card["Cost"] if (card && card.has("Cost")) else 0
	var script:Dictionary = scripts.get(card_name,{})
	script = script.duplicate()
	
	#Add game specific rules valid for all cards
	
	#Play From hand: discard a specific number of cards to play
	#TODO this is not specific to core set and should therefore be moved somewhere else more general
	var playFromHand: Dictionary = { }
	if (cost):
		playFromHand = {
			"manual": {
				"hand": [
					{
						"name": "move_card_to_container",
						"is_cost": true,
						"subject": "index",
						"subject_count": "all",
						"subject_index": "top",
						SP.KEY_NEEDS_SELECTION: true,
						SP.KEY_SELECTION_COUNT: cost,
						SP.KEY_SELECTION_TYPE: "equal",
						SP.KEY_SELECTION_OPTIONAL: false,
						SP.KEY_SELECTION_IGNORE_SELF: true,
						"src_container": "hand",
						"dest_container": "discard{current_hero}", #TODO need to update based on player
					},
					{
						"name": "move_card_to_board",
						"subject": "self",
					},
				]
			}
		}
	script.merge(playFromHand)
	return script
