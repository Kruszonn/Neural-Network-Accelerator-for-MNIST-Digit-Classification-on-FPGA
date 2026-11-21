-- fifo_sync.vhd : small synchronous byte FIFO, first-word-fall-through read.
-- rd_data always shows the oldest byte; pulse rd_en for one clock to drop it.
-- A write while full is lost and reported on 'overrun' (1-clock pulse).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fifo_sync is
  generic (AW : positive := 5);                     -- depth = 2**AW bytes
  port (
    clk     : in  std_logic;
    rst     : in  std_logic;                        -- synchronous, active high
    wr_en   : in  std_logic;
    wr_data : in  std_logic_vector(7 downto 0);
    rd_en   : in  std_logic;
    rd_data : out std_logic_vector(7 downto 0);
    empty   : out std_logic;
    overrun : out std_logic
  );
end entity fifo_sync;

architecture rtl of fifo_sync is
  type mem_t is array (0 to 2**AW - 1) of std_logic_vector(7 downto 0);
  signal mem    : mem_t := (others => (others => '0'));
  signal wr_ptr : unsigned(AW - 1 downto 0) := (others => '0');
  signal rd_ptr : unsigned(AW - 1 downto 0) := (others => '0');
  signal count  : unsigned(AW downto 0) := (others => '0');
begin

  process (clk)
    variable do_wr, do_rd : boolean;
  begin
    if rising_edge(clk) then
      overrun <= '0';
      if rst = '1' then
        wr_ptr <= (others => '0');
        rd_ptr <= (others => '0');
        count  <= (others => '0');
      else
        do_wr := (wr_en = '1') and (count /= 2**AW);
        do_rd := (rd_en = '1') and (count /= 0);
        if wr_en = '1' and count = 2**AW then
          overrun <= '1';
        end if;
        if do_wr then
          mem(to_integer(wr_ptr)) <= wr_data;
          wr_ptr <= wr_ptr + 1;
        end if;
        if do_rd then
          rd_ptr <= rd_ptr + 1;
        end if;
        if do_wr and not do_rd then
          count <= count + 1;
        elsif do_rd and not do_wr then
          count <= count - 1;
        end if;
      end if;
    end if;
  end process;

  rd_data <= mem(to_integer(rd_ptr));
  empty   <= '1' when count = 0 else '0';

end architecture rtl;
