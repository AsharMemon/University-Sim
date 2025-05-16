# UnscheduledCourseEntry.gd
# Script for a single draggable entry representing an unscheduled course.
extends Button 

# --- Node References ---
@onready var course_name_label: Label = get_node_or_null("CourseNameLabel") 

# --- Data ---
var offering_id: String = ""
var course_id: String = ""
var course_name: String = ""
var program_id: String = ""

# --- Initialization ---
func _ready():
	if is_instance_valid(course_name_label):
		course_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

# --- Public Functions ---
func setup(offering_data: Dictionary):
	if offering_data.is_empty():
		printerr("UnscheduledCourseEntry: Received empty offering_data in setup."); return
	self.offering_id = offering_data.get("offering_id", "")
	self.course_id = offering_data.get("course_id", "")
	self.course_name = offering_data.get("course_name", "N/A Course")
	self.program_id = offering_data.get("program_id", "N/A Program")
	var display_text = "%s (%s) - [%s]" % [self.course_name, self.course_id, self.program_id]
	self.text = display_text 
	if is_instance_valid(course_name_label): course_name_label.text = display_text
	set_meta("offering_id", self.offering_id)
	set_meta("course_details", { "course_id": self.course_id, "course_name": self.course_name, "program_id": self.program_id})

# --- Drag and Drop Logic ---
func _get_drag_data(at_position: Vector2) -> Variant:
	if offering_id.is_empty(): return null 
	print_debug("Drag started for: ", self.course_name, " (Offering ID: ", offering_id, ")")
	
	var drag_data = {
		"type": "course_offering", 
		"offering_id": offering_id,
		"course_id": course_id,
		"course_name": course_name
		# Removed default_duration_slots, as it's now determined by drop day in AcademicManager
	}

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
	preview_label.set_size(Vector2.ZERO); preview_label.set_size(preview_label.get_minimum_size()) 
	set_drag_preview(preview_label)
	self.modulate = Color(1,1,1,0.4) 
	return drag_data

func _notification(what: int):
	if what == NOTIFICATION_DRAG_END:
		self.modulate = Color(1,1,1,1) 

# --- Helper Functions ---
func print_debug(message_parts):
	var final_message = "[UnscheduledCourseEntry]: "
	if typeof(message_parts) == TYPE_STRING: final_message += message_parts
	elif typeof(message_parts) == TYPE_ARRAY or typeof(message_parts) == TYPE_PACKED_STRING_ARRAY:
		var temp_array : Array = message_parts; final_message += " ".join(temp_array)
	else: final_message += str(message_parts)
	print(final_message)
