extends Control


# Declare member variables here. Examples:
# var a = 2
# var b = "text"

#returns true if all unlocked heroes already have at least a victory
#this could indicate a gridlock where we are not able to unlock more
#due to a bug 
func hero_unlock_gridlock():
	var hero_unlocks = cfc.game_settings["heroes_used_for_unlocks"]
	var unlocked_heroes = cfc.get_unlocked_heroes()
	for unlocked_hero_id in unlocked_heroes:
		var unlock = hero_unlocks.get(unlocked_hero_id, false)
		if !unlock:
			return false
	return true	

#returns true if all unlocked villains already have at least a defeat
#this could indicate a gridlock where we are not able to unlock more
#due to a bug 
func scenario_unlock_gridlock():
	var villain_unlocks = cfc.game_settings["villains_used_for_unlocks"]
	var unlocked_scenarios = cfc.get_unlocked_scenarios()
	for unlocked_scenario_id in unlocked_scenarios:
		var unlock = villain_unlocks.get(unlocked_scenario_id, false)
		if !unlock:
			return false
	return true	

func init_game_settings(keys):
	for key in keys:
		if !cfc.game_settings.has(key):
			cfc.game_settings[key] = {}
func victory():
	if !cfc.is_adventure_mode():
		return
	var unlocked_hero_id = ""
	var unlocked_scenario_id = ""
	
	init_game_settings([
		"hero_victories", 
		"heroes_used_for_unlocks", 
		"villain_defeats", 
		"villains_used_for_unlocks"
	])
		
		
	var my_hero = gameData.get_team_member(1)
	var hero_deck_data:HeroDeckData = my_hero["hero_data"]
	var hero_id = hero_deck_data.get_hero_id()

	#add 1 victory to my hero
	var hero_victories = cfc.game_settings["hero_victories"]
	if (!hero_victories.has(hero_id)):
		hero_victories[hero_id] = 0
	hero_victories[hero_id] +=1
	
	#has this hero already been used for an other hero unlock
	var hero_used_for_unlocks = cfc.game_settings["heroes_used_for_unlocks"].get(hero_id, false)
	if (!hero_used_for_unlocks) or hero_unlock_gridlock() :
		cfc.game_settings["heroes_used_for_unlocks"][hero_id] = true
		unlocked_hero_id = cfc.adventure_unlock_random_hero()
	
	var scenario = gameData.scenario
	var scenario_id = scenario.scheme_card_id
	var villain_defeats = cfc.game_settings["villain_defeats"]
	if (!villain_defeats.has(scenario_id)):
		villain_defeats[scenario_id] = 0
	villain_defeats[scenario_id] +=1
	
	if !unlocked_hero_id:	
		var scenario_used_for_unlocks = cfc.game_settings["villains_used_for_unlocks"].get(scenario_id, false)

		if (!scenario_used_for_unlocks) or scenario_unlock_gridlock():
			cfc.game_settings["villains_used_for_unlocks"][scenario_id] = true
			unlocked_scenario_id = cfc.adventure_unlock_next_scenario()
		
	
	var texture = null
	var unlockedmsg = ""
	if unlocked_hero_id:
		texture = cfc.get_hero_portrait(unlocked_hero_id)
		unlockedmsg = "New Hero Unlocked!"
	elif unlocked_scenario_id:
		var villains = ScenarioDeckData.get_villains_from_scheme(unlocked_scenario_id)
		if (villains):
			var villain = villains[0]
			var display_name = villain["shortname"]
			texture = cfc.get_villain_portrait(villain["_code"])			
			unlockedmsg = "New Villain Unlocked: " + display_name

	if texture:
		var texture_rect = get_node("%TextureRect")
		var msg = get_node("%UnlockMsg")
		texture_rect.texture = texture
		texture_rect.visible = true
		msg.text = unlockedmsg
		msg.visible = true
	
	
	cfc.save_settings()

# Called when the node enters the scene tree for the first time.
func _ready():
	resize()
	set_as_toplevel(true)
	pass


# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass

func resize():
	var target_size = get_viewport().size
	$CenterContainer.rect_size = target_size
	$CenterContainer/ColorRect.rect_min_size = $CenterContainer/MarginContainer.rect_size + Vector2(20, 20)	

func _on_Button_pressed():
	cfc.NMAP.board._close_game()
	pass # Replace with function body.
