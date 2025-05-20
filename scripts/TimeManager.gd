# TimeManager.gd
class_name TimeManager
extends Node

# --- Macro Time Signals ---
signal date_changed(day: int, month: int, year: int)
signal new_day_has_started(day: int, month: int, year: int) # Emitted by your _advance_macro_day
signal new_month_has_started(month: int, year: int)    # Emitted by your _advance_macro_day
signal new_year_started(year: int)                      # Emitted by your _advance_macro_day
signal september_enrollment_starts(year: int)           # Emitted by your _advance_macro_day

# --- General Time Control Signals ---
signal pause_state_changed(is_paused: bool)
signal speed_changed(new_speed: float)

# --- Visual Time Signals (for student AI visual loop) ---
signal visual_hour_slot_changed(day_str: String, time_slot_str: String) # Existing signal
signal visual_day_changed(day_str: String) # Existing signal

# --- NEW: Detailed Simulation Time Signal ---
signal simulation_time_updated(day_str: String, hour_int: int, minute_int: int, visual_slot_str: String)

# --- Macro Time Variables ---
@export var seconds_per_game_day: float = 5.0
var current_day: int = 20 # Example start day
var current_month: int = 8  # Example start month (August)
var current_year: int = 2025
var days_in_month: Array[int] = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
var has_triggered_september_enrollment_this_year: bool = false

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

# --- NEW: Micro Time Variables ---
var _seconds_per_simulation_minute: float = 1.0 # Calculated in _ready
var _time_accumulator_for_minute: float = 0.0
var _current_simulation_minute_in_hour: int = 0
var _current_simulation_hour_int: int = 8 # Initial hour, will be updated from slot
var _current_visual_day_str: String = "Mon" # Initial visual day string
var _current_visual_time_slot_str: String = "0500" # Initial visual time slot string

# --- Optional: UI Label for Time Display ---
@export var time_display_label_path: NodePath
var time_display_label: Label


func _ready():
	if not time_display_label_path.is_empty():
		time_display_label = get_node_or_null(time_display_label_path)
		if not is_instance_valid(time_display_label):
			printerr("TimeManager: UI Time display label not found at path: ", time_display_label_path)
	
	if seconds_per_visual_hour_slot <= 0:
		printerr("TimeManager: seconds_per_visual_hour_slot is not positive! Minute simulation will be incorrect or too fast.")
		_seconds_per_simulation_minute = 1.0 / 60.0 # Fallback to avoid division by zero, 1 real sec = 1 sim minute
	else:
		_seconds_per_simulation_minute = seconds_per_visual_hour_slot / 60.0

	current_visual_day_index = 0 # Start visual cycle on Monday
	current_visual_time_slot_index = 0 # Start at "0800"
	
	_current_visual_day_str = get_current_visual_day_string() # Update from index
	_current_visual_time_slot_str = get_current_visual_time_slot_string() # Update from index
	_update_current_simulation_hour_from_slot_str() # Set initial integer hour

	print("TimeManager Ready. Macro day: %.1fs, Visual hour slot: %.1fs, Sim Minute: %.3fs real sec" % [seconds_per_game_day, seconds_per_visual_hour_slot, _seconds_per_simulation_minute])
	
	emit_signals_for_initial_state() # Emits macro time, pause, speed
	
	# Emit initial visual and detailed time states
	emit_signal("visual_day_changed", _current_visual_day_str)
	emit_signal("visual_hour_slot_changed", _current_visual_day_str, _current_visual_time_slot_str)
	emit_signal("simulation_time_updated", _current_visual_day_str, _current_simulation_hour_int, _current_simulation_minute_in_hour, _current_visual_time_slot_str)
	_update_time_display_ui()


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
		_macro_time_accumulator -= seconds_per_game_day # Or use fposmod for precision
		_advance_macro_day()

	# --- Visual Time Advancement (for hour slots) ---
	_visual_time_accumulator += effective_delta
	if _visual_time_accumulator >= seconds_per_visual_hour_slot:
		_visual_time_accumulator -= seconds_per_visual_hour_slot # Or use fposmod
		_advance_visual_hour_slot() # This will now also handle minute reset & detailed signal

	# --- Micro Time Advancement (for minutes within the current hour slot) ---
	# TimeManager.gd - in _process(delta)

	# --- Micro Time Advancement (for minutes within the current hour slot) ---
	if _seconds_per_simulation_minute <= 0: return # Guard

	_time_accumulator_for_minute += effective_delta
	var minute_ticked_this_frame: bool = false
	while _time_accumulator_for_minute >= _seconds_per_simulation_minute:
		if _current_simulation_minute_in_hour < 59: 
			_time_accumulator_for_minute -= _seconds_per_simulation_minute
			_current_simulation_minute_in_hour += 1
			minute_ticked_this_frame = true
		elif _current_simulation_minute_in_hour == 59: 
			# If it's xx:59, let it stay 59. The next actual tick should be the hour change via _advance_visual_hour_slot.
			# This prevents minute from becoming 60 before the hour slot officially changes.
			# If _time_accumulator_for_minute still has surplus, it will be handled in the next frame or when hour advances.
			if _time_accumulator_for_minute >= _seconds_per_simulation_minute: 
				 # This means enough time has passed for MORE than one minute from 59.
				 # The hour should ideally have flipped. If not, this indicates a slight desync
				 # or very fast minute progression relative to frame delta.
				 # For safety, ensure it doesn't go past 59 here.
				pass # Stay at 59, wait for _advance_visual_hour_slot to reset to 0.
				break 
			else: # Should not happen if capped at 59
				break 

	if minute_ticked_this_frame:
		emit_signal("simulation_time_updated", _current_visual_day_str, _current_simulation_hour_int, _current_simulation_minute_in_hour, _current_visual_time_slot_str)
		_update_time_display_ui() # Update your HH:MM label


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
			has_triggered_september_enrollment_this_year = false
			emit_signal("new_year_started", current_year)
			emit_signal("new_month_has_started", current_month, current_year) # Emit again for Jan

	emit_signal("date_changed", current_day, current_month, current_year)
	emit_signal("new_day_has_started", current_day, current_month, current_year)
	
	if current_month == 9 and current_day == 1 and not has_triggered_september_enrollment_this_year:
		emit_signal("september_enrollment_starts", current_year)
		has_triggered_september_enrollment_this_year = true
		print("TimeManager: Emitted september_enrollment_starts for Year %d" % current_year)

