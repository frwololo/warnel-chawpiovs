#!/usr/bin/python

import sys
import json
import glob
import os
import re



files = glob.glob("../Sets/SetScripts_*.json")
source_file = "../Sets/SetDefinition_" + sys.argv[1]
output_file  = "./SetScripts_" + sys.argv[1]
scenario_file  = "./scenarios_" + sys.argv[1]

hardcoded_no = ["Energy","Genius", "Strength"]

primitives = [
  'Hinder ',
  'Incite ',
  'Quickstrike.',
  'Surge.',
  'Uses (',
  'Limit once per phase',
  'Limit once per round',
  '<b>When Revealed</b>',
  '<b>When Revealed (Alter-Ego)</b>',
  '<b>When Revealed (Hero)</b>',    
  '<b>When Defeated',
  'Attach to ',
  ' get +',
  ' gets +',  
  '<b>Hero Action',
  '<b>Alter-Ego Action',  
  '<b>Hero Interrupt',
  '<b>Hero Response',  
  '<b>Hero Resource',
  '<b>Resource',  
  '<b>Forced Interrupt',
  '<b>Action',
  '<b>Response',
  '<b>Interrupt',      
  '<i>(attack)</i>',
  '<i>(thwart)</i>',
  '<b>Boost</b>',
  
]


parsed_json = []
result_json = {}

sorted_json = []
cards = {}
simple_cards = {}
scenarios = {}

existing_scripts = {}

def parse_file(source_file):
    basename = os.path.basename(source_file)
    basename = basename[11:-5]
    box_name = basename
    cards[basename] = {}
    with open(source_file) as user_file:
        result = json.load(user_file);
#        print ("the result is" , result)
        for card, card_data in result.items():
            cards[basename][card] = card_data
            simple_cards[card]= card_data
            
def get_base_json(card_data):
  text = card_data.get("text", "").lower()
  type_code = card_data['type_code']
  result = { "TODO" : "" }
  for _primitive in primitives:
    primitive = _primitive.lower()
    if not primitive in text:
      continue

    location = "board"
    if type_code in ["event"]:
      location = "hand"

    
    if primitive in ['<b>hero action', '<b>alter-ego action', '<b>action']:
      if not "manual" in result:
        result["manual"] = {}
      if not location in result["manual"]:
        result["manual"][location] = []
        
    if primitive == 'limit once per phase':
      result["once_per_phase"]= {
			"__name__": "__TODO"
		}

    if primitive == 'limit once per round':
      result["once_per_round"]= {
			"__name__": "__TODO"
		}                               

    if primitive == 'hinder ':
      result["hinder"] = {
	  "__amount__": "TODO",
	  "__each_player__": True
      }

    if primitive == 'incite ':
      result["incite"] = {
	  "__amount__": "TODO",
      }

    if primitive == 'quickstrike.':
      result["quickstrike"] = {
      }

    if primitive == 'surge.':
      result["_surge"] = {
      }

    if primitive == 'uses (':
      result["uses"] = {
	  "__name__": "TODO",
	  "__amount__": "TODO"
      }       


    if primitive == '<b>when revealed</b>':
       result["reveal"] = {
	  "all": [
            {
	      "name": "TODO",
            }
	    ]
	}

    if primitive == '<b>when defeated':
       result["card_defeated"] = {
           "trigger": "self",
	  "all": [
            {
	      "name": "TODO",
            }
	    ]
	}       

    if primitive == '<b>when revealed (alter-ego)</b>':
       result["reveal_alter_ego"] = {
	  "all": [
            {
	      "name": "TODO",
            }
	    ]
	}

    if primitive == '<b>when revealed (hero)</b>':
       result["reveal_hero"] = {
	  "all": [
            {
	      "name": "TODO",
            }
	    ]
	}                                       

      
    if primitive == 'attach to ':  
      result["card_moved_to_board"] = {
	"trigger": "self",
	"board": [
	  {
	    "name": "attach_to_card",
	    "subject": "TODO"
	  }
	]
      }
      
     
    if primitive == '<b>hero action':
      result["manual"][location].append(
	  {
	    "name": "constraints",
	    "is_cost": True,
	    "tags": [
	      "hero_action"
	    ]
	  }         
      )


      
    if primitive == '<b>alter-ego action':
       result["manual"][location].append(
	  {
	    "name": "constraints",
	    "is_cost": True,
	    "tags": [
	      "alter_ego_action"
	    ]
	  }         
      )
    if primitive == '<b>action':
      result["manual"][location].append(
	  {
	    "name": "constraints",
	    "is_cost": True,
	    "tags": [
	      "action_ability"
	    ]
	  }         
      )

    if primitive == '<b>hero resource':
      result["resource"] = {location: [
	  {
	    "name": "constraints",
	    "is_cost": True,
	    "tags": [
	      "hero_resource"
	    ]
	  },
 	  {
	    "name": "add_resource",
	    "amount": 1,
	    "resource_name": "TODO"
	  }         
        ]
      }

    if primitive == '<b>resource':
      result["resource"] = {location:   [
  	  {
	    "name": "add_resource",
	    "amount": 1,
	    "resource_name": "TODO"
	  }                
        ]
      }
      
    if primitive == '<i>(attack)</i>' and "manual" in result:
      result["manual"][location].append(
	{
	  "name": "attack",
             "amount": 1,
            "subject": "target",
            "needs_subject": True,
            "filter_state_subject": [
                {"filter_group": "group_enemies"}
            ]                  
	}         
      )              
    if primitive == '<i>(thwart)</i>' and "manual" in result:
      result["manual"][location].append(
	  {
	    "name": "thwart",
            "amount": 1,
            "subject": "target",
            "needs_subject": True,
            "filter_state_subject": [
                {"filter_group": "group_schemes"}
            ]
	  }         
      )


      
    if primitive == '<b>response':
      result["response"] = {
	  "event_name": "TODO",
          "is_optional_" + location: True,          
          location: []
	}         
                    
    if primitive == '<b>interrupt':
       result["interrupt"] = {
	  "event_name": "TODO",
          "is_optional_" + location: True,
          location: []
	}


    if primitive == '<b>forced interrupt':
      result["interrupt"] = {
	  "event_name": "TODO",
          "is_optional_" + location: True,
          location: []
	}               
      

    if primitive == '<b>alter-ego response':
      result["response"] = {
	  "event_name": "TODO",
          "is_optional_" + location: True,          
          location: [
 	  {
	    "name": "constraints",
	    "is_cost": True,
	    "tags": [
	      "alter_ego_response"
	    ]
	  },                    
          ]
	}         
                    
    if primitive == '<b>alter_ego interrupt':
       result["interrupt"] = {
	  "event_name": "TODO",
          "is_optional_" + location: True,          
          location: [
 	  {
	    "name": "constraints",
	    "is_cost": True,
	    "tags": [
	      "alter_ego_interrupt"
	    ]
	  },                    
          ]
	}         
      

    if primitive == '<b>hero response':
      result["response"] = {
	  "event_name": "TODO",
           "is_optional_" + location: True,         
          location: [
 	  {
	    "name": "constraints",
	    "is_cost": True,
	    "tags": [
	      "hero_response"
	    ]
	  }                    
          ]
	}         



    if primitive == ' get +' or primitive == ' gets +':
      result["alterants"] = {
	 location: [
	   {
	     "filter_task": "get_property",
	     "filter_property_name": "TODO",
	     "filter_state_trigger": [
	       {
		 "TODO": "TODO"
	       }
	     ],
	     "alteration": 1
	   }
	 ]
       }        
      
    if primitive == '<b>hero interrupt':
       result["interrupt"] = {
	  "event_name": "TODO",
          "is_optional_" + location: True,          
          location: [
            	  {
	    "name": "constraints",
	    "is_cost": True,
	    "tags": [
	      "hero_interrupt"
	    ]
	  }         
          ]
	}                                 

    if primitive == '<b>when revealed (hero)</b>':
       result["reveal_hero"] = {
	  "all": [
            {
	      "name": "TODO",
            }
	    ]
	}                                       

       
    if primitive == '<b>boost</b>':
       result["boost"] = {
	  "all": [
            {
	      "name": "TODO",
            }
	    ]
	}



  
  return result

