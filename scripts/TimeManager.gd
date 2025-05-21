# TimeManager.gd
class_name TimeManager
extends Node

# --- Macro Time Signals ---
signal date_changed(day: int, month: int, year: int)
signal new_day_has_started(day: int, month: int, year: int)
signal new_month_has_started(month: int, year: int)
signal new_year_started(year: int)
# signal september_enrollment_starts(year: int) # Will be replaced by semester signal

# --- NEW: Academic Term Signals ---
signal fall_semester_starts(year: int)
signal spring_semester_starts(year: int)
signal summer_semester_starts(year: int)
signal winter_break_starts(year: int)
signal spring_break_starts(year: int)
signal summer_break_starts(year: int) # This is the longer break
signal academic_term_changed(current_term: String, year: int) # e.g., "Fall", "Winter Break"

# --- General Time Control Signals ---
signal pause_state_changed(is_paused: bool)
signal speed_changed(new_speed: float)

# --- Visual Time Signals (for student AI visual loop) ---
signal visual_hour_slot_changed(day_str: String, time_slot_str: String)
signal visual_day_changed(day_str: String)

# --- Detailed Simulation Time Signal ---
signal simulation_time_updated(day_str: String, hour_int: int, minute_int: int, visual_slot_str: String)

# --- Macro Time Variables ---
@export var seconds_per_game_day: float = 5.0
var current_day: int = 20 # Example start day
var current_month: int = 8  # Example start month (August) - Fall semester often starts late Aug
var current_year: int = 2025
var days_in_month: Array[int] = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
# var has_triggered_september_enrollment_this_year: bool = false # Replaced by term tracking

# --- NEW: Academic Term Definitions ---
# These are example dates, adjust to your game's desired academic calendar
# (Month, Day)
const FALL_SEMESTER_START_DATE: Vector2i = Vector2i(9, 1)  # Aug 26
const FALL_SEMESTER_END_DATE: Vector2i = Vector2i(12, 13)    # Dec 13

const WINTER_BREAK_START_DATE: Vector2i = Vector2i(12, 14) # Dec 14
const WINTER_BREAK_END_DATE: Vector2i = Vector2i(1, 5)      # Jan 5 (of next year)

const SPRING_SEMESTER_START_DATE: Vector2i = Vector2i(1, 6) # Jan 6
const SPRING_SEMESTER_END_DATE: Vector2i = Vector2i(4, 25)   # April 25

const SPRING_BREAK_START_DATE: Vector2i = Vector2i(3, 10) # Mar 10 (Example mid-Spring break)
const SPRING_BREAK_END_DATE: Vector2i = Vector2i(3, 16)    # Mar 16

const SUMMER_SEMESTER_START_DATE: Vector2i = Vector2i(5, 5) # May 5 (Optional/Shorter)
const SUMMER_SEMESTER_END_DATE: Vector2i = Vector2i(8, 1)    # Aug 1

const SUMMER_BREAK_START_DATE: Vector2i = Vector2i(8, 2)  # Aug 2 (Longer break after Summer Sem)
const SUMMER_BREAK_END_DATE: Vector2i = Vector2i(8, 25) # Aug 25 (Before Fall starts)

# Term States
enum AcademicTerm { NONE, FALL, WINTER_BREAK, SPRING, SPRING_BREAK_MID, SUMMER, SUMMER_BREAK_MAIN }
var current_academic_term: AcademicTerm = AcademicTerm.NONE
var current_term_string: String = "None" # For display/signals
var has_emitted_term_start_this_year: Dictionary = { # Tracks if Fall/Spring/Summer start signals emitted
	AcademicTerm.FALL: false,
	AcademicTerm.SPRING: false,
	AcademicTerm.SUMMER: false,
	AcademicTerm.WINTER_BREAK: false,
	AcademicTerm.SPRING_BREAK_MID: false,
	AcademicTerm.SUMMER_BREAK_MAIN: false,
}


# --- Visual Time Loop Variables ---
@export var seconds_per_visual_hour_slot: float = 120.0
const VISUAL_DAYS_OF_WEEK: Array[String] = ["Mon", "Tue", "Wed", "Thu", "Fri"]
const VISUAL_HOURLY_TIME_SLOTS: Array[String] = [
	"0800", "0900", "1000", "1100", "1200",
	"1300", "1400", "1500", "1600", "1700"
]
const END_OF_ACADEMIC_DAY_SLOT = "1800"

