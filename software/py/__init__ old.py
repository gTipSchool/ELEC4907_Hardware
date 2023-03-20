#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Nerve Protocol

Created on Wed Feb  1 02:09:43 2023

@author: yakov petrukhin

LOGGING: 
    - INFO = FPGA
    - DEBUG = COMMAND PACKAGER
"""

from fpga import FPGA, eval_outputs, start_cts_monitor
# import pipe
from command_handler import start_command_packager
import logging
from collections import deque
import time
import threading

if __name__ == "__main__":
             
    format = "%(asctime)s: %(message)s"
    logging.basicConfig(format=format, level=logging.DEBUG, datefmt="%H:%M:%S")
                    
    fpga = FPGA('COM3', 576000, exitOnFail = True)
    
    # # 4 neuron test instruction set
    # instruction_queue = deque(['LD_INPUT,1,15',
    #                            "LD_WEIGHT,2,0,1,4",
    #                            "LD_WEIGHT,2,1,2,10",
    #                            "LD_WEIGHT,2,2,3,-5",
    #                            "LD_STEP_LEN,10,60",
    #                            "LD_WEIGHT,3,0,2,5",
    #                            "LD_WEIGHT,3,1,3,5",
    #                            "LD_WEIGHT,4,0,1,5",
    #                            "SET_NUM_PERIODS,3000",
    #                            "RUN_EXECUTION"])
    
    # # 6 neuron test instruction set
    # instruction_queue = deque(['LD_INPUT,1,15',
    #                             "LD_WEIGHT,3,0,1,10",
    #                             "LD_STEP_LEN,3,100",
    #                             "LD_WEIGHT,4,0,2,10",
    #                             "LD_STEP_LEN,4,200",
    #                             "LD_WEIGHT,5,0,3,5",
    #                             "LD_WEIGHT,5,1,4,2",
    #                             "LD_WEIGHT,6,0,4,5",
    #                             "SET_NUM_PERIODS,1025",
    #                             "RUN_EXECUTION"])
    
    
    
    
    # DONT USE THIS YET. Don't have a way to load new commands after reading
    # inital execution response. 
    
    # 21 neuron test instruction set
    instruction_queue = deque([#'LD_INPUT,1,0',
                               # 'LD_INPUT,2,0',
                               # 'LD_INPUT,3,0',
                               
                               #  'LD_INPUT,4,0',
                               #  'LD_INPUT,5,0',
                               #  'LD_INPUT,6,0',
                                
                               #  'LD_INPUT,7,0',
                               #  'LD_INPUT,8,0',
                               #  'LD_INPUT,9,0',
                                
                                # "LD_WEIGHT,10,0,1,10",
                                # "LD_WEIGHT,10,1,2,10",
                                # "LD_WEIGHT,10,2,3,10",
                                # "LD_STEP_LEN,10,20",
                               
                                # "LD_WEIGHT,11,0,4,8",
                                # "LD_WEIGHT,11,1,5,8",
                                # "LD_WEIGHT,11,2,6,8",
                                # "LD_STEP_LEN,11,200",
                               
                                # "LD_WEIGHT,12,0,7,10",
                                # "LD_WEIGHT,12,1,8,10",
                                # "LD_WEIGHT,12,2,9,10",
                                # "LD_STEP_LEN,12,20",
                               
                                # "LD_WEIGHT,13,0,10,5",
                                # "LD_WEIGHT,13,1,11,-20",
                                # "LD_WEIGHT,13,2,12,-5",
                               
                                # "LD_WEIGHT,14,0,10,-5",
                                # "LD_WEIGHT,14,1,11,-20",
                                # "LD_WEIGHT,14,2,12,5",
                               
                                # "LD_WEIGHT,15,0,13,-12",
                                # "LD_WEIGHT,15,1,14,-12",
                                # "LD_WEIGHT,15,2,11,-12",
                                # "LD_STEP_LEN,15,20",
                                #  'LD_INPUT,15,12',
                               
                                # "LD_WEIGHT,16,0,13,-12",
                                # "LD_WEIGHT,16,1,14,-12",
                                # "LD_WEIGHT,16,2,11,-12",
                                # "LD_STEP_LEN,16,20",
                               
                                # "LD_WEIGHT,17,0,15,6",
                                # "LD_WEIGHT,17,1,13,10",
                                # "LD_WEIGHT,17,2,16,-6",
                                # "LD_WEIGHT,17,3,11,-15",
                               
                                # "LD_WEIGHT,18,0,16,6",
                                # "LD_WEIGHT,18,1,14,10",
                                # "LD_WEIGHT,18,2,15,-6",
                                # "LD_WEIGHT,18,3,11,-15",
                               
                                # "LD_WEIGHT,19,0,17,10",
                               
                                # "LD_WEIGHT,20,0,11,8",
                               
                                # "LD_WEIGHT,21,0,18,10",
                               
                                "SET_NUM_PERIODS,5000",
                                "RUN_EXECUTION"])
    
    
    tx_cmd_queue = deque()
    
    start_command_packager(instruction_queue, tx_cmd_queue)
    
    logging.debug("Waiting for all instructions to be added to the queue")
    time.sleep(5)
    
    logging.debug("Starting to write.")
    fpga.write_data(tx_cmd_queue)
    outputs = fpga.read_outputs()
    print("Left:" + str(outputs[0]) + " Center:" + str(outputs[1]) + " Right:" + str(outputs[2]))
    movement_response = eval_outputs(outputs)
    print(movement_response)
        
    instruction_queue2 = deque(["RUN_EXECUTION"])
    start_command_packager(instruction_queue, tx_cmd_queue)
    logging.debug("Starting to write.")
    fpga.write_data(tx_cmd_queue)
    outputs = fpga.read_outputs()
    print("Left:" + str(outputs[0]) + " Center:" + str(outputs[1]) + " Right:" + str(outputs[2]))
    movement_response = eval_outputs(outputs)
    print(movement_response)
    
    if fpga.connection.is_open:
        fpga.connection.close()