# CourseResource.gd
class_name CourseResource
extends Resource

@export var course_id: String = ""
@export var course_name: String = ""
@export var credits: float = 3.0
@export_multiline var description: String = ""
@export var progress_needed: int = 100
@export var prerequisites: Array[CourseResource] = [] # Array of CourseResource objects

@export_category("Typical Placement")
@export_range(1, 4, 1) var default_program_year: int = 1 # Assuming 4-year programs
@export_range(1, 2, 1) var default_program_semester: int = 1 # Assuming 2 semesters per year