var current_visual_day_index: int = 0
var current_visual_time_slot_index: int = 0
var _visual_time_accumulator: float = 0.0

# --- General Time Control ---
var _is_paused: bool = false
var _current_speed_multiplier: float = 1.0
var _macro_time_accumulator: float = 0.0

# --- Micro Time Variables ---
var _seconds_per_simulation_minute: float = 1.0
var _time_accumulator_for_minute: float = 0.0
var _current_simulation_minute_in_hour: int = 0
var _current_simulation_hour_int: int = 8
var _current_visual_day_str: String = "Mon"
var _current_visual_time_slot_str: String = "0500"

@export var time_display_label_path: NodePath
var time_display_label: Label


func _ready():
	if not time_display_label_path.is_empty():
		time_display_label = get_node_or_null(time_display_label_path)
		if not is_instance_valid(time_display_label):
			printerr("TimeManager: UI Time display label not found at path: ", time_display_label_path)
	
	if seconds_per_visual_hour_slot <= 0:
		printerr("TimeManager: seconds_per_visual_hour_slot is not positive! Minute simulation will be incorrect or too fast.")
		_seconds_per_simulation_minute = 1.0 / 60.0
	else:
		_seconds_per_simulation_minute = seconds_per_visual_hour_slot / 60.0

	current_visual_day_index = 0
	current_visual_time_slot_index = 0
	
	_current_visual_day_str = get_current_visual_day_string()
	_current_visual_time_slot_str = get_current_visual_time_slot_string()
	_update_current_simulation_hour_from_slot_str()

	_update_academic_term(true) # Determine initial term

	print("TimeManager Ready. Macro day: %.1fs, Visual hour slot: %.1fs, Sim Minute: %.3fs real sec. Current Term: %s" % [seconds_per_game_day, seconds_per_visual_hour_slot, _seconds_per_simulation_minute, current_term_string])
	
	emit_signals_for_initial_state()
	
	emit_signal("visual_day_changed", _current_visual_day_str)
	emit_signal("visual_hour_slot_changed", _current_visual_day_str, _current_visual_time_slot_str)
	emit_signal("simulation_time_updated", _current_visual_day_str, _current_simulation_hour_int, _current_simulation_minute_in_hour, _current_visual_time_slot_str)
	_update_time_display_ui()


func emit_signals_for_initial_state():
	emit_signal("date_changed", current_day, current_month, current_year)
	emit_signal("pause_state_changed", _is_paused)
	emit_signal("speed_changed", _current_speed_multiplier)
	emit_signal("academic_term_changed", current_term_string, current_year) # Emit initial term


func _process(delta: float):
	if _is_paused or _current_speed_multiplier == 0.0:
		return

	var effective_delta = delta * _current_speed_multiplier

	_macro_time_accumulator += effective_delta
	if _macro_time_accumulator >= seconds_per_game_day:
		_macro_time_accumulator -= seconds_per_game_day
		_advance_macro_day()

	_visual_time_accumulator += effective_delta
	if _visual_time_accumulator >= seconds_per_visual_hour_slot:
		_visual_time_accumulator -= seconds_per_visual_hour_slot
		_advance_visual_hour_slot()

	if _seconds_per_simulation_minute <= 0: return

	_time_accumulator_for_minute += effective_delta
	var minute_ticked_this_frame: bool = false
	while _time_accumulator_for_minute >= _seconds_per_simulation_minute:
		if _current_simulation_minute_in_hour < 59:
			_time_accumulator_for_minute -= _seconds_per_simulation_minute
			_current_simulation_minute_in_hour += 1
			minute_ticked_this_frame = true
		elif _current_simulation_minute_in_hour == 59:
			if _time_accumulator_for_minute >= _seconds_per_simulation_minute:
				pass
				break
			else:
				break

	if minute_ticked_this_frame:
		emit_signal("simulation_time_updated", _current_visual_day_str, _current_simulation_hour_int, _current_simulation_minute_in_hour, _current_visual_time_slot_str)
		_update_time_display_ui()


