-- uart_rx.vhd : UART receiver, 8N1, samples in the middle of each bit.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_rx is
  generic (
    CLK_FREQ : positive := 100_000_000;
    BAUD     : positive := 115_200
  );
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;                     -- synchronous, active high
    rx        : in  std_logic;                     -- asynchronous serial input
    data      : out std_logic_vector(7 downto 0);
    valid     : out std_logic;                     -- 1-cycle pulse: 'data' is new
    frame_err : out std_logic                      -- 1-cycle pulse: stop bit was not '1'
  );
end entity uart_rx;

architecture rtl of uart_rx is
  constant CLKS_PER_BIT : positive := CLK_FREQ / BAUD;   -- 868 for 100 MHz / 115200

  type st_t is (IDLE, START_BIT, DATA_BITS, STOP_BIT);
  signal st      : st_t := IDLE;
  signal rx_meta : std_logic := '1';
  signal rx_s    : std_logic := '1';                     -- synchronised rx
  signal cnt     : natural range 0 to CLKS_PER_BIT - 1 := 0;
  signal bit_idx : natural range 0 to 7 := 0;
  signal shreg   : std_logic_vector(7 downto 0) := (others => '0');
begin

  process (clk)
  begin
    if rising_edge(clk) then
      -- two-flop synchroniser (rx is asynchronous to clk)
      rx_meta <= rx;
      rx_s    <= rx_meta;

      valid     <= '0';
      frame_err <= '0';

      if rst = '1' then
        st <= IDLE;
      else
        case st is
          when IDLE =>
            cnt <= 0;
            if rx_s = '0' then                         -- falling edge = start bit
              st <= START_BIT;
            end if;

          when START_BIT =>                            -- go to the middle of the start bit
            if cnt = CLKS_PER_BIT / 2 - 1 then
              cnt <= 0;
              if rx_s = '0' then                       -- still low: real start bit
                bit_idx <= 0;
                st      <= DATA_BITS;
              else                                     -- glitch
                st <= IDLE;
              end if;
            else
              cnt <= cnt + 1;
            end if;

          when DATA_BITS =>                            -- one sample per bit period, LSB first
            if cnt = CLKS_PER_BIT - 1 then
              cnt   <= 0;
              shreg <= rx_s & shreg(7 downto 1);
              if bit_idx = 7 then
                st <= STOP_BIT;
              else
                bit_idx <= bit_idx + 1;
              end if;
            else
              cnt <= cnt + 1;
            end if;

          when STOP_BIT =>
            if cnt = CLKS_PER_BIT - 1 then
              cnt <= 0;
              st  <= IDLE;
              data <= shreg;
              if rx_s = '1' then
                valid <= '1';
              else
                frame_err <= '1';
              end if;
            else
              cnt <= cnt + 1;
            end if;
        end case;
      end if;
    end if;
  end process;

end architecture rtl;
