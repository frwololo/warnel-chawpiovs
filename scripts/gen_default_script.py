#!/usr/bin/python

import sys
import json

parsed_json = []
result_json = {}

sorted_json = []


source_file = sys.argv[1]
output_file  = "./SetScripts_" + source_file 

with open(source_file) as user_file:
  parsed_json = json.load(user_file);

sorted_json = sorted(parsed_json, key=lambda x: x['name'])


for card in sorted_json:
    type_code = card['type_code']
    shortname = card['name']
    subname = card.get('subname', "")
    if type_code == "villain":
      subname = "1"
    fullname = shortname
    if subname:
      fullname = shortname + " - " + subname
    result_json[fullname] = { "TODO" : "" }


    
with open(output_file, 'w') as f:
    json.dump(result_json, f)
