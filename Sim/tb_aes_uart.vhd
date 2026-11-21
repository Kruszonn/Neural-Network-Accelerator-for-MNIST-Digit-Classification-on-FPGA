-- tb_aes_uart.vhd : end-to-end testbench for aes_uart_top (AES-128 CTR over UART), real serial timing.
--   1  commands without their preconditions, and unknown commands        -> NAK
--   2  NIST SP 800-38A F.5.1 CTR-AES128 known answers (4 blocks, sent back-to-back, no waiting)
--   3  decryption = same operation with the counter reset to the IV
--   4  counter carry into the upper bytes and wrap-around (IV = ff..ff)
--   5  loading a new key invalidates the counter (C -> NAK until a new N)
--   6  the counter advances: the same plaintext block encrypts differently the second time
--   7  16-block stream round trip (encrypt, reset counter, decrypt)
--   8  'Z' wipes key and counter (C and N then -> NAK)
--   9  frame timeout -> NAK, counter untouched, normal operation afterwards
--  10  status LEDs
-- Replies are captured by a free-running UART monitor, because the FPGA starts
-- answering half a bit before the PC finishes its own stop bit.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_aes_uart is
end entity tb_aes_uart;

architecture sim of tb_aes_uart is
  subtype slv8   is std_logic_vector(7 downto 0);
  subtype slv128 is std_logic_vector(127 downto 0);
  type blk_arr4_t  is array (0 to 3)  of slv128;
  type blk_arr16_t is array (0 to 15) of slv128;

  constant CLK_PERIOD : time := 10 ns;
  constant BIT_TIME   : time := 868 * CLK_PERIOD;      -- 115200 baud @ 100 MHz

  constant CMD_K : slv8 := x"4B";
  constant CMD_N : slv8 := x"4E";
  constant CMD_C : slv8 := x"43";
  constant CMD_Z : slv8 := x"5A";
  constant ACK   : slv8 := x"06";
  constant NAK   : slv8 := x"15";

  constant KEY_B : slv128 := x"2b7e151628aed2a6abf7158809cf4f3c";
  constant IV_B  : slv128 := x"f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff";
  constant PT_B  : blk_arr4_t := (x"6bc1bee22e409f96e93d7e117393172a",
                                  x"ae2d8a571e03ac9c9eb76fac45af8e51",
                                  x"30c81c46a35ce411e5fbc1191a0a52ef",
                                  x"f69f2445df4f9b17ad2b417be66c3710");
  constant CT_B  : blk_arr4_t := (x"874d6191b620e3261bef6864990db6ce",
                                  x"9806f66b7970fdff8617187bb9fffdff",
                                  x"5ae4df3edbd5d35e5b4f09020db03eab",
                                  x"1e031dda2fbe03d1792170a0f3009cee");
  -- AES_K(ff..ff) and AES_K(00..00) for KEY_B (pycryptodome): keystream around the counter wrap
  constant KS_FF : slv128 := x"8af2860142f786f409307c1a3f7eaaac";
  constant KS_00 : slv128 := x"7df76b0c1ab899b33e42f047b91b546f";
  constant ZERO  : slv128 := (others => '0');
  constant ONES  : slv128 := (others => '1');

  type rxbuf_t is array (0 to 1023) of slv8;
  signal rx_buf : rxbuf_t := (others => (others => '0'));
  signal rx_wr  : natural := 0;

  signal clk      : std_logic := '0';
  signal resetn   : std_logic := '0';
  signal pc_to_fpga, fpga_to_pc : std_logic := '1';
  signal led      : std_logic_vector(7 downto 0);
  signal sim_done : boolean := false;

  procedure send_byte (signal line : out std_logic; b : slv8) is
  begin
    line <= '0'; wait for BIT_TIME;                    -- start bit
    for i in 0 to 7 loop
      line <= b(i); wait for BIT_TIME;                 -- LSB first
    end loop;
    line <= '1'; wait for BIT_TIME;                    -- stop bit
  end procedure;

  procedure send_cmd (signal line : out std_logic; cmd : slv8; v : slv128) is
  begin
    send_byte(line, cmd);
    for i in 0 to 15 loop
      send_byte(line, v(127 - 8*i downto 120 - 8*i));
    end loop;
  end procedure;
