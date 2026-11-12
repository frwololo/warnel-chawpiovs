# Runs the single player test suite in several game instances at once,
# each instance taking a slice of the tests.
#
# Command line options (also usable from the editor through
# Project Settings > Editor > Main Run Args):
#   --run-tests[=filters]  start the test suite as soon as the main menu is
#                          loaded. Filters are comma separated, same words as
#                          the Options menu (default: sanity).
#                          e.g. --run-tests=sanity  --run-tests=all,-scenario
#   --test-shards=N        coordinator: start N-1 more instances (workers),
#                          run slice 0, then merge every slice's results
#                          into the usual test_results_1.txt
#   --test-shard=i/N       worker (started by the coordinator): run only
#                          slice i of N, write the results, quit.
#                          Can also be used by hand, without a coordinator.
#   --test-hide-workers    coordinator: start workers without a window and
#                          without rendering (--no-window --no-render)
#   --no-render            don't render (game logic still runs)
#   --test-quit-when-done  quit once the results are written
#
# Test i (in the order of the test list) belongs to slice i % N.
#
# All instances share the same user:// folder: workers write their own
# log/results files (suffix _shard<i>) and never write caches or settings.
# The coordinator writes a heartbeat file every second; workers quit if it
# stops (coordinator closed or killed, e.g. with the editor's Stop button).
extends Node

const SHARD_DIR := "user://test_shards/"
const COORDINATOR_HEARTBEAT := SHARD_DIR + "coordinator_alive.txt"
#a worker quits if the coordinator heartbeat is older than this (seconds)
const COORDINATOR_TIMEOUT := 15
#the coordinator gives up on a worker whose heartbeat is older than this
const WORKER_TIMEOUT := 60

var run_tests := false
var filters := ["sanity"]
var shard_index := 0
var shard_count := 1
#number of slices requested with --test-shards (coordinator only)
var parallel := 1
var quit_when_done := false
var no_render := false
var hide_workers := false
#worker started by a coordinator (watches its heartbeat)
var coordinated := false

var autostart_done := false
var _worker_pids := {}
var _workers_started_at := 0
var _heartbeat_timer := 0.0
var _started_at := 0

func _init():
	parse(OS.get_cmdline_args())
	_started_at = OS.get_unix_time()

func parse(args) -> void:
	for arg in args:
		arg = str(arg)
		if arg.begins_with("--run-tests"):
			run_tests = true
			if "=" in arg:
				var new_filters := []
				for f in arg.split("=", true, 1)[1].split(","):
					f = f.strip_edges().to_lower()
					if f:
						new_filters.append(f)
				if new_filters:
					filters = new_filters
		elif arg.begins_with("--test-shards="):
			parallel = int(max(1, int(arg.split("=", true, 1)[1])))
			run_tests = true
		elif arg.begins_with("--test-shard="):
			var parts = arg.split("=", true, 1)[1].split("/")
			if parts.size() == 2 and int(parts[1]) > 0:
				shard_count = int(parts[1])
				shard_index = int(clamp(int(parts[0]), 0, shard_count - 1))
			run_tests = true
		elif arg == "--test-quit-when-done":
			quit_when_done = true
		elif arg == "--no-render":
			no_render = true
		elif arg == "--test-hide-workers":
			hide_workers = true
		elif arg == "--test-coordinated":
			coordinated = true
	if parallel > 1:
		shard_index = 0
		shard_count = parallel

#instances used by the main menu's Tests button: half the CPU threads,
#at most 4 (the run was measured at 4)
func default_instance_count() -> int:
	return int(clamp(OS.get_processor_count() / 2, 1, 4))

#makes this instance the coordinator of a parallel run, as --test-shards=N
#would (main menu's Tests button). Call start_workers() next
func setup_parallel_run(count: int, test_filters: Array) -> void:
	if is_worker():
		return
	run_tests = true
	filters = test_filters
	parallel = int(max(1, count))
	shard_index = 0
	shard_count = parallel

#parallel run: tile the instances' windows on the current screen, 2x2,
#each a quarter of the screen (960x540 on a 1920x1080 screen):
#slice 0 (main instance) top left, 1 top right, 2 bottom left,
#3 bottom right. More than 4 instances wrap around
func apply_window_layout() -> void:
	if !is_sharded():
		return
	var screen = OS.current_screen
	var origin = OS.get_screen_position(screen)
	var cell = OS.get_screen_size(screen) / 2
	var slot = shard_index % 4
	OS.window_fullscreen = false
	OS.window_maximized = false
	OS.window_size = cell
	# warning-ignore:integer_division
	OS.window_position = origin + Vector2((slot % 2) * cell.x, (slot / 2) * cell.y)

#true for an instance started by the coordinator (or by hand) for slice >= 1
func is_worker() -> bool:
	return shard_count > 1 and shard_index > 0 and parallel == 1

#true for the instance that starts the workers and merges the results
func is_coordinator() -> bool:
	return parallel > 1

func is_sharded() -> bool:
	return shard_count > 1

#added to the name of files written to user:// by workers
func file_suffix() -> String:
	if is_worker():
		return "_shard" + str(shard_index)
	return ""

#index = position of the test in the test list
func keeps_test(index: int) -> bool:
	if !is_sharded():
		return true
	return index % shard_count == shard_index

func _ready():
	if no_render:
		VisualServer.render_loop_enabled = false
		OS.vsync_enabled = false
	if is_worker():
		var master_bus = AudioServer.get_bus_index("Master")
		if master_bus >= 0:
			AudioServer.set_bus_mute(master_bus, true)

