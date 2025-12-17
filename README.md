
# Warnel Chawpiovs



![Warnel Chawpiovs preview image](preview.png "Warnel Chawpiovs preview image")

A card game using a (heavily modified) version of [Card Game Framework](https://github.com/db0/godot-card-game-framework) for Godot

## Current Status
As of this writing, this simulator supports the Core Box with its 3 villains and 5 heroes.
For all intents and purposes, the game works for a single player using a single hero. Other game modes, in particular Multiplayer, are hit and miss. The Multiplayer layer in particular is a disgusting pile of race conditions and I'm not sure I have the skills/patience to fix it.
* Single Player Mode:
  * 1 Player, 1 Hero: Generally works well
  * 1 Player, 2 heroes: Still work in progress but should generally work, with the occasional glitch or game-breaking bug
  * 1 Player, 3 or 4 heroes: untested
* Multiplayer Mode:
  * Multiplayer (2 players, 1 hero per player): Should work in theory, but in practice it's difficult to finish a game without running into a freeze, crash or race condition. To mitigate this, the host can try and click on the "force sync" option button to force other clients to reload the host's current board state. ![force_resync_image](doc/pictures/resync.png "force resync")
  * Multiplayer (Other cases): Not tested

## Features
* **Complete card rules enforcement** capacity, via provided Scripting Engine. (see [doc](doc/script_doc.html))
* Multiplayer Support (Work in progress)

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

## Users: Running the Game
When you run the game for the first time, Warnel Chawpiovs needs to download some data, including card definitions and card pictures. By default, most of this data is downloaded from https://marvelcdb.com.
Image downloads in particular might take some time, but this should only happen the first time you run the game.

Alternatively, it is possible to have all the images packed in a PCK file at the root of the user folder (PCK are the DLC file format for Godot) with the right structure. See below for folder structure.

## Users: Folder Structure
The user folder is based on Godot rules. On Windows, it lives in "user_folder"\AppData\Roaming\Godot\app_userdata\WC.
Relevant files and subfolders of the user folder are:
* settings.json: Settings file
* *.pck: all your dlc/mods can live as pck files at the root of the user folder. For example a file named core.pck can include all images for the core Set ![pck_example](doc/pictures/pck_format.png "pck_example")
* Saves: where the savegames live. Probably need to regularly empty the "past_games" subfolder
* Decks: Hero decks (those follow the format of marvelcdb.com)
* Sets: where the Set definitions and images live
  * images: image subfolder for set. Each "box" is a subfolder with its own pictures, e.g. images/core/01001a.png
  * SetDefinition_*.json: definition of a given set, typically downloaded "as is" from marvelcdb.com. This describes the cards in a given set, but does not contain the scripting data for these cards (see the Modders section below) 

## Modders: Adding new cards to the Game
The basics to adding new cards to the game is to choose a specific set from marvelcdb, create a scripts json file for it, and modify the settings file to include this set. Specifically:
* open settings.json from the user folder, and modify the "database" entry, by adding a new element to it. For example: "trors" : "https://marvelcdb.com/api/public/cards/trors.json" to add the return of red Skull set.
* Next you'll want to create a file Sets/SetScripts_name.json where you'll replace name with the actual entry key. In our example, Sets/SetScripts_trors.json. This should work in the User Sets folders, but has only been tested in the REs folder so far
* Now the actual work: you'll want to add an entry for each card in Sets/SetScripts_trors.json, that describes the behavior of each card for the engine.
  * inspiration for how to do this can be found in the [core set](Sets/SetScripts_core.json)      

## Developers: Source code Structure
* assets: icons, textures, and fonts for the game
* Decks: a series of default decks for the game to start. These are in theory overridden by Decks folder in the User directory
* doc: Documentation for the game and card engine
* fonts: additional fonts
* scripts: offline scripts e.g. in python for various tasks related to the game
* Sets: hardcoded definitions of the game card scripts. These should be overridden by files of the same name in the USer Directory
  * _macros.json: some macros to make writing some scripts a bit less tedious
  * _scenarios.json: the scenarios for each villain/scheme. Describes default modular set, etc...
  * SetScripts_*.json: actual code for the cards for each set
* Test: test files for the test suite
* Themes: default GUI theme for the app 

### src folder
* core: Most of the code from  [Card Game Framework](https://github.com/db0/godot-card-game-framework). This is supposed to be generic code for any card game, but I have heavily modified it and kind of broke the intent. Generally speaking though, nothing should need to be modified in there, in particular if it is specific to WC
* multiplayer: Multiplayer specific layer. Unfortunately, a lot of multiplayer code also lives in the next folder
* WC: overrides and actual code of the game
  * board: 
  * cards: 
  * data:
  * grids:
  * lobby:
  * menus:
  * ScriptingEngine: All the logic for card mechanics and rules enforcment
    *  ScriptingEngine.gd: actual logic for card scripts
    *  GlobalScriptStack: the heart of the multiplayer code and also the stack that handles interrupts, etc...
  * shaders:
  * Announce.gd: 
  * Board.gd: The board on which most "currently in play" cards are. Note that it is separate from piles such as deck, discard, etc...
  * **CardTemplate.gd**: The class that describes each card an its functionality
  * CfControlExtended.gd: General game singleton class in charge of loading cards database, running the game, etc
  * **GameData.gd**: The overlord of the game, centralized singleton that knows almost everything about the game
  * GhostCard.gd: A type of card (extends CardTemplate) specific for "Make the call" to play other players' cards
  * OVUtils.gd: Utility functions specific to gameplay and scripting the cards
  * PhaseContainer.gd: The class in charge of moving phases through the game, going from player phase to villain phase, etc...
  * SP.gd: aka ScriptProperties. Additional functionality for Scripts targets, etc... 
  * WCUtils.gd: utility functions for generic purpose (reading json files, array/dictionary utilities, etc...)   

## Developers: Test suite
### Running the Test suite
No code should be submitted without running the test suite. The test suite is a simple feature in the game that runs basic gameplay scenarios to ensure the overall engine isn't broken. It is an integration test mechanism that tests both cards and the engine.

The test suite needs to be run twice: once as a single player, and a second time in a 2-player multiplayer game.
* To run the single player test suite, start a single player game (e.g. with spider-Man against Rhino). Once the game has loaded, click on options > Tests, then wait until the test suite has run
* To run the multiplayer test suite, start a 2 player multiplayer game (run Godot Twice), e.g. with spider-Man for player 1 and Captain marvel for player 2, against Rhino. On the host machine, click on options > Tests, then wait until the test suite has run.

For tests to be considered succesful, bot the single player and multiplayer tests need to display a "succesful" message at the end.

The "single player" test suite actually also run multi-hero tests on a single machine. The multiplayer tests run those multi hero tests as well, but with one player per hero.

### Adding new tests
New tests can be added in the Test subfolder of the project. They are json files with a simple structure (TODO). Best way to create a new test is to copy/paste and exsiting one and modify it as needed.
test file names need to start with "test_" to b automatically included in the test suite.
Note: If a file named "_tests.txt" exists in the Test folder, it will be used in priority as a list of tests to run. One test file name per line. This can be used e.g. to run a single test to debug issues

## Developers: Misc & FAQ
* Why Godot 3.x ?
  * The Card Framework I used was designed for Godot 3.5x. Additionally, Godot 3.5x has been ported to multiple homebrew consoles such as the PS4 and the Nintendo Switch, and it is my hope that Warnel Chawpiovs can eventually be ported to these consoles somewhat easily. 


## Credits

Based on [Card Game Framework](https://github.com/db0/godot-card-game-framework)

## License

This software is licensed undel AGPL3.
