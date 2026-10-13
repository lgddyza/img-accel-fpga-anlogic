"""Copy each reconstructed frame into an owned GstBuffer without GI array conversion."""
import ctypes
import ctypes.util
import os


class FramePusher:
    def __init__(self, source, gst):
        self.source = source
        self.gst = gst
        self.native = os.environ.get('JPEG_NATIVE_PUSH', '1') != '0'
        if not self.native:
            return
        self.core = ctypes.CDLL(ctypes.util.find_library('gstreamer-1.0'))
        self.app = ctypes.CDLL(ctypes.util.find_library('gstapp-1.0'))
        capsule_pointer = ctypes.pythonapi.PyCapsule_GetPointer
        capsule_pointer.argtypes = [ctypes.py_object, ctypes.c_char_p]
        capsule_pointer.restype = ctypes.c_void_p
        self.pointer = capsule_pointer(source.__gpointer__, None)
        self.core.gst_buffer_new_allocate.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p]
        self.core.gst_buffer_new_allocate.restype = ctypes.c_void_p
        self.core.gst_buffer_fill.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t]
        self.core.gst_buffer_fill.restype = ctypes.c_size_t
        self.core.gst_buffer_unref.argtypes = [ctypes.c_void_p]
        self.core.gst_buffer_unref.restype = None
        self.app.gst_app_src_push_buffer.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        self.app.gst_app_src_push_buffer.restype = ctypes.c_int

    def push(self, frame):
        if not self.native:
            return int(self.source.emit('push-buffer', self.gst.Buffer.new_wrapped(frame)))
        buffer = self.core.gst_buffer_new_allocate(None, len(frame), None)
        if not buffer:
            raise MemoryError('could not allocate HDMI GstBuffer')
        copied = self.core.gst_buffer_fill(buffer, 0, ctypes.c_char_p(frame), len(frame))
        if copied != len(frame):
            self.core.gst_buffer_unref(buffer)
            raise RuntimeError('incomplete HDMI buffer copy')
        # push_buffer takes ownership, including when it returns a flow error.
        return self.app.gst_app_src_push_buffer(self.pointer, buffer)
