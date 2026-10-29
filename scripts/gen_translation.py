#!/usr/bin/python

import sys
import json
import glob
import os
import re

parsed_json = []

source_file = sys.argv[1]
output_json = {}


with open(source_file) as user_file:
  parsed_json = json.load(user_file);

f = open("output.json", "w")
  
for card in parsed_json:
    card_id = card["code"]
    print (card_id)
    fr_data = {}
    fr_data["Name"] = card["name"]
    fr_data["text"] = card.get("text", "")
    if card.get("flavor", ""):
      fr_data["flavor"] = card.get("flavor", "")
    output_json[card_id] = fr_data

json.dump(output_json, f)
f.close()
        

        
