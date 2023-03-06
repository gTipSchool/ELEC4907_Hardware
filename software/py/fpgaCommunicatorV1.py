#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Sat Jan  7 17:38:18 2023

@author: yakov
"""

# ==========================================================================================================================================================
# CHANGE LOG
#
# Classes created [Jan 7, 2023]
# Inital loop waiting for CTS created [Jan 8, 2023]
# Watchdog timer added [Jan 9, 2023]
# Watchdog timer tested and working [Jan 11, 2023]
# Read write thread created and working [Jan 12, 2023]
# Manual CTS raise programmed [Jan 18, 2023]
# FPGA Connection established and working [Jan 19, 2023]
# Rewrote reader and writer thread to be continuous [Jan 24, 2023]
#
# ==========================================================================================================================================================

# ==========================================================================================================================================================
# REQUIRED CHANGES
#
# RESOLVED: Add built in test in .connect() method to verify connection --> send some phrase back and forth and confirm it works [Jan 7, 2023]
# Reader and writer thread should stay active. Reader should be a daemon. Writer should be activated by flag.
# Determine maximum error free baud rate
# Set a write location in the readerThread module
# Include logging statements in new threaded 
# 
#
# ==========================================================================================================================================================

import sys
import serial
import time
import logging
import threading
import queue

# FPGA connection class -> verifies serial connection and enables reset, data sending and receiving, and sending acknowledgement
class FPGA:
    
    def __init__(self, port, baud, exitOnFail = True):
        self.comPort = port
        self.baudRate = baud
        logging.info("Initiating FPGA connection on COM port '%s' with baud rate '%s'.", self.comPort, self.baudRate)
        self.connect(exitOnFail)
    
    
        
    def connect(self, exitOnFail):
        try:
            # Connect to FPGA via com port. FPGA should raise CTS flag when waiting for intial instruction. 
            # When CTS is raised send a reset command to reset the FPGA
            
            self.connection = serial.Serial(port = self.comPort, baudrate = self.baudRate)
            logging.info("Connection succesful!")
            time.sleep(3)
            # self.reset()
        except:
            # exit the program when not in test mode, if in test mode continue going through other functions
            logging.info("Connection failed!")
            if exitOnFail == True:
                sys.exit()
            else:
                pass            
    
    def reset(self):
        try:
            logging.info("Resetting FPGA")
            # fpga.sendData(FPGA_RESET) TURN ON AFTER TESTING
        except: 
            logging.info("Unable to reset FPGA. Exiting program.")
            sys.exit()
        
    
    def sendData(self, dataList):
        logging.info("Sending following data list: ")
        
        
    def sendDataByte(self, intItem):
        writing_done.clear()
        bytesItem = bytes(intItem)
        logging.info("Writer thread started. Writing flag set.")
        logging.info("Sending data byte")
        self.connection.write(bytesItem)
        self.connection.flush()
        self.connection.reset_output_buffer()
        logging.warning("Byte sent: %s. Clearing writing flag.", bytesItem.hex())
        logging.info("Exiting writer thread.")
        writing_done.set()
        
                
    def writerThread(self, game_engine_queue):
        while True:
            if engine_data_present.is_set():
                writing_serial.set()
                writing_done.clear()
                byte_to_send = game_engine_queue.get()
                logging.warning("Sending byte: %s", byte_to_send.hex())
                self.connection.write(byte_to_send)
                self.connection.flush()
                self.connection.reset_output_buffer()
            else:
                logging.debug("Writing done, all data sent. Clearing writing flag, and raising writing done flag.")
                writing_serial.clear()
                writing_done.set()


    # Initial implementation of reader thread. In this implementation the reader thread 
    def readData(self, loop = True, bytes_to_read = 1):
        
        # Read loop with timeouts.
        self.data_read = False
        logging.info("Starting reader thread. Waiting for writer thread to finish.")
        writing_done.wait()
        logging.info("Writer thread finished.")
        reading_done.clear()
        logging.info('Reading flag set.')
        if loop == False:
            while self.data_read == False:
                self.lastReadData = self.connection.read(bytes_to_read)
                self.connection.reset_input_buffer()
                logging.warning("Byte read: %s", self.lastReadData.hex())
                self.data_read = True
        else:
            while True:
                self.lastReadData = self.connection.read(bytes_to_read)
                self.connection.reset_input_buffer()
                logging.warning("Byte read: %s", self.lastReadData.hex())
            
        logging.info("Exiting reader thread.")
        reading_done.set()
        
    def readerThread(self, write_location, bytes_to_read = 1):
        while True:
            bytes_waiting = self.connection.in_waiting
            if (fpga_data_present.is_set() and not writing_serial.is_set()):
                logging.info("Writer done writing. Setting reading flag and starting to read data.")
                reading_serial.set()
                self.lastReadData = self.connection.read(bytes_to_read)
                self.connection.reset_input_buffer()
                logging.warning("Byte read: %s", self.lastReadData.hex())
                if bytes_waiting == 0:
                    
                    fpga_data_present.clear()
                    reading_serial.clear()
                else:
                    pass
            else:
                if bytes_waiting > 0:
                    logging.info("FPGA data present in COM port input buffer, setting FPGA data flag")
                    fpga_data_present.set()
                else:
                    pass
        
    def sendACK(self):
        pass
        
    def checkCTS(self):
        pass 
    
    def raiseRTS(self):
        logging.info("Setting RTS high.")
        self.connection.setRTS(True)
        logging.info("RTS high. Waiting for CTS.")
        

class watchdogTimer(Exception):
    
    def __init__(self, lengthSeconds, errorHandler = None):
        self.timerLength = lengthSeconds
        self.errorHandler = errorHandler if errorHandler != None else self.defaultErrorHandler
        logging.info("Starting %s second watchdog timer.", self.timerLength)
        self.timer = threading.Timer(self.timerLength, self.errorHandler)
        self.timer.start()

    def reset(self):
        self.timer.cancel()
        logging.info("Restarting %s second watchdog timer.", self.timerLength)
        self.timer = threading.Timer(self.timerLength, self.errorHandler)
        self.timer.start()
    
    def stop(self):
        logging.info("Stopping %s second watchdog timer.", self.timerLength)
        self.timer.cancel()
        
    def defaultErrorHandler(self):
        logging.info("Watchdog timer expired. Exiting program.")
        raise self
    

class inputPipe:   
    
    def __init__(self):
        pass
       

class outputPipe:
    
    def __init__(self):
        pass

## THREAD STARTING FUNCTIONS

def startWriterThread(fpga, dame_engine_q):
    logging.info("Starting writer thread.")
    writer = threading.Thread(name = "WriterThread",target = fpga.writerThread, args = (game_engine_q,), daemon = True)
    return writer

def startReaderThread(fpga, fpga_q):
    logging.info("Starting reader thread.")
    reader = threading.Thread(name = "ReaderThread", target = fpga.readerThread, args = (fpga_q, 1), daemon = True)
    return reader

def startFlagMonitorThread(game_engine_q):
    logging.info("Starting flag monitor thread.")
    monitor = threading.Thread(name = "MonitorThread", target = flagMonitor, args = (game_engine_q,), daemon = True)
    return monitor

## FUNCTIONS

def flagMonitor(game_engine_q):
    while True:
        # Check game engine queue status and set flags accordingly
        logging.debug("Monitoring thread running")
        if (game_engine_q.qsize() > 0 and not engine_data_present.is_set()):
            logging.warning("Game engine data available in queue. Setting game engine data flag.")
            engine_data_present.set()
        elif (game_engine_q.qsize() == 0 and engine_data_present.is_set()):
            logging.warning("Game engine data queue empty. Removing game engine data flag.")
            engine_data_present.clear()
        else:
            # logging.warning("No conditions met.")
            pass
    



# def initialize_nn(fpga, data = None, pipe  = None):
#     # Create bytes data to send to the FPGA in initialization process
#     if (data != None) and (pipe == None):
#         logging.info("Using test data for initialization.")
#         initialization_data = []
#         for val in data:
#             initialization_data.append(bytes([val]))
#         logging.info("Initialization data to be used: %s", initialization_data)
#     elif (data == None) and (pipe != None):
#         logging.info("Using environment data from pipe.")
#         pass
#     else:
#         logging.info("No data to initialize the FPGA with. Exiting program.")
#         sys.exit()
        
#     # Raise RTS flag. If FPGA was correctly started, connected to, and reset then the CTS wire should
#     # return high within 1 second of raising RTS flag

#     fpga.raiseRTS()
    
#     ## WIP
    

def cts_timeout():
    raise Exception("Timed out waiting for CTS. Check FPGA and connection. Exiting program.")


# =============================================================================
#   FLAGS

manualCTS = True

# =============================================================================
#   THREAD-SAFE FLAGS

timeoout = threading.Event()
cts_high = threading.Event()

reading_done = threading.Event() # deprecated used for initial writer/reader threads
writing_done = threading.Event() # deprecated used for initial writer/reader threads

reading_serial = threading.Event()
writing_serial = threading.Event()

fpga_data_present = threading.Event()
engine_data_present = threading.Event()

# =============================================================================
#   CONSTANT DECLARATIONS

FPGA_RESET = [0x00, 0xFF]
FPGA_ACK = [0x00, 0xC3]

# =============================================================================


if __name__ == '__main__':
    
    # Logging setting:
    # DEBUG - Captures flag changes
    # INFO - Captures thread activations
    # WARNING - Captures data transmission from reader/writer threads

    
    format = "%(asctime)s: %(message)s"
    logging.basicConfig(format=format, level=logging.WARNING, datefmt="%H:%M:%S")
    
    # # Initialize data input pipe from game engine
    # logging.info("Input data pipe initialized. WIP")

    # # Initialize command input pipe from game engine
    # logging.info("Input command pipe initialized. WIP")

    # # Initialize output to game engine pipe
    # logging.info("Output data pipe initialized. WIP")    
    
    # Initialize FPGA connection
    logging.info("Beginning FPGA initialization.")
    fpga = FPGA('/dev/cu.usbmodem1301', 115200, exitOnFail = True)
    
    # # Initialize Keyboard monitoring thread
    # if manualCTS = True:
    #     logging.info("Manual CTS Enabled. Press C to raise CTS")
    #     keyboard_thread = threading.Thread(target = manualRaiseCTS, args = (), daemon = True)
    #     keyboard_thread.start()
    # else:
    #     pass
    
    # Initialize FPGA Neural Network
    ## PROTOCOL VERIFICATION: FOR NOW JUST SENDS RANDOM DATA 
    
    # Test Bench  
    # 1. Initialize data queue, writer thread, reader thread, queue monitor
    
    game_engine_q = queue.Queue(0)
    fpga_q = queue.Queue(0)
    
    monitor = startFlagMonitorThread(game_engine_q)
    monitor.start()

    reader = startReaderThread(fpga, fpga_q)
    reader.start()
    
    writer = startWriterThread(fpga, game_engine_q)
    writer.start()
    
    # 2. Simulate receiving from data pipe
    # array = [0x11,0x22,0x33,0x44,0x55,0x66,0x77,0x88,0x99]
    # array = [0x00]
    array = [1,15,2,15,3,0,1,10,3,100,4,0,2,10,4,200,5,0,3,5,5,1,4,2,6,0,4,5,0,1]
    
    # 3. Convert array to bytes & append each byte to the Queue
    bytes_to_send = bytes(array)
    for i in range(len(bytes_to_send)):
        current_byte = bytes_to_send[i:i+1]
        game_engine_q.put(current_byte)
        logging.info("Placed %s into game engine queue.", current_byte)
            
    # 4. The writer and reader thread should automatically execute the protocol
    #    Just need to run a forever loop now
    
    while True:
        pass
        
 
    
    
    
    
    
    
    
    
    
    
    # # NOT SURE IF NEEDED
    # # Initialize game engine data queue. This is the data being sent from the game environment to the FPGA
    # logging.info("Preparing neural network initialization data.")
    # initialize_data = [0x55, 0x67, 0x88, 0x89] ## test data
    # initialize_nn(fpga, initialize_data)
    
    # try:
    #     while run == True:
    #         if fpga.checkCTS() == True:
    #             logging.info("CTS high, sending data to FPGA.")
    #         else:
    #             logging.info("CTS low, waiting for FPGA execution to complete.")

    # except KeyboardInterrupt:
    #     logging.info("Quit on Keyboard Interupt.")
    #     sys.exit()
        