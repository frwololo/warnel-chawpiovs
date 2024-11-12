#!/usr/bin/python

import os
import sys
import json
import urllib.request 


parsed_json = []

source_file = sys.argv[1]
home_folder = "/home/wololo/wc/"
output_folder  = home_folder + "sets/"
base_url = "https://marvelcdb.com"

def origFolder(setName):
    return output_folder + setName + "/0_orig/"

def rotatedFolder(setName):
    return output_folder + setName + "/1_rotated/"

def resizedFolder(setName):
    return output_folder + setName + "/2_resized/"

def maskedFolder(setName):
    return output_folder + setName + "/3_masked/"


def createFolders(setName):
    os.makedirs(output_folder + setName, exist_ok = True)
    os.makedirs(origFolder(setName), exist_ok = True)
    os.makedirs(rotatedFolder(setName), exist_ok = True)
    os.makedirs(maskedFolder(setName), exist_ok = True)
    os.makedirs(resizedFolder(setName), exist_ok = True)

def isHorizontal(card):
    return ("scheme" in card["type_code"])
    
with open(source_file) as user_file:
  parsed_json = json.load(user_file);

for card in parsed_json:
    setName = card["pack_code"]
    createFolders(setName)

    w = 300
    h = 419
    rotate_suffix = "0"


    img_url = card["imagesrc"]
    img_basename = os.path.basename(img_url)
    img_filename = origFolder(setName) + img_basename

    #Download
    if not os.path.isfile(img_filename):
        urllib.request.urlretrieve(base_url + img_url, img_filename)        

    #Rotate if needed
    if isHorizontal(card):
        rotate_suffix = "90"
        
    rotated_filename = rotatedFolder(setName) + img_basename    
    if not os.path.isfile(rotated_filename):
        os.system('convert ' + img_filename + ' -rotate -' + rotate_suffix + ' ' + rotated_filename)

    #Resize    
    resized_filename = resizedFolder(setName) + img_basename    
    if not os.path.isfile(resized_filename):
        os.system('magick ' + rotated_filename + ' -resize ' + str(w) + "x" + str(h) + '\! '
              + resized_filename)

    #Apply mask    
    masked_filename = maskedFolder(setName) + img_basename    
    if not os.path.isfile(masked_filename):
        os.system('magick composite ' + resized_filename + ' '
              + home_folder +'wc_transparent.png '
              + home_folder + 'wc_card_mask.png '
              + masked_filename)

