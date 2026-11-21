-- aes_pkg.vhd : AES-128 building blocks (encryption only)
-- State layout (FIPS-197): byte index i = 4*column + row; byte 0 is the
-- first byte of the block = bits 127..120 of the 128-bit vector.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package aes_pkg is
  subtype byte_t   is std_logic_vector(7 downto 0);
  subtype block_t  is std_logic_vector(127 downto 0);
  type    state_t  is array (0 to 15) of byte_t;

  function to_state (v : block_t) return state_t;
  function to_block (s : state_t) return block_t;
  function sub_bytes   (s : state_t) return state_t;
  function shift_rows  (s : state_t) return state_t;
  function mix_columns (s : state_t) return state_t;
  function rcon_for (round : natural) return byte_t;
  function next_round_key (rk : block_t; rcon : byte_t) return block_t;
end package aes_pkg;

package body aes_pkg is

  type sbox_t is array (0 to 255) of byte_t;
  constant SBOX : sbox_t := (
    x"63", x"7c", x"77", x"7b", x"f2", x"6b", x"6f", x"c5", x"30", x"01", x"67", x"2b", x"fe", x"d7", x"ab", x"76",
    x"ca", x"82", x"c9", x"7d", x"fa", x"59", x"47", x"f0", x"ad", x"d4", x"a2", x"af", x"9c", x"a4", x"72", x"c0",
    x"b7", x"fd", x"93", x"26", x"36", x"3f", x"f7", x"cc", x"34", x"a5", x"e5", x"f1", x"71", x"d8", x"31", x"15",
    x"04", x"c7", x"23", x"c3", x"18", x"96", x"05", x"9a", x"07", x"12", x"80", x"e2", x"eb", x"27", x"b2", x"75",
    x"09", x"83", x"2c", x"1a", x"1b", x"6e", x"5a", x"a0", x"52", x"3b", x"d6", x"b3", x"29", x"e3", x"2f", x"84",
    x"53", x"d1", x"00", x"ed", x"20", x"fc", x"b1", x"5b", x"6a", x"cb", x"be", x"39", x"4a", x"4c", x"58", x"cf",
    x"d0", x"ef", x"aa", x"fb", x"43", x"4d", x"33", x"85", x"45", x"f9", x"02", x"7f", x"50", x"3c", x"9f", x"a8",
    x"51", x"a3", x"40", x"8f", x"92", x"9d", x"38", x"f5", x"bc", x"b6", x"da", x"21", x"10", x"ff", x"f3", x"d2",
    x"cd", x"0c", x"13", x"ec", x"5f", x"97", x"44", x"17", x"c4", x"a7", x"7e", x"3d", x"64", x"5d", x"19", x"73",
    x"60", x"81", x"4f", x"dc", x"22", x"2a", x"90", x"88", x"46", x"ee", x"b8", x"14", x"de", x"5e", x"0b", x"db",
    x"e0", x"32", x"3a", x"0a", x"49", x"06", x"24", x"5c", x"c2", x"d3", x"ac", x"62", x"91", x"95", x"e4", x"79",
    x"e7", x"c8", x"37", x"6d", x"8d", x"d5", x"4e", x"a9", x"6c", x"56", x"f4", x"ea", x"65", x"7a", x"ae", x"08",
    x"ba", x"78", x"25", x"2e", x"1c", x"a6", x"b4", x"c6", x"e8", x"dd", x"74", x"1f", x"4b", x"bd", x"8b", x"8a",
    x"70", x"3e", x"b5", x"66", x"48", x"03", x"f6", x"0e", x"61", x"35", x"57", x"b9", x"86", x"c1", x"1d", x"9e",
    x"e1", x"f8", x"98", x"11", x"69", x"d9", x"8e", x"94", x"9b", x"1e", x"87", x"e9", x"ce", x"55", x"28", x"df",
    x"8c", x"a1", x"89", x"0d", x"bf", x"e6", x"42", x"68", x"41", x"99", x"2d", x"0f", x"b0", x"54", x"bb", x"16"
  );

  function to_state (v : block_t) return state_t is
    variable s : state_t;
  begin
    for i in 0 to 15 loop
      s(i) := v(127 - 8*i downto 120 - 8*i);
    end loop;
    return s;
  end function;

  function to_block (s : state_t) return block_t is
    variable v : block_t;
  begin
    for i in 0 to 15 loop
      v(127 - 8*i downto 120 - 8*i) := s(i);
    end loop;
    return v;
  end function;

  function sbox_f (b : byte_t) return byte_t is
  begin
    return SBOX(to_integer(unsigned(b)));
  end function;

  function xtime (b : byte_t) return byte_t is
    variable r : byte_t := b(6 downto 0) & '0';
  begin
    if b(7) = '1' then
      r := r xor x"1B";
    end if;
    return r;
  end function;

  function sub_bytes (s : state_t) return state_t is
    variable r : state_t;
  begin
    for i in 0 to 15 loop
      r(i) := sbox_f(s(i));
    end loop;
    return r;
  end function;

  -- new(row, col) = old(row, (col + row) mod 4)
  function shift_rows (s : state_t) return state_t is
    variable r : state_t;
  begin
    for c in 0 to 3 loop
      for rw in 0 to 3 loop
        r(4*c + rw) := s(4*((c + rw) mod 4) + rw);
      end loop;
    end loop;
    return r;
  end function;

  function mix_columns (s : state_t) return state_t is
    variable r : state_t;
    variable a0, a1, a2, a3 : byte_t;
  begin
    for c in 0 to 3 loop
      a0 := s(4*c);   a1 := s(4*c+1);
      a2 := s(4*c+2); a3 := s(4*c+3);
      r(4*c)   := xtime(a0) xor (xtime(a1) xor a1) xor a2 xor a3;
      r(4*c+1) := a0 xor xtime(a1) xor (xtime(a2) xor a2) xor a3;
      r(4*c+2) := a0 xor a1 xor xtime(a2) xor (xtime(a3) xor a3);
      r(4*c+3) := (xtime(a0) xor a0) xor a1 xor a2 xor xtime(a3);
    end loop;
    return r;
  end function;

  function rcon_for (round : natural) return byte_t is
  begin
    case round is
      when 1  => return x"01";
      when 2  => return x"02";
      when 3  => return x"04";
      when 4  => return x"08";
      when 5  => return x"10";
      when 6  => return x"20";
      when 7  => return x"40";
      when 8  => return x"80";
      when 9  => return x"1B";
      when 10 => return x"36";
      when others => return x"00";
    end case;
  end function;

  -- One step of the AES-128 key schedule (on-the-fly): rk(i) -> rk(i+1)
  function next_round_key (rk : block_t; rcon : byte_t) return block_t is
    variable w0, w1, w2, w3, t : std_logic_vector(31 downto 0);
    variable n0, n1, n2, n3    : std_logic_vector(31 downto 0);
  begin
    w0 := rk(127 downto 96);
    w1 := rk(95 downto 64);
    w2 := rk(63 downto 32);
    w3 := rk(31 downto 0);
    -- RotWord then SubWord on w3, then Rcon into the top byte
    t := sbox_f(w3(23 downto 16)) & sbox_f(w3(15 downto 8)) &
         sbox_f(w3(7 downto 0))   & sbox_f(w3(31 downto 24));
    t(31 downto 24) := t(31 downto 24) xor rcon;
    n0 := w0 xor t;
    n1 := w1 xor n0;
    n2 := w2 xor n1;
    n3 := w3 xor n2;
    return n0 & n1 & n2 & n3;
  end function;

end package body aes_pkg;
