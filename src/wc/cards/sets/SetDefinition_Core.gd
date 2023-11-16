# This file contains just card definitions. See also `CardConfig.gd`

extends Reference

const SET = "Core Set"
const CARDS := {
	"Spider-Man": {
		"Type": "Hero",
		"Tags": ["Genius","Avenger"],
		"Requirements": "",
		"Abilities": " ",
		"Cost": 0,
		"Power": 0,
		"Health": 12,
	},
	"Beast in Black": {
		"Type": "Hero",
		"Tags": ["Fast", "Flanking"],
		"Requirements": "Cannot be played on first turn",
		"Abilities": " ",
		"Cost": 1,
		"Power": 2,
		"Health": 1,
	},
}
