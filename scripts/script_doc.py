#!/usr/bin/python

import sys
import os
import json
import glob
import collections

# Find all `.jpg` files in a specific directory
files = glob.glob("./project/Sets/SetScripts_*.json")
print(files)


definition_files = glob.glob("./sets/SetDefinition_*.json")

events = {}
cards = {}
metadata = {}
abilities = {}
functions = {}

comments = {
    "add_resource": "adds resources based on specific computations",
    "add_script": "adds a script to a target card",
    "add_threat": "adds threat to subjects",
    "attach_to_card": "attach script owner to subject",
#Commented out attack because it appears in other cases (e.g. tags) and that can be confusing
    #    "attack": "starts an attack event from you/the card owning the script to [subjects]",
    "cancel_current_encounter": "discards the current encounter into villain discard, not executing its reveal or any other content",
    "change_controller_hero": "change controller hero",
    "change_form": "change hero form",
    "conditional_script": "allows to run one of several optional tasks (nested_tasks) based on the result of a condition check",
    "constraints": "an ability that does nothing but is used as a cost to constraint when a card/ability can be used. Typically, Hero vs Alter Ego form, etc...",
    "count_tokens": "count number of tokens of a specific type",
    "deal_damage": "deal damage to [subject]. also see receive_damage",
    "deal_encounter": "deal an encounter to current hero",
     #    "discard": "shortcut for move_to_container discard",   
    "draw_cards": "the owner of [subject]cards draws cards",
    "enemy_schemes": "subject enemy (typically the villain) starts a scheme action",
    "execute_scripts": "runs card.execute_scripts for a specific card and trigger",
    "exhaust_card": "exhausts [subject] cards. See ready_card",
    "heal": "heal [subjects]. Can be used as a cost, in which case the heal must happen at least partially for the cost to be considered paid",
    "host_card": "owner of the script will become the host of the subjects. Can be used to steal cards for example",
    "i_attack": "current script owner attacks a series of subjects",
    "mod_counter": "modify a general counter on the app",
    "mod_tokens": "modify tokens on the card. See Damage, threat, stunned, confused, etc...",
    "modify_properties": "modify specific properties of the card (also see alterants)",
    "move_card_to_board": "move [subjects] cards to the boards, sometimes specifying a grid location",
    "move_card_to_container": "move [subject] cards to a specific container (aka pile)",
    "move_token_to": "moves some specific token from 'source' to 'subject' If number of tokens is not enough, still moves as many as possible", 
    "move_to_player_zone": "move [subject]cards to a specific hero board",
    "nop": "does nothing, but used for example to ensure some conditioi is met, as a cost",
    "pay_cost": "pay a specific cost (not necessarily the card's cost",
    "pay_regular_cost": "trigger to initiate the card's cost payment",
    "prevent": "prevents damage (also see replacement_effect)",
    "ready_card": "ready a specific card (also see exhaust)",
    "receive_damage": "also see deal_damage",
    "remove_threat": "removes threat from [subject] schemes. Also see thwart.",
    "replacement_effect": "replaces some task on the stack with something else (e.g. damage replaced, targets, replaced, etc...)",
    "return_attachments_to_owner": "returns attachments of the script's owner to their respective owners",
    "reveal_encounter": "reveal encounter by trying multiple sources, first looking into subjects, then falling back to src_container, and finally into the villain's deck",
    "reveal_encounters": "reveals encounters as described by subjects, otherwise fails",
    "reveal_nemesis": "Reveals the current hero's nemesis",
    "scheme": "The Villain schemes",
    "sequence": "initiates a sequence of multiple script calls on multiple calls. Specifically used for Black Panther",
    "shuffle_card_into_container": "shullfes subject cards into dest_container",
    "surge": "triggers an encounter surge",
    "temporary_effect": "adds a temporary effect on a card, which stays until a specific event is triggered (typically for event cards that grant a benefit -alterant- until end of round or phase)",
    "thwart": "either removes a given amount of threat, or starts a thwart action from a character. Also see remove_threat",
    "villain_and_enemies_attack_you": "Triggers an attack of the Villain and enemies engaged with current hero",
    "villain_attacks_you": "Triggers an attack of the villain against current hero",    
#event comments
    "alterants": "a special trigger keyword for modifications that alter values of cards on the board",
    "about_to_reveal": "called before an encounter reveal event. Used for interrupts that prevent revealing",
    "attack_happened": "triggers after attack occured. Attack needs to happen for this to trigger, this will not trigger e.g. if character was stunned",    
    "boost": "special trigger called for card's boost star abilities",
    "card_damaged": "triggers when a card receives damage greater than zero",
    "card_moved_to_board": "when a card moves to the board (excluding any pile e.g. discard, deck, etc...)",
    "card_moved_to_pile": "triggers when a card moves to any pile on the board. Additional filters required to understand which pile",
    "card_played": "triggers when a card is played by a player.",
    "enemy_attack_happened": "triggers after an enemy attack occured. Attack needs to happen for this to trigger, this will not trigger e.g. if enemy was stunned",
    "enemy_initiates_attack": "triggers when enemy initiates attack",
    "enemy_scheme_happened": "triggers after an enemy scheme event occured. Scheme needs to happen for this to trigger, this will not trigger e.g. if enemy was confused",
    "give_obligation": "a shortcut macro to give an obligation to its matching player. See _macros.json",
    "identity_changed_form": "triggers when an identity changed from hero to alter_ego or vice versa",
    "interrupt": "special trigger used for interrupt checks",
    "minion_died": "triggered when a minion dies",
    "minion_moved_to_board": "triggered when a minion moves to the board.Might be easier to use than card_moved_to_board",
    "once_per_round": "special macro that creates a token which can limit some specific actions to once per round. see _macros.json",
    "modifiers": "a special keyword to modify some aspects of the engine at runtime",
    "phase_ended": "triggered when a phase of the game ended (player or villain phase)",
    "quickstrike": "macro for the quickstrike keyword, starts an automated attack",
    "resource": "special trigger for resource abilities",
    "response":  "special trigger used for interrupt/response checks. Currently Response events are hardcoded to act exactly like interrupts",
    "reveal_alter_ego": "special trigger that will be prioritized over 'reveal' if it's available and if the current identity is in alter ego form",
    "reveal_hero": "special trigger that will be prioritized over 'reveal' if it's available and if the current identity is in hero form",
    "reveal_side_a": "special trigger to reveal the side A of main schemes",
    "round_ended": "triggered when a round ends. Also see phase_ended",
    "setup": "special trigger for setup on some cards",
    "thwarted": "triggered when a succesful thwart action has completed",
    "uses": "special macro to implement the 'uses' keyword",
    "villain_step_one_threat_added": "triggers when threat was added during step one of the villain phase",
    

#function comments
    "!identity_has_trait": "returns true if your identity doesn't have the trait, false if it does",	
    "card_is_in_play": "Returns true if card_name is in play",
    "count_boost_icons": "Returns number of boost icons on subject",
    "count_printed_resources": "Returns number of resources of resource_type printed on subject card",   
    "count_resource_types": "counts the number of resource *types* in a list of subjects",	
    "current_activation_status": "returns true if the current activation (attack, scheme, encounter...) matches the passed params. e.g. to check if attack is undefended",
    "get_remaining_damage": "returns remaining damage (health - damage) for subject card",
    "get_script_bool_property": "returns script_definition element as a bool",
    "get_sustained_damage": "returns sustained damage for subject card (typically, number of damage tokens)", 
    "identity_has_trait": "returns true if your identity has the trait",	
    "paid_with_includes": "returns true if this ability was paid for with a specific type of resource",
#other comments
    "is_cost": "this part of the script is a cost. Typically the script won't get executed unless all costs can be paid",
    "is_else": "a part of the script that will explicitly be executed <em>if</em> the cost cannot be paid",
    "for_each_player": "this will internally duplicate this part of the script for each hero in game (and assign containers accordingly for each player, e.g hand becomes hand1, hand2, hand3,)",
}

