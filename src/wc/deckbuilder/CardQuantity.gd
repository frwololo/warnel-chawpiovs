extends MarginContainer


# Declare member variables here. Examples:
# var a = 2
# var b = "text"
onready var background = $Background
onready var minus_button:TextureButton = $MarginContainer/HBoxContainer/MinusButton
onready var plus_button:TextureButton = $MarginContainer/HBoxContainer/PlusButton
onready var quantity_label = $MarginContainer/HBoxContainer/QuantityLabel
onready var container = $MarginContainer/HBoxContainer

var quantity = 0
var is_edit_mode = false
var owner_card = null


# Called when the node enters the scene tree for the first time.
func _ready():
	minus_button.connect("pressed", self, "decrease_quantity")
	plus_button.connect("pressed", self, "increase_quantity")
	owner_card = get_parent()
	display_mode()

	pass # Replace with function body.


func _process(_delta):
	resize()

func edit_mode():
	self.visible = true
	for c in container.get_children():
		container.remove_child(c)	
	container.add_child(minus_button)
	container.add_child(quantity_label)
	container.add_child(plus_button)
	resize()
	is_edit_mode = true
	
	rules_check()

func rules_check():
	var disable_all = false
	var disable_plus = false
	if owner_card.enforce_rules:		
		var hero_id = owner_card.deck_edit_hero_id
		var hero_data = cfc.get_card_by_id(hero_id)
		var hero_set_name = hero_data["card_set_code"].to_lower()
		var set_name = owner_card.get_property("card_set_code","").to_lower()
		
		if set_name == hero_set_name:
			disable_all = true
	
		if !owner_card.can_add_card_to_deck():
			disable_plus = true

		
	if disable_all:	
		minus_button.disabled = true
		plus_button.disabled = true
	else:
		minus_button.disabled = false
		plus_button.disabled = disable_plus		

func display_mode():
	for c in container.get_children():
		container.remove_child(c)
	container.add_child(quantity_label)
	if quantity <= 1:
		self.visible = false
	resize()	
	is_edit_mode = false

func refresh():
	if is_edit_mode:
		edit_mode()
	else:
		display_mode()

func increase_quantity():
	set_quantity(quantity+1)
	

func decrease_quantity():
	if quantity < 1:
		return
	set_quantity(quantity-1)

func set_quantity(new_quantity):
	var before = quantity
	quantity = new_quantity
	quantity_label.text = "X" + str(new_quantity)
	if !is_edit_mode:
		self.visible = (quantity > 1)
	
	if before != quantity:
		owner_card.set_quantity(quantity)
		
	rules_check()
	
func resize():
	
	$MarginContainer.rect_min_size = Vector2(0,0)
	$MarginContainer.margin_bottom = 0
	$MarginContainer.margin_top = 0	
	$MarginContainer.margin_left = 0
	$MarginContainer.margin_right = 0		
	$MarginContainer.rect_size =  Vector2(0,0)	
	$MarginContainer/HBoxContainer.rect_min_size = Vector2(0,0)
	$MarginContainer/HBoxContainer.rect_size = Vector2(0,0)
	minus_button.rect_min_size = Vector2(0,0)
	minus_button.rect_size = Vector2(0,0)
	plus_button.rect_min_size = Vector2(0,0)
	plus_button.rect_size = Vector2(0,0)
	background.rect_min_size = Vector2(0,0)
	background.rect_size = $MarginContainer.rect_size

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
