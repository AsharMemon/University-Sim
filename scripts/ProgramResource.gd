# ProgramResource.gd
class_name ProgramResource
extends Resource

# NEW: Enum for Program Level
enum ProgramLevel {
	UNDERGRADUATE,
	MASTERS,
	PHD
}

@export var program_id: String = ""
@export var program_name: String = ""

@export_category("Academic Details")
@export var level: ProgramLevel = ProgramLevel.UNDERGRADUATE # NEW: Program Level
@export var credits_to_graduate: float = 120.0
@export_range(1, 8, 1) var typical_duration_years: int = 4 # NEW: Typical duration
@export_range(1, 3, 1) var semesters_per_year: int = 2
@export var requires_thesis_or_dissertation: bool = false # NEW: For grad programs

@export_category("Administrative")
@export var unlock_cost: int = 5000

@export_category("Curriculum & Requirements")
@export var courses_in_program_resources: Array[CourseResource] = [] 
@export var mandatory_courses_resources: Array[CourseResource] = []
