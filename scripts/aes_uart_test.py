#!/usr/bin/env python3
"""Hardware test for aes_uart_top (Nexys A7), AES-128 CTR.   pip install pyserial pycryptodome
Usage: ./aes_uart_test.py [/dev/ttyUSB1] [--text "Hello World"]

Protocol: 'K'+16B key -> ACK | 'N'+16B counter -> ACK | 'C'+16B data -> 16B (xor keystream)
          'Z' -> ACK (wipe) | anything else / precondition missing / stalled frame -> NAK
ACK = 0x06, NAK = 0x15
"""
import argparse, os, sys, time
import serial
from Crypto.Cipher import AES
from Crypto.Util import Counter

ACK, NAK = b"\x06", b"\x15"

def rd(s, n):
    d = s.read(n)
    if len(d) != n:
        raise SystemExit(f"timeout: wanted {n} bytes, got {len(d)} ({d.hex()})")
    return d

def cmd16(s, c, payload):
    s.write(c + payload)

def load_key(s, key):
    cmd16(s, b"K", key); assert rd(s, 1) == ACK, "key not acknowledged"

def set_counter(s, ctr):
    cmd16(s, b"N", ctr); assert rd(s, 1) == ACK, "counter not acknowledged"

def crypt(s, block):
    cmd16(s, b"C", block); return rd(s, 16)

def ref_ctr(key, ctr):
    return AES.new(key, AES.MODE_CTR, counter=Counter.new(128, initial_value=int.from_bytes(ctr, "big")))

def check(name, ok):
    print(f"{'PASS' if ok else 'FAIL'}  {name}")
    return ok

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("port", nargs="?", default="/dev/ttyUSB1")
    ap.add_argument("--text", help="also encrypt/decrypt this text (CTR, random counter)")
    a = ap.parse_args()

    s = serial.Serial(a.port, 115200, timeout=1.0)
    time.sleep(0.1); s.reset_input_buffer()
    ok = True

    # 1. NIST SP 800-38A F.5.1 known answers
    key = bytes.fromhex("2b7e151628aed2a6abf7158809cf4f3c")
    iv  = bytes.fromhex("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff")
    pts = [bytes.fromhex(x) for x in ("6bc1bee22e409f96e93d7e117393172a", "ae2d8a571e03ac9c9eb76fac45af8e51",
                                       "30c81c46a35ce411e5fbc1191a0a52ef", "f69f2445df4f9b17ad2b417be66c3710")]
    cts = ["874d6191b620e3261bef6864990db6ce", "9806f66b7970fdff8617187bb9fffdff",
           "5ae4df3edbd5d35e5b4f09020db03eab", "1e031dda2fbe03d1792170a0f3009cee"]
    load_key(s, key); set_counter(s, iv)
    ok &= check("SP 800-38A F.5.1 (4 blocks)", [crypt(s, p).hex() for p in pts] == cts)

    # 2. preconditions
    load_key(s, key)
    cmd16(s, b"C", bytes(16))
    ok &= check("C after key change, without new N -> NAK", rd(s, 1) == NAK)
    s.write(b"X")
    ok &= check("unknown command -> NAK", rd(s, 1) == NAK)

    # 3. random data, one request at a time (also gives the round-trip time)
    key = os.urandom(16); ctr = os.urandom(16)
    load_key(s, key); set_counter(s, ctr); ref = ref_ctr(key, ctr)
    blocks = [os.urandom(16) for _ in range(100)]
    t0 = time.perf_counter()
    got = [crypt(s, b) for b in blocks]
    dt = (time.perf_counter() - t0) / len(blocks)
    ok &= check(f"100 random blocks (avg round trip {dt*1e3:.2f} ms)", got == [ref.encrypt(b) for b in blocks])

    # 4. pipelined: 40 requests in one write, replies read afterwards
    set_counter(s, ctr); ref = ref_ctr(key, ctr)
    blocks = [os.urandom(16) for _ in range(40)]
    s.write(b"".join(b"C" + b for b in blocks))
    out = rd(s, 16 * len(blocks))
    ok &= check("40 pipelined blocks", out == b"".join(ref.encrypt(b) for b in blocks))

    # 5. counter wrap-around (ff..ff -> 00..00)
    set_counter(s, b"\xff" * 16); ref = ref_ctr(key, b"\xff" * 16)
    ok &= check("128-bit counter wrap", crypt(s, bytes(16)) + crypt(s, bytes(16)) == ref.encrypt(bytes(32)))

    # 6. stalled frame -> NAK after the FPGA timeout (100 ms); counter must be untouched
    set_counter(s, ctr); ref = ref_ctr(key, ctr)
    s.write(b"C" + b"\xA5" * 5)
    ok &= check("stalled frame -> NAK", rd(s, 1) == NAK)
    b = os.urandom(16)
    ok &= check("recovery after timeout (counter unchanged)", crypt(s, b) == ref.encrypt(b))

    # 7. wipe
    s.write(b"Z")
    ok &= check("Z -> ACK", rd(s, 1) == ACK)
    cmd16(s, b"C", bytes(16))
    ok &= check("C after wipe -> NAK", rd(s, 1) == NAK)

    # 8. optional text demo: random counter, CTR needs no padding on the host side
    if a.text:
        key = os.urandom(16); ctr = os.urandom(16)
        load_key(s, key); set_counter(s, ctr)
        data = a.text.encode(); padded = data + bytes(-len(data) % 16)
        ct = b"".join(crypt(s, padded[i:i+16]) for i in range(0, len(padded), 16))[:len(data)]
        print(f"text '{a.text}' -> {ct.hex()}")
        ok &= check("decrypts back on the host", ref_ctr(key, ctr).decrypt(ct) == data)
        s.write(b"Z"); rd(s, 1)

    print("ALL OK" if ok else "FAILED")
    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
