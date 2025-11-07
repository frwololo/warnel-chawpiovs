#!/usr/bin/python

import sys
import os
import json
import glob
import collections

# Find all `.jpg` files in a specific directory
files = glob.glob("./project/wc/Sets/SetScripts_*.json")
print(files)


definition_files = glob.glob("./sets/SetDefinition_*.json")

events = {}
cards = {}
metadata = {}
abilities = {}

ability_comments = {
    "add_resource": "adds resources based on specific computations",
    "add_script": "adds a script to a target card",
    "attach_to_card": "attach script owner to subject",
    "attack": "starts an attack event from you/the card owning the script to [subjects]",
    "change_controller_hero": "change controller hero",
    "change_form": "change hero form",
    "constraints": "an ability that does nothing but is used as a cost to constraint when a card/ability can be used. Typically, Hero vs Alter Ego form, etc...",
    "count_tokens": "count number of tokens of a specific type",
    "deal_damage": "deal damage to [subject]. also see receive_damage",
    "deal_encounter": "deal an encounter to current hero",
    "draw_cards": "the owner of [subject]cards draws cards",
    "exhaust_card": "exhausts [subject] cards. See ready_card",
    "heal": "heal [subjects]. Can be used as a cost, in which case the heal must happen at least partially for the cost to be considered paid",
    "mod_counter": "modify a general counter on the app",
    "mod_tokens": "modify tokens on the card. See Damage, threat, stunned, confused, etc...",
    "modify_properties": "modify specific properties of the card (also see alterants)",
    "move_card_to_board": "move [subjects] cards to the boards, sometimes specifying a grid location",
    "move_card_to_container": "move [subject] cards to a specific container (aka pile)",
    "move_to_player_zone": "move [subject]cards to a specific hero board",
    "nop": "does nothing, but used for example to ensure some conditioi is met, as a cost",
    "pay_cost": "pay a specific cost (not necessarily the card's cost",
    "pay_regular_cost": "trigger to initiate the card's cost payment",
    "prevent": "prevents damage (also see replacement_effect)",
    "ready_card": "ready a specific card (also see exhaust)",
    "receive_damage": "also see deal_damage",
    "remove_threat": "removes threat from [subject] schemes. Also see thwart.",
    "replacement_effect": "replaces some task on the stack with something else (e.g. damage replaced, targets, replaced, etc...)",
    "reveal_nemesis": "Reveals the current hero's nemesis",
    "scheme": "The Villain schemes",
    "surge": "triggers an encounter surge",
    "temporary_effect": "adds a temporary effect on a card, which stays until a specific event is triggered (typically for event cards that grant a benefit -alterant- until end of round or phase)",
    "thwart": "either removes a given amount of threat, or starts a thwart action from a character. Also see remove_threat",
    "villain_and_enemies_attack_you": "Triggers an attack of the Villain and enemies engaged with current hero",
    "villain_attacks_you": "Triggers an attack of the villain against current hero",    
}

#don't display these in the links
event_exceptions = ["manual", "reveal"]
ability_exceptions = []

output_file  = "./script_doc.html"
images_url = "https://marvelcdb.com/bundles/cards/"

def parse_definition_file(source_file):
    basename = os.path.basename(source_file)
    basename = basename[14:-5]
    metadata[basename] = {}
    with open(source_file) as user_file:
        result = json.load(user_file);
#        print ("the result is" , result)
        for card_data in result:
            card_name = card_data["name"]
            metadata[basename][card_name] = {}
            metadata[basename][card_name]["img"] = card_data["code"] + ".png"

def get_ability_params(card_data, ability):
    result = {}
    if type(card_data) is dict:
        if "name" in card_data and card_data["name"] == ability:
            for key,value in card_data.items():
                if key == "name":
                    continue
                else:
                    result[key] = True
                    other_params = get_ability_params(value, ability)
                    if other_params:
                        for i in other_params:
                            result[i] = True
        else:
            for key,value in card_data.items():
                other_params = get_ability_params(value, ability)
                if other_params:
                    for i in other_params:
                        result[i] = True
    elif type(card_data) is list:
        for item in card_data:
            other_params = get_ability_params(item, ability)
            if other_params:
                for i in other_params:
                    result[i] = True
#    if result:
#        print (result)                
    return result

            
