# -*- coding: utf-8 -*-
"""
Created on Sun Mar  5 16:34:57 2023

@author: yakovpetrukhin

Test bench for accelerating communication functions
"""

import timeit

def deque_timer():
    
    SETUP_CODE = """
from collections import deque
    
q = deque([0,1,2,3,4,5,6,7,8,9])
    """
    
    TEST_CODE = """
for i in range(100000):
    x = q.pop()
    q.appendleft(x)
    """
    
    print(timeit.timeit(setup = SETUP_CODE,
                        stmt = TEST_CODE,
                        number = 10000))
          
deque_timer()