# -*- coding: utf-8 -*-
"""
Created on Tue Mar 21 01:17:08 2023

@author: yakovpetrukhin
"""
import timeit
import global_vars
import csv
import matplotlib.pyplot as plt
import threading
import logging
from collections import deque
import pandas as pd

def binary_decoder(byte):
    
    bit_arr = []
    bit_str = bin(byte)[2::]
    
    if len(bit_str) < 8:
        bit_arr = [0 for i in range(8-len(bit_str))]
        
    for bit in bit_str:
        bit_arr.append(int(bit))
                    
    return bit_arr


def debug_log_packager(debug_dest, packaged_log_dest, save_packaged_log = True):
 
    colors = 'black'
    lineoffsets = 1
    linelengths = 1

    while True:
        if len(debug_dest) > 0:
            if (debug_dest[0][0:4] == "EXIT"):
                logging.info("Exiting Debug Data Handler Thread.")
                
                if save_packaged_log:
                    pass
                    
                    
                    
                    # This version does not work well and appends each time step as a list
                    
                    # # log_data = list(packaged_log_dest)
                    # # logging.info("Log Data Being Written to CSV: %s",log_data)
                    # logging.info("Log Data Being Written to CSV: %s",packaged_log_dest)

                    
                    # with open('debug_monitor_log.csv', 'w', newline = "") as f:
                    #     # using csv.writer method from CSV package
                    #     logging.info("Saving Debug Monitor output.")
                    #     write = csv.writer(f)
                    #     write.writerows(packaged_log_dest)
                else:
                    pass
                break
            
            debug_data = debug_dest.popleft()
            # logging.info("Current raw debug monitor data: %s", debug_data.hex(" ", 1))
            curr_timestep_data = []
            packaged_log_reversed = []
            df = pd.DataFrame()
            
            
            for byte in debug_data:
                curr_timestep_data.extend(binary_decoder(byte))
                #logging.info("New extended array: %s",curr_timestep_data)
                if len(curr_timestep_data) >= global_vars.NUM_NEURONS:
                    # logging.info("Length of Non Cut Timestep Arr: %s", len(curr_timestep_data))
                    clean_curr_timestep_data = curr_timestep_data[len(curr_timestep_data)-(global_vars.NUM_NEURONS):len(curr_timestep_data)]
                    # logging.info("Current Timestep: %s", clean_curr_timestep_data)
                    clean_curr_timestep_data.reverse()
                    # logging.info("Reverse Current Timestep (Correct Order): %s", clean_curr_timestep_data)
                    # logging.info("Length of Timestep Arr: %s", len(clean_curr_timestep_data))
                    packaged_log_reversed.append(clean_curr_timestep_data)
                    curr_timestep_data = []
                else:
                    pass
                
            packaged_log_reversed.reverse()
            # logging.info("Final log appended to destination: %s", packaged_log_reversed)
            # create a horizontal plot
            plt.eventplot(packaged_log_reversed, colors=colors, lineoffsets=lineoffsets,
                                linelengths=linelengths, orientation='vertical')
            plt.show()

            # packaged_log_dest.append(packaged_log_reversed)
            
            
        else:
            pass
            



def start_debug_log_packager(debug_dest, packaged_log_dest, save_packaged_log = True):
    logging.info("Debug Log Packager thread started.")
    log_packager = threading.Thread(name = "Debug packager", target = debug_log_packager, args = (debug_dest, packaged_log_dest, save_packaged_log,), daemon = True)
    log_packager.start()
                        
            

def timeit_test():
    
    SETUP ="""
from __main__ import binary_decoder

test_data = bytes([0x22])

"""
    
    TEST = """
log_output = []
for x in range(5375):
    log_output.append(binary_decoder(test_data))"""
    
    times = timeit.timeit(SETUP,TEST,1000)
    print(times)



if __name__ == "__main__":
    
    format = "%(asctime)s: %(message)s"
    logging.basicConfig(format=format, level=logging.DEBUG, datefmt="%H:%M:%S")
    
    packaged_log_dest = deque()
    test_data = deque([bytes([0x00, 0x11, 0x22, 
                        0x33, 0x44, 0x55,
                        0x66, 0x77, 0x88,
                        0x99, 0xaa, 0xbb,
                        0xcc, 0xdd, 0xee,
                        0xff,0x00, 0x11, 0x22, 
                        0x33, 0x44, 0x55,
                        0x66, 0x77, 0x88,
                        0x99, 0xaa, 0xbb,0x00, 0x11, 0x22, 
                        0x33, 0x44, 0x55,
                        0x66, 0x77, 0x88,
                        0x99, 0xaa, 0xbb,
                        0xcc, 0xdd, 0xee,
                        0xff]), "EXIT" ])
    
    start_debug_log_packager(test_data, packaged_log_dest)
