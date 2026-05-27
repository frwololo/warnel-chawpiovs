## A custom ScrollContainer that supports dragging from touch screens by ensuring children
## are using the Pass mouse_filter property
class_name TouchScrollContainer
extends ScrollContainer

func _ready() -> void:
	# This assumes you have a top level container in the ScrollContainer
	# when children are added it ensures mouse_filter pass gets set
	for c in get_children():
		if c is Container:
			c.connect("child_entered_tree", self, "_on_child_entered_tree")
	set_all_children_mouse_filter_pass(self)

func _on_child_entered_tree(node: Node) -> void:
	set_all_children_mouse_filter_pass(node, true)

func set_all_children_mouse_filter_pass(parent: Node, set_parent: bool = false) -> void:
	if set_parent and parent is Control:
		if parent.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			parent.mouse_filter = Control.MOUSE_FILTER_PASS
	for child in parent.get_children():
		if child is Control:
			if child.mouse_filter != Control.MOUSE_FILTER_IGNORE:			
				child.mouse_filter = Control.MOUSE_FILTER_PASS
		set_all_children_mouse_filter_pass(child)
