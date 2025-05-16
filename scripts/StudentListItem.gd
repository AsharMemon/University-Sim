# StudentListItem.gd
# This script is attached to the root node of StudentListItem.tscn.
# It populates the UI elements with data from a student node.
extends PanelContainer

# --- Node References (Set in Godot Editor or via @onready) ---
# Ensure these paths match the node structure in your StudentListItem.tscn scene.
@onready var student_name_label: Label = $MarginContainer/VBoxContainer/StudentNameLabel
@onready var program_label: Label = $MarginContainer/VBoxContainer/ProgramLabel
@onready var courses_label: Label = $MarginContainer/VBoxContainer/CoursesLabel
@onready var status_label: Label = $MarginContainer/VBoxContainer/StatusLabel   # Label to show "Status: Enrolled" or "Status: Graduated!"
@onready var credits_label: Label = $MarginContainer/VBoxContainer/CreditsLabel # Label to show "Credits: X / Y"

func _ready():
	# This function is called when the node is ready.
	# It's a good place to check if all required child nodes were found.
	if not is_instance_valid(student_name_label):
		printerr("StudentListItem: StudentNameLabel node not found or path is incorrect in StudentListItem.tscn.")
	if not is_instance_valid(program_label):
		printerr("StudentListItem: ProgramLabel node not found or path is incorrect in StudentListItem.tscn.")
	if not is_instance_valid(courses_label):
		printerr("StudentListItem: CoursesLabel node not found or path is incorrect in StudentListItem.tscn.")
	if not is_instance_valid(status_label):
		printerr("StudentListItem: StatusLabel node not found or path is incorrect in StudentListItem.tscn. Please add this Label.")
	if not is_instance_valid(credits_label):
		printerr("StudentListItem: CreditsLabel node not found or path is incorrect in StudentListItem.tscn. Please add this Label.")

# Call this function from your main UI script (e.g., BuildingManager) 
# to populate this list item with data from a specific student.
func set_student_data(student_node: Node):
	# Fallback text if student_node is invalid.
	var default_name_text = "Name: Error - Invalid Node"
	var default_program_text = "Program: N/A"
	var default_courses_text = "Courses: N/A"
	var default_status_text = "Status: N/A"
	var default_credits_text = "Credits: N/A"

	if not is_instance_valid(student_node):
		# If the student node itself is invalid, set all labels to their default error/N/A state.
		if is_instance_valid(student_name_label): student_name_label.text = default_name_text
		if is_instance_valid(program_label): program_label.text = default_program_text
		if is_instance_valid(courses_label): courses_label.text = default_courses_text
		if is_instance_valid(status_label): status_label.text = default_status_text
		if is_instance_valid(credits_label): credits_label.text = default_credits_text
		return

	# Attempt to get data using the get_info_summary() method from the student node.
	if student_node.has_method("get_info_summary"):
		var info: Dictionary = student_node.get_info_summary()
		
		# Populate Name Label
		if is_instance_valid(student_name_label):
			student_name_label.text = "Name: " + info.get("name", "N/A")
		else:
			printerr("StudentListItem (" + name + "): student_name_label is null when trying to set student info for " + student_node.name)

		# Populate Program Label
		if is_instance_valid(program_label):
			program_label.text = "Program: " + info.get("program_name", "N/A")
		else:
			printerr("StudentListItem (" + name + "): program_label is null when trying to set student info for " + student_node.name)

		# Populate Courses Label
		if is_instance_valid(courses_label):
			var current_course_names_list : Array[String] = info.get("current_courses_list", [])
			if not current_course_names_list.is_empty():
				courses_label.text = "Taking: " + ", ".join(current_course_names_list)
			elif info.get("status", "Enrolled") == "Graduated!": # Check status from info dictionary
				courses_label.text = "Taking: None (Graduated)"
			else:
				courses_label.text = "Taking: None"
		else:
			printerr("StudentListItem (" + name + "): courses_label is null when trying to set student info for " + student_node.name)
		
		# Populate Status Label
		if is_instance_valid(status_label):
			status_label.text = "Status: " + info.get("status", "Unknown")
		else:
			printerr("StudentListItem (" + name + "): status_label is null when trying to set student info for " + student_node.name)
			
		# Populate Credits Label
		if is_instance_valid(credits_label):
			var credits_earned = info.get("credits_earned", 0)
			var credits_needed = info.get("credits_needed_for_program", 0)
			credits_label.text = "Credits: " + str(credits_earned) + " / " + str(credits_needed)
		else:
			printerr("StudentListItem (" + name + "): credits_label is null when trying to set student info for " + student_node.name)
			
	else: 
		# Fallback if get_info_summary method is not found on the student node.
		# This indicates a potential issue with the student script or the node being passed.
		printerr("StudentListItem (" + name + "): Student node " + student_node.name + " does NOT have get_info_summary method. Using fallback display.")
		if is_instance_valid(student_name_label):
			student_name_label.text = "Name: " + student_node.name # Use node name as a basic fallback.
		if is_instance_valid(program_label):
			program_label.text = "Program: Data Unavailable"
		if is_instance_valid(courses_label):
			courses_label.text = "Courses: Data Unavailable"
		if is_instance_valid(status_label):
			status_label.text = "Status: Data Unavailable"
		if is_instance_valid(credits_label):
			credits_label.text = "Credits: Data Unavailable"
