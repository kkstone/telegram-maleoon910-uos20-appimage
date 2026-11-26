#!/usr/bin/env python3
"""Smoke-test that the deployed libs can create autoaudiosink and load PSL data.
Run inside the ALT rootfs with LD_LIBRARY_PATH/GST_PLUGIN_PATH pointing at the
extracted AppDir. Prints PASS/FAIL for each check.
"""
import ctypes
import ctypes.util

ok = True

# --- GStreamer: gst_init + gst_element_factory_make("autoaudiosink") ---
try:
    gst = ctypes.CDLL("libgstreamer-1.0.so.0")
    gst.gst_init(None, None)
    gst.gst_element_factory_make.restype = ctypes.c_void_p
    gst.gst_element_factory_make.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    for element in (b"autoaudiosink", b"pulsesink", b"alsasink", b"playbin"):
        ptr = gst.gst_element_factory_make(element, b"test")
        print("GST element %-15s : %s" % (element.decode(), "FOUND" if ptr else "MISSING"))
        if element == b"autoaudiosink" and not ptr:
            ok = False
except Exception as e:
    print("GStreamer check FAILED:", repr(e))
    ok = False

# --- libpsl: psl_latest reads the patched path, psl_is_public_suffix works ---
try:
    psl = ctypes.CDLL("libpsl.so.5")
    psl.psl_latest.restype = ctypes.c_void_p
    psl.psl_latest.argtypes = [ctypes.c_char_p]
    ctx = psl.psl_latest(None)
    print("PSL psl_latest()      : %s" % ("OK" if ctx else "NULL (no data)"))
    if not ctx:
        ok = False
    else:
        psl.psl_is_public_suffix2.restype = ctypes.c_int
        psl.psl_is_public_suffix2.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
        # 0 = PSL_CHECK_NONE; known public suffix should return 1
        for dom in (b"com", b"co.uk", b"example.com"):
            r = psl.psl_is_public_suffix2(ctx, dom, 0)
            print("  %-20s public_suffix=%d" % (dom.decode(), r))
except Exception as e:
    print("libpsl check FAILED:", repr(e))
    ok = False

print("RESULT:", "PASS" if ok else "FAIL")
