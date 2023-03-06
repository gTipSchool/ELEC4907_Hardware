import time
import sys
from os.path import join
from collections import deque

import logging
import threading

import win32pipe, win32file, pywintypes

# ========================  Threading Flags  ==================================

shutdown = threading.Event()

# =============================================================================

## Logger formatting
format = "%(asctime)s: %(message)s"
logging.basicConfig(format=format, level=logging.INFO, datefmt="%H:%M:%S")

# Pipe server function for testing. Creates a pipe server, takes string input,
# and sends a utf-8 encoded version of it to the pipe. Takes a mode of 0 or 1 as
# the input argument. Mode 0 allows a user to continuously enter input data to
# until they write "stop". Mode 1 will read an nerve_cmd.txt file with commands 
# to write to the Python based Nerve network connection interface.

# The command file supports the following commands:
# INIT, TYPE (FPGA or MAT)
# SEND INPUTS, NEURON_ID, VALUE
# SHUTDOWN, OUTPUT_LOG (True or False)

def pipeWriterServer(name = "nci_write", mode = 0):
    path = r'\\.\pipe'
    pipe_input = 0

    logging.info("Writer Server - Creating Pipe Server Writer with Name '%s'", name)
    
    # Create a pipe with the specified name. 
    pipe = win32pipe.CreateNamedPipe(
        join(path, name),
        # Pipe is bi-directional - both sides can read and write
        win32pipe.PIPE_ACCESS_DUPLEX, 
        # Pipe data format is message (an encoded string), PIPE_WAIT specifies
        # that the pipe is blocking while writing until all data is written
        win32pipe.PIPE_TYPE_MESSAGE | win32pipe.PIPE_READMODE_MESSAGE | win32pipe.PIPE_WAIT,
        # max instances, output buffer bytes, input buffer, timeout (50 ms),
        1, 65536, 65536,
        0,
        # security
        None)
    
    try:
        # In mode 0 the pipe waits for a client to connect. Once connected
        # the user is prompted for an input string that is then UTF-8 encoded
        # and sent to the pipe. THe user enters "stop" to close the server and
        # client threads
        if mode == 0:
            logging.info("Writer Server - Waiting for Client")
            win32pipe.ConnectNamedPipe(pipe, None)
            logging.info("Writer Server - Client Connected")
            
            pipe_input = 0
            while pipe_input != "stop":
                pipe_input = input("Writer Server - Enter a message to the send to the client.")
                logging.info("Writer Server Sending %s", pipe_input.encode())
                win32file.WriteFile(pipe, pipe_input.encode())
            logging.info("Writer Server - Writing 'EXIT, 0'")
            win32file.WriteFile(pipe, 'EXIT, 0'.encode())
            
        # In mode 1 the pipe inputs are read in from neuron_cmd.txt to test the
        # functionality of reading and writing back and forth. 
        elif mode == 1:
            pass
        
    # Shutdown the pipe by closing the pipe handle    
    finally:
        logging.info("Writer Server - Shutting down writer server.")
        shutdown.set()
        win32file.CloseHandle(pipe)
        
def pipeReaderServer(name = "nci_read"):
    path = r'\\.\pipe'
    pipe_input = 0

    logging.info("Reader Server - Creating Pipe Server Reader with Name '%s'", name)
    
    # Create a pipe with the specified name. 
    pipe = win32pipe.CreateNamedPipe(
        join(path, name),
        # Pipe is bi-directional - both sides can read and write
        win32pipe.PIPE_ACCESS_DUPLEX, 
        # Pipe data format is message (an encoded string), PIPE_WAIT specifies
        # that the pipe is blocking while writing until all data is written
        win32pipe.PIPE_TYPE_MESSAGE | win32pipe.PIPE_READMODE_MESSAGE | win32pipe.PIPE_WAIT,
        # max instances, output buffer bytes, input buffer, timeout (50 ms),
        1, 65536, 65536,
        0,
        # security
        None)
    

    logging.info("Reader Server - Waiting for Client")
    win32pipe.ConnectNamedPipe(pipe, None)
    logging.info("Reader Server - Client Connected")
    
    while not shutdown.is_set():
        _, message = win32file.ReadFile(pipe, 64*1024)
        logging.info("Reader Server - Message Received: %s", message)
    logging.info("Reader Server - Shutting down reader server.")
    shutdown.set()
    win32file.CloseHandle(pipe)
    

 

        
