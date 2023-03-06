#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Tue Jan 10 20:02:37 2023

February 7: Added rts and cts monitor thread. NOTE: they make communication extremely slow.

Need to check if checking rts/cts is equally slow when done sequentially in a function, 
but a monitor thread will make cmmunications brutally slow.

@author: yakov
"""

import sys
import serial
import time
import logging
import threading
from queue import Queue

#CONSTANT DECLARATIONS
FPGA_RESET = [0x00, 0xFF]
FPGA_ACK = [0x00, 0xC3]

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
            
            self.connection = serial.Serial(port = self.comPort, baudrate = self.baudRate, rtscts = False)
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
        logging.info("Watchdog timer expired.")
        raise self
        
def startWriterThread(fpga, data_list):
    writing_done.clear()
    writer = threading.Thread(target = fpga.sendDataByte, args = (data_list,))
    return writer

def startReaderThread(fpga, receive_loop = False, bits_to_receive = 1):
    reader = threading.Thread(target = fpga.readData, args = (receive_loop, bits_to_receive,))
    return reader
                                                  
        
long_message_even = [0x00, 0xFF, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66]
long_message_odd = [0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66]

timeoout = threading.Event()
ctsHigh = threading.Event()
ctsLow = threading.Event()
rtsHigh = threading.Event()
rtsLow = threading.Event()

reading_done = threading.Event()
writing_done = threading.Event()

def ctsMonitor(fpga):
    
    logging.error("CTS Low.")
    prev = False
    
    while fpga.connection.is_open:
        if fpga.connection.cts:
            ctsHigh.set()
            if prev == False:
                logging.error("CTS Switched High.")
            prev = True
        else:
            ctsHigh.clear()
            if prev == True:
                logging.error("CTS Switched Low.")
            prev = False
    
def rtsMonitor(fpga):
    
    logging.error("RTS Low.")
    prev = False

    while fpga.connection.is_open:
        if fpga.connection.rts:
            rtsHigh.set()
            if prev == False:
                logging.error("RTS Switched High.")
            prev = True
        else:
            rtsHigh.clear()
            if prev == True:
                logging.error("RTS Switched Low.")
            prev = False

if __name__ =="__main__":

    format = "%(asctime)s: %(message)s"
    logging.basicConfig(format=format, level=logging.WARNING, datefmt="%H:%M:%S")
    
    fpga = FPGA('COM3', 576000, exitOnFail = True)
    time.sleep(3)
    # rts_monitor = threading.Thread(target = rtsMonitor, args = (fpga,), daemon = True)
    # rts_monitor.start()
    # cts_monitor = threading.Thread(target = ctsMonitor, args = (fpga,), daemon = True)
    # cts_monitor.start()

    ## Test Case 1: Send a byte, and receive it back
    
    # writer = startWriterThread(fpga, [0xff])
    # reader = threading.Thread(target = fpga.readData, args = ())
    # writer.start()
    # reader.start()
    
    ## Test Case 2: Continuously read from the COM port
    
    # writing_done.set()
    # reader = threading.Thread(target = fpga.readData, args = (True,))
    # reader.start()
    
    ## Test Case 3: Continuously send data back and forth
    
    for i in range(256):
        writer = startWriterThread(fpga, [i])
        reader = startReaderThread(fpga)
        writer.start()
        reader.start()
        reader.join()
    
    ## Test Case 4: Continuously send data to COM port
    
    # for i in range(10):
    #     writer = startWriterThread(fpga, [i*10])
    #     writer.start()
    #     writer.join()
    #     time.sleep(3)
    
    fpga.connection.close()
    
