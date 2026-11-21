-- tb_aes_core.vhd : self-checking testbench for aes_core.
-- Vectors: FIPS-197 C.1, NIST SP 800-38A F.1.1 (ECB-AES128, 4 blocks),
-- all-zero / all-one corner cases and 20 random vectors (reference:
-- pycryptodome). Also checks that the latency is exactly 11 clocks.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.aes_pkg.all;

entity tb_aes_core is
end entity tb_aes_core;

architecture sim of tb_aes_core is
  constant CLK_PERIOD : time := 10 ns;   -- 100 MHz

  type vec_t is record
    key : std_logic_vector(127 downto 0);
    pt  : std_logic_vector(127 downto 0);
    ct  : std_logic_vector(127 downto 0);
  end record;
  type vec_arr_t is array (natural range <>) of vec_t;

  constant VECTORS : vec_arr_t(0 to 27 - 1) := (
    ( key => x"000102030405060708090a0b0c0d0e0f", pt => x"00112233445566778899aabbccddeeff", ct => x"69c4e0d86a7b0430d8cdb78070b4c55a" ),  -- FIPS-197 C.1
    ( key => x"2b7e151628aed2a6abf7158809cf4f3c", pt => x"6bc1bee22e409f96e93d7e117393172a", ct => x"3ad77bb40d7a3660a89ecaf32466ef97" ),  -- SP800-38A F.1.1 block 1
    ( key => x"2b7e151628aed2a6abf7158809cf4f3c", pt => x"ae2d8a571e03ac9c9eb76fac45af8e51", ct => x"f5d3d58503b9699de785895a96fdbaaf" ),  -- SP800-38A F.1.1 block 2
    ( key => x"2b7e151628aed2a6abf7158809cf4f3c", pt => x"30c81c46a35ce411e5fbc1191a0a52ef", ct => x"43b1cd7f598ece23881b00e3ed030688" ),  -- SP800-38A F.1.1 block 3
    ( key => x"2b7e151628aed2a6abf7158809cf4f3c", pt => x"f69f2445df4f9b17ad2b417be66c3710", ct => x"7b0c785e27e8ad3f8223207104725dd4" ),  -- SP800-38A F.1.1 block 4
    ( key => x"00000000000000000000000000000000", pt => x"00000000000000000000000000000000", ct => x"66e94bd4ef8a2c3b884cfa59ca342b2e" ),  -- all zeros
    ( key => x"ffffffffffffffffffffffffffffffff", pt => x"ffffffffffffffffffffffffffffffff", ct => x"bcbf217cb280cf30b2517052193ab979" ),  -- all ones
    ( key => x"e13b032e112a32b579080f08b1f7ed4c", pt => x"2e5d3a07f97f21ee232d178a209af6b5", ct => x"e434f495f239d04dab23441aef64dbba" ),  -- random 0
    ( key => x"887f66e8092402aa49f2c1551b27fe53", pt => x"266e490db138489ce814d58d145a8b4f", ct => x"23f18ac60d5eac61a95a2667ef0de734" ),  -- random 1
    ( key => x"994fed15c5b2fdaeeff317f157e1e097", pt => x"8c3f5fd5df3d34f8c08262b03750894f", ct => x"e4a77a5cf65f92fd9c1ca36407d94392" ),  -- random 2
    ( key => x"a5e42428ca6d189213702ca29ceb2183", pt => x"25da6733cb63eb78b869d759689a1eb4", ct => x"3d66058267038ec6f4700d961afedcc0" ),  -- random 3
    ( key => x"4efff1aa474318544a23a657001f2c4b", pt => x"6f14ddc8a66ac38f9bd8a34d2f858ed2", ct => x"09b73ba02ab3f9187a24c00bfc37341b" ),  -- random 4
    ( key => x"cc8d3ac08c6d98cb1ab2e177fb54c29d", pt => x"0125f5ca98dbf55fcdf45090bdb16956", ct => x"cd085d616e1d1fb11536631fd9a16582" ),  -- random 5
    ( key => x"eaf20eef350dbbf32147a9b29498a996", pt => x"638e2568adaba4ea882b3d7d83be460e", ct => x"f6431605f8a376aeb3a858bb39bbe885" ),  -- random 6
    ( key => x"ca13166a4fa0b5de239c85f870b22a09", pt => x"a97553f4ff47224a7c54c9a742e414be", ct => x"01f42755fedac3c8fd26d4f36e90c9d8" ),  -- random 7
    ( key => x"23bcd11624a07465b1c2fc1a0fe52996", pt => x"daae4bf87b0fb6bed45926096c644843", ct => x"b788386bd326b11915ae74e0d3a13c8e" ),  -- random 8
    ( key => x"8219efb9be93cbd0bc779204a0883d12", pt => x"6fbd5ea495b98b5ae95601d17a62e38b", ct => x"aca488462a59e9e3b3017c03999df082" ),  -- random 9
    ( key => x"59b5d1f8f6f5e3be34cd4136f0f93143", pt => x"837a24abc896b5cf60f2eea3e237ed2b", ct => x"f7d890e82d9c87243d5ebdc7bd7458d5" ),  -- random 10
    ( key => x"26655aab58c18b66870f50a133171c85", pt => x"d9a5ae9dde55c0ca049491a27f4f63e7", ct => x"99e1a2d001b960428d3dbd6b875fa9e3" ),  -- random 11
    ( key => x"e3d5ac89dec884fca17e925053d25011", pt => x"77b569dce30ccf2320247dc3f8c2799a", ct => x"48a52a74b9ed357a3bc06bf75bbc73fb" ),  -- random 12
    ( key => x"a7e7209b0d5c494bc0db5a469a30faab", pt => x"4488dcf18ea15521e075e27f22884f8c", ct => x"0f0bf73bb73c81ce59d5c3dc84efded8" ),  -- random 13
    ( key => x"4ac96f664a6cafd300b161720809b9e1", pt => x"7905d4d8fed7a97ff89cf0080a953fe7", ct => x"4a8bd754faa537db8051fcabd7659d58" ),  -- random 14
    ( key => x"7dcad66b15dcc839d35b5925bc577520", pt => x"c21041890eb01e8c0917d2f60f935d76", ct => x"28c78f7307ad2890d22c41ef40c29201" ),  -- random 15
    ( key => x"fa1f967ce4ea598652d59f0495a6695e", pt => x"109dff09d953dead923028d6ab13d1e2", ct => x"c850afc20239c43e020f1876fdb73a46" ),  -- random 16
    ( key => x"5dcf36a96133ca2da24025a9f6862720", pt => x"e605b4126e37e45b1588cc9e10acaf6c", ct => x"dbdaefd60889132b512954abb01556a5" ),  -- random 17
    ( key => x"2c7c329908222b0e98b0dc09c8e92c6f", pt => x"28b2abb4c6b5300f4244e6b740311f88", ct => x"9a057f9ba583e7714dede087794912f2" ),  -- random 18
    ( key => x"5110adfc2adeb809d7a1625475d857dd", pt => x"ff47c2f3c59c8d8449b743859f7f9755", ct => x"7b9bddf804b873ec4270347c6f07ef32" )   -- random 19
  );

  signal clk, rst, start, busy, done : std_logic := '0';
  signal key, din, dout : std_logic_vector(127 downto 0) := (others => '0');
  signal cyc      : natural := 0;
  signal sim_done : boolean := false;

  function hex128 (v : std_logic_vector(127 downto 0)) return string is
    constant H : string(1 to 16) := "0123456789abcdef";
    variable r : string(1 to 32);
  begin
    for i in 0 to 31 loop
      r(i + 1) := H(to_integer(unsigned(v(127 - 4*i downto 124 - 4*i))) + 1);
    end loop;
    return r;
  end function;
