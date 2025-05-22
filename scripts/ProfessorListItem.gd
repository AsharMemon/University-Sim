# ProfessorListItem.gd
class_name ProfessorListItem
extends Button

signal professor_selected(professor_id: String)

@export var name_label: Label
@export var rank_label: Label
@export var specialization_label: Label
@export var salary_label: Label

var current_professor_id: String = ""
# var professor_object_ref: Professor # Optional: if you need to store the whole object

const DETAILED_LOGGING_ENABLED: bool = true # For this script's debug messages

func _ready():
	# Validate @onready vars
	if not is_instance_valid(name_label): printerr("ProfessorListItem (%s): NameLabel not found! Check path in .tscn" % name)
	if not is_instance_valid(rank_label): printerr("ProfessorListItem (%s): RankLabel not found! Check path in .tscn" % name)
	if not is_instance_valid(specialization_label): printerr("ProfessorListItem (%s): SpecializationLabel not found! Check path in .tscn" % name)
	if not is_instance_valid(salary_label): printerr("ProfessorListItem (%s): SalaryLabel not found! Check path in .tscn" % name)

	# Connect the button's pressed signal to a local method
	if not self.is_connected("pressed", Callable(self, "_on_self_pressed")):
		self.pressed.connect(Callable(self, "_on_self_pressed"))

# MODIFIED: Now strictly expects a Professor object.
# The second parameter 'show_salary_in_list' controls if the salary label is visible.
func setup_item(prof_object: Professor, show_salary_in_list: bool = false):
	# Corrected type check:
	if not is_instance_valid(prof_object) or not prof_object is Professor:
		if DETAILED_LOGGING_ENABLED: print_debug("Invalid or non-Professor object passed to setup_item. Object was: " + str(prof_object))
		if is_instance_valid(name_label): name_label.text = "Error: Invalid Data"
		if is_instance_valid(rank_label): rank_label.text = "-"
		if is_instance_valid(specialization_label): specialization_label.text = "-"
		if is_instance_valid(salary_label): salary_label.visible = false
		current_professor_id = ""
		# professor_object_ref = null
		return

	# Store the ID from the Professor object
	current_professor_id = prof_object.professor_id
	# professor_object_ref = prof_object # If you need to store the full object reference

	# Directly access properties and methods of the Professor object
	if is_instance_valid(name_label):
		name_label.text = prof_object.professor_name
	
	if is_instance_valid(rank_label):
		# Ensure your Professor.gd script has get_rank_string()
		if prof_object.has_method("get_rank_string"):
			rank_label.text = prof_object.get_rank_string()
		else:
			rank_label.text = "Rank N/A" # Fallback
			if DETAILED_LOGGING_ENABLED: print_debug("Professor object for ID '%s' is missing get_rank_string() method." % current_professor_id)

	if is_instance_valid(specialization_label):
		# Ensure your Professor.gd script has get_specialization_string()
		if prof_object.has_method("get_specialization_string"):
			specialization_label.text = prof_object.get_specialization_string()
		else:
			specialization_label.text = "Spec. N/A" # Fallback
			if DETAILED_LOGGING_ENABLED: print_debug("Professor object for ID '%s' is missing get_specialization_string() method." % current_professor_id)
	
	if is_instance_valid(salary_label):
		if show_salary_in_list:
			salary_label.text = "$%.0f" % prof_object.annual_salary # Direct property access
			salary_label.visible = true
		else:
			salary_label.visible = false
			
func _on_self_pressed():
	if not current_professor_id.is_empty():
		emit_signal("professor_selected", current_professor_id)
	elif DETAILED_LOGGING_ENABLED:
		print_debug("Button pressed but no current_professor_id set for this item.")

# Optional method for visual feedback if the item is selected in a list
func set_selected_visual(is_selected: bool):
	if is_selected:
		modulate = Color(0.7, 0.85, 1.0, 0.9) # Example: Light blue highlight
	else:
		modulate = Color.WHITE # Default (opaque white)

func print_debug(message: String): # Added type hint for message
	if not DETAILED_LOGGING_ENABLED: return
	# Using self.name gives the node's name in the scene tree, which can be helpful for specific instances
	print("[ProfListItem %s]: %s" % [name, message])
