#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Wed Feb  1 02:15:21 2023

Main fpga package, enables connection and control of reading and writing to the
fpga over a serial port. 

February 7: 
Need to re-write reading and writing module. read_write_threads_V1.py
works as expected with the loop program but the functions in the fpga class don't.

RTS and CTS working weirdly. Test with read_write_threads_V1.py


@author: yakov
"""

import serial
import logging
import sys
import threading
from collections import deque
import time
from command_handler import start_command_packager, start_command_packager_v2
import global_vars
from math import ceil
#import numpy as np


shutdown = threading.Event()
cts_high = threading.Event()
watchdog_expired = threading.Event()

# For use with pipe_connected_operation_test
writing_to_fpga_done = threading.Event()
reading_back_from_fpga_done = threading.Event()
reading_back_from_fpga_done.set()

def tests(fpga, test):
    try:
        if test == "basic":
            logging.info("Starting basic test.")
            for x in range(0,255):
                fpga.write_func(bytes([((x%16)<<4)+(x%16)]))
                # time.sleep(0.05)
                response = fpga.read_func()
                # time.sleep(0.05)
        elif test == "send_rw_address": #send a read then a write, should return with value in prot_rdata, then the same address as the write address
             logging.info("Starting read address then write address test.") 
             fpga.write_func(bytes([0b00000001]))
             fpga.read_func()
             fpga.write_func(bytes([0b10000001]))
             fpga.read_func()
        elif test == "test":
            fpga.write_func(bytes([0b00000001]))
            fpga.read_func()
            fpga.write_func(bytes([0b00000010]))
            fpga.read_func()
            fpga.write_func(bytes([0b00000011]))
            fpga.read_func()
            fpga.write_func(bytes([0b10000001]))
            fpga.read_func()
            fpga.write_func(bytes([0b10000010]))
            fpga.read_func()
             
             
    except:
        Exception("Unable to connect to device.")
            


class FPGA:
    
    def __init__(self, port, baud, exitOnFail = True):
        self.comPort = port
        self.baudRate = baud
        self.queue = deque()
        logging.info("Initiating FPGA connection on COM port '%s' with baud rate '%s'.", self.comPort, self.baudRate)
        self.connect(exitOnFail)
    
    
    
    def connect(self, exitOnFail):
        try:
            # Connect to FPGA via com port. FPGA should raise CTS flag when waiting for initial instruction. 
            # When CTS is raised send a reset command to reset the FPGA
            
            self.connection = serial.Serial(port = self.comPort, baudrate = self.baudRate, rtscts = False, timeout = global_vars.READ_TIMEOUT)
            logging.info("Connection succesful!")
            time.sleep(1)
            # self.reset()
        except:
            # exit the program when not in test mode, if in test mode continue going through other functions
            logging.info("Connection failed!")
            if exitOnFail == True:
                sys.exit()
            else:
                pass       
    

    def read_func(self, num_bytes = 1, timeout = global_vars.READ_TIMEOUT):
        response = None
        timeout_counter = 0
        
        if self.connection.timeout != timeout:
            self.connection.timeout = timeout
        
        while (response == None and timeout_counter < 3):
            response = self.connection.read(num_bytes)
            if response != None:
                logging.info("Read %s.", response.hex(" ", 1))
                break
            else:
                timeout_counter += 1
                logging.info("Timed out waiting for response")
                
        return response
    
    
    
    def read_outputs(self, destination = None):
        writing_to_fpga_done.wait()
        network_status = 1
        while network_status == 1:
            self.write_func(bytes([0]))
            network_status = self.read_func()
            if network_status == None:
                raise Exception("Unable to retrieve network status")
            else:
                logging.info("Network execution completed. Reading back outputs.")
        
        output_counter_sel_addr = bytes([0x0C | 0b10000000])
        counter_output_reg = bytes([0x0D])
        
        output_counter_addr = [bytes([0x00]), # LEFT
                               bytes([0x01]), # CENTER
                               bytes([0x02])] # RIGHT
        
        outputs = [None, # LEFT
                   None, # CENTER
                   None] # RIGHT
                   
        for idx, addr in enumerate(output_counter_addr):
            logging.info("CURRENT PACKET: %s, %s",output_counter_sel_addr,addr)
            q = deque()
            q.append(output_counter_sel_addr)
            q.append(addr)
            self.write_data(q)
            self.write_func(counter_output_reg)
            outputs[idx] = int.from_bytes(self.read_func(), "big")
            logging.info("Output %d: %s",idx,outputs[idx])
            if outputs[idx] == None:
                raise Exception("Missing an output.")
                sys.exit()
            else:
                pass
        
        
        evaluated_outputs = eval_outputs(outputs)
        reading_back_from_fpga_done.set()
        if destination != None:
            destination.append(evaluated_outputs)
        else:
            return evaluated_outputs

         
                
    
    """
    This implementation of the read_func expects the FPGA to send back a response 
    once execution is complete. This is not yet implemented on the FPGA.
    """
    # def read_outputs(self):
        
    #     outputs = [None, None, None]
    #     queue = deque([0])

    #     for output, i in enumerate(outputs):
    #         output_read_failures = 0
    #         cts_high.wait()
    #         queue = deque([0, i])
            
    #         self.write_data(queue)
    #         while output_read_failures < 3:
    #             outputs[i] = self.read_func()
    #             if outputs[i] == None:
    #                 output_read_failures += 1
    #             else:
    #                 logging.info("Received output byte: %s", outputs[i])
    #                 break
    #         if output_read_failures == 3:
    #             logging.warning("Unable to receive outputs.")
    #             sys.exit()
    #         else:
    #             logging.warning("Received the following data bytes: %s, %s, %s", outputs[0], output[1], outputs[2])
        
    #     return outputs
    
    # This function send s a single byte to the fpga. The name
    # is a bit misleading and the function should be interpreted as send_func
    def write_func(self, byte_to_send):
        try:
            self.connection.reset_input_buffer()
            self.connection.reset_output_buffer()
            self.connection.write(byte_to_send)
            self.connection.flush()
            logging.info("Sent %s.", byte_to_send.hex(" ",1))
            return None
        except: 
            logging.info("Unable to send byte, check connection.")
            
     
    def fpga_writer(self, source, destination = None, debug_destination = None):
        
        while True:
            
            if global_vars.shutdown.is_set():
                logging.info("Shutting down NN Iterator thread.")
                break
            else:
                pass

            
            if (len(source) !=  0) and (source[0] == "EXIT"):
                logging.info("Received EXIT in tx_queue. Shutting down FPGA connection.")
                destination.append("EXIT")
                debug_destination.append("EXIT")
                self.connection.close()
                break
            
            
            elif (len(source) !=  0) and bytes([source[0][1]]) == bytes([0xFF]) :

                message = source.popleft()
                logging.info("Message to send: %s", message.hex(" ",1))
                self.write_func(message) # send an input string to the FPGA
                
                ## Poll FPGA for a response
                
                error = True
                outputs = None
                
                
                for x in range(3):
                    
                    response = self.read_func(4)
                    
                    # Check if any data was received, or if the data received 
                    # indicates that the network excution is incomplete "0"
                    if response == bytes():
                        logging.info("No response received.")
                        
                    elif response[0] == 1:
                        logging.info("Execution not yet complete.")
                        
                    elif response[0] == 0:
                        
                        logging.info("Execution complete. Reading outputs")
                        
                        _ , *outputs = response
                                                
                        if len(outputs) < global_vars.NUM_OUTPUTS:
                            logging.info("Not enough outputs received. Trying %s more times",(2-x))
                            if x == 2 :
                                logging.info("Exiting.")
                                self.connection.close()
                                sys.exit()
                            else:
                                error = False
                                break
                    else:
                        logging.info("Unknown response received. Shutting down FPGA connections.")
                        self.connection.close()
                        sys.exit()


                    logging.info("ERROR: %s, X: %s", error,x)
                    
                    if (error == True) and (x == 2):
                        logging.info("Unable to recover data. Exiting program.")
                        sys.exit()
                        
                    elif outputs != None:
                        
                        evaluated_outputs = eval_outputs(outputs)
                        
                        if destination != None:
                            destination.append(evaluated_outputs)
                        else:
                            logging.info("RESPONSE: %s",evaluated_outputs)
                            #return evaluated_outputs
                        break
                    else:
                        pass
            
            elif (len(source) !=  0) and bytes([source[0][1]]) == bytes([0x55]):
                message = source.popleft()
                logging.info("Message to send: %s", message.hex(" ",1))
                self.write_func(message) # send an input string to the FPGA
                

            elif (len(source) !=  0) and bytes([source[0][1]]) == bytes([0xAA]):
                message = source.popleft()
                logging.info("Message to send: %s", message.hex(" ",1))
                self.write_func(message) # send an input string to the FPGA
                # Determine how many bytes to read based on number of inputs
                if global_vars.NUM_NEURONS%8 == 0:
                    num_bytes_to_read = (global_vars.NUM_NEURONS/8)*global_vars.NUM_TIMESTEPS
                    logging.info("Reading debug monitor log. %s bytes.", num_bytes_to_read)
                    debug_log = self.read_func(num_bytes_to_read)
                else:
                    num_bytes_to_read = ceil(global_vars.NUM_NEURONS/8)*global_vars.NUM_TIMESTEPS
                    logging.info("Reading debug monitor log. %s bytes.", num_bytes_to_read)
                    debug_log = self.read_func(num_bytes_to_read)
                    
                    if debug_destination != None:
                        debug_destination.append(debug_log)


                    
                    
                
            else:
                pass
                    


    def write_data(self, source):
        logging.info("Starting FPGA writer")
        # logging.warning("Starting to send data in queue.")
        while len(source)>0:
            reading_back_from_fpga_done.wait()
            if len(source) != 0:
                address_byte = source.popleft()
                data_byte = source.popleft()
                logging.info("Current packet: %s, %s", address_byte.hex(), data_byte.hex())            
                address_failures = 0
                data_failures = 0
                
                while address_failures < 3 and data_failures < 3:
                    # logging.info("Waiting for CTS")
                    # cts_high.wait()
                    # logging.info("CTS is high, starting to write")
                    logging.warning("Sending address: %s", address_byte.hex())
                    self.write_func(address_byte)
                    address_response = self.read_func()
                    if address_response == None or address_response != address_byte:
                        logging.info("Failed to send address")
                        address_failures += 1
                        continue
                    else:
                        logging.warning("Received address: %s", address_response.hex())
                    
                    logging.warning("Sending data: %s", data_byte.hex())
                    self.write_func(data_byte)
                    
                    data_response = self.read_func()
                    if data_response == None or data_response != data_byte:
                        logging.info("Failed to send data")
                        data_failures += 1
                        continue
                    else:
                        logging.info("Received data byte: %s", data_response.hex())
                        break
                        
                if address_failures == 3 or data_failures == 3:
                    logging.warning("Unable to send data")
                    # self.connection.close()
                    # sys.exit()
            else:
                writing_to_fpga_done.set()
                # continue
            
        logging.info("Shutting down FPGA writer")
            # logging.warning("All data in queue sent.")

def eval_outputs(outputs):           

    if ((outputs[0] > outputs[1]) and (outputs[0] > outputs[2])):
        return "LEFT"    
    elif ((outputs[1] >= outputs[0]) and (outputs[1] >= outputs[2])):
        return "CENTER"   
    else:
        return "RIGHT"
    


def cts_monitor(fpga):

    while fpga.connection.is_open:
        # Check game engine queue status and set flags accordingly

        if fpga.connection.rts and not cts_high.is_set():
            cts_high.set()
            logging.info("Raising CTS")
        elif not fpga.connection.rts:
            logging.info("Lowering CTS")
            cts_high.clear()
            # logging.warning("No conditions met.")
        else:
            continue
    
def start_cts_monitor(fpga):
    logging.info("CTS monitor thread started.")
    monitor = threading.Thread(name = "cts_monitor", target = cts_monitor, args = (fpga,), daemon = True)
    monitor.start()
    
def start_temp_fpga_writer(fpga, source_arr):
    logging.info("FPGA writer thread started.")
    writer = threading.Thread(name = "FPGA writer", target = fpga.write_data, args = (source_arr,), daemon = True)
    writer.start()
    
def start_fpga_writer(fpga, source_arr, dest_arr = None, debug_dest_arr = None):
    logging.info("FPGA Writer thread started.")
    writer = threading.Thread(name = "FPGA Writer", target = fpga.fpga_writer, args = (source_arr,dest_arr,debug_dest_arr,), daemon = True)
    writer.start()
    
       
if __name__ == "__main__":
    
    format = "%(asctime)s: %(message)s"
    logging.basicConfig(format=format, level=logging.DEBUG, datefmt="%H:%M:%S")
                    
    fpga = FPGA('COM3', 576000, exitOnFail = True)
    
    input_cmd = [
                "SET_NUM_PERIODS,500",
                'LD_INPUT,1,0',
                'LD_INPUT,2,0',
                'LD_INPUT,3,0',
                'LD_INPUT,4,0',
                'LD_INPUT,5,0',
                'LD_INPUT,6,0',
                'LD_INPUT,7,0',
                'LD_INPUT,8,0',
                'LD_INPUT,9,0',
                'LD_INPUT,10,0',
                'LD_INPUT,11,0',
                'LD_INPUT,12,5',
                'LD_INPUT,13,0',
                'LD_INPUT,14,0',
                'LD_INPUT,15,0',
                'LD_INPUT,16,0',
                'LD_INPUT,17,0',
                'LD_INPUT,18,0',
                'LD_INPUT,19,0',
                'LD_INPUT,20,0',
                'LD_INPUT,21,0',
                'LD_INPUT,22,0',
                'LD_INPUT,23,0',
                "RUN_EXECUTION",
                "READ_DEBUG_MONITOR",
                "SET_NUM_PERIODS,500",
                'LD_INPUT,1,0',
                'LD_INPUT,2,0',
                'LD_INPUT,3,0',
                'LD_INPUT,4,0',
                'LD_INPUT,5,0',
                'LD_INPUT,6,0',
                'LD_INPUT,7,0',
                'LD_INPUT,8,0',
                'LD_INPUT,9,0',
                'LD_INPUT,10,0',
                'LD_INPUT,11,0',
                'LD_INPUT,12,5',
                'LD_INPUT,13,0',
                'LD_INPUT,14,0',
                'LD_INPUT,15,0',
                'LD_INPUT,16,0',
                'LD_INPUT,17,0',
                'LD_INPUT,18,0',
                'LD_INPUT,19,0',
                'LD_INPUT,20,0',
                'LD_INPUT,21,0',
                'LD_INPUT,22,0',
                'LD_INPUT,23,0',
                "RUN_EXECUTION",
                "READ_DEBUG_MONITOR",
                "SET_NUM_PERIODS,500",
                'LD_INPUT,1,0',
                'LD_INPUT,2,0',
                'LD_INPUT,3,0',
                'LD_INPUT,4,0',
                'LD_INPUT,5,0',
                'LD_INPUT,6,0',
                'LD_INPUT,7,0',
                'LD_INPUT,8,0',
                'LD_INPUT,9,0',
                'LD_INPUT,10,0',
                'LD_INPUT,11,0',
                'LD_INPUT,12,5',
                'LD_INPUT,13,0',
                'LD_INPUT,14,0',
                'LD_INPUT,15,0',
                'LD_INPUT,16,0',
                'LD_INPUT,17,0',
                'LD_INPUT,18,0',
                'LD_INPUT,19,0',
                'LD_INPUT,20,0',
                'LD_INPUT,21,0',
                'LD_INPUT,22,0',
                'LD_INPUT,23,0',
                "RUN_EXECUTION",
                "READ_DEBUG_MONITOR",
                "SET_NUM_PERIODS,500",
                'LD_INPUT,1,0',
                'LD_INPUT,2,0',
                'LD_INPUT,3,0',
                'LD_INPUT,4,0',
                'LD_INPUT,5,0',
                'LD_INPUT,6,0',
                'LD_INPUT,7,0',
                'LD_INPUT,8,0',
                'LD_INPUT,9,0',
                'LD_INPUT,10,0',
                'LD_INPUT,11,0',
                'LD_INPUT,12,5',
                'LD_INPUT,13,0',
                'LD_INPUT,14,0',
                'LD_INPUT,15,0',
                'LD_INPUT,16,0',
                'LD_INPUT,17,0',
                'LD_INPUT,18,0',
                'LD_INPUT,19,0',
                'LD_INPUT,20,0',
                'LD_INPUT,21,0',
                'LD_INPUT,22,0',
                'LD_INPUT,23,0',
                "RUN_EXECUTION",
                "READ_DEBUG_MONITOR",
                "SET_NUM_PERIODS,500",
                'LD_INPUT,1,0',
                'LD_INPUT,2,0',
                'LD_INPUT,3,0',
                'LD_INPUT,4,0',
                'LD_INPUT,5,0',
                'LD_INPUT,6,0',
                'LD_INPUT,7,0',
                'LD_INPUT,8,0',
                'LD_INPUT,9,0',
                'LD_INPUT,10,0',
                'LD_INPUT,11,0',
                'LD_INPUT,12,5',
                'LD_INPUT,13,0',
                'LD_INPUT,14,0',
                'LD_INPUT,15,0',
                'LD_INPUT,16,0',
                'LD_INPUT,17,0',
                'LD_INPUT,18,0',
                'LD_INPUT,19,0',
                'LD_INPUT,20,0',
                'LD_INPUT,21,0',
                'LD_INPUT,22,0',
                'LD_INPUT,23,0',
                "RUN_EXECUTION",
                "READ_DEBUG_MONITOR",
                "SET_NUM_PERIODS,500",
                'LD_INPUT,1,0',
                'LD_INPUT,2,0',
                'LD_INPUT,3,0',
                'LD_INPUT,4,0',
                'LD_INPUT,5,0',
                'LD_INPUT,6,0',
                'LD_INPUT,7,0',
                'LD_INPUT,8,0',
                'LD_INPUT,9,0',
                'LD_INPUT,10,0',
                'LD_INPUT,11,0',
                'LD_INPUT,12,5',
                'LD_INPUT,13,0',
                'LD_INPUT,14,0',
                'LD_INPUT,15,0',
                'LD_INPUT,16,0',
                'LD_INPUT,17,0',
                'LD_INPUT,18,0',
                'LD_INPUT,19,0',
                'LD_INPUT,20,0',
                'LD_INPUT,21,0',
                'LD_INPUT,22,0',
                'LD_INPUT,23,0',
                "RUN_EXECUTION",
                "READ_DEBUG_MONITOR",
                "SET_NUM_PERIODS,500",
                'LD_INPUT,1,0',
                'LD_INPUT,2,0',
                'LD_INPUT,3,0',
                'LD_INPUT,4,0',
                'LD_INPUT,5,0',
                'LD_INPUT,6,0',
                'LD_INPUT,7,0',
                'LD_INPUT,8,0',
                'LD_INPUT,9,0',
                'LD_INPUT,10,0',
                'LD_INPUT,11,0',
                'LD_INPUT,12,5',
                'LD_INPUT,13,0',
                'LD_INPUT,14,0',
                'LD_INPUT,15,0',
                'LD_INPUT,16,0',
                'LD_INPUT,17,0',
                'LD_INPUT,18,0',
                'LD_INPUT,19,0',
                'LD_INPUT,20,0',
                'LD_INPUT,21,0',
                'LD_INPUT,22,0',
                'LD_INPUT,23,0',
                "RUN_EXECUTION",
                "READ_DEBUG_MONITOR",
                "SET_NUM_PERIODS,500",
                'LD_INPUT,1,0',
                'LD_INPUT,2,0',
                'LD_INPUT,3,0',
                'LD_INPUT,4,0',
                'LD_INPUT,5,0',
                'LD_INPUT,6,0',
                'LD_INPUT,7,0',
                'LD_INPUT,8,0',
                'LD_INPUT,9,0',
                'LD_INPUT,10,0',
                'LD_INPUT,11,0',
                'LD_INPUT,12,5',
                'LD_INPUT,13,0',
                'LD_INPUT,14,0',
                'LD_INPUT,15,0',
                'LD_INPUT,16,0',
                'LD_INPUT,17,0',
                'LD_INPUT,18,0',
                'LD_INPUT,19,0',
                'LD_INPUT,20,0',
                'LD_INPUT,21,0',
                'LD_INPUT,22,0',
                'LD_INPUT,23,0',
                "RUN_EXECUTION",
                "READ_DEBUG_MONITOR",
                "SET_NUM_PERIODS,500",
                'LD_INPUT,1,0',
                'LD_INPUT,2,0',
                'LD_INPUT,3,0',
                'LD_INPUT,4,0',
                'LD_INPUT,5,0',
                'LD_INPUT,6,0',
                'LD_INPUT,7,0',
                'LD_INPUT,8,0',
                'LD_INPUT,9,0',
                'LD_INPUT,10,0',
                'LD_INPUT,11,0',
                'LD_INPUT,12,5',
                'LD_INPUT,13,0',
                'LD_INPUT,14,0',
                'LD_INPUT,15,0',
                'LD_INPUT,16,0',
                'LD_INPUT,17,0',
                'LD_INPUT,18,0',
                'LD_INPUT,19,0',
                'LD_INPUT,20,0',
                'LD_INPUT,21,0',
                'LD_INPUT,22,0',
                'LD_INPUT,23,0',
                "RUN_EXECUTION",
                "READ_DEBUG_MONITOR"]


    instruction_queue = deque(input_cmd)
    tx_cmd_queue = deque()
    
    debug_dest = []
    
    start_command_packager_v2(instruction_queue, tx_cmd_queue)
    start_fpga_writer(fpga, tx_cmd_queue, debug_dest_arr = debug_dest)
    

    
    
    
