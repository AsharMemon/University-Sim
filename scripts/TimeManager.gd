# TimeManager.gd
# Manages game time, speed, and date progression.
class_name TimeManager
extends Node

signal date_changed(day, month, year) # Emitted when any part of the date changes
signal pause_state_changed(is_paused)
signal speed_changed(new_speed_multiplier)
signal new_year_started(year)
signal new_day_has_started(day, month, year) # Explicit signal for a new day

# --- Exported Variables ---
@export var student_manager: Node # Assign your StudentManager node here

# --- Time and Date Variables ---
var current_day: int = 1
var current_month: int = 1
var current_year: int = 2025

const DAYS_IN_MONTH = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

var time_accumulator: float = 0.0
@export var seconds_per_game_day: float = 5.0 # Adjust for testing; 1-2s makes days pass quickly

var game_speed_multiplier: float = 1.0
var is_paused: bool = false

func _ready():
	print_debug("TimeManager Ready. Seconds per game day: " + str(seconds_per_game_day))
	if not is_instance_valid(student_manager):
		printerr("TimeManager: StudentManager node not assigned in the Inspector!")


func set_paused(pause: bool):
	if is_paused == pause: return
	is_paused = pause
	# print_debug("Game Paused" if is_paused else "Game Resumed at speed " + str(game_speed_multiplier) + "x")
	pause_state_changed.emit(is_paused)

func toggle_pause(): set_paused(not is_paused)

func set_speed(multiplier: float):
	var new_speed = clampf(multiplier, 0.0, 10.0)
	if game_speed_multiplier == new_speed and not (is_paused and new_speed > 0): return

	game_speed_multiplier = new_speed
	if game_speed_multiplier == 0.0:
		if not is_paused: set_paused(true)
	else:
		if is_paused: set_paused(false)
	
	# print_debug("Game speed set to " + str(game_speed_multiplier) + "x")
	speed_changed.emit(game_speed_multiplier)

func get_current_date_string() -> String: return "Day: %d, Month: %d, Year: %d" % [current_day, current_month, current_year]
func get_current_day() -> int: return current_day
func get_current_month() -> int: return current_month
func get_current_year() -> int: return current_year
func get_is_paused() -> bool: return is_paused
func get_speed_multiplier() -> float: return game_speed_multiplier if not is_paused else 0.0


func _process(delta: float):
	if is_paused or game_speed_multiplier == 0.0: return

	time_accumulator += delta * game_speed_multiplier

	if time_accumulator >= seconds_per_game_day:
		time_accumulator = fmod(time_accumulator, seconds_per_game_day)
		advance_day()

func advance_day():
	current_day += 1
	
	var days_in_current_month = DAYS_IN_MONTH[current_month]
	if current_month == 2 and is_leap_year(current_year):
		days_in_current_month = 29
		
	if current_day > days_in_current_month:
		current_day = 1
		advance_month() 
	
	date_changed.emit(current_day, current_month, current_year)
	new_day_has_started.emit(current_day, current_month, current_year) # EMIT DAILY SIGNAL
	# print_debug("Advanced to Day: " + str(current_day))


func advance_month():
	current_month += 1
	if current_month > 12:
		current_month = 1
		advance_year()

func advance_year():
	current_year += 1
	# print_debug("Year advanced to: " + str(current_year)) # Already in BuildingManager
	new_year_started.emit(current_year)
	# The BuildingManager's _on_time_manager_new_year_started handles yearly financial updates
	# and *also* calls student_manager.update_all_students_daily_activities().
	# This means academic progress and needs decay will happen at least yearly.
	# The new_day_has_started signal ensures needs decay daily if TimeManager is set up for faster days.


func is_leap_year(year: int) -> bool:
	return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0)

func print_debug(message):
	print("[TimeManager]: ", message)