func _advance_macro_day():
	current_day += 1
	var days_in_current_m = days_in_month[current_month]
	if current_month == 2 and _is_leap_year(current_year): days_in_current_m = 29

	if current_day > days_in_current_m:
		current_day = 1
		current_month += 1
		emit_signal("new_month_has_started", current_month, current_year)
		if current_month > 12:
			current_month = 1
			current_year += 1
			# Reset term emission flags for the new year
			for term_key in has_emitted_term_start_this_year:
				has_emitted_term_start_this_year[term_key] = false
			emit_signal("new_year_started", current_year)
			emit_signal("new_month_has_started", current_month, current_year)

	emit_signal("date_changed", current_day, current_month, current_year)
	emit_signal("new_day_has_started", current_day, current_month, current_year)
	
	_update_academic_term()


func _update_academic_term(is_initial_setup: bool = false):
	var previous_term = current_academic_term
	var new_term = _determine_current_term(current_month, current_day, current_year)
	
	if new_term != previous_term or is_initial_setup:
		current_academic_term = new_term
		# Update string representation
		match current_academic_term:
			AcademicTerm.FALL: current_term_string = "Fall Semester"
			AcademicTerm.WINTER_BREAK: current_term_string = "Winter Break"
			AcademicTerm.SPRING: current_term_string = "Spring Semester"
			AcademicTerm.SPRING_BREAK_MID: current_term_string = "Spring Break"
			AcademicTerm.SUMMER: current_term_string = "Summer Session"
			AcademicTerm.SUMMER_BREAK_MAIN: current_term_string = "Summer Break"
			_: current_term_string = "Inter-Session"

		emit_signal("academic_term_changed", current_term_string, current_year)
		print("TimeManager: Academic term changed to %s, Year %d" % [current_term_string, current_year])

		# Emit specific term start signals (only once per year for main semesters/breaks)
		if not has_emitted_term_start_this_year.get(current_academic_term, true): # Default to true to avoid re-emission if key missing
			match current_academic_term:
				AcademicTerm.FALL:
					emit_signal("fall_semester_starts", current_year)
					has_emitted_term_start_this_year[AcademicTerm.FALL] = true
					print("TimeManager: Emitted fall_semester_starts for Year %d" % current_year)
				AcademicTerm.WINTER_BREAK:
					emit_signal("winter_break_starts", current_year) # Year might be tricky if break spans Dec-Jan
					has_emitted_term_start_this_year[AcademicTerm.WINTER_BREAK] = true
				AcademicTerm.SPRING:
					emit_signal("spring_semester_starts", current_year)
					has_emitted_term_start_this_year[AcademicTerm.SPRING] = true
				AcademicTerm.SPRING_BREAK_MID:
					emit_signal("spring_break_starts", current_year)
					has_emitted_term_start_this_year[AcademicTerm.SPRING_BREAK_MID] = true
				AcademicTerm.SUMMER:
					emit_signal("summer_semester_starts", current_year)
					has_emitted_term_start_this_year[AcademicTerm.SUMMER] = true
				AcademicTerm.SUMMER_BREAK_MAIN:
					emit_signal("summer_break_starts", current_year)
					has_emitted_term_start_this_year[AcademicTerm.SUMMER_BREAK_MAIN] = true


func _is_date_on_or_after(month: int, day: int, target_month: int, target_day: int) -> bool:
	if month > target_month: return true
	if month == target_month and day >= target_day: return true
	return false

func _is_date_on_or_before(month: int, day: int, target_month: int, target_day: int) -> bool:
	if month < target_month: return true
	if month == target_month and day <= target_day: return true
	return false

