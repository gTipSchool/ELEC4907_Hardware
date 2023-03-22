# -*- coding: utf-8 -*-
"""
Created on Mon Mar 20 12:02:43 2023

@author: yakovpetrukhin
"""

import threading

# =========   GLOBAL PARAMETERS   =============================================

# NN Parameters
NUM_NEURONS = 41
NUM_INPUTS = 23
NUM_OUTPUTS = 3
NUM_TIMESTEPS = 500
DEBUG_MONITOR_MODE = True

# COM Port Config
READ_TIMEOUT = 2 #seconds

# =============================================================================


# =======   GLOBAL THREADING EVENTS   =========================================

shutdown = threading.Event()

# =============================================================================


