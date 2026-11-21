#!/bin/sh
# Runs all three testbenches in GHDL (VHDL-93). Usage: sh scripts/run_sim.sh  (from the project root)
set -e
RTL="rtl/aes_pkg.vhd rtl/aes_core.vhd rtl/uart_rx.vhd rtl/uart_tx.vhd rtl/fifo_sync.vhd rtl/aes_uart_ctrl.vhd rtl/aes_uart_top.vhd rtl/uart_echo_top.vhd"
for tb in tb_aes_core tb_uart_echo tb_aes_uart; do
  echo "== $tb"
  ghdl -a --std=93c $RTL sim/$tb.vhd
  ghdl -e --std=93c $tb
  ghdl -r --std=93c $tb 2>&1 | grep -i "passed\|error\|failure\|fail"
done