func _determine_current_term(month: int, day: int, year: int) -> AcademicTerm:
	# Fall Semester
	if _is_date_on_or_after(month, day, FALL_SEMESTER_START_DATE.x, FALL_SEMESTER_START_DATE.y) and \
	   _is_date_on_or_before(month, day, FALL_SEMESTER_END_DATE.x, FALL_SEMESTER_END_DATE.y):
		return AcademicTerm.FALL

	# Winter Break (spans year change)
	if (_is_date_on_or_after(month, day, WINTER_BREAK_START_DATE.x, WINTER_BREAK_START_DATE.y) and month == 12) or \
	   (_is_date_on_or_before(month, day, WINTER_BREAK_END_DATE.x, WINTER_BREAK_END_DATE.y) and month == 1):
		# If in Jan and before break end, it's still Winter Break of the *previous* academic start year
		# This logic might need refinement based on how you define academic years vs calendar years for breaks.
		return AcademicTerm.WINTER_BREAK

	# Spring Semester
	if _is_date_on_or_after(month, day, SPRING_SEMESTER_START_DATE.x, SPRING_SEMESTER_START_DATE.y) and \
	   _is_date_on_or_before(month, day, SPRING_SEMESTER_END_DATE.x, SPRING_SEMESTER_END_DATE.y):
		# Check for mid-spring break
		if _is_date_on_or_after(month, day, SPRING_BREAK_START_DATE.x, SPRING_BREAK_START_DATE.y) and \
		   _is_date_on_or_before(month, day, SPRING_BREAK_END_DATE.x, SPRING_BREAK_END_DATE.y):
			return AcademicTerm.SPRING_BREAK_MID
		return AcademicTerm.SPRING

	# Summer Semester
	if _is_date_on_or_after(month, day, SUMMER_SEMESTER_START_DATE.x, SUMMER_SEMESTER_START_DATE.y) and \
	   _is_date_on_or_before(month, day, SUMMER_SEMESTER_END_DATE.x, SUMMER_SEMESTER_END_DATE.y):
		return AcademicTerm.SUMMER

	# Summer Break (main, after summer session, before fall)
	if _is_date_on_or_after(month, day, SUMMER_BREAK_START_DATE.x, SUMMER_BREAK_START_DATE.y) and \
	   _is_date_on_or_before(month, day, SUMMER_BREAK_END_DATE.x, SUMMER_BREAK_END_DATE.y):
		return AcademicTerm.SUMMER_BREAK_MAIN
		
	# If outside all defined terms, could be inter-session or leading up to Fall
	# For simplicity, if it's August before Fall starts, treat as part of the tail end of Summer Break
	if month == 8 and day < FALL_SEMESTER_START_DATE.y :
		return AcademicTerm.SUMMER_BREAK_MAIN

	return AcademicTerm.NONE # Default if no specific term matches


func _advance_visual_hour_slot():
	current_visual_time_slot_index += 1
	var new_visual_day_str = get_current_visual_day_string()

	if current_visual_time_slot_index >= VISUAL_HOURLY_TIME_SLOTS.size():
		_current_visual_time_slot_str = END_OF_ACADEMIC_DAY_SLOT
		_update_current_simulation_hour_from_slot_str()
		_current_simulation_minute_in_hour = 0
		_time_accumulator_for_minute = 0.0
		
		emit_signal("visual_hour_slot_changed", new_visual_day_str, _current_visual_time_slot_str)
		emit_signal("simulation_time_updated", new_visual_day_str, _current_simulation_hour_int, _current_simulation_minute_in_hour, _current_visual_time_slot_str)
		_update_time_display_ui()
		
		current_visual_time_slot_index = 0
		current_visual_day_index = (current_visual_day_index + 1) % VISUAL_DAYS_OF_WEEK.size()
		_current_visual_day_str = get_current_visual_day_string()
		emit_signal("visual_day_changed", _current_visual_day_str)
	
	_current_visual_time_slot_str = get_current_visual_time_slot_string()
	_update_current_simulation_hour_from_slot_str()
	_current_simulation_minute_in_hour = 0
	_time_accumulator_for_minute = 0.0

	emit_signal("visual_hour_slot_changed", _current_visual_day_str, _current_visual_time_slot_str)
	emit_signal("simulation_time_updated", _current_visual_day_str, _current_simulation_hour_int, _current_simulation_minute_in_hour, _current_visual_time_slot_str)
	_update_time_display_ui()

func _update_current_simulation_hour_from_slot_str():
	_current_simulation_hour_int = time_slot_str_to_hour_int(_current_visual_time_slot_str)

func _is_leap_year(year: int) -> bool:
	return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0)

func set_paused(pause_state: bool):
	if _is_paused == pause_state: return
	_is_paused = pause_state
	emit_signal("pause_state_changed", _is_paused)
func get_is_paused() -> bool: return _is_paused

