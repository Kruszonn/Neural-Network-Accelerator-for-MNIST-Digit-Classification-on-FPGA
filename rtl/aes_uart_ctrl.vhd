-- aes_uart_ctrl.vhd : command FSM between the UART and aes_core. AES-128 in CTR mode.
--
-- Protocol (multi-byte fields are sent first byte / MSB first):
--   'K' + 16 B key            -> ACK  loads the key; INVALIDATES the counter (a new 'N' is required)
--   'N' + 16 B counter block  -> ACK  sets the initial counter block (nonce || counter); needs a key
--   'C' + 16 B data           -> 16 B data xor AES_K(counter); counter += 1 (128-bit, big endian)
--                                needs key and counter; same command encrypts and decrypts
--   'Z'                       -> ACK  wipes key, counter and all working registers
--   anything else, a command whose precondition is not met, or a frame stalled
--   for TIMEOUT_CLKS without its next byte -> NAK, FSM back to idle
--   A 'N' or 'C' whose precondition is not met still has its 16 payload bytes consumed
--   before the NAK is sent, so the payload is never misread as commands. An unknown
--   byte is NAKed on its own (one NAK per byte).
-- ACK = 0x06, NAK = 0x15. The key is only ever written; no command reads it back.
-- Reset also wipes key, counter and working registers.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity aes_uart_ctrl is
  generic (
    TIMEOUT_CLKS : positive := 10_000_000           -- 100 ms @ 100 MHz
  );
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;
    -- from the RX FIFO (first-word-fall-through)
    rx_data   : in  std_logic_vector(7 downto 0);
    rx_empty  : in  std_logic;
    rx_pop    : out std_logic;
    -- to uart_tx
    tx_data   : out std_logic_vector(7 downto 0);
    tx_start  : out std_logic;
    tx_busy   : in  std_logic;
    -- aes_core
    aes_start : out std_logic;
    aes_wipe  : out std_logic;
    aes_key   : out std_logic_vector(127 downto 0);
    aes_din   : out std_logic_vector(127 downto 0);
    aes_done  : in  std_logic;
    aes_dout  : in  std_logic_vector(127 downto 0);
    -- status
    key_valid : out std_logic;
    ctr_valid : out std_logic;
    nak_seen  : out std_logic;                      -- sticky
    blk_count : out std_logic_vector(1 downto 0)    -- processed blocks, modulo 4
  );
end entity aes_uart_ctrl;

architecture rtl of aes_uart_ctrl is
  constant CMD_KEY  : std_logic_vector(7 downto 0) := x"4B";   -- 'K'
  constant CMD_NONC : std_logic_vector(7 downto 0) := x"4E";   -- 'N'
  constant CMD_CRYP : std_logic_vector(7 downto 0) := x"43";   -- 'C'
  constant CMD_ZERO : std_logic_vector(7 downto 0) := x"5A";   -- 'Z'
  constant ACK      : std_logic_vector(7 downto 0) := x"06";
  constant NAK      : std_logic_vector(7 downto 0) := x"15";
  constant ZEROS120 : std_logic_vector(119 downto 0) := (others => '0');
  constant ZEROS128 : std_logic_vector(127 downto 0) := (others => '0');

  type st_t is (S_CMD, S_KEY, S_CTR, S_BLK, S_WAIT, S_REPLY);
  signal st        : st_t := S_CMD;
  signal idx       : natural range 0 to 15 := 0;
  signal tmo       : natural range 0 to TIMEOUT_CLKS := 0;
  signal sh        : std_logic_vector(127 downto 0) := (others => '0');   -- incoming bytes
  signal key_r     : std_logic_vector(127 downto 0) := (others => '0');
  signal ctr_r     : unsigned(127 downto 0) := (others => '0');
  signal blk_r     : std_logic_vector(127 downto 0) := (others => '0');   -- data block being processed
  signal key_ok    : std_logic := '0';
  signal ctr_ok    : std_logic := '0';
  signal reply_buf : std_logic_vector(127 downto 0) := (others => '0');
  signal reply_len : natural range 1 to 16 := 1;
  signal rej       : std_logic := '0';                 -- current N/C command is rejected (payload is skipped)
  signal nak_r     : std_logic := '0';
  signal cnt_r     : unsigned(1 downto 0) := (others => '0');
  signal pop       : std_logic;
  signal tx_start_r : std_logic := '0';