#don't display these in the links
exceptions = ["manual", "reveal"]

output_file  = "./project/doc/script_doc.html"
images_url = "https://marvelcdb.com/bundles/cards/"

def add_definition_data(card_name, card_data, box_name):
    metadata[box_name][card_name] = {}
    metadata[box_name][card_name]["img"] = card_data["code"] + ".png"
    metadata[box_name][card_name]["img_style_suffix"] = ""
    card_type = card_data["type_code"]
    if card_type in ["main_scheme", "side_scheme"]:
        metadata[box_name][card_name]["img_style_suffix"] = "_horizontal"

def parse_definition_file(source_file):
    basename = os.path.basename(source_file)
    basename = basename[14:-5]
    metadata[basename] = {}
    with open(source_file) as user_file:
        result = json.load(user_file);
#        print ("the result is" , result)
        for card_data in result:
            card_name = card_data["name"]
            card_code = card_data["code"]
            add_definition_data(card_name, card_data, basename)
            add_definition_data(card_name  +" #" + card_code, card_data, basename)            
            if "subname" in card_data:
                card_subname = card_data["subname"]
                if card_subname:
                    card_fullname = card_name + " - " + card_subname
                    add_definition_data(card_fullname, card_data, basename)

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

def get_function_params(card_data, function):
    result = {}
    if type(card_data) is dict:
        if "func_name" in card_data and card_data["func_name"] == function:
            for key,value in card_data.items():
                if key == "func_name":
                    continue  
                if key == "func_params":
                    for subkey, subvalue in value.items():
                        result[subkey] = True
                else:
                    continue
        else:
            for key,value in card_data.items():
                other_params = get_function_params(value, function)
                if other_params:
                    for i in other_params:
                        result[i] = True
    elif type(card_data) is list:
        for item in card_data:
            other_params = get_function_params(item, function)
            if other_params:
                for i in other_params:
                    result[i] = True
