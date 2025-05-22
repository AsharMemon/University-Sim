# UnscheduledCourseEntry.gd
# Script for a single draggable entry representing an unscheduled course.
extends Button

# --- Node References ---
@onready var course_name_label: Label = get_node_or_null("HBoxContainer/CourseNameLabel")
# NEW - Add this line and ensure you have a Label node named "ProgramIDLabel" (or similar)
# in your UnscheduledCourseEntry.tscn if you want to display the program ID.
# Adjust the path if it's not a direct child.
@onready var program_id_label: Label = get_node_or_null("HBoxContainer/ProgramIDLabel")

# --- Data ---
var offering_id: String = ""
var course_id: String = ""
var course_name: String = ""
var program_id: String = "" # Storing this from offering_data

# Optional: Store AcademicManager if needed for other actions within this entry
# var academic_manager_ref: AcademicManager

const DETAILED_LOGGING_ENABLED: bool = true # For this script's debug messages

# --- Initialization ---
func _ready():
	if not is_instance_valid(course_name_label):
		printerr("UnscheduledCourseEntry (%s): CourseNameLabel node not found! Check path." % name)
	else:
		course_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE # Good for drag functionality on button

	# NEW: Validate ProgramIDLabel
	if not is_instance_valid(program_id_label):
		if DETAILED_LOGGING_ENABLED: print_debug("ProgramIDLabel node not found in %s. Program ID will not be displayed directly on this entry." % name)
		# This is not necessarily an error if you don't intend to show it here,
		# but the variable must be declared if used in setup().

# --- Public Functions ---
# Setup function now accepts academic_manager, though it's not strictly used in this version
# unless you need it for more complex logic within the entry itself.
func setup(offering_data: Dictionary, _p_academic_manager: AcademicManager): # Renamed to avoid shadowing
	self.offering_id = offering_data.get("offering_id", "")
	self.course_name = offering_data.get("course_name", "N/A Course Name")
	self.course_id = offering_data.get("course_id", "N/A")
	self.program_id = offering_data.get("program_id", "N/A Program") # Store for tooltip or other uses

	# self.academic_manager_ref = _p_academic_manager # Store if you need it for other actions

	if is_instance_valid(course_name_label):
		course_name_label.text = "%s (%s)" % [self.course_name, self.course_id.right(6)] # Show last 6 chars of course_id for brevity
	
	# This is where the error occurred because program_id_label was not declared at class level
	if is_instance_valid(program_id_label):
		program_id_label.text = "For: %s" % self.program_id
		program_id_label.visible = true # Make sure it's visible if it exists
	elif get_node_or_null("ProgramIDLabel"): # If node exists but var isn't set up right
		printerr("UnscheduledCourseEntry (%s): ProgramIDLabel node exists but @onready var might be misconfigured." % name)


	self.tooltip_text = "Drag to schedule:\n%s (%s)\nProgram: %s\nOffering ID: %s" % [
		self.course_name,
		self.course_id,
		self.program_id,
		self.offering_id
	]

# --- Drag and Drop Logic ---
func _get_drag_data(_at_position: Vector2) -> Variant: # _at_position often not needed here
	if offering_id.is_empty():
		print_debug("Cannot start drag: offering_id is empty for course '", course_name, "'")
		return null

	if DETAILED_LOGGING_ENABLED: print_debug("Drag started for: %s (Offering ID: %s)" % [self.course_name, self.offering_id])
	
	var drag_data = {
		"type": "course_offering",
		"offering_id": offering_id,
		"course_id": course_id,
		"course_name": course_name,
		"program_id": program_id # Pass program_id in drag data as well, might be useful for filtering professors
	}

	# Create a drag preview
	var preview_label = Label.new()
	preview_label.text = "%s (%s)" % [course_name, course_id]
	preview_label.modulate = Color(0.95, 0.95, 0.95, 0.85)
	preview_label.add_theme_font_size_override("font_size", 14)
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.1, 0.1, 0.15, 0.8)
	style_box.set_content_margin_all(4)
	style_box.corner_radius_top_left = 3; style_box.corner_radius_top_right = 3
	style_box.corner_radius_bottom_left = 3; style_box.corner_radius_bottom_right = 3
	preview_label.add_theme_stylebox_override("normal", style_box)
	# Set size after adding stylebox and text to ensure it fits
	preview_label.set_size(Vector2.ZERO) # Reset size
	preview_label.set_size(preview_label.get_minimum_size()) # Recalculate based on content
	
	set_drag_preview(preview_label)
	self.modulate = Color(1,1,1,0.4) # Make original button semi-transparent during drag
	return drag_data

func _notification(what: int):
	if what == NOTIFICATION_DRAG_END:
		self.modulate = Color(1,1,1,1) # Restore full opacity when drag ends

# --- Helper Functions ---
func print_debug(message_parts):
	if not DETAILED_LOGGING_ENABLED: return
	var final_message = "[UnscheduledEntry]: " # Shortened prefix
	# Standardized message formatting
	if typeof(message_parts) == TYPE_STRING:
		final_message += message_parts
	elif typeof(message_parts) == TYPE_ARRAY:
		var string_array : Array[String] = []
		for item in message_parts: string_array.append(str(item))
		final_message += String(" ").join(string_array)
	else:
		final_message += str(message_parts)
	print(final_message)
