
# -*- coding: utf-8 -*-
"""
Created on Thu Mar  9 13:28:34 2023

@author: yakovpetrukhin
"""

from fpga import FPGA, eval_outputs, start_temp_fpga_writer, start_cts_monitor
from pipe import start_pipes
from command_handler import start_command_packager
import logging
from collections import deque
import time
import threading
import cProfile
import pstats


def main():
    format = "%(asctime)s: %(message)s"
    logging.basicConfig(format=format, level=logging.DEBUG, datefmt="%H:%M:%S")
                    
    fpga = FPGA('COM3', 576000, exitOnFail = True)
    
    engine_return_queue = deque([])
    instruction_queue = deque([])
    tx_cmd_queue = deque([])
    
    start_pipes(instruction_queue, engine_return_queue)
    
    start_command_packager(instruction_queue, tx_cmd_queue)
        
    start_temp_fpga_writer(fpga, tx_cmd_queue)
    
    # logging.disable(logging.CRITICAL)

    # with cProfile.Profile() as pr:
    #     fpga.write_data(tx_cmd_queue)
    
    # stats = pstats.Stats(pr)
    # stats.sort_stats(pstats.SortKey.TIME)
    # stats.print_stats()
    # stats.dump_stats(filename='needs_profiling.prof')
  

if __name__ == "__main__":
    
    main()
    

    
    
    
    