#    if result:
#        print (result)                
    return result


def get_stuff_matching_key(card_data, needle):
    result = []
    if type(card_data) is dict:        
        for key,value in card_data.items():
            if key == needle:
                result.append(value)
            else:
                other_abilities = get_stuff_matching_key(value, needle)
                if other_abilities:
                    for ab in other_abilities:
                        if ab not in result:
                            result.append(ab)
    elif type(card_data) is list:
        for item in card_data:
            other_abilities = get_stuff_matching_key(item, needle)
            if other_abilities:
                for ab in other_abilities:
                    if ab not in result:
                        result.append(ab)
    return result
    
def get_abilities(card_data):
    return get_stuff_matching_key(card_data, "name")

def get_functions(card_data):
     return get_stuff_matching_key(card_data, "func_name")   

            
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
                card_functions = get_functions(trigger_data)
                if card_functions:
                    for function in card_functions:
                        if function not in functions:
                            functions[function] = {
                                "cards": {},
                                "params": get_function_params(result, function)
                            }
                        function_data = functions[function]["cards"]
                        if box_name not in function_data:
                            function_data[box_name] = []
                        if card not in function_data[box_name]:
                            function_data[box_name].append(card)                           

                            
def simple_nav_html():
    result = ""
    for name in ["abilities", "functions", "events", "cards"]:
        result += '    <a href="#' + name +  '\">' + name  + "</a>\n"
    return result

def array_nav_html(names, section_name):
    section_id = section_name.lower()
    result = '<h2 id="' + section_id +'">' + section_name +'</h2>' + "\n"
    result +="<table>"
    for name in sorted(names):
        if name in exceptions:
            continue
        result += '<tr><td><a href="#' + name +  '\">' + name  + "</a></td><td>"
        if name in comments:
            result+= comments[name]        
        result+= "</td></tr>\n"
    result += "</table>\n"
    return result

def functions_nav_html(separator ="\n", id =""):
    result = '<h2 id="' + id +'">FUNCTIONS</h2>' + "\n"
    for function in sorted(functions):
        if function in exceptions:
            continue
        result += '    <a href="#' + function +  '\">' + function  + "</a>" + separator
    return result