func _advance_visual_hour_slot():
	current_visual_time_slot_index += 1
	var new_visual_day_str = get_current_visual_day_string() # Day before potential change

	if current_visual_time_slot_index >= VISUAL_HOURLY_TIME_SLOTS.size():
		# Reached end of academic day slots (e.g., after 17:00, next is effectively 18:00)
		_current_visual_time_slot_str = END_OF_ACADEMIC_DAY_SLOT
		_update_current_simulation_hour_from_slot_str() # Update hour to 18 (or whatever END_OF_DAY is)
		_current_simulation_minute_in_hour = 0 # Reset minutes for this special slot
		_time_accumulator_for_minute = 0.0
		
		emit_signal("visual_hour_slot_changed", new_visual_day_str, _current_visual_time_slot_str)
		emit_signal("simulation_time_updated", new_visual_day_str, _current_simulation_hour_int, _current_simulation_minute_in_hour, _current_visual_time_slot_str)
		_update_time_display_ui()
		
		# Now advance to the next day and reset to the first time slot
		current_visual_time_slot_index = 0 
		current_visual_day_index = (current_visual_day_index + 1) % VISUAL_DAYS_OF_WEEK.size()
		_current_visual_day_str = get_current_visual_day_string() # Get the new day string
		emit_signal("visual_day_changed", _current_visual_day_str)
	
	# Update to the current or next regular slot
	_current_visual_time_slot_str = get_current_visual_time_slot_string() # From new index
	_update_current_simulation_hour_from_slot_str() # Update hour int
	_current_simulation_minute_in_hour = 0 # Reset minutes for the new hour
	_time_accumulator_for_minute = 0.0     # Reset accumulator

	emit_signal("visual_hour_slot_changed", _current_visual_day_str, _current_visual_time_slot_str)
	emit_signal("simulation_time_updated", _current_visual_day_str, _current_simulation_hour_int, _current_simulation_minute_in_hour, _current_visual_time_slot_str)
	_update_time_display_ui()
	# print("Visual Time Advanced to: %s, %s (%02d:%02d)" % [_current_visual_day_str, _current_visual_time_slot_str, _current_simulation_hour_int, _current_simulation_minute_in_hour])

func _update_current_simulation_hour_from_slot_str():
	_current_simulation_hour_int = time_slot_str_to_hour_int(_current_visual_time_slot_str)

func _is_leap_year(year: int) -> bool:
	return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0)

# --- Public Methods for Time Control ---
func set_paused(pause_state: bool): 
	if _is_paused == pause_state: return
	_is_paused = pause_state
	emit_signal("pause_state_changed", _is_paused)
func get_is_paused() -> bool: return _is_paused
func set_speed(multiplier: float): 
	var new_speed = clampi(multiplier, 0.0, 100.0) # Assuming clampi exists, else use clamp
	if abs(_current_speed_multiplier - new_speed) < 0.01:
		if new_speed > 0.0 && _is_paused: set_paused(false)
		return
	_current_speed_multiplier = new_speed
	if _current_speed_multiplier > 0.0 and _is_paused: set_paused(false)
	elif _current_speed_multiplier == 0.0 and not _is_paused: set_paused(true)
	emit_signal("speed_changed", _current_speed_multiplier)
