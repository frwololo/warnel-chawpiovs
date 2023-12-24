extends HBoxContainer


var heroZone = preload("res://src/wc/board/WCHeroZone.tscn")

# Called when the node enters the scene tree for the first time.
func _ready():
	pass

func _init():	
	var hero_count: int = gameData.get_team_size()
	for i in range (hero_count): 
		var new_hero_zone = heroZone.instance()
		add_child(new_hero_zone)
		new_hero_zone.set_player(i+1)

func get_all_cards():
	var cardsArray := []
	for obj in get_children():
		if obj as Card: cardsArray.append(obj)
		if obj as WCHeroZone: cardsArray.append(obj.get_all_cards())	
	return(cardsArray)

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
