# -*- coding: utf-8 -*-
"""
Created on Thu Mar  9 13:28:34 2023

@author: yakovpetrukhin
"""

# PROJECT INTERNAL LIBRARIES
from fpga import FPGA, eval_outputs, start_fpga_writer, start_cts_monitor
from pipe import start_pipes
from command_handler import start_command_packager, start_command_packager_v2
from debug_log_handler import start_debug_log_packager
import global_vars

# EXTRENAL LIBRARY IMPORTS
import logging
from collections import deque
import time
import threading

def main():
    
    format = "%(asctime)s: %(message)s"
    logging.basicConfig(format=format, level=logging.INFO, datefmt="%H:%M:%S")
                    
    fpga = FPGA('COM3', 576000, exitOnFail = True)
    
    engine_return_queue = deque([])
    instruction_queue = deque([])
    tx_cmd_queue = deque([])
    debug_return_queue = deque([])
    packaged_log_queue = deque([])
    
    logging.disable(logging.CRITICAL)
    
    start_pipes(instruction_queue, engine_return_queue)
    start_command_packager_v2(instruction_queue, tx_cmd_queue, global_vars.DEBUG_MONITOR_MODE)
    start_fpga_writer(fpga, tx_cmd_queue, engine_return_queue, debug_return_queue)
    start_debug_log_packager(debug_return_queue, packaged_log_queue, True)
    
    
if __name__ == "__main__":

    main()
    
