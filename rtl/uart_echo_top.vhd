-- uart_echo_top.vhd : Nexys A7-100T top level.
-- Every received byte is echoed back; its value is also shown on LED[7:0].
-- Note the Digilent naming (board's point of view):
--   UART_TXD_IN  = line driven by the PC  -> our RX input
--   UART_RXD_OUT = line read by the PC    <- our TX output
library ieee;
use ieee.std_logic_1164.all;

entity uart_echo_top is
  generic (
    CLK_FREQ : positive := 100_000_000;
    BAUD     : positive := 115_200
  );
  port (
    CLK100MHZ    : in  std_logic;
    CPU_RESETN   : in  std_logic;                  -- red button, active low
    UART_TXD_IN  : in  std_logic;
    UART_RXD_OUT : out std_logic;
    LED          : out std_logic_vector(7 downto 0);
    LED16_R      : out std_logic                   -- lights on framing error
  );
end entity uart_echo_top;

architecture rtl of uart_echo_top is
  signal rst_meta, rst      : std_logic := '1';
  signal rx_data            : std_logic_vector(7 downto 0);
  signal rx_valid, rx_ferr  : std_logic;
  signal tx_start, tx_busy  : std_logic := '0';
  signal tx_data            : std_logic_vector(7 downto 0) := (others => '0');
  signal hold               : std_logic_vector(7 downto 0) := (others => '0');
  signal pending            : std_logic := '0';
  signal led_r              : std_logic_vector(7 downto 0) := (others => '0');
  signal ferr_r             : std_logic := '0';
begin

  -- synchronise the (asynchronous) reset button
  process (CLK100MHZ)
  begin
    if rising_edge(CLK100MHZ) then
      rst_meta <= not CPU_RESETN;
      rst      <= rst_meta;
    end if;
  end process;

  u_rx : entity work.uart_rx
    generic map (CLK_FREQ => CLK_FREQ, BAUD => BAUD)
    port map (clk => CLK100MHZ, rst => rst, rx => UART_TXD_IN,
              data => rx_data, valid => rx_valid, frame_err => rx_ferr);

  u_tx : entity work.uart_tx
    generic map (CLK_FREQ => CLK_FREQ, BAUD => BAUD)
    port map (clk => CLK100MHZ, rst => rst, start => tx_start,
              data => tx_data, busy => tx_busy, tx => UART_RXD_OUT);

  -- one-byte holding register between RX and TX
  process (CLK100MHZ)
  begin
    if rising_edge(CLK100MHZ) then
      tx_start <= '0';
      if rst = '1' then
        pending <= '0';
        led_r   <= (others => '0');
        ferr_r  <= '0';
      else
        if rx_valid = '1' then
          hold    <= rx_data;
          led_r   <= rx_data;
          pending <= '1';
        end if;
        if rx_ferr = '1' then
          ferr_r <= '1';
        end if;
        if pending = '1' and tx_busy = '0' and tx_start = '0' and rx_valid = '0' then
          tx_data  <= hold;
          tx_start <= '1';
          pending  <= '0';
        end if;
      end if;
    end if;
  end process;

  LED     <= led_r;
  LED16_R <= ferr_r;

end architecture rtl;