def get_abilities(card_data):
    result = []
    if type(card_data) is dict:        
        for key,value in card_data.items():
            if key == "name":
                result.append(value)
            else:
                other_abilities = get_abilities(value)
                if other_abilities:
                    for ab in other_abilities:
                        if ab not in result:
                            result.append(ab)
    elif type(card_data) is list:
        for item in card_data:
            other_abilities = get_abilities(item)
            if other_abilities:
                for ab in other_abilities:
                    if ab not in result:
                        result.append(ab)
    return result

            
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
            for trigger, trigger_data in card_data.items():
                if trigger not in events:
                    events[trigger] = {}
                events[trigger][card] = trigger_data
                card_abilities = get_abilities(trigger_data)
                if card_abilities:
                    for ability in card_abilities:
                        if ability not in abilities:
                            abilities[ability] = {
                                "cards": {},
                                "params": get_ability_params(result, ability)
                            }
                        ability_data = abilities[ability]["cards"]
                        if box_name not in ability_data:
                            ability_data[box_name] = []
                        if card not in ability_data[box_name]:
                            ability_data[box_name].append(card)


def abilities_nav_html():
    result = "<h2>ABILITIES</h2>\n"
    for ability in sorted(abilities):
        if ability in ability_exceptions:
            continue
        result += '    <a href="#' + ability +  '\">' + ability  + "</a>\n"
    return result


def abilities_html():
    result = "<h2>ABILITIES</h2>\n"
    for ability in sorted(abilities):
        if ability in ability_exceptions:
            continue
        result += '<section id="' + ability + '"><h3>' + ability  + "</h3>\n"
        if ability in ability_comments:
            result+= "<p>" + ability_comments[ability] + "</p>\n"
        ability_data = abilities[ability]["cards"]
        ability_params = abilities[ability]["params"]
        result+= '<p><strong>params:</strong><br /><ul class="slight_right">' +"\n"                             
        for param in ability_params:
            result+= "<li>" + param + "</li>\n"
        result+="</ul></p>\n"
        all_cards = []
        result+= '<p><strong>cards</strong><br /><ul class="slight_right">' +"\n"                                    
        for box_name in ability_data:
            box_data = ability_data[box_name]
            for card in box_data:
                all_cards.append(card)
        for card in all_cards:
            result += '    <li><a href="#' + card + '">' + card + "</a></li>\n"
        result += "</ul></p></section>\n"       
    return result

                        
def events_nav_html():
    result = "<h2>EVENTS</h2>\n"
    for trigger in sorted(events):
        if trigger in event_exceptions:
            continue
        result += '    <a href="#' + trigger +  '\">' + trigger  + "</a>\n"
    return result

def events_html():
    result = "<h2>EVENTS</h2>\n"
    for trigger in sorted(events):
        if trigger in event_exceptions:
            continue       
        trigger_cards = events[trigger]
        result += '<section id="' + trigger + '"><h3>' + trigger  + "</h3>\n"       
        for card in sorted(trigger_cards):
            card_data = trigger_cards[card]
            result += '    <li><a href="#' + card + '">' + card + "</a></li>\n"
        result += "</section>\n"
    return result       


def cards_nav_html():
    result = "<h2>CARDS</h2>\n"
    for box_name, cards_data in cards.items():
        result += "<h3>" + box_name + "</h3>\n"
        for card in sorted(cards_data):
            card_data = cards_data[card]
            result += "    <a href=\"#" + card +  "\">" + card  + "</a>\n"
    return result


def cards_html():
    result = "<H2>CARDS</H2>"
    for box_name, cards_data in cards.items():
        result += "<h3>" + box_name + "</h3>\n"
        for card in sorted(cards_data):
            card_data = cards_data[card]
            result += "<section id=\"" + card + "\"><h2>" + card  + "</h2>\n"
            if box_name in metadata:
                box_meta = metadata[box_name]
                if card in box_meta:
                    card_meta = box_meta[card]
                    result+= '<img src="' + images_url + card_meta["img"] + '" class="resize"/>' + "\n"
            card_code = json.dumps(card_data, indent = 2)
            for ability in ability_comments:
                card_code = card_code.replace(ability, '<a href="#' + ability +'">' + ability + "</a>")
            result += "    <pre>" + card_code + "</pre>\n"
            result += "</section>\n"
    return result
                
def header_html():
    result = """<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>WC - Documentation</title>
  <link rel="stylesheet" href="styles.css" />
</head>
<body>
"""
    return result
    
def footer_html():
    result = """
</body>
</html>
"""
    return result

def all_html():
    result = ""
    result+= header_html()
    result +="<nav>\n"
    result+= abilities_nav_html()    
    result+= events_nav_html()
    result+= cards_nav_html()
    result+="</nav><main>\n"
    result+= abilities_html()        
    result+= events_html()
    result+= cards_html()
    result+="</main>\n"
    result+=footer_html()

    return result

#main loop    
for my_file in files:
    parse_file(my_file)

for my_file in definition_files:
    parse_definition_file(my_file)

html = all_html()
    
with open(output_file, 'w') as f:
    f.write(html)
