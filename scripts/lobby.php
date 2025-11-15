<?php

// log?  true/false
define('ENABLE_LOGS',true);
define('ROOM_LIFETIME', 1200);

// log file name
define('LOG_FILE','/home/wololo/wc_register.log');
define('ROOM_FOLDER','/home/wololo/www/wc/rooms/');


$colors = [
  "blue", "red", "yellow", "green", "purple", "gold", "orange", "black", "brown"
];

$nouns = [
  "horse", "fish", "cat", "mouse", "lizard", "rabbit", "elephant", "dog", "capybara"
];


$defaults = [
    'mode' => "list_rooms",
    'room_name' => "",
    'password' => ""
];

// Merge defaults with actual GET values
$params = array_merge($defaults, $_GET);

// Nullbyte hack fix
if (strpos($_params['mode'], "\0") !== FALSE) die('');
if (strpos($_params['password'], "\0") !== FALSE) die('');
if (strpos($_params['room_name'], "\0") !== FALSE) die('');



$mode = $params['mode'];

//sanitize room name
$room_name = $params['room_name'];
$room_name = strtolower($room_name);
$room_name = preg_replace('/[^a-z0-9-]/', '', $room_name);

//sanitize password
$password = $params['password'];
$password = strtolower($password);
$password = preg_replace('/[^a-z0-9-]/', '', $password);

function getClientIP() {
	 $my_ip = 0;
	 if (!empty($_SERVER['HTTP_CLIENT_IP'])) {
	    $my_ip = $_SERVER['HTTP_CLIENT_IP']; // Shared internet
	 } elseif (!empty($_SERVER['HTTP_X_FORWARDED_FOR'])) {
	   $my_ip = $_SERVER['HTTP_X_FORWARDED_FOR']; // Proxy
	 } else {
	   $my_ip = $_SERVER['REMOTE_ADDR']; // Direct connection
	 }
	 return strval($my_ip);
}

$ip = getClientIp();

function empty_room_info(){
  $my_result = array(
    "ip" => "",
    "room_name" => "",
    "password" => "",
    "error" => "",
  );
  return $my_result;
}

function random_room_name(){
  global $colors, $nouns;
  $rand1 = $colors[array_rand($colors)];
  $rand2 = $nouns[array_rand($nouns)];
  $rand3 = strval(rand(1, 99));
  
  $random_name = $rand1 . "-" . $rand2 . "-" . $rand3;
  return $random_name;
}

function create_room(){
  global $room_name, $password, $ip;
  $result = empty_room_info();


  //if this ip already has a room we just update it
  //to avoid one ip creating multiple rooms (which wouldn't work properly)
  $existing_room = find_room_by_ip();
  if ($existing_room) {
    $room_name = $existing_room["room_name"];
    $result = $existing_room;
  } else {
    if (!$room_name){
      $room_name = random_room_name();
    }
    $filename = ROOM_FOLDER . $room_name;
    if (file_exists($filename)) {
       $result["error"] = "This room exists";
       return json_encode($result);
    }
  }

  $result["ip"] = $ip;
  $result["room_name"] = $room_name;
  $result["password"] = $password;
  
  $to_write = json_encode($result);
  $filename = ROOM_FOLDER . $room_name;  
  file_put_contents($filename, $to_write);
  return $to_write;
}

function find_room_by_ip(){
   global $ip;
   $result = [];
   $files =  scandir(ROOM_FOLDER);
   foreach ($files as $file) {
     if (!str_starts_with($file,".")){
       $filename = ROOM_FOLDER . $file;
       if( (filectime($filename) + ROOM_LIFETIME) < time()){
           unlink($filename);
       }else{
           $json_data = file_get_contents($filename);
	   $dict = json_decode($json_data, true);
           if (array_key_exists("ip", $dict)) {
  	     if (strcasecmp($ip, $dict["ip"]) === 0) {
	         return $dict;
	     }
          }
       }
     }
   }
   return null;
}

function scan_dir($dir) {
    $files = array();    
    foreach (scandir($dir) as $file) {
        if (str_starts_with($file,"."))continue;    
        $files[$file] = filemtime($dir . $file);
    }

    arsort($files);
    $files = array_keys($files);

    return $files;
}

function list_rooms(){
   $result = [];
   $files =  scan_dir(ROOM_FOLDER);
   foreach ($files as $file) {
     if (!str_starts_with($file,".")){
       $filename = ROOM_FOLDER . $file;
       if( (filectime($filename) + ROOM_LIFETIME) < time()){
           unlink($filename);
       }else{
           $json_data = file_get_contents($filename);
	   $dict = json_decode($json_data, true);
           if (array_key_exists("room_name", $dict)) {
  	     if ($dict["password"]){
	         $dict["password"] = "yes";
	     }
	     $dict["ip"] = "";
	     $result[] = $dict;
          }
       }
     }
   }
   return json_encode($result);
}


function join_room(){
  global $room_name, $password;
  
  $result = empty_room_info();

  if (!$room_name){
    $result["error"] = "please give me a room_name";
    return json_encode($result);
  }
  $filename = ROOM_FOLDER . $room_name;
  $data = file_get_contents($filename);
  if (!$data) {
     $result["error"] = "No room with this name";
     return json_encode($result);
  }
  $dict = json_decode($data, true);
  if ($dict["password"]) {
      if (strcasecmp($password, $dict["password"]) !== 0) {
           $result["error"] = "password incorrect";
           return json_encode($result);
      }
  }
  $dict["password"] = "";
  return json_encode($dict);

}

if ($mode == "create_room") {
   $data = create_room();
} elseif ($mode =="join_room") {
   $data = join_room();
} else { //list rooms
  $data = list_rooms();
}

echo $data;

