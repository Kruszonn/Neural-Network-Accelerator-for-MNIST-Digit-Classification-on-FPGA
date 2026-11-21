# Hardware Neural Network Accelerator for MNIST Digit Classification on FPGA

VHDL-93, simulated in GHDL (all three testbenches pass).

## Files
rtl/aes_pkg.vhd, aes_core.vhd        AES-128 encrypt, iterative, 11 clocks/block, optional `wipe` input
rtl/uart_rx.vhd, uart_tx.vhd         UART 8N1, 115200 @ 100 MHz
rtl/fifo_sync.vhd                    32-byte RX FIFO (first-word-fall-through, overrun pulse)
rtl/aes_uart_ctrl.vhd                command FSM: CTR mode, nonce discipline, wipe, timeouts
rtl/aes_uart_top.vhd                 top for the Nexys A7: UART -> FIFO -> FSM -> AES -> UART
rtl/uart_echo_top.vhd                step-1 top (UART echo), kept for bring-up
sim/tb_aes_core.vhd                  27 AES vectors + latency check
sim/tb_uart_echo.vhd                 echo test
sim/tb_aes_uart.vhd                  end-to-end test over the serial line, 10 test groups
constr/nexys_a7_100t_aes_uart.xdc    pins for aes_uart_top (and ..._uart_echo.xdc for the echo top)
scripts/run_sim.sh                   runs all three testbenches in GHDL
scripts/aes_uart_test.py             hardware test (pyserial + pycryptodome)
scripts/uart_echo_test.py            echo test for bring-up

## Protocol (ACK = 0x06, NAK = 0x15; multi-byte fields first byte first)
'K' + 16 B key             -> ACK   loads key, INVALIDATES the counter
'N' + 16 B counter block   -> ACK   needs a key
'C' + 16 B data            -> 16 B  data xor AES_K(counter), counter += 1 (128-bit, big endian);
                                    needs key + counter; same command encrypts and decrypts
'Z'                        -> ACK   wipes key, counter and all working registers
Unknown byte, missing precondition (payload is still consumed), or a frame stalled for 100 ms -> NAK.

## Security properties (what is implemented, and what is not claimed)
Implemented, and checked in simulation:
- CTR mode instead of ECB; the counter is a 128-bit register that increments after every block.
- Counter discipline: no `C` without a counter, and a new key invalidates the counter.
- Key is write-only (no command reads it back); wiped by reset and by `Z`, together with the AES
  working registers (state, round key), the byte shift register and the counter.
- Frame timeout and payload skipping on rejected commands (no payload misread as commands).
- AES latency is a constant 11 clocks for every input (asserted for all 27 test vectors).
## LEDs
0 key loaded | 1 counter loaded | 2 NAK sent (sticky) | 3 RX FIFO overrun (sticky)
4 UART framing error (sticky) | 5 AES busy | 7..6 processed blocks mod 4.  Reset: red CPU_RESETN button.

## Vivado
1. Project for xc7a100tcsg324-1; add rtl/*.vhd as design sources, sim/*.vhd as simulation sources.
2. Simulation: tb_aes_core / tb_uart_echo / tb_aes_uart -> Run Behavioral Simulation -> Run All
   (tb_aes_uart is ~130 ms of simulated serial traffic; set the run time to "all" and give it time).
3. Hardware: top = aes_uart_top, constraints = constr/nexys_a7_100t_aes_uart.xdc, bitstream, program.
4. python3 scripts/aes_uart_test.py /dev/ttyUSB1
   After synthesis record: LUT/FF usage, worst slack at 100 MHz (the AES round is the critical path).

## GHDL
sh scripts/run_sim.sh
