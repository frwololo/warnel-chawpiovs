class_name GameRecorder
extends Reference

enum ACTIONS {
	PLAY
	ACTIVATE
	SELECT
	TARGET
	CHOOSE
	NEXT_PHASE
	PASS
	WAIT
}

const actions_to_string = [
	"play",
	"activate",
	"select",
	"target",
	"choose",
	"next_phase",
	"pass",
	"other"
]

const tmp_filename:= "user://recorded_gameplay_tmp.txt"
const filename:= "user://recorded_gameplay.txt"

static func init_game():
	INIT_LOG()
	var data = {
		"init": gameData.save_gamedata()
	}
	var buffer = JSON.print(data, '\t')
	buffer = buffer.substr(0, buffer.length()-1)
	buffer+= ",\n \"actions\": [\n"
	log_string(buffer)
	
static func finalize_game():
	var file = File.new()
	if (!file.file_exists(tmp_filename)):
		#this means we already closed
		return	
		
	var data = {
		"end": gameData.save_gamedata()
	}
	var buffer = JSON.print(data, '\t')
	buffer = "\n]," + buffer.substr(1)
	log_string(buffer)
	var dir = Directory.new()
	dir.rename(tmp_filename, filename)	

static func add_entry(action, values, comments = ""):
	var data = {
		"type": actions_to_string[action],
		"value" : values
	}
	if comments:
		data["_comments"] = comments
		
	var buffer = JSON.print(data, '\t')
	buffer+= ","				
	log_string(buffer)
	
static func log_json(data):
	var file = File.new()

	if (!file.file_exists(tmp_filename)):
		#this means we didn't initialize
		return		
	
	file.open(tmp_filename, File.READ_WRITE)
	file.seek_end()
	file.store_string(JSON.print(data, '\t'))
	file.close()	

static func log_string(buffer):
	var file = File.new()

	if (!file.file_exists(tmp_filename)):
		#this means we didn't initialize
		return	
	
	file.open(tmp_filename, File.READ_WRITE)
	file.seek_end()
	file.store_string(buffer)
	file.close()	
	
	
static func INIT_LOG():
	var file = File.new()
	file.open(tmp_filename, File.WRITE)
	file.close() 		
