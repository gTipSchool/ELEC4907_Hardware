#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Tue Feb  7 01:49:17 2023

@author: yakov
"""


import logging
import sys
import threading
from collections import deque
import time
import global_vars


FPGA_PRECISION = 1
NUMBER_OF_NEURONS = 23

shutdown = threading.Event()

## NOTE ELEMENTS ARE ADDED TO THE RIGHT SIDE OF THE QUEUE BY THE COMMAND PACKAGER (ie. Placed on the end of the queue)
# When removing elements from the tx_cmd_queue .popleft must be used to remove elements from the front of the queue

def mmu_write(addr_neuron_index, addr_internal, value):
    mmu_address_reg = [6,7,8]
    mmu_data_reg = [9,10,11]
    mmu_write_enable = 5
    
    address = addr_neuron_index + addr_internal
    byte_string = bytes()
    
    for i in range(3):
        logging.debug("Address Bit %s: %s", i, bytes([address[i]]).hex())
    for i in range(3):
        logging.debug("Value Bit %s: %s", i, bytes([value[i]]).hex())
        
    # Create 3 byte address packet
    for i in range(3):
        byte_string = byte_string + bytes([0b10000000|mmu_address_reg[i]]) + bytes([address[i]])
        logging.debug("Current byte string: %s", byte_string.hex())

    # Create 3 byte value packet 
    for i in range(3):
        byte_string = byte_string + bytes([0b10000000|mmu_data_reg[i]]) + bytes([value[i]])
        logging.debug("Current byte string: %s", byte_string.hex())
    
    byte_string = byte_string + bytes([0b10000000|mmu_write_enable])+bytes([1])

    return byte_string
    
    
def command_packager_v2(instruction_queue, tx_cmd_queue, debug_mode = False):
   
    cmd = None
    byte_string = bytes()
    
    while True:
        
        if shutdown.is_set():
            logging.info("Shutting down Command Packager thread.")
            break
            
        ## CONDITION TO RUN DEBUG MONITOR AFTER EVERY ITERATION
        if cmd == "RUN_EXECUTION" and debug_mode == True:
            instruction_queue.appendleft("READ_DEBUG_MONITOR")
        
        if len(instruction_queue) > 0:
            
            instruction = instruction_queue.popleft()
            cmd, *args = instruction.split(",")
            
            if cmd == "LD_INPUT":
                
                address = int(args[0],10).to_bytes(2, "big")
                input_current = (int(args[1],10)*(2**FPGA_PRECISION)).to_bytes(3, "big")
                logging.debug("Received in command queue: %s, %s, %s", cmd,address.hex(), input_current.hex())
                
                
                byte_string = byte_string + input_current
                
            elif cmd == "RUN_EXECUTION":
                tx_cmd_queue.append(bytes([0x00,0xff])+byte_string)
                logging.info(f"Appending to tx_queue: %s", (bytes([0x00,0xff])+byte_string).hex(" ",1))
                byte_string = bytes()
                
            elif cmd == "SET_NUM_PERIODS":
                # Parse command string for args
                max_num_periods = int(args[0],10).to_bytes(2, "big")
                logging.debug("Received in command queue: %s, %s", cmd,max_num_periods.hex())
                
                # Update NUM_TIMESTEPS global parameter
                global_vars.NUM_TIMESTEPS = int(args[0],10)
                
                # Append CMD and NUM_PERIODS byte string to tx_queue
                tx_cmd_queue.append(bytes([0x00,0x55])+max_num_periods)
                logging.info(f"Appending to tx_queue: %s", (bytes([0x00,0x55])+max_num_periods).hex(" ",1))
                
            elif cmd == "READ_DEBUG_MONITOR":
                logging.debug("Received in command queue: %s", cmd)
                tx_cmd_queue.append(bytes([0x00,0xAA]))
                logging.info(f"Appending to tx_queue: %s", bytes([0x00,0xAA]).hex(" ",1))

            
            
            elif cmd == "EXIT":
                tx_cmd_queue.append("EXIT")
                logging.info("Received EXIT command. Shutting down Command Packager thread.")
                break
                
            else:
                logging.info("Unknown Command: %s", cmd)
                
                

def command_packager(instruction_queue, tx_cmd_queue):
    while True:
        if len(instruction_queue) > 0:
            instruction = instruction_queue.popleft()
            cmd, *args = instruction.split(",")
            if cmd == "LD_INPUT":
                
                target_neuron = int(args[0],10).to_bytes(2, "big")
                internal_address = 0
                internal_address = internal_address.to_bytes(1, 'big')
                address = target_neuron + internal_address
                input_current = (int(args[1],10)*(2**FPGA_PRECISION)).to_bytes(3, "big")
                logging.debug("Received in command queue: %s, %s, %s", cmd,address.hex(), input_current.hex())
                
                byte_string = mmu_write(target_neuron, internal_address,input_current)
                logging.debug("Final byte string placed in TX queue: %s", byte_string.hex())
                
            elif cmd == "LD_WEIGHT":
                
                """
                Need to add weight precision modifier still
                """
                
                target_neuron = int(args[0],10).to_bytes(2, "big")
                row = int(args[1],10)
                associated_neuron_idx = int(args[2],10).to_bytes(3, "big")
                weight = int(args[3],10)*(2**FPGA_PRECISION)
                weight = weight.to_bytes(3, "big", signed = True)
                logging.debug("Received in command queue: %s, %s, %s, %s, %s", cmd,target_neuron.hex(), row.to_bytes(1, "big").hex(), associated_neuron_idx.hex(), weight.hex())
        
                
                byte_string = mmu_write(target_neuron, int(row*2+2).to_bytes(1, "big"), associated_neuron_idx)
                byte_string = byte_string + mmu_write(target_neuron, int(row*2+3).to_bytes(1, "big"),weight)
                logging.debug("Final byte string placed in TX queue: %s", byte_string.hex())
        
            elif cmd == "LD_STEP_LEN":
                
                target_neuron = int(args[0], 10).to_bytes(2, "big")
                internal_address = 1
                internal_address = internal_address.to_bytes(1, 'big')
                address = target_neuron + internal_address
                count = int(args[1], 10).to_bytes(3, "big")
                logging.debug("Received in command queue: %s, %s, %s", cmd,address.hex(), count.hex())
        
                byte_string = mmu_write(target_neuron, internal_address,count)
                logging.debug("Final byte string placed in TX queue: %s", byte_string.hex())
                
            elif cmd == "SET_NUM_PERIODS":
                
                max_num_periods = int(args[0],10).to_bytes(2, "big")
                logging.debug("Received in command queue: %s, %s", cmd,max_num_periods.hex())
        
                byte_string = bytes([0b10000000|3]) + bytes([max_num_periods[0]]) + bytes([0b10000000|4]) + bytes([max_num_periods[1]])  
                logging.debug("Final byte string placed in TX queue: %s", byte_string.hex())
                
            elif cmd == "RUN_EXECUTION":
                logging.debug("Received in command queue: %s", cmd)
    
                byte_string = bytes([0b10000000|0]) + bytes([1]) 
                logging.debug("Final byte string placed in TX queue: %s", byte_string.hex())
            
            elif cmd == "SHUTDOWN":
                logging.debug("Received in command queue: %s", cmd)
                logging.debug("Shutting Down")
                sys.exit()

            
            for i in range(len(byte_string)):
                tx_cmd_queue.append(bytes([byte_string[i]]))
            
        else:
            continue
        

def start_command_packager(instruction_queue, tx_cmd_queue):
    packager = threading.Thread(name = "command_packager", target = command_packager, args = (instruction_queue, tx_cmd_queue,), daemon = False)
    packager.start()
    logging.info("Starting Command Packager Thread.")
    
def start_command_packager_v2(instruction_queue, tx_cmd_queue, debug_mode = False):
    packager = threading.Thread(name = "command_packager", target = command_packager_v2, args = (instruction_queue, tx_cmd_queue,debug_mode,), daemon = False)
    packager.start()
    logging.info("Starting Command Packager Thread.")

    


        

            
if __name__ == "__main__":
             
    format = "%(asctime)s: %(message)s"
    logging.basicConfig(format=format, level=logging.DEBUG, datefmt="%H:%M:%S")
    
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
    
    ## command_packager_V2 test
    instruction_queue = deque(['LD_INPUT,1,22',
                              'LD_INPUT,2,223',
                              'LD_INPUT,3,456',
                              'LD_INPUT,4,3',
                              'LD_INPUT,5,12',
                              'RUN_EXECUTION',
                              'LD_INPUT,1,15',
                              'LD_INPUT,2,255',
                              'LD_INPUT,3,34',
                              'LD_INPUT,4,3',
                              'LD_INPUT,5,12',
                              'RUN_EXECUTION'])
    
    tx_cmd_queue = deque()

    start_command_packager(instruction_queue, tx_cmd_queue)
        
        
    # command_packager("LD_INPUT,13,15")    
    
    # command_packager("LD_WEIGHT,2,0,1,4")       
    
    # command_packager("LD_STEP_LEN,10,60")
    
