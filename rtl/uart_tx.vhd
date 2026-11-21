-- uart_tx.vhd : UART transmitter, 8N1.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_tx is
  generic (
    CLK_FREQ : positive := 100_000_000;
    BAUD     : positive := 115_200
  );
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;                         -- synchronous, active high
    start : in  std_logic;                         -- 1-cycle pulse, only when busy = '0'
    data  : in  std_logic_vector(7 downto 0);
    busy  : out std_logic;
    tx    : out std_logic
  );
end entity uart_tx;

architecture rtl of uart_tx is
  constant CLKS_PER_BIT : positive := CLK_FREQ / BAUD;

  type st_t is (IDLE, SEND);
  signal st    : st_t := IDLE;
  signal frame : std_logic_vector(9 downto 0) := (others => '1');  -- stop & data & start
  signal idx   : natural range 0 to 9 := 0;
  signal cnt   : natural range 0 to CLKS_PER_BIT - 1 := 0;
  signal tx_r  : std_logic := '1';
  signal busy_r : std_logic := '0';
begin

  tx   <= tx_r;
  busy <= busy_r;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        st     <= IDLE;
        tx_r   <= '1';
        busy_r <= '0';
      else
        case st is
          when IDLE =>
            tx_r <= '1';
            if start = '1' then
              frame  <= '1' & data & '0';
              tx_r   <= '0';                           -- start bit
              idx    <= 0;
              cnt    <= 0;
              busy_r <= '1';
              st     <= SEND;
            end if;

          when SEND =>
            if cnt = CLKS_PER_BIT - 1 then
              cnt <= 0;
              if idx = 9 then                          -- stop bit finished
                tx_r   <= '1';
                busy_r <= '0';
                st     <= IDLE;
              else
                idx  <= idx + 1;
                tx_r <= frame(idx + 1);
              end if;
            else
              cnt <= cnt + 1;
            end if;
        end case;
      end if;
    end if;
  end process;

end architecture rtl;
