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
from command_handler import start_command_packager

shutdown = threading.Event()
cts_high = threading.Event()
watchdog_expired = threading.Event()

def tests(fpga, test):
    try:
        if test == "basic":
            logging.info("Starting basic test.")
            for x in range(0,30):
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
            
            self.connection = serial.Serial(port = self.comPort, baudrate = self.baudRate, rtscts = False, timeout = 0.1)
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
    

    def read_func(self):
        response = None
        timeout_counter = 0
        
        while (response == None and timeout_counter < 3):
            response = self.connection.read(1)
            if response != None:
                logging.info("Read %s.", response)
                break
            else:
                timeout_counter += 1
                logging.info("Timed out waiting for response")
                
        return response
    
    
    def read_outputs(self):
        
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
        
        return outputs
            

         
                
    
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
            logging.info("Sent %s.", byte_to_send)
            return None
        except: 
            logging.info("Unable to send byte, check connection.")
            
        
    def write_data(self, source):
        logging.warning("Starting to send data in queue.")
        while len(source) != 0:
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
                self.connection.close()
                sys.exit()
        logging.warning("All data in queue sent.")

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
    
       
if __name__ == "__main__":
    
    format = "%(asctime)s: %(message)s"
    logging.basicConfig(format=format, level=logging.INFO, datefmt="%H:%M:%S")
                    
    fpga = FPGA('COM3', 576000, exitOnFail = True)
    
    # start_cts_monitor(fpga)
    
    tests(fpga, "tests") # "tests"
    
    if fpga.connection.is_open:
        fpga.connection.close()
    
    
