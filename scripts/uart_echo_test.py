#!/usr/bin/env python3
"""Echo test for the Nexys A7 UART. Usage: ./uart_echo_test.py /dev/ttyUSB1"""
import sys, os, serial

port = sys.argv[1] if len(sys.argv) > 1 else "/dev/ttyUSB1"
s = serial.Serial(port, 115200, timeout=1)
s.reset_input_buffer()

tests = [bytes([0x55]), b"A", bytes(range(256)), os.urandom(64), b"Hello World"]
ok = True
for t in tests:
    s.write(t)
    r = s.read(len(t))
    good = (r == t)
    ok &= good
    print(f"{len(t):4d} bytes: {'OK' if good else 'FAIL'}" + ("" if good else f"  got {r[:16].hex()}"))
print("ALL OK" if ok else "FAILED")
sys.exit(0 if ok else 1)
