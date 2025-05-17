# TimeManager.gd
class_name TimeManager
extends Node

# --- Macro Time Signals ---
signal date_changed(day: int, month: int, year: int)
signal new_day_has_started(day: int, month: int, year: int)
signal new_month_has_started(month: int, year: int)
signal new_year_started(year: int)
signal september_enrollment_starts(year: int)

# --- General Time Control Signals ---
signal pause_state_changed(is_paused: bool)
signal speed_changed(new_speed: float)

# --- NEW: Visual Time Signals (for student AI visual loop) ---
signal visual_hour_slot_changed(day_str: String, time_slot_str: String)
signal visual_day_changed(day_str: String) # For when the visual Mon-Fri cycle changes day

# --- Macro Time Variables ---
@export var seconds_per_game_day: float = 5.0 # How many real seconds for one game day to pass
var current_day: int = 1
var current_month: int = 8
var current_year: int = 2025
var days_in_month: Array[int] = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
var has_triggered_september_enrollment_this_year: bool = false

# --- Visual Time Loop Variables ---
@export var seconds_per_visual_hour_slot: float = 10.0 # Real seconds for one visual hour slot (e.g., 0800 -> 0900)
const VISUAL_DAYS_OF_WEEK: Array[String] = ["Mon", "Tue", "Wed", "Thu", "Fri"] # Academic week
# HOURLY_TIME_SLOTS defined in AcademicManager, we can get it from there or duplicate it
const VISUAL_HOURLY_TIME_SLOTS: Array[String] = [ 
	"0800", "0900", "1000", "1100", "1200", 
	"1300", "1400", "1500", "1600", "1700" # Ends at 17:00, next is end of day
]
const END_OF_ACADEMIC_DAY_SLOT = "1800" # A virtual slot representing end of classes

var current_visual_day_index: int = 0 # 0=Mon, 1=Tue, ..., 4=Fri
var current_visual_time_slot_index: int = 0 # Index in VISUAL_HOURLY_TIME_SLOTS
var _visual_time_accumulator: float = 0.0

# --- General Time Control ---
var _is_paused: bool = false
var _current_speed_multiplier: float = 1.0 # Affects both macro and visual time equally for now
var _macro_time_accumulator: float = 0.0


func _ready():
	print("TimeManager Ready. Macro day: %.1fs, Visual hour slot: %.1fs" % [seconds_per_game_day, seconds_per_visual_hour_slot])
	current_visual_day_index = 0 # Start visual cycle on Monday
	current_visual_time_slot_index = 0 # Start at "0800"
	emit_signals_for_initial_state()
	# Emit initial visual time state
	emit_signal("visual_hour_slot_changed", get_current_visual_day_string(), get_current_visual_time_slot_string())
	emit_signal("visual_day_changed", get_current_visual_day_string())


func emit_signals_for_initial_state():
	emit_signal("date_changed", current_day, current_month, current_year)
	emit_signal("pause_state_changed", _is_paused)
	emit_signal("speed_changed", _current_speed_multiplier)

func _process(delta: float):
	if _is_paused or _current_speed_multiplier == 0.0:
		return

	var effective_delta = delta * _current_speed_multiplier

	# --- Macro Time Advancement ---
	_macro_time_accumulator += effective_delta
	if _macro_time_accumulator >= seconds_per_game_day:
		_macro_time_accumulator -= seconds_per_game_day
		_advance_macro_day()

	# --- Visual Time Advancement ---
	_visual_time_accumulator += effective_delta
	if _visual_time_accumulator >= seconds_per_visual_hour_slot:
		_visual_time_accumulator -= seconds_per_visual_hour_slot
		_advance_visual_hour_slot()

