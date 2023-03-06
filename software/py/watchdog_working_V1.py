#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Mon Jan  9 07:53:38 2023

@author: yakov
"""

import time
import logging
from queue import Queue
import threading
from pathlib import Path
import sys
import os
import serial

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
        
def error():
    logging.info("Oh no timer ran out!!!")
    os._exit(1)
    
def task( length):
    logging.info("Starting sleep.")
    time.sleep(length)
    logging.info("Task done, exiting thread")
    os._exit(1)


if __name__ =='__main__':
    
    
    format = "%(asctime)s: %(message)s"
    logging.basicConfig(format=format, level=logging.INFO, datefmt="%H:%M:%S")
    
    
    timer = watchdogTimer(2, error)
    thread = threading.Thread(target = task, args = (4.5,))
    thread.start()