begin

  -- take a byte from the FIFO whenever we are in a state that wants input
  pop    <= '1' when rx_empty = '0' and
                     (st = S_CMD or st = S_KEY or st = S_CTR or st = S_BLK) else '0';
  rx_pop <= pop;

  aes_key   <= key_r;
  aes_din   <= std_logic_vector(ctr_r);               -- AES encrypts the counter block
  key_valid <= key_ok;
  ctr_valid <= ctr_ok;
  nak_seen  <= nak_r;
  blk_count <= std_logic_vector(cnt_r);
  tx_start  <= tx_start_r;

  process (clk)
  begin
    if rising_edge(clk) then
      tx_start_r <= '0';
      aes_start  <= '0';
      aes_wipe   <= '0';

      if rst = '1' then
        st        <= S_CMD;
        key_ok    <= '0';
        ctr_ok    <= '0';
        nak_r     <= '0';
        cnt_r     <= (others => '0');
        tmo       <= 0;
        idx       <= 0;
        key_r     <= (others => '0');                 -- wipe all secrets and working data
        ctr_r     <= (others => '0');
        sh        <= (others => '0');
        blk_r     <= (others => '0');
        reply_buf <= (others => '0');
      else
        case st is

          when S_CMD =>
            tmo <= 0;
            idx <= 0;
            if pop = '1' then
              if rx_data = CMD_KEY then
                st <= S_KEY;
              elsif rx_data = CMD_NONC then
                rej <= not key_ok;
                st  <= S_CTR;
              elsif rx_data = CMD_CRYP then
                rej <= not (key_ok and ctr_ok);
                st  <= S_BLK;
              elsif rx_data = CMD_ZERO then              -- wipe everything, then ACK
                key_r     <= (others => '0');
                ctr_r     <= (others => '0');
                sh        <= (others => '0');
                blk_r     <= (others => '0');
                key_ok    <= '0';
                ctr_ok    <= '0';
                aes_wipe  <= '1';
                reply_buf <= ACK & ZEROS120;
                reply_len <= 1;
                st        <= S_REPLY;
              else                                       -- unknown command / precondition not met
                reply_buf <= NAK & ZEROS120;
                reply_len <= 1;
                nak_r     <= '1';
                st        <= S_REPLY;
              end if;
            end if;

          when S_KEY =>
            if pop = '1' then
              tmo <= 0;
              sh  <= sh(119 downto 0) & rx_data;
              if idx = 15 then
                key_r     <= sh(119 downto 0) & rx_data;
                key_ok    <= '1';
                ctr_ok    <= '0';                        -- new key: counter must be set again
                sh        <= (others => '0');
                reply_buf <= ACK & ZEROS120;
                reply_len <= 1;
                idx       <= 0;
                st        <= S_REPLY;
              else
                idx <= idx + 1;
              end if;
            elsif tmo = TIMEOUT_CLKS - 1 then            -- frame stalled
              sh        <= (others => '0');
              reply_buf <= NAK & ZEROS120;
              reply_len <= 1;
              nak_r     <= '1';
              idx       <= 0;
              st        <= S_REPLY;
            else
              tmo <= tmo + 1;
            end if;

          when S_CTR =>
            if pop = '1' then
              tmo <= 0;
              sh  <= sh(119 downto 0) & rx_data;
              if idx = 15 then
                sh        <= (others => '0');
                reply_len <= 1;
                idx       <= 0;
                st        <= S_REPLY;
                if rej = '1' then
                  reply_buf <= NAK & ZEROS120;
                  nak_r     <= '1';
                else
                  ctr_r     <= unsigned(sh(119 downto 0) & rx_data);
                  ctr_ok    <= '1';
                  reply_buf <= ACK & ZEROS120;
                end if;
              else
                idx <= idx + 1;
              end if;
            elsif tmo = TIMEOUT_CLKS - 1 then
              sh        <= (others => '0');
              reply_buf <= NAK & ZEROS120;
              reply_len <= 1;
              nak_r     <= '1';
              idx       <= 0;
              st        <= S_REPLY;
            else
              tmo <= tmo + 1;
            end if;

          when S_BLK =>
            if pop = '1' then
              tmo <= 0;
              sh  <= sh(119 downto 0) & rx_data;
              if idx = 15 then
                sh <= (others => '0');
                if rej = '1' then
                  reply_buf <= NAK & ZEROS120;
                  reply_len <= 1;
                  nak_r     <= '1';
                  idx       <= 0;
                  st        <= S_REPLY;
                else
                  blk_r     <= sh(119 downto 0) & rx_data;
                  aes_start <= '1';                      -- encrypt the counter block
                  st        <= S_WAIT;
                end if;
              else
                idx <= idx + 1;
              end if;
            elsif tmo = TIMEOUT_CLKS - 1 then
              sh        <= (others => '0');
              reply_buf <= NAK & ZEROS120;
              reply_len <= 1;
              nak_r     <= '1';
              idx       <= 0;
              st        <= S_REPLY;
            else
              tmo <= tmo + 1;
            end if;

          when S_WAIT =>
            if aes_done = '1' then
              reply_buf <= aes_dout xor blk_r;           -- data xor keystream
              reply_len <= 16;
              blk_r     <= (others => '0');
              ctr_r     <= ctr_r + 1;                    -- never reuse a counter value
              idx       <= 0;
              cnt_r     <= cnt_r + 1;
              st        <= S_REPLY;
            end if;

          when S_REPLY =>
            -- the guard on tx_start_r covers the one clock before busy rises
            if tx_busy = '0' and tx_start_r = '0' then
              tx_data    <= reply_buf(127 downto 120);
              tx_start_r <= '1';
              reply_buf  <= reply_buf(119 downto 0) & x"00";
              if idx = reply_len - 1 then
                st <= S_CMD;
              else
                idx <= idx + 1;
              end if;
            end if;

        end case;
      end if;
    end if;
  end process;

end architecture rtl;
