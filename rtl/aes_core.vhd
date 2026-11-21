-- aes_core.vhd : iterative AES-128 encryption core (1 round per clock).
-- Latency: 11 clock cycles from the edge that samples 'start' to the edge
-- after which 'done' is high (1 load/initial AddRoundKey + 10 rounds).
-- The round key is generated on the fly, so there is no key RAM.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.aes_pkg.all;

entity aes_core is
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;                      -- synchronous, active high
    wipe     : in  std_logic := '0';               -- synchronous: clear state and round-key registers
    start    : in  std_logic;                      -- 1-cycle pulse, only when busy = '0'
    key      : in  std_logic_vector(127 downto 0);
    data_in  : in  std_logic_vector(127 downto 0);
    busy     : out std_logic;
    done     : out std_logic;                      -- 1-cycle pulse, data_out valid
    data_out : out std_logic_vector(127 downto 0)  -- holds until the next start
  );
end entity aes_core;

architecture rtl of aes_core is
  type st_t is (IDLE, RUN);
  signal st      : st_t := IDLE;
  signal state_r : state_t := (others => (others => '0'));
  signal rk_r    : block_t := (others => '0');
  signal rnd     : natural range 0 to 10 := 0;
begin

  process (clk)
    variable nrk : block_t;
    variable s   : state_t;
  begin
    if rising_edge(clk) then
      done <= '0';
      if rst = '1' or wipe = '1' then
        st      <= IDLE;
        state_r <= (others => (others => '0'));    -- no key material / keystream left behind
        rk_r    <= (others => '0');
        rnd     <= 0;
      else
        case st is
          when IDLE =>
            if start = '1' then
              state_r <= to_state(data_in xor key);   -- initial AddRoundKey
              rk_r    <= key;
              rnd     <= 1;
              st      <= RUN;
            end if;

          when RUN =>
            nrk := next_round_key(rk_r, rcon_for(rnd));
            s   := shift_rows(sub_bytes(state_r));
            if rnd /= 10 then
              s := mix_columns(s);                    -- no MixColumns in the last round
            end if;
            state_r <= to_state(to_block(s) xor nrk); -- AddRoundKey
            rk_r    <= nrk;
            if rnd = 10 then
              st   <= IDLE;
              done <= '1';
            else
              rnd <= rnd + 1;
            end if;
        end case;
      end if;
    end if;
  end process;

  busy     <= '1' when st = RUN else '0';
  data_out <= to_block(state_r);

end architecture rtl;