def stage_to_stage(stage):
    if stage =="I":
        return "1"
    if stage =="II":
        return "2"
    if stage =="III":
        return "3"
    return "1"

def add_potential_scenario(card):
    shortname = card['name']    
    type_code = card['type_code']
    code = card['code']
    code = re.sub(r"\D", "", code)    
    if type_code != "main_scheme":
        return
    stage = card.get("stage", "")
    if stage != "1A":
        return

    villain_name = "TODO"
    
    text = card.get('text', "")
    villain_modes = ["1", "2", "3"]
    match = re.search(r":(.*)\(I\)", text)
    if match:
        villain_name = (match.group(1)).strip()
    else:
        match = re.search(r":(.*)\(A1\)", text)
        if match:
            villain_name = (match.group(1)).strip()
            villain_modes = ["A1", "B1", "C1"]
    print ("found scheme " , shortname, " with villain :",  villain_name)
    scenarios[code]= {
        "code": code,
        "name": card['name'],
        "modular_default": [],
        "encounter_sets": [
            "TODO",
            "Standard",
            "Modular"
            ],
        "villains": [
            villain_name + " - " + villain_modes[0],
            villain_name + " - " + villain_modes[1],
            ],
        "expert": {
	    "encounter_sets": [
		"TODO",
		"Standard",
		"modular",
		"expert"
	    ],
	    "villains": [
		villain_name + " - "  + villain_modes[1],
		villain_name + " - " + villain_modes[2],
	    ]
        }
    }
    return
    
def get_fullname(card):
    shortname = card['name']    
    type_code = card['type_code']
    subname = card.get('subname', "")
    if type_code == "villain":
        stage = card.get("stage", "1")
        subname = stage_to_stage(stage)
    if type_code == "main_scheme":
        subname = card.get("stage", "")
        
    fullname = shortname
    if subname:
      fullname = shortname + " - " + subname

    return fullname

for my_file in files:
    print (my_file +"\n")   
    parse_file(my_file)

with open(source_file) as user_file:
  parsed_json = json.load(user_file);

linked_cards = {}
  
for card in parsed_json:
  if "linked_card" in card:
    linked_name = card["linked_card"]["name"]
    fullname = get_fullname(card["linked_card"])
    linked_cards[fullname] = card["linked_card"]
    
for card, card_data in linked_cards.items():
  parsed_json.append(card_data)
    
sorted_json = sorted(parsed_json, key=lambda x: x['name'])


for card in sorted_json:
    shortname = card['name']

    if shortname in hardcoded_no:
        continue

    add_potential_scenario(card)
    
    fullname = get_fullname(card)

    if fullname in simple_cards:
      result_json[fullname] =  simple_cards[fullname]
    else:
      result_json[fullname] = get_base_json(card)


    
with open(output_file, 'w') as f:
    json.dump(result_json, f)


sorted_scenarios = dict(sorted(scenarios.items()))
with open(scenario_file, 'w') as f:
    json.dump(sorted_scenarios, f)