func _advance_macro_day():
	current_day += 1
	# No change to visual day index here, it runs independently or resets with macro day if desired
	# current_day_of_week_index was removed as visual_day_index serves the Mon-Fri cycle for students

	var days_in_current_m = days_in_month[current_month]
	if current_month == 2 and _is_leap_year(current_year): days_in_current_m = 29

	if current_day > days_in_current_m:
		current_day = 1
		current_month += 1
		emit_signal("new_month_has_started", current_month, current_year)
		if current_month > 12:
			current_month = 1
			current_year += 1
			has_triggered_september_enrollment_this_year = false
			emit_signal("new_year_started", current_year)
			emit_signal("new_month_has_started", current_month, current_year)

	emit_signal("date_changed", current_day, current_month, current_year)
	emit_signal("new_day_has_started", current_day, current_month, current_year)
	
	if current_month == 9 and current_day == 1 and not has_triggered_september_enrollment_this_year:
		emit_signal("september_enrollment_starts", current_year)
		has_triggered_september_enrollment_this_year = true
		print("TimeManager: Emitted september_enrollment_starts for Year %d" % current_year)

func _advance_visual_hour_slot():
	current_visual_time_slot_index += 1
	if current_visual_time_slot_index >= VISUAL_HOURLY_TIME_SLOTS.size():
		# End of academic day for visual purposes
		emit_signal("visual_hour_slot_changed", get_current_visual_day_string(), END_OF_ACADEMIC_DAY_SLOT)
		
		current_visual_time_slot_index = 0 # Reset to first slot for next day
		current_visual_day_index = (current_visual_day_index + 1) % VISUAL_DAYS_OF_WEEK.size()
		emit_signal("visual_day_changed", get_current_visual_day_string()) # Notify new visual day
	
	emit_signal("visual_hour_slot_changed", get_current_visual_day_string(), get_current_visual_time_slot_string())
	# print("Visual Time: %s, %s" % [get_current_visual_day_string(), get_current_visual_time_slot_string()])


func _is_leap_year(year: int) -> bool:
	return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0)

# --- Public Methods for Time Control ---
func set_paused(pause_state: bool): # Unchanged from before
	if _is_paused == pause_state: return
	_is_paused = pause_state
	emit_signal("pause_state_changed", _is_paused)
func get_is_paused() -> bool: return _is_paused # Unchanged
func set_speed(multiplier: float): # Unchanged from before
	var new_speed = clampi(multiplier, 0.0, 100.0)
	if abs(_current_speed_multiplier - new_speed) < 0.01:
		if new_speed > 0.0 && _is_paused: set_paused(false)
		return
	_current_speed_multiplier = new_speed
	if _current_speed_multiplier > 0.0 and _is_paused: set_paused(false)
	elif _current_speed_multiplier == 0.0 and not _is_paused: set_paused(true)
	emit_signal("speed_changed", _current_speed_multiplier)
func get_speed_multiplier() -> float: return _current_speed_multiplier # Unchanged

# --- Public Methods for Macro Time Access ---
func get_current_day() -> int: return current_day
func get_current_month() -> int: return current_month
func get_current_year() -> int: return current_year

# --- NEW Public Methods for Visual Time Access ---
func get_current_visual_day_string() -> String:
	if current_visual_day_index >= 0 and current_visual_day_index < VISUAL_DAYS_OF_WEEK.size():
		return VISUAL_DAYS_OF_WEEK[current_visual_day_index]
	return "InvalidDay" 

func get_current_visual_time_slot_string() -> String:
	if current_visual_time_slot_index >= 0 and current_visual_time_slot_index < VISUAL_HOURLY_TIME_SLOTS.size():
		return VISUAL_HOURLY_TIME_SLOTS[current_visual_time_slot_index]
	# If index is out of bounds (e.g., exactly at size(), meaning end of day), return a special slot
	if current_visual_time_slot_index == VISUAL_HOURLY_TIME_SLOTS.size():
		return END_OF_ACADEMIC_DAY_SLOT
	return "InvalidTime"

func get_visual_hourly_time_slots_list() -> Array[String]: # If student AI needs the list
	return VISUAL_HOURLY_TIME_SLOTS
