-- aes_uart_top.vhd : Nexys A7-100T top level for the "milestone without CPU":
--   PC --UART--> RX FIFO --> aes_uart_ctrl --> aes_core --> aes_uart_ctrl --> UART --> PC
-- AES-128 in CTR mode, protocol in aes_uart_ctrl.vhd.
-- LEDs: 0 key loaded | 1 counter loaded | 2 NAK sent (sticky) | 3 RX FIFO overrun (sticky)
--       4 UART framing error (sticky) | 5 AES busy | 7..6 processed blocks mod 4
library ieee;
use ieee.std_logic_1164.all;

entity aes_uart_top is
  generic (
    CLK_FREQ     : positive := 100_000_000;
    BAUD         : positive := 115_200;
    TIMEOUT_CLKS : positive := 10_000_000
  );
  port (
    CLK100MHZ    : in  std_logic;
    CPU_RESETN   : in  std_logic;
    UART_TXD_IN  : in  std_logic;                   -- PC -> FPGA
    UART_RXD_OUT : out std_logic;                   -- FPGA -> PC
    LED          : out std_logic_vector(7 downto 0)
  );
end entity aes_uart_top;

architecture rtl of aes_uart_top is
  signal rst_meta, rst : std_logic := '1';

  signal rx_data, fifo_data, tx_data : std_logic_vector(7 downto 0);
  signal rx_valid, rx_ferr           : std_logic;
  signal fifo_empty, fifo_pop, fifo_over : std_logic;
  signal tx_start, tx_busy           : std_logic;

  signal aes_start, aes_wipe, aes_busy, aes_done : std_logic;
  signal aes_key, aes_din, aes_dout    : std_logic_vector(127 downto 0);

  signal key_valid, ctr_valid, nak_seen : std_logic;
  signal blk_count           : std_logic_vector(1 downto 0);
  signal over_sticky, ferr_sticky : std_logic := '0';
begin

  process (CLK100MHZ)
  begin
    if rising_edge(CLK100MHZ) then
      rst_meta <= not CPU_RESETN;
      rst      <= rst_meta;
      if rst = '1' then
        over_sticky <= '0';
        ferr_sticky <= '0';
      else
        if fifo_over = '1' then over_sticky <= '1'; end if;
        if rx_ferr   = '1' then ferr_sticky <= '1'; end if;
      end if;
    end if;
  end process;

  u_rx : entity work.uart_rx
    generic map (CLK_FREQ => CLK_FREQ, BAUD => BAUD)
    port map (clk => CLK100MHZ, rst => rst, rx => UART_TXD_IN,
              data => rx_data, valid => rx_valid, frame_err => rx_ferr);

  u_fifo : entity work.fifo_sync
    generic map (AW => 5)
    port map (clk => CLK100MHZ, rst => rst,
              wr_en => rx_valid, wr_data => rx_data,
              rd_en => fifo_pop, rd_data => fifo_data,
              empty => fifo_empty, overrun => fifo_over);

  u_ctrl : entity work.aes_uart_ctrl
    generic map (TIMEOUT_CLKS => TIMEOUT_CLKS)
    port map (clk => CLK100MHZ, rst => rst,
              rx_data => fifo_data, rx_empty => fifo_empty, rx_pop => fifo_pop,
              tx_data => tx_data, tx_start => tx_start, tx_busy => tx_busy,
              aes_start => aes_start, aes_wipe => aes_wipe, aes_key => aes_key, aes_din => aes_din,
              aes_done => aes_done, aes_dout => aes_dout,
              key_valid => key_valid, ctr_valid => ctr_valid,
              nak_seen => nak_seen, blk_count => blk_count);

  u_aes : entity work.aes_core
    port map (clk => CLK100MHZ, rst => rst, wipe => aes_wipe, start => aes_start,
              key => aes_key, data_in => aes_din,
              busy => aes_busy, done => aes_done, data_out => aes_dout);

  u_tx : entity work.uart_tx
    generic map (CLK_FREQ => CLK_FREQ, BAUD => BAUD)
    port map (clk => CLK100MHZ, rst => rst, start => tx_start,
              data => tx_data, busy => tx_busy, tx => UART_RXD_OUT);

  LED <= blk_count & aes_busy & ferr_sticky & over_sticky & nak_seen & ctr_valid & key_valid;

end architecture rtl;
