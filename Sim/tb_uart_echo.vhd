-- tb_uart_echo.vhd : sends bytes into uart_echo_top at 115200 baud and checks
-- that the same bytes come back and appear on the LEDs.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_uart_echo is
end entity tb_uart_echo;

architecture sim of tb_uart_echo is
  constant CLK_PERIOD : time := 10 ns;
  constant BIT_TIME   : time := 868 * CLK_PERIOD;   -- 115200 baud @ 100 MHz

  signal clk      : std_logic := '0';
  signal resetn   : std_logic := '0';
  signal pc_to_fpga, fpga_to_pc : std_logic := '1';
  signal led      : std_logic_vector(7 downto 0);
  signal led_err  : std_logic;
  signal sim_done : boolean := false;

  type byte_arr_t is array (natural range <>) of std_logic_vector(7 downto 0);
  constant TEST_BYTES : byte_arr_t := (x"55", x"A3", x"00", x"FF", x"48", x"69");
begin

  dut : entity work.uart_echo_top
    port map (CLK100MHZ => clk, CPU_RESETN => resetn,
              UART_TXD_IN => pc_to_fpga, UART_RXD_OUT => fpga_to_pc,
              LED => led, LED16_R => led_err);

  clk_gen : process
  begin
    while not sim_done loop
      clk <= '0'; wait for CLK_PERIOD / 2;
      clk <= '1'; wait for CLK_PERIOD / 2;
    end loop;
    wait;
  end process;

  stim : process
    procedure send_byte (b : std_logic_vector(7 downto 0)) is
    begin
      pc_to_fpga <= '0'; wait for BIT_TIME;               -- start
      for i in 0 to 7 loop
        pc_to_fpga <= b(i); wait for BIT_TIME;            -- LSB first
      end loop;
      pc_to_fpga <= '1'; wait for BIT_TIME;               -- stop
    end procedure;
  begin
    resetn <= '0'; wait for 1 us; resetn <= '1'; wait for 1 us;
    for i in TEST_BYTES'range loop
      send_byte(TEST_BYTES(i));
      wait for 2 * BIT_TIME;                              -- idle gap
    end loop;
    wait for 20 * BIT_TIME;                         -- let the last echo finish
    sim_done <= true;
    wait;
  end process;

  check : process
    variable b : std_logic_vector(7 downto 0);
  begin
    for i in TEST_BYTES'range loop
      wait until fpga_to_pc = '0';                        -- start bit from FPGA
      wait for BIT_TIME + BIT_TIME / 2;                   -- middle of data bit 0
      for k in 0 to 7 loop
        b(k) := fpga_to_pc;
        wait for BIT_TIME;
      end loop;
      assert fpga_to_pc = '1' report "no stop bit on echo " & integer'image(i) severity failure;
      assert b = TEST_BYTES(i)
        report "echo mismatch on byte " & integer'image(i) severity failure;
      assert led = TEST_BYTES(i)
        report "LED mismatch on byte " & integer'image(i) severity failure;
      report "byte " & integer'image(i) & " echoed OK, value = " &
             integer'image(to_integer(unsigned(b))) & "" severity note;
    end loop;
    assert led_err = '0' report "unexpected framing error" severity failure;
    report "UART ECHO TEST PASSED" severity note;
    wait;
  end process;

end architecture sim;
