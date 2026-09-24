library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use work.lib_config.all;

entity progLineal_tb is
end entity progLineal_tb;

architecture sim of progLineal_tb is

    constant C_VARS  : integer := 3;
    constant C_REST  : integer := 3;
    constant CLK_PER : time := 10 ns;

    function to_fp(val : real) return fp_type is
    begin
        return to_signed(integer(val * real(2**FRAC_WIDTH)), TOTAL_WIDTH);
    end function;

    signal clk               : std_logic := '0';
    signal reset             : std_logic := '1';
    signal start             : std_logic := '0';
    signal done              : std_logic;
    signal result            : array_of_fp(0 to C_VARS - 1);
    
    -- Z = 5x1 + 4x2 + 3x3
    signal funcObj           : array_of_fp(0 to C_VARS - 1) := (
        to_fp(5.0), to_fp(4.0), to_fp(3.0)
    );
    
    -- Restricciones
    signal restrictionsFuncs : matrix_of_fp(0 to C_REST - 1)(0 to C_VARS) := (
        (to_fp(2.0), to_fp(3.0), to_fp(1.0), to_fp(5.0)),  -- R0: 2x1 + 3x2 + 1x3 <= 5
        (to_fp(4.0), to_fp(1.0), to_fp(2.0), to_fp(11.0)), -- R1: 4x1 + 1x2 + 2x3 <= 11
        (to_fp(3.0), to_fp(4.0), to_fp(2.0), to_fp(8.0))   -- R2: 3x1 + 4x2 + 2x3 <= 8
    );

begin

    UUT : entity work.progLineal
        generic map (
            N_VARIABLES    => C_VARS,
            N_RESTRICTIONS => C_REST
        )
        port map (
            clk               => clk,
            reset             => reset,
            start             => start,
            done              => done,
            result            => result,
            funcObj           => funcObj,
            restrictionsFuncs => restrictionsFuncs
        );

    clk_process : process
    begin
        clk <= '0';
        wait for CLK_PER / 2;
        clk <= '1';
        wait for CLK_PER / 2;
    end process;

    stim_proc: process
    begin
        reset <= '1';
        start <= '0';
        wait for CLK_PER * 5;
        
        reset <= '0';
        wait for CLK_PER * 2;
        
        report "Iniciando modulo de Programacion Lineal (Matriz 3x3)...";
        start <= '1';
        wait for CLK_PER;
        start <= '0'; 
        
        wait until done = '1';
        
        report "Procesamiento finalizado. Revisa GTKWave.";
        wait;
    end process;

end architecture sim;

-- ghdl -a --std=08 ../lib_config.vhd
-- ghdl -a --std=08 ../ops_varias/gauss_jordan.vhd
-- ghdl -a --std=08 ../Cntrl_Inteligente/progLineal.vhd
-- ghdl -a --std=08 progLineal_tb.vhd
-- ghdl -e --std=08 progLineal_tb
-- ghdl -r --std=08 progLineal_tb --fst=ondas_fst.fst --stop-time=50000ns