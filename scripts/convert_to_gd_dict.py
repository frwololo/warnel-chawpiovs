#!/usr/bin/python

import sys
import json

parsed_json = []
result_json = []

source_file = sys.argv[1]
output_file  = "/cygdrive/c/Users/wololo/AppData/Roaming/Godot/app_userdata/WC/Sets/SetDefinition_" + source_file 

def capitalize(x):
    return x.capitalize()

def splitToArray(x):
    array = x.split()
    result = []
    for value in array:
        result.append(value.replace(".", ""))
    return result

conversion = {
    "type_code" : ["Type", capitalize],
    "traits" : ["Tags", splitToArray],
    }

name_conversion = {
    "name" : "Name",
    "code" : "_code",
    "attack" : "Power",
    "health" : "Health",
    "cost"   : "Cost",
    "pack_code"   : "_set",
    }


with open(source_file) as user_file:
  parsed_json = json.load(user_file);

for card in parsed_json:
    converted_card = {
        "Requirements": "",
        "Abilities": "",
    }

    for key in card:
        converted_card[key] = card[key]

    for key in name_conversion.keys():
        if key in card :
            new_key = name_conversion[key] 
            converted_card[new_key] = card[key]

    for key in conversion.keys():
        if key in card :
            new_key = conversion[key][0]
            method = conversion[key][1]
            converted_card[new_key] = method(card[key])        


    #finalize                    
    result_json.append(converted_card)

    
with open(output_file, 'w') as f:
    json.dump(result_json, f)
