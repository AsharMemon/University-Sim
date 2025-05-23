# ProfessorListEntry.gd
extends PanelContainer

@onready var professor_name_label: Label = $MarginContainer/VBoxContainer/ProfessorNameLabel
@onready var specialization_label: Label = $MarginContainer/VBoxContainer/SpecializationLabel
# Add @onready vars for other labels if you add them

var professor_data: Professor

func setup(prof: Professor):
	self.professor_data = prof
	if not is_instance_valid(prof):
		professor_name_label.text = "Invalid Professor Data"
		specialization_label.text = ""
		return

	professor_name_label.text = prof.professor_name
	specialization_label.text = prof.get_specialization_string()
	# Update other labels

func _get_drag_data(_at_position: Vector2) -> Variant:
	if not is_instance_valid(professor_data):
		return null

	var preview_label = Label.new()
	preview_label.text = "Prof: " + professor_data.professor_name
	# You can make a more elaborate preview by instancing the scene itself
	# var preview = get_tree().current_scene.instantiate() # Or preload self
	# preview.setup(professor_data) # If making a full copy
	set_drag_preview(preview_label)

	return {
		"type": "professor",
		"professor_id": professor_data.professor_id,
		"professor_name": professor_data.professor_name # For debug or quick display
	}

func _can_drop_data(_at_position: Vector2, _data: Variant) -> bool:
	# Professors are usually not drop targets themselves in this list
	return false
