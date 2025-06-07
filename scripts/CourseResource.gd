# CourseResource.gd
class_name CourseResource
extends Resource

# NEW: Enum for Course Level
enum CourseLevel {
	UNDERGRADUATE, # e.g., 100-400 level
	GRADUATE       # e.g., 500+ level
}

@export var course_id: String = ""
@export var course_name: String = ""

@export_category("Academic Details")
@export var course_level: CourseLevel = CourseLevel.UNDERGRADUATE # NEW: Course Level
@export var credits: float = 3.0
@export_multiline var description: String = ""
@export var progress_needed: int = 100
@export var prerequisites: Array[CourseResource] = []

@export_category("Typical Placement in Program")
@export_range(1, 6, 1) var default_program_year: int = 1 # Max year might increase for PhD
@export_range(1, 3, 1) var default_program_semester: int = 1 # Max 3 if you include summer
