'''cornado =  tornado + greenlet'''

import logging
import sys
import thread
import threading
import time

from greenlet import greenlet

import tornado.ioloop

def muteConsoleLogging():
    logging.getLogger('tornado').addHandler(logging.NullHandler())

_io_thread = None
def inIOThread():
    return thread.get_ident() == _io_thread

_io_instance = None
def setInstance(new_instance):
    _io_instance = new_instance

def getInstance():
    return _io_instance or tornado.ioloop.IOLoop.instance()

_io_loop = None
def run(method=None, *args, **kargs):
    '''Greenlet version of tornado.ioloop.IOLoop.instance().start
    If method is not None, will add_callback(method, *args, *kargs).
    '''
    
    #muteConsoleLogging()

    global _io_thread
    _io_thread = thread.get_ident()

    instance = getInstance()
    real_call = instance._run_callback

    def greenlet_call(*args, **kargs):
        greenlet(real_call).switch(*args, **kargs)
        
    instance._run_callback = greenlet_call
    
    if method:
        instance.add_callback(method, *args, **kargs)

    global _io_loop
    _io_loop = greenlet(instance.start)
    _io_loop.switch()

def sleep(secs):
    '''Put current greenlet in sleep. 
    Unlike time.sleep, this won't block IO thread, other greenlet can keep running.
    '''
    assert inIOThread()

    def wakeup():
        pending_greenlet.switch()
                                
    getInstance().add_timeout(time.time() + secs, wakeup)
    pending_greenlet = greenlet.getcurrent()
    return _io_loop.switch()

class AsyncResult:
    result = None
    exc_info = None

_event_cache = []
def callFromThread(f, *args, **kargs):
    '''Execute the function inside IO thread, wait it complete in non-io thread'''
    assert not inIOThread()

    try:
        evt = _event_cache.pop()
    except IndexError:
        evt = threading.Event()

    evt.clear()

    async_result = AsyncResult()

    def callback():
        try:
            async_result.result = f(*args, **kargs)
        except:
            async_result.exc_info = sys.exc_info()

        evt.set()
    
    getInstance().add_callback(callback)
    evt.wait() 

    _event_cache.append(evt)

    if async_result.exc_info:
        t, v, tb = async_result.exc_info
        raise t, v, tb 

    return async_result.result

class AsyncCall(object):
    '''A placeholder for Tornado callback argument. 
    
    Usage:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM, 0)
        stream = tornado.iostream.IOStream(s)
        
        async_call = AsyncCall()
        stream.connect((ip_addr, tcp_port), async_call.callback)
        async_call.wait()
    '''
    
    _pending_greenlet = None
    
    def callback(self, *args, **kargs):
        self._pending_greenlet.switch(*args, **kargs)
        
    def wait(self):
        self._pending_greenlet = greenlet.getcurrent()
        return _io_loop.switch()
