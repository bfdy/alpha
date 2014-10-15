import unittest
import time
import functools
import socket

from tornado.tcpserver import TCPServer
import tornado.netutil

import common.cornado as cornado

class TestCornadoSleep(unittest.TestCase):
    steps = []

    def test(self):
        cornado.run(self.start)

    def start(self):
        self.now = time.time()
        cornado.getInstance().add_callback(self.sleepLonger)
        cornado.getInstance().add_callback(self.sleepShorter)

    def sleepShorter(self):
        self.steps.append('1.1')
        cornado.sleep(1)
        self.steps.append('1.2')

    def sleepLonger(self):
        self.steps.append('2.1')
        cornado.sleep(2)
        self.steps.append('2.2')

        dur = time.time() - self.now
        self.assertTrue(dur > 1 and dur < 3) #sleep works
        self.assertTrue(self.steps, ['1.1', '2.1', '1.2', '2.2'])
        cornado.getInstance().stop()

class EchoServer(TCPServer):
    def handle_stream(self, stream, address):
        input = functools.partial(self.__handleInput, stream)
        cornado.getInstance().add_callback(input)

    def __handleInput(self, stream):
        async_call = cornado.AsyncCall()
        
        stream.read_bytes(1, async_call.callback)
        data = async_call.wait()
        stream.write(data)

        cornado.getInstance().add_callback(self.__handleInput, stream)

class TestTCP(unittest.TestCase):
    def test(self):
        cornado.run(self.start)

    def start(self):
        s_socks = tornado.netutil.bind_sockets(0, address='127.0.0.1')
        server = EchoServer()
        server.add_sockets(s_socks)
        server_addr = s_socks[0].getsockname()

        client = tornado.iostream.IOStream(
            socket.socket(socket.AF_INET, socket.SOCK_STREAM, 0))
        
        async_call = cornado.AsyncCall()
        client.connect(server_addr, async_call.callback)
        async_call.wait()

        msg = 'hello' 
        client.write(msg)

        async_call = cornado.AsyncCall()
        client.read_bytes(len(msg), async_call.callback)
        self.assertEqual(msg, async_call.wait())

        cornado.getInstance().stop()