def functions_html():
    result = array_nav_html(functions, "FUNCTIONS")
    for function in sorted(functions):
        if function in exceptions:
            continue
        result += '<section id="' + function + '"><h3>' + function  + "</h3>\n"
        if function in comments:
            result+= "<p>" + comments[function] + "</p>\n"
        function_data = functions[function]["cards"]
        function_params = functions[function]["params"]
        result+= '<p><strong>params:</strong><br /><ul class="slight_right">' +"\n"                             
        for param in function_params:
            result+= "<li>" + param + "</li>\n"
        result+="</ul></p>\n"
        all_cards = []
        result+= '<p><strong>cards</strong><br /><div class="slight_right">' +"\n"                                    
        for box_name in function_data:
            box_data = function_data[box_name]
            for card in box_data:
                all_cards.append(card)
        for card in all_cards:
            result += '<a href="#' + card + '">' + card + "</a>,\n"
        result += "</div></p></section>\n"       
    return result

                            
def abilities_nav_html(separator ="\n", id=""):
    result = '<h2 id="' + id +'">ABILITIES</h2>' + "\n"
    for ability in sorted(abilities):
        if ability in exceptions:
            continue
        result += '    <a href="#' + ability +  '\">' + ability  + "</a>" + separator
    return result


def abilities_html():
    result = array_nav_html(abilities, "ABILITIES")
    for ability in sorted(abilities):
        if ability in exceptions:
            continue
        result += '<section id="' + ability + '"><h3>' + ability  + "</h3>\n"
        if ability in comments:
            result+= "<p>" + comments[ability] + "</p>\n"
        ability_data = abilities[ability]["cards"]
        ability_params = abilities[ability]["params"]
        result+= '<p><strong>params:</strong><br /><ul class="slight_right">' +"\n"                             
        for param in ability_params:
            result+= "<li>" + param + "</li>\n"
        result+="</ul></p>\n"
        all_cards = []
        result+= '<p><strong>cards</strong><br /><div class="slight_right">' +"\n"                                    
        for box_name in ability_data:
            box_data = ability_data[box_name]
            for card in box_data:
                all_cards.append(card)
        for card in all_cards:
            result += '<a href="#' + card + '">' + card + "</a>,\n"
        result += "</div></p></section>\n"       
    return result

                        
def events_nav_html(separator ="\n", id=""):
    result = '<h2 id="' + id +'">EVENTS</h2>' + "\n"    
    for trigger in sorted(events):
        if trigger in exceptions:
            continue
        result += '    <a href="#' + trigger +  '\">' + trigger  + "</a>" + separator
    return result

def events_html():
    result = array_nav_html(events, "EVENTS")
    for trigger in sorted(events):
        if trigger in exceptions:
            continue       
        trigger_cards = events[trigger]
        result += '<section id="' + trigger + '"><h3>' + trigger  + "</h3>\n"       
        for card in sorted(trigger_cards):
            card_data = trigger_cards[card]
            result += '    <li><a href="#' + card + '">' + card + "</a></li>\n"
        result += "</section>\n"
    return result       


def cards_nav_html(separator ="\n", id =""):
    result = '<h2 id="' + id +'">CARDS</h2>' + "\n"        
    for box_name, cards_data in cards.items():
        result += "<h3>" + box_name + "</h3>\n"
        for card in sorted(cards_data):
            card_data = cards_data[card]
            result += "    <a href=\"#" + card +  "\">" + card  + "</a>" + separator
    return result


def cards_html():
    result = cards_nav_html("-", "cards")
    for box_name, cards_data in cards.items():
        result += "<h3>" + box_name + "</h3>\n"
        for card in sorted(cards_data):
            card_data = cards_data[card]
            result += "<section id=\"" + card + "\"><h2>" + card  + "</h2>\n"
            if box_name in metadata:
                box_meta = metadata[box_name]
                if card in box_meta:
                    card_meta = box_meta[card]
                    result+= '<img src="' + images_url + card_meta["img"] + '" class="resize' +  card_meta["img_style_suffix"] + '"/>' + "\n"
            card_code = json.dumps(card_data, indent = 2)
            for ability in comments:
                card_code = card_code.replace('"' + ability + '"', '"<a class="tooltip" href="#' + ability +'"><span class="tooltiptext">'+ comments[ability] + '</span>' + ability + '</span></a>"')
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
    result+= simple_nav_html()
#    result+= abilities_nav_html()
#    result+= functions_nav_html()        
#    result+= events_nav_html()
#    result+= cards_nav_html()
    result+="</nav><main>\n"
    result+= abilities_html()
    result+= functions_html()           
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
