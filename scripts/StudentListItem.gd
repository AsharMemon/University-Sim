# StudentListItem.gd
# This script is attached to the root node of StudentListItem.tscn.
# It populates the UI elements with data from a student info dictionary.
extends PanelContainer

# --- Node References (Set in Godot Editor or via @onready) ---
@export var student_name_label: Label
@export var program_label: Label
@export var courses_label: Label
@export var status_label: Label
@export var credits_label: Label

# Optional: Add a student_id_label if you want to display it for debugging
# @export var student_id_label: Label

func _ready():
	# Check if all required child nodes were found.
	if not is_instance_valid(student_name_label):
		printerr("StudentListItem (%s): StudentNameLabel node not found or path is incorrect." % name)
	if not is_instance_valid(program_label):
		printerr("StudentListItem (%s): ProgramLabel node not found or path is incorrect." % name)
	if not is_instance_valid(courses_label):
		printerr("StudentListItem (%s): CoursesLabel node not found or path is incorrect." % name)
	if not is_instance_valid(status_label):
		printerr("StudentListItem (%s): StatusLabel node not found or path is incorrect." % name)
	if not is_instance_valid(credits_label):
		printerr("StudentListItem (%s): CreditsLabel node not found or path is incorrect." % name)

# Call this function from your main UI script (e.g., BuildingManager)
# to populate this list item with data from a specific student's info dictionary.
func set_student_data(student_info: Dictionary):
	# Fallback text if student_info is invalid or missing expected fields.
	var default_name_text = "Name: N/A"
	var default_program_text = "Program: N/A"
	var default_courses_text = "Courses: N/A"
	var default_status_text = "Status: N/A"
	var default_credits_text = "Credits: N/A"
	# var default_id_text = "ID: N/A" # If you add an ID label

	if not student_info is Dictionary or student_info.is_empty():
		printerr("StudentListItem (%s): Received invalid or empty student_info dictionary." % name)
		# Set all labels to their default error/N/A state.
		if is_instance_valid(student_name_label): student_name_label.text = default_name_text
		if is_instance_valid(program_label): program_label.text = default_program_text
		if is_instance_valid(courses_label): courses_label.text = default_courses_text
		if is_instance_valid(status_label): status_label.text = default_status_text
		if is_instance_valid(credits_label): credits_label.text = default_credits_text
		# if is_instance_valid(student_id_label): student_id_label.text = default_id_text
		return

	var student_id_for_log = student_info.get("student_id", "UnknownID") # For better logging

	# Populate Name Label
	if is_instance_valid(student_name_label):
		student_name_label.text = "Name: " + student_info.get("name", "N/A")
	else:
		printerr("StudentListItem (%s): student_name_label is null for student_id: %s" % [name, student_id_for_log])

	# Populate Program Label
	if is_instance_valid(program_label):
		program_label.text = "Program: " + student_info.get("program_name", "N/A")
	else:
		printerr("StudentListItem (%s): program_label is null for student_id: %s" % [name, student_id_for_log])

	# Populate Courses Label
	if is_instance_valid(courses_label):
		var current_course_names_list: Array[String] = student_info.get("current_courses_list", [])
		if not current_course_names_list.is_empty():
			courses_label.text = "Taking: " + ", ".join(current_course_names_list)
		elif student_info.get("status", "Enrolled") == "Graduated!":
			courses_label.text = "Taking: None (Graduated)"
		else:
			courses_label.text = "Taking: None / Not Specified" # More descriptive for non-graduated
	else:
		printerr("StudentListItem (%s): courses_label is null for student_id: %s" % [name, student_id_for_log])
	
	# Populate Status Label
	if is_instance_valid(status_label):
		status_label.text = "Status: " + student_info.get("status", "Unknown")
	else:
		printerr("StudentListItem (%s): status_label is null for student_id: %s" % [name, student_id_for_log])
		
	# Populate Credits Label
	if is_instance_valid(credits_label):
		var credits_earned: float = student_info.get("credits_earned", 0.0)
		var credits_needed: float = student_info.get("credits_needed_for_program", 0.0)
		credits_label.text = "Credits: " + ("%.1f" % credits_earned) + " / " + ("%.1f" % credits_needed)
	else:
		printerr("StudentListItem (%s): credits_label is null for student_id: %s" % [name, student_id_for_log])

	# Optional: Populate ID Label (if you add one to your .tscn and export it)
	# if is_instance_valid(student_id_label):
	# 	student_id_label.text = "ID: " + student_info.get("student_id", "N/A")
