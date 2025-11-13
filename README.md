
# Warnel Chawpiovs



![Warnel Chawpiovs preview image](preview.png "Warnel Chawpiovs preview image")

A card game using a (heavily modified) version of [Card Game Framework](https://github.com/db0/godot-card-game-framework) for Godot

## Provided features

* **Complete card rules enforcement** capacity, via provided Scripting Engine. (see [doc](doc/script_doc.html))
* Multiplayer Support

### Scripting Engine Features

* Can define card scripts in plain text, using dictionaries.
* Can set cards to trigger off of any board manipulation.
* Can filter the triggers based on card properties, or a special subset.
* Can define optional abilities.
* Can define multiple-choice abilities.
* Can calculate effect intensity based on state of the board during runtime.
* Can request simple inputs from the player during execution.
* Tag-marking scripts which can be filtered by scripts triggering off of them.
* Can store results from one script to use in another.
* Can be plugged into by any object, not just cards.


## Credits

Based on [Card Game Framework](https://github.com/db0/godot-card-game-framework)

## License

This software is licensed undel AGPL3.
