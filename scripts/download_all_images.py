#!/usr/bin/python

import os
import sys
import json
import urllib.request 
import imghdr

parsed_json = []

source_file = sys.argv[1]
output_folder  = "./sets_raw/"
temp_filename = "./image.jpg"
failed_cards = []


def destFolder(serverName, setName):
    return output_folder + serverName + "/" + setName + "/"  

def createFolders(serverName, setName):
    os.makedirs(output_folder + serverName , exist_ok = True)    
    os.makedirs(destFolder(serverName, setName), exist_ok = True)    

def failed_dl(img_url):
    with open('dl_errors.txt', 'a') as file:
        file.write(img_url + "\n")


def load_failures():
    failed = []
    try:
        with open('dl_errors.txt') as my_file:
            failed = my_file.read().splitlines() 
    except:
        return failed
    return failed

    
def download_img(img_url, img_code, serverName, setName):
    if img_url in failed_cards:
        print(img_url + " is failed, not retrying")
        return
    

    #Download
    dest_filename =  destFolder(serverName, setName) + img_code

    found = False
    for ext in [".jpg", ".png", ".webp"]:
        if os.path.isfile(dest_filename + ext):
            found = True
            break
    if found:
        return
    
    print("dl " + img_url + " --> " + dest_filename)              
    try:
        urllib.request.urlretrieve(img_url, dest_filename)        
    except:
        print("error downloading " + img_url)
        failed_dl(img_url)
        return
    
    extension = ".jpg"
    do_skip = False
    image_type = imghdr.what(dest_filename)

    if image_type == "jpeg":
        extension = ".jpg"
    elif image_type == "webp":
        extension = ".webp"
    elif image_type == "png":
        extension = ".png"       
    else:
        extension = ".jpeg"
        do_skip = True

    if do_skip:
        print("##\nskipping " + img_url + " of type " + image_type + "\n##")
        return
    
    new_filename =  destFolder(serverName, setName) + img_code + extension
    if new_filename != dest_filename:
        print("moving " + dest_filename + " to " + new_filename)       
        os.rename(dest_filename,new_filename )

failed_cards = load_failures()

with open(source_file) as user_file:
  parsed_json = json.load(user_file);

for server in parsed_json:
    for card in parsed_json[server]:
        setName = card["set_name"]
        createFolders(server, setName)

        img_url = card["url"]
        img_code = card["card_id"]

        
        download_img(img_url, img_code, server, setName)

        