def pipeReaderClient(output_queue, name = "nci_pipe"):
    
    if type(output_queue) != type(deque()):
        shutdown.set()
        raise Exception("Reader Client - Reader client output queue must be of class deque from collections package!")
        
    
    ## Set the pipe path
    path = r'\\.\pipe'
    logging.info("Reader Client - Creating Client for Pipe with Name '%s'", name)
    
    try:
        ## Create a handle for the pipe to read from.
        handle = win32file.CreateFile(
            join(path, name),
            # Enable reading and writing from handle
            win32file.GENERIC_READ | win32file.GENERIC_WRITE,
            0, # share mode: 0 indicates that the file can't be opened elsewhere while the handle is open
            None, # security attr.
            win32file.OPEN_EXISTING, # creatrion disposition - i.e. don't overwrite
            0, # flags and attr.
            None # template
        )
        
        # Open a connection to the pipe at the given handle.
        connection_resp = win32pipe.SetNamedPipeHandleState(handle, win32pipe.PIPE_READMODE_MESSAGE, None, None)
        
        # If attempt to connect returns 0 shutdown the server. Otherwise receive
        # messages until shutdown flag is set.
        if connection_resp == 0:
            logging.info("Reader Client - SetNamedPipeHandleState return code: %s", connection_resp)
            shutdown.set()
        else:
            while not shutdown.is_set():
                _, message = win32file.ReadFile(handle, 64*1024)
                message = message.decode("utf-8")
                output_queue.appendleft(message)
                logging.info("Reader Client - Message Received: %s", message)
    finally:
        logging.info("Reader Client - Shutting down reader client.")
            
def pipeWriterClient(input_queue, name = "nci_pipe"):
    
    if type(input_queue) != type(deque()):
        shutdown.set()
        raise Exception("Writer Client - Writer client input queue must be of class deque from collections package!")
    
    ## Set the pipe path
    path = r'\\.\pipe'
    logging.info("Writer Client - Creating Writer Client for Pipe with Name '%s'", name)
    
    try:
        ## Create a handle for the pipe to read from.
        handle = win32file.CreateFile(
            join(path, name),
            # Enable reading and writing from handle
            win32file.GENERIC_READ | win32file.GENERIC_WRITE,
            0, # share mode: 0 indicates that the file can't be opened elsewhere while the handle is open
            None, # security attr.
            win32file.OPEN_EXISTING, # creatrion disposition - i.e. don't overwrite
            0, # flags and attr.
            None # template
        )
        
        # Open a connection to the pipe at the given handle.
        connection_resp = win32pipe.SetNamedPipeHandleState(handle, win32pipe.PIPE_READMODE_MESSAGE, None, None)
        
        # If attempt to connect returns 0 shutdown the server. Otherwise sends
        # messages until shutdown flag is set.
        if connection_resp == 0:
            logging.info("Writer Client - SetNamedPipeHandleState return code: %s", connection_resp)
            shutdown.set()
        else:
            
            while not shutdown.is_set():
                if len(input_queue) > 0:
                    message = input_queue.pop()
                    logging.info("Writer Client - Message to send: %s", message)
                    win32file.WriteFile(handle, message.encode())
                    logging.info("Writer Client - Message Sent: %s", message.encode())
                else:
                    pass
    finally:
        logging.info("Writer Client - Shutting down writer client.")
    


if __name__ == "__main__":
    
    from_server = deque()
    to_server = deque()
    
    server_reader = threading.Thread(name = "server_writer", target = pipeReaderServer)
    server_reader.start()
    
    server_writer = threading.Thread(name = "server_writer", target = pipeWriterServer)
    server_writer.start()
    
    client_reader = threading.Thread(name = "client_reader", target = pipeReaderClient, args= (from_server, "nci_write",), daemon = True)
    client_reader.start()
    
    client_writer = threading.Thread(name = "client_writer", target = pipeWriterClient, args= (to_server, "nci_read", ), daemon = True)
    client_writer.start()
    
    while not shutdown.is_set():
        if len(from_server)> 0:
            x = from_server.pop()
            to_server.appendleft(x)
            
    # time.sleep(5)
    
    # if server_reader.is_alive():
    #     logging.info("reader server")
    # if server_writer.is_alive():
    #     logging.info("writer server")
    # if client_writer.is_alive():
    #     logging.info("writer client")
    # if client_reader.is_alive():
    #     logging.info("reader_client")


    
    
    