begin

  dut : entity work.aes_uart_top
    generic map (TIMEOUT_CLKS => 30000)                -- 300 us, so the timeout test is quick
    port map (CLK100MHZ => clk, CPU_RESETN => resetn,
              UART_TXD_IN => pc_to_fpga, UART_RXD_OUT => fpga_to_pc, LED => led);

  clk_gen : process
  begin
    while not sim_done loop
      clk <= '0'; wait for CLK_PERIOD / 2;
      clk <= '1'; wait for CLK_PERIOD / 2;
    end loop;
    wait;
  end process;

  watchdog : process
  begin
    wait until sim_done for 2000 ms;
    assert sim_done report "WATCHDOG: testbench did not finish" severity failure;
    wait;
  end process;

  -- free-running UART receiver for the FPGA -> PC line
  rx_monitor : process
    variable b : slv8;
  begin
    wait until fpga_to_pc = '0';                       -- start bit
    wait for BIT_TIME + BIT_TIME / 2;                  -- middle of data bit 0
    for i in 0 to 7 loop
      b(i) := fpga_to_pc;
      wait for BIT_TIME;
    end loop;                                          -- now in the middle of the stop bit
    assert fpga_to_pc = '1' report "FPGA sent a byte without a valid stop bit" severity failure;
    rx_buf(rx_wr mod 1024) <= b;
    rx_wr <= rx_wr + 1;
  end process;

  stim : process
    variable b : slv8;
    variable v : slv128;
    variable rd_idx : natural := 0;
    variable ct : blk_arr16_t;

    procedure get_byte (variable r : out slv8) is
    begin
      if rd_idx = rx_wr then
        wait until rx_wr /= rd_idx;
      end if;
      r := rx_buf(rd_idx mod 1024);
      rd_idx := rd_idx + 1;
    end procedure;

    procedure get_block (variable r : out slv128) is
      variable t : slv8;
    begin
      for i in 0 to 15 loop
        get_byte(t);
        r(127 - 8*i downto 120 - 8*i) := t;
      end loop;
    end procedure;

    procedure expect_ack (msg : string) is
      variable t : slv8;
    begin
      get_byte(t);
      assert t = ACK report "expected ACK: " & msg severity failure;
    end procedure;

    procedure expect_nak (msg : string) is
      variable t : slv8;
    begin
      get_byte(t);
      assert t = NAK report "expected NAK: " & msg severity failure;
    end procedure;

    procedure expect_blk (exp : slv128; msg : string) is
      variable t : slv128;
    begin
      get_block(t);
      assert t = exp report "wrong output block: " & msg severity failure;
    end procedure;
  begin
    resetn <= '0'; wait for 1 us; resetn <= '1'; wait for 1 us;

    -- 1. preconditions
    send_cmd(pc_to_fpga, CMD_C, ZERO);  expect_nak("C without key");
    send_cmd(pc_to_fpga, CMD_N, IV_B);  expect_nak("N without key");
    send_byte(pc_to_fpga, x"58");       expect_nak("unknown command");
    report "test 1 OK: commands without preconditions rejected";

    -- 2. SP 800-38A F.5.1, everything sent without waiting for replies
    send_cmd(pc_to_fpga, CMD_K, KEY_B);
    send_cmd(pc_to_fpga, CMD_N, IV_B);
    for i in 0 to 3 loop
      send_cmd(pc_to_fpga, CMD_C, PT_B(i));
    end loop;
    expect_ack("key");
    expect_ack("counter");
    for i in 0 to 3 loop
      expect_blk(CT_B(i), "F.5.1 block " & integer'image(i));
    end loop;
    report "test 2 OK: SP 800-38A F.5.1 known answers";

    -- 3. decryption: same operation, counter reset to the IV
    send_cmd(pc_to_fpga, CMD_N, IV_B);
    for i in 0 to 3 loop
      send_cmd(pc_to_fpga, CMD_C, CT_B(i));
    end loop;
    expect_ack("counter (decrypt)");
    for i in 0 to 3 loop
      expect_blk(PT_B(i), "decrypt block " & integer'image(i));
    end loop;
    report "test 3 OK: decryption";

    -- 4. 128-bit counter: IV = ff..ff, next value wraps to 00..00 (zero data -> raw keystream)
    send_cmd(pc_to_fpga, CMD_N, ONES);
    send_cmd(pc_to_fpga, CMD_C, ZERO);
    send_cmd(pc_to_fpga, CMD_C, ZERO);
    expect_ack("counter ff..ff");
    expect_blk(KS_FF, "keystream for counter ff..ff");
    expect_blk(KS_00, "keystream for wrapped counter 00..00");
    report "test 4 OK: counter wrap-around";

    -- 5. new key invalidates the counter
    send_cmd(pc_to_fpga, CMD_K, KEY_B);  expect_ack("new key");
    send_cmd(pc_to_fpga, CMD_C, ZERO);   expect_nak("C after key change without new N");
    report "test 5 OK: key change invalidates counter";

    -- 6. counter advances: same plaintext, different output the second time
    send_cmd(pc_to_fpga, CMD_N, IV_B);   expect_ack("counter");
    send_cmd(pc_to_fpga, CMD_C, PT_B(0));
    send_cmd(pc_to_fpga, CMD_C, PT_B(0));
    expect_blk(CT_B(0), "first use of PT0");
    get_block(v);
    assert v /= CT_B(0) report "same plaintext gave the same output twice (counter reuse)" severity failure;
    assert v = (PT_B(0) xor CT_B(1) xor PT_B(1)) report "second output is not PT0 xor keystream(1)" severity failure;
    report "test 6 OK: counter advances";

    -- 7. 16-block stream round trip (no waiting between requests)
    send_cmd(pc_to_fpga, CMD_N, IV_B);
    for i in 0 to 15 loop
      send_cmd(pc_to_fpga, CMD_C, PT_B(i mod 4));
    end loop;
    expect_ack("counter (stream)");
    for i in 0 to 15 loop
      get_block(ct(i));
    end loop;
    for i in 0 to 3 loop
      assert ct(i) = CT_B(i) report "stream: first four blocks differ from F.5.1" severity failure;
    end loop;
    send_cmd(pc_to_fpga, CMD_N, IV_B);
    for i in 0 to 15 loop
      send_cmd(pc_to_fpga, CMD_C, ct(i));
    end loop;
    expect_ack("counter (stream decrypt)");
    for i in 0 to 15 loop
      expect_blk(PT_B(i mod 4), "stream round trip block " & integer'image(i));
    end loop;
    report "test 7 OK: 16-block stream round trip";

    -- 8. wipe
    send_byte(pc_to_fpga, CMD_Z);        expect_ack("wipe");
    wait for 2 * BIT_TIME;
    assert led(0) = '0' and led(1) = '0' report "key/counter flags still set after wipe" severity failure;
    send_cmd(pc_to_fpga, CMD_C, ZERO);   expect_nak("C after wipe");
    send_cmd(pc_to_fpga, CMD_N, IV_B);   expect_nak("N after wipe");
    report "test 8 OK: wipe";

    -- 9. stalled frame: 'C' + 5 bytes, then silence -> NAK; counter must be unchanged
    send_cmd(pc_to_fpga, CMD_K, KEY_B);  expect_ack("key");
    send_cmd(pc_to_fpga, CMD_N, IV_B);   expect_ack("counter");
    send_byte(pc_to_fpga, CMD_C);
    for i in 0 to 4 loop
      send_byte(pc_to_fpga, x"A5");
    end loop;
    expect_nak("stalled frame");
    send_cmd(pc_to_fpga, CMD_C, PT_B(0));
    expect_blk(CT_B(0), "block after timeout (counter must still be the IV)");
    report "test 9 OK: frame timeout and recovery";

    -- 10. status LEDs: key + counter loaded, NAK seen, no overrun, no framing error,
    --     blocks processed = 4+4+2+2+32+1 = 45 -> 45 mod 4 = 1
    wait for 2 * BIT_TIME;
    assert led(0) = '1' report "LED0 (key loaded) should be on" severity failure;
    assert led(1) = '1' report "LED1 (counter loaded) should be on" severity failure;
    assert led(2) = '1' report "LED2 (NAK seen) should be on" severity failure;
    assert led(3) = '0' report "RX FIFO overrun" severity failure;
    assert led(4) = '0' report "UART framing error" severity failure;
    assert led(7 downto 6) = "01" report "block counter should be 45 mod 4 = 1" severity failure;
    report "test 10 OK: LED status";

    report "AES-CTR UART PROJECT: ALL TESTS PASSED";
    sim_done <= true;
    wait;
  end process;

end architecture sim;