begin

  dut : entity work.aes_core
    port map (clk => clk, rst => rst, start => start, key => key,
              data_in => din, busy => busy, done => done, data_out => dout);

  clk_gen : process
  begin
    while not sim_done loop
      clk <= '0'; wait for CLK_PERIOD / 2;
      clk <= '1'; wait for CLK_PERIOD / 2;
    end loop;
    wait;
  end process;

  cycle_counter : process (clk)
  begin
    if rising_edge(clk) then
      cyc <= cyc + 1;
    end if;
  end process;

  stim : process
    variable c0, lat : natural;
    variable errors  : natural := 0;
  begin
    rst <= '1';
    wait for 5 * CLK_PERIOD;
    wait until rising_edge(clk);
    rst <= '0';

    for i in VECTORS'range loop
      key <= VECTORS(i).key;
      din <= VECTORS(i).pt;
      wait until rising_edge(clk);
      start <= '1';
      wait until rising_edge(clk);      -- DUT samples start on this edge
      c0 := cyc;
      start <= '0';
      wait until done = '1' for 1 us;
      lat := cyc - c0;
      wait for 1 ns;                    -- let data_out settle (delta-cycle skew in simulation)

      if done /= '1' then
        report "vector " & integer'image(i) & ": TIMEOUT" severity error;
        errors := errors + 1;
      else
        if dout /= VECTORS(i).ct then
          report "vector " & integer'image(i) & ": MISMATCH" & LF &
                 "  got      " & hex128(dout) & LF &
                 "  expected " & hex128(VECTORS(i).ct) severity error;
          errors := errors + 1;
        end if;
        if lat /= 11 then
          report "vector " & integer'image(i) & ": latency " &
                 integer'image(lat) & " clocks, expected 11" severity error;
          errors := errors + 1;
        end if;
      end if;
      wait until rising_edge(clk);
    end loop;

    if errors = 0 then
      report "ALL " & integer'image(VECTORS'length) &
             " TESTS PASSED (latency 11 clocks = 110 ns @ 100 MHz)" severity note;
    else
      report integer'image(errors) & " ERROR(S)" severity failure;
    end if;
    sim_done <= true;
    wait;
  end process;

end architecture sim;