func set_speed(multiplier: float):
	var new_speed = clampf(multiplier, 0.0, 100.0)
	if abs(_current_speed_multiplier - new_speed) < 0.01:
		if new_speed > 0.0 && _is_paused: set_paused(false)
		return
	_current_speed_multiplier = new_speed
	if _current_speed_multiplier > 0.0 and _is_paused: set_paused(false)
	elif _current_speed_multiplier == 0.0 and not _is_paused: set_paused(true)
	emit_signal("speed_changed", _current_speed_multiplier)
func get_speed_multiplier() -> float: return _current_speed_multiplier

func get_current_day() -> int: return current_day
func get_current_month() -> int: return current_month
func get_current_year() -> int: return current_year
func get_current_academic_term_enum() -> AcademicTerm: return current_academic_term # New getter
func get_current_academic_term_string() -> String: return current_term_string # New getter


func get_current_visual_day_string() -> String:
	if current_visual_day_index >= 0 and current_visual_day_index < VISUAL_DAYS_OF_WEEK.size():
		return VISUAL_DAYS_OF_WEEK[current_visual_day_index]
	printerr("TimeManager: Invalid current_visual_day_index: ", current_visual_day_index)
	return "InvalidDay"

func get_current_visual_time_slot_string() -> String:
	if current_visual_time_slot_index >= 0 and current_visual_time_slot_index < VISUAL_HOURLY_TIME_SLOTS.size():
		return VISUAL_HOURLY_TIME_SLOTS[current_visual_time_slot_index]
	if current_visual_time_slot_index == VISUAL_HOURLY_TIME_SLOTS.size():
		return END_OF_ACADEMIC_DAY_SLOT
	printerr("TimeManager: Invalid current_visual_time_slot_index: ", current_visual_time_slot_index)
	return "InvalidTime"

func get_current_simulation_hour_int() -> int:
	return _current_simulation_hour_int

func get_current_simulation_minute() -> int:
	return _current_simulation_minute_in_hour

func get_visual_hourly_time_slots_list() -> Array[String]:
	return VISUAL_HOURLY_TIME_SLOTS

func get_next_academic_slot_info() -> Dictionary:
	var next_slot_day_str: String = _current_visual_day_str
	var next_slot_time_str: String = ""
	
	if current_visual_time_slot_index < -1 or current_visual_time_slot_index > VISUAL_HOURLY_TIME_SLOTS.size():
		printerr("TimeManager (get_next_academic_slot_info): Invalid current_visual_time_slot_index: ", current_visual_time_slot_index)
		return {"day": _current_visual_day_str, "slot": "InvalidTime"}

	var next_slot_idx = current_visual_time_slot_index + 1

	if next_slot_idx < VISUAL_HOURLY_TIME_SLOTS.size():
		next_slot_time_str = VISUAL_HOURLY_TIME_SLOTS[next_slot_idx]
	else:
		var next_day_idx = (current_visual_day_index + 1) % VISUAL_DAYS_OF_WEEK.size()
		next_slot_day_str = VISUAL_DAYS_OF_WEEK[next_day_idx]
		if not VISUAL_HOURLY_TIME_SLOTS.is_empty():
			next_slot_time_str = VISUAL_HOURLY_TIME_SLOTS[0]
		else:
			printerr("TimeManager (get_next_academic_slot_info): VISUAL_HOURLY_TIME_SLOTS is empty!")
			return {"day": next_slot_day_str, "slot": "InvalidTime"}
			
	return {"day": next_slot_day_str, "slot": next_slot_time_str}
	
func time_slot_str_to_hour_int(time_slot_str: String) -> int:
	if not time_slot_str.is_empty() and time_slot_str.length() >= 2:
		var hour_str = time_slot_str.substr(0, 2)
		if hour_str.is_valid_int():
			return hour_str.to_int()
		else:
			if hour_str.is_valid_integer():
				return hour_str.to_int()
	printerr("TimeManager: Could not parse hour from time_slot_str: '", time_slot_str, "'")
	return -1

func _update_time_display_ui():
	if is_instance_valid(time_display_label):
		# Append term to the display
		time_display_label.text = "%s, %02d:%02d (%s)" % [
			_current_visual_day_str,
			_current_simulation_hour_int,
			_current_simulation_minute_in_hour,
			current_term_string
		]
