#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Tue Jan 10 20:02:37 2023

@author: yakov
"""

import sys
import serial
import time
import logging
import threading
import keyboard
from queue import Queue

#CONSTANT DECLARATIONS
FPGA_RESET = [0x00, 0xFF]
FPGA_ACK = [0x00, 0xC3]

# FPGA connection class -> verifies serial connection and enables reset, data sending and receiving, and sending acknowledgement
class FPGA:
    
    def __init__(self, port, baud, exitIfFailed = True):
        self.comPort = port
        self.baudRate = baud
        logging.info("Initiating FPGA connection on COM port '%s' with baud rate '%s'.", self.comPort, self.baudRate)
        self.connect(exitIfFailed)
    
    
        
    def connect(self, exitOnFail):
        try:
            # Connect to FPGA via com port. FPGA should raise CTS flag when waiting for intial instruction. 
            # When CTS is raised send a reset command to reset the FPGA
            
            self.connection = serial.Serial(port = self.comPort, baudrate = self.baudRate)
            logging.info("Connection succesful!")
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
        
    def sendDataByte(self, bytesItem):
        logging.info("Writer thread started. Writing flag set.")
        logging.info("Sending data byte")
        self.connection.write(bytesItem)
        self.connection.flush()
        logging.warning("Byte sent: %s. Clearing writing flag.", bytesItem)
        logging.info("Exiting writer thread.")
        writing_done.set()


    
    def readData(self):
        
        # Read loop with timeouts.
        
        logging.info("Starting reader thread. Waiting for writer thread to finish.")
        writing_done.wait()
        logging.info("Writer thread finished.")
        reading_done.clear()
        logging.info('Reading flag set.')
        self.lastReadData = self.connection.read(10)
        self.connection.reset_input_buffer()
        logging.warning("Byte read:")
        logging.info("Exiting reader thread.")
        reading_done.set()
        
        # Single read Version (DOEST WORK WELL)
        
        # logging.info("Starting reader thread. Waiting for writer thread to finish.")
        # writing.wait()
        # logging.info("Writer thread finished.")
        # reading.set()
        # logging.info('Reading flag set.')
        # self.lastReadData = self.connection.read(2)
        # self.connection.flush()
        # logging.info("Byte read: %s", self.lastReadData)
        # logging.info("Exiting reader thread.")
        # reading.clear()


        
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

def manualRaiseCTS():
    while True:  # making a loop
        try:  # used try so that if user pressed other than the given key error will not be shown
            if keyboard.is_pressed('c'):  # if key 'c' is pressed 
                logging.info("CTS High! Starting Transmssion")
                ctsHigh.set()
                break  # finishing the loop
        except:
            pass
            

def startReaderThread(fpga, receive_loop = False, bits_to_receive = 1):
    reader = threading.Thread(target = fpga.readData, args = (receive_loop, bits_to_receive,), daemon = True)
    return reader
                                                               
        
long_message_even = [0x00, 0xFF, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66]
long_message_odd = [0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66]

timeoout = threading.Event()
ctsHigh = threading.Event()
reading_done = threading.Event()
writing_done = threading.Event()

format = "%(asctime)s: %(message)s"
logging.basicConfig(format=format, level=logging.INFO, datefmt="%H:%M:%S")

logging.info("Waiting for CTS.")
    
keyboard_thread = threading.Thread(target = manualRaiseCTS, args = (), daemon = True)
keyboard_thread.start()

fpga = FPGA('/dev/cu.usbmodem11201', 115200, exitIfFailed = True)

reader = startReaderThread(fpga)

while True:
    if not ctsHigh.is_set():
        pass
    else:
        break

## TEST CASE 1: 
# Thread monitoring the keyboard for c key press
# Main thread exits on CTS high



