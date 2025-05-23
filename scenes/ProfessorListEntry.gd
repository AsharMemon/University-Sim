# ProfessorListEntry.gd
extends PanelContainer

signal professor_drag_started(professor_id)
signal professor_drag_ended # Emitted when the drag finishes, successfully or not

@onready var professor_name_label: Label = $MarginContainer/VBoxContainer/ProfessorNameLabel
@onready var specialization_label: Label = $MarginContainer/VBoxContainer/SpecializationLabel

var professor_data: Professor

func _ready():
	# For debugging visibility of the entry itself
	#var style_box = StyleBoxFlat.new()
	#style_box.bg_color = Color.DARK_CYAN # Or any color
	#style_box.set_content_margin_all(4)
	#add_theme_stylebox_override("panel", style_box)
	#custom_minimum_size.y = 40
	pass

func setup(prof: Professor):
	self.professor_data = prof
	if not is_instance_valid(prof):
		professor_name_label.text = "Invalid Professor Data"
		specialization_label.text = ""
		return

	professor_name_label.text = prof.professor_name
	specialization_label.text = prof.get_specialization_string()
	# Ensure labels are visible if they were hidden by default in editor
	professor_name_label.visible = true
	specialization_label.visible = true


func _get_drag_data(_at_position: Vector2) -> Variant:
	if not is_instance_valid(professor_data):
		return null

	var preview_label = Label.new()
	preview_label.text = "Prof: " + professor_data.professor_name
	set_drag_preview(preview_label)

	emit_signal("professor_drag_started", professor_data.professor_id) # Emit signal with ID

	return {
		"type": "professor",
		"professor_id": professor_data.professor_id,
		"professor_name": professor_data.professor_name
	}

func _notification(what: int):
	if what == NOTIFICATION_DRAG_END:
		# This notification is received by the control that initiated the drag
		# when the drag operation concludes, regardless of a successful drop.
		emit_signal("professor_drag_ended")

# _can_drop_data remains false as these entries are not drop targets themselves