func _process(delta: float):
	if !is_sharded():
		return
	_heartbeat_timer += delta
	if _heartbeat_timer < 1.0:
		return
	_heartbeat_timer = 0.0
	if is_coordinator():
		if _workers_started_at:
			_write_timestamp(COORDINATOR_HEARTBEAT)
	elif is_worker() and coordinated:
		_write_timestamp(_worker_heartbeat_file(shard_index))
		var age = _timestamp_age(COORDINATOR_HEARTBEAT)
		#no heartbeat at all: grace period while the coordinator starts
		if age < 0:
			age = OS.get_unix_time() - _started_at
		if age > COORDINATOR_TIMEOUT:
			print("test worker " + str(shard_index) + ": coordinator gone, quitting")
			get_tree().quit()

func _notification(what):
	#coordinator closing: don't leave workers running
	if what == NOTIFICATION_WM_QUIT_REQUEST or what == NOTIFICATION_PREDELETE:
		kill_workers()

###
### Coordinator
###

func start_workers() -> void:
	if !is_coordinator() or _workers_started_at:
		return
	_clean_shard_dir()
	_workers_started_at = OS.get_unix_time()
	_write_timestamp(COORDINATOR_HEARTBEAT)

	var exe = OS.get_executable_path()
	for i in range(1, shard_count):
		var args := []
		#run from the editor: the executable is the Godot editor binary,
		#it needs the project path or it opens the project manager
		if !OS.has_feature("standalone"):
			args += ["--path", ProjectSettings.globalize_path("res://")]
		args.append("--run-tests=" + PoolStringArray(filters).join(","))
		args.append("--test-shard=" + str(i) + "/" + str(shard_count))
		args.append("--test-coordinated")
		if hide_workers:
			args += ["--no-window", "--no-render"]
		elif no_render:
			args.append("--no-render")
		var pid = OS.execute(exe, PoolStringArray(args), false)
		print("started test worker " + str(i) + "/" + str(shard_count) + " pid " + str(pid))
		_worker_pids[i] = pid

func kill_workers() -> void:
	for i in _worker_pids:
		var pid = _worker_pids[i]
		if pid > 0 and !File.new().file_exists(_result_file(i)):
			# warning-ignore:return_value_discarded
			OS.kill(pid)
	_worker_pids = {}

#Coroutine: waits until every worker wrote its results or stopped
#responding. Returns {slice index: results dictionary, or null}
func wait_for_workers() -> Dictionary:
	yield(get_tree(), "idle_frame")
	var results := {}
	while true:
		var pending := false
		for i in range(1, shard_count):
			if results.has(i):
				continue
			var file = File.new()
			if file.file_exists(_result_file(i)):
				results[i] = _read_json(_result_file(i))
				continue
			var age = _timestamp_age(_worker_heartbeat_file(i))
			if age < 0:
				age = OS.get_unix_time() - _workers_started_at
			if age > WORKER_TIMEOUT:
				results[i] = null
				continue
			pending = true
		if !pending:
			break
		yield(get_tree().create_timer(0.5), "timeout")
	_worker_pids = {}
	#allows another parallel run in the same session (Tests button)
	_workers_started_at = 0
	return results

###
### Worker
###

func write_results(data: Dictionary) -> void:
	_ensure_shard_dir()
	var tmp = SHARD_DIR + "result_" + str(shard_index) + ".tmp"
	var file = File.new()
	file.open(tmp, File.WRITE)
	file.store_string(to_json(data))
	file.close()
	#rename once complete, so the coordinator never reads a partial file
	var dir = Directory.new()
	# warning-ignore:return_value_discarded
	dir.remove(_result_file(shard_index))
	# warning-ignore:return_value_discarded
	dir.rename(tmp, _result_file(shard_index))

###
### Helpers
###

func _result_file(i: int) -> String:
	return SHARD_DIR + "result_" + str(i) + ".json"

func _worker_heartbeat_file(i: int) -> String:
	return SHARD_DIR + "worker_" + str(i) + "_alive.txt"

func _ensure_shard_dir():
	var dir = Directory.new()
	if !dir.dir_exists(SHARD_DIR):
		# warning-ignore:return_value_discarded
		dir.make_dir_recursive(SHARD_DIR)

func _clean_shard_dir():
	_ensure_shard_dir()
	var dir = Directory.new()
	if dir.open(SHARD_DIR) != OK:
		return
	# warning-ignore:return_value_discarded
	dir.list_dir_begin(true, true)
	var file_name = dir.get_next()
	while file_name != "":
		if !dir.current_is_dir():
			# warning-ignore:return_value_discarded
			dir.remove(SHARD_DIR + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

func _write_timestamp(path: String):
	_ensure_shard_dir()
	var file = File.new()
	if file.open(path, File.WRITE) == OK:
		file.store_string(str(OS.get_unix_time()))
		file.close()

#seconds since the timestamp in that file was written, -1 if no file
func _timestamp_age(path: String) -> int:
	var file = File.new()
	if !file.file_exists(path):
		return -1
	if file.open(path, File.READ) != OK:
		return -1
	var content = file.get_as_text()
	file.close()
	if !content.is_valid_integer():
		#being written right now
		return 0
	return OS.get_unix_time() - int(content)

func _read_json(path: String):
	var file = File.new()
	if file.open(path, File.READ) != OK:
		return null
	var content = file.get_as_text()
	file.close()
	var parsed = JSON.parse(content)
	if parsed.error != OK:
		return null
	return parsed.result