func get_speed_multiplier() -> float: return _current_speed_multiplier

# --- Public Methods for Macro Time Access ---
func get_current_day() -> int: return current_day
func get_current_month() -> int: return current_month
func get_current_year() -> int: return current_year

# --- Public Methods for Visual/Simulation Time Access ---
func get_current_visual_day_string() -> String:
	if current_visual_day_index >= 0 and current_visual_day_index < VISUAL_DAYS_OF_WEEK.size():
		return VISUAL_DAYS_OF_WEEK[current_visual_day_index]
	printerr("TimeManager: Invalid current_visual_day_index: ", current_visual_day_index)
	return "InvalidDay"

func get_current_visual_time_slot_string() -> String:
	if current_visual_time_slot_index >= 0 and current_visual_time_slot_index < VISUAL_HOURLY_TIME_SLOTS.size():
		return VISUAL_HOURLY_TIME_SLOTS[current_visual_time_slot_index]
	if current_visual_time_slot_index == VISUAL_HOURLY_TIME_SLOTS.size(): # End of day case before reset
		return END_OF_ACADEMIC_DAY_SLOT
	printerr("TimeManager: Invalid current_visual_time_slot_index: ", current_visual_time_slot_index)
	return "InvalidTime"

func get_current_simulation_hour_int() -> int:
	return _current_simulation_hour_int

func get_current_simulation_minute() -> int:
	return _current_simulation_minute_in_hour

func get_visual_hourly_time_slots_list() -> Array[String]:
	return VISUAL_HOURLY_TIME_SLOTS

# Add this function to your TimeManager.gd script

# Helper function to get the next actual academic slot and its day
# Assumes VISUAL_HOURLY_TIME_SLOTS[0] is the start of the academic day (e.g., "0800")
# Assumes _current_visual_day_str and current_visual_time_slot_index are correctly maintained
func get_next_academic_slot_info() -> Dictionary:
	# Returns {"day": String, "slot": String}
	var next_slot_day_str: String = _current_visual_day_str 
	var next_slot_time_str: String = ""
	
	# Ensure current_visual_time_slot_index is valid
	if current_visual_time_slot_index < -1 or current_visual_time_slot_index > VISUAL_HOURLY_TIME_SLOTS.size():
		printerr("TimeManager (get_next_academic_slot_info): Invalid current_visual_time_slot_index: ", current_visual_time_slot_index)
		return {"day": _current_visual_day_str, "slot": "InvalidTime"} # Return current day, invalid time

	var next_slot_idx = current_visual_time_slot_index + 1

	if next_slot_idx < VISUAL_HOURLY_TIME_SLOTS.size():
		# Next slot is on the same day
		next_slot_time_str = VISUAL_HOURLY_TIME_SLOTS[next_slot_idx]
	else: 
		# Current slot is the last one of the academic day (e.g., 17:00), or it's END_OF_ACADEMIC_DAY_SLOT
		# So, the next academic slot is the first slot of the next visual day.
		var next_day_idx = (current_visual_day_index + 1) % VISUAL_DAYS_OF_WEEK.size()
		next_slot_day_str = VISUAL_DAYS_OF_WEEK[next_day_idx]
		if not VISUAL_HOURLY_TIME_SLOTS.is_empty():
			next_slot_time_str = VISUAL_HOURLY_TIME_SLOTS[0] # First slot of next day (e.g., "0800")
		else:
			printerr("TimeManager (get_next_academic_slot_info): VISUAL_HOURLY_TIME_SLOTS is empty!")
			return {"day": next_slot_day_str, "slot": "InvalidTime"}
			
	return {"day": next_slot_day_str, "slot": next_slot_time_str}
	
# --- Helper to convert "HHMM" string to int hour ---
func time_slot_str_to_hour_int(time_slot_str: String) -> int:
	if not time_slot_str.is_empty() and time_slot_str.length() >= 2: # e.g., "0800" or "1800"
		var hour_str = time_slot_str.substr(0, 2)
		if hour_str.is_valid_int(): # Use is_valid_int for Godot 3.x
			return hour_str.to_int()
		else: # Try is_valid_integer for Godot 4.x if the above fails
			if hour_str.is_valid_integer():
				return hour_str.to_int()
	printerr("TimeManager: Could not parse hour from time_slot_str: '", time_slot_str, "'")
	return -1 # Indicate error

# --- UI Update Function ---
func _update_time_display_ui():
	if is_instance_valid(time_display_label):
		time_display_label.text = "%s, %02d:%02d" % [_current_visual_day_str, _current_simulation_hour_int, _current_simulation_minute_in_hour]
