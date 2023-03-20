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

FPGA_PRECISION = 2
NUMBER_OF_NEURONS = 6

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
                input_current = int(args[1]*FPGA_PRECISION,10).to_bytes(3, "big")
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
            
            for i in range(len(byte_string)):
                tx_cmd_queue.append(bytes([byte_string[i]]))
            
        else:
            continue
        

def start_command_packager(instruction_queue, tx_cmd_queue):
    packager = threading.Thread(name = "command_packager", target = command_packager, args = (instruction_queue, tx_cmd_queue,), daemon = True)
    packager.start()
    logging.debug("Starting Command Packager Thread.")
    


        

            
if __name__ == "__main__":
             
    format = "%(asctime)s: %(message)s"
    logging.basicConfig(format=format, level=logging.DEBUG, datefmt="%H:%M:%S")
    
    # 4 neuron test instruction set
    instruction_queue = deque(['LD_INPUT,1,15',
                               "LD_WEIGHT,2,0,1,4",
                               "LD_WEIGHT,2,1,2,10",
                               "LD_WEIGHT,2,2,3,-5",
                               "LD_STEP_LEN,10,60",
                               "LD_WEIGHT,3,0,2,5",
                               "LD_WEIGHT,3,1,3,5",
                               "LD_WEIGHT,4,0,1,5",
                               "SET_NUM_PERIODS,3000",
                               "RUN_EXECUTION"])
    tx_cmd_queue = deque()

    start_command_packager(instruction_queue, tx_cmd_queue)
        
        
    # command_packager("LD_INPUT,13,15")    
    
    # command_packager("LD_WEIGHT,2,0,1,4")       
    
    # command_packager("LD_STEP_LEN,10,60")
    
