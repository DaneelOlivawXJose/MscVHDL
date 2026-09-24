-- ==============================================================================
-- @file    steepestGradient_tb.vhd
-- @brief   Testbench for the Steepest Gradient Descent algorithm using fcn_2
-- @author  Jose Segura Montes
-- @date    17/09/2026
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.lib_config.all;

entity steepestGradient_tb is
end entity steepestGradient_tb;

architecture sim of steepestGradient_tb is
    constant CLK_PERIOD : time := 10 ns;

    signal clk         : std_logic := '0';
    signal reset       : std_logic := '1';
    signal start       : std_logic := '0';
    signal done        : std_logic;
    
    signal start_point : array_of_fp(0 to 1);
    signal result      : array_of_fp(0 to 1);

    -- x0 = 3.0, x1 = 4.5
    constant X0_INIT : fp_type := to_signed(integer(3.0 * real(2**24)), 32);
    constant X1_INIT : fp_type := to_signed(integer(4.5 * real(2**24)), 32);

begin

    DUT: entity work.steepestGradient
        generic map (
            MAX_ITER    => 2000,
            N_DIM       => 2,
            H           => to_signed(2**(24-5), 32),
            H_SHIFT     => 5,
            ALPHA_SHIFT => 5,
            MAX_ERR     => to_signed(integer(0.000002*real(2**24)), TOTAL_WIDTH) 
        )
        port map (
            clk         => clk,
            reset       => reset,
            start       => start,
            done        => done,
            start_point => start_point,
            result      => result
        );

    clk_process : process
    begin
        clk <= '0';
        wait for CLK_PERIOD/2;
        clk <= '1';
        wait for CLK_PERIOD/2;
    end process;

    stim_proc: process
    begin
        reset <= '1';
        start <= '0';
        start_point(0) <= (others => '0');
        start_point(1) <= (others => '0');
        wait for CLK_PERIOD * 5;
        
        reset <= '0';
        wait for CLK_PERIOD * 2;

        start_point(0) <= X0_INIT;
        start_point(1) <= X1_INIT;
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        wait until done = '1';
        wait for CLK_PERIOD;

        report "====== SIMULATION COMPLETED ======" severity note;
        report "Expected Result: Close to [0.0, 0.0]" severity note;
        
        wait for CLK_PERIOD * 10;
        std.env.stop;
    end process;

end architecture sim;

-- ghdl -a --std=08 ../lib_config.vhd
-- ghdl -a --std=08 ../Fcn_example/fcn_1.vhd
-- ghdl -a --std=08 ../ops_varias/computeGradient.vhd
-- ghdl -a --std=08 ../Cntrl_Inteligente/steepestGradient.vhd
-- ghdl -a --std=08 steepestGradient_tb.vhd
-- ghdl -e --std=08 steepestGradient_tb
-- ghdl -r --std=08 steepestGradient_tb --fst=ondas_fst.fst --stop-time=50000ns