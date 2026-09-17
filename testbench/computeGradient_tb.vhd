-- ==============================================================================
-- @file    computeGradient_tb.vhd
-- @brief   Testbench for the N-Dimensional Gradient Computation module.
-- @author  Jose Segura Montes
-- @date    17/09/2026
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.lib_config.all;
-- =====================================================================
-- MAIN TESTBENCH
-- =====================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.lib_config.all;

entity computeGradient_tb is
end entity computeGradient_tb;

architecture sim of computeGradient_tb is

    -- Clock period definition
    constant CLK_PERIOD : time := 10 ns;

    -- DUT signals
    signal clk     : std_logic := '0';
    signal reset   : std_logic := '1';
    signal start   : std_logic := '0';
    signal done    : std_logic;
    
    signal x_start : array_of_fp(0 to 1);
    signal grad    : array_of_fp(0 to 1);

    -- Expected results in Q8.24 (grad_0 = 1.0, grad_1 = 2.0)
    constant EXPECTED_G0 : fp_type := to_signed(1 * (2**24), 32);
    constant EXPECTED_G1 : fp_type := to_signed(2 * (2**24), 32);

begin

    -- Device Under Test (DUT) Instantiation
    DUT: entity work.computeGradient
        generic map (
            N_DIM   => 2,
            H       => to_signed(2**(24-5), 32), -- 2^-5 in Q8.24 format
            H_SHIFT => 5
        )
        port map (
            clk     => clk,
            reset   => reset,
            start   => start,
            done    => done,
            x_start => x_start,
            grad    => grad
        );

    -- Clock Generation
    clk_process : process
    begin
        clk <= '0';
        wait for CLK_PERIOD/2;
        clk <= '1';
        wait for CLK_PERIOD/2;
    end process;

    -- Stimulus Process
    stim_proc: process
    begin
        -- 1. Initialize System
        reset <= '1';
        start <= '0';
        x_start(0) <= (others => '0');
        x_start(1) <= (others => '0');
        wait for CLK_PERIOD * 5;
        
        reset <= '0';
        wait for CLK_PERIOD * 2;

        -- 2. Provide input vector: x = [3.0, 4.5] (arbitrary test values)
        x_start(0) <= to_signed(integer(3.0 * real(2**24)), 32);
        x_start(1) <= to_signed(integer(4.5 * real(2**24)), 32);
        
        -- Trigger computation
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        -- 3. Wait for DUT to assert 'done'
        wait until done = '1';
        
        -- 4. Verification and Console Output
        wait for CLK_PERIOD;

        -- End simulation gracefully
        wait for CLK_PERIOD * 10;
        std.env.stop;
    end process;

end architecture sim;

-- ghdl -a --std=08 ../lib_config.vhd
-- ghdl -a --std=08 ../Fcn_example/fcn_2.vhd
-- ghdl -a --std=08 ../ops_varias/computeGradient.vhd
-- ghdl -a --std=08 computeGradient_tb.vhd
-- ghdl -e --std=08 computeGradient_tb
-- ghdl -r --std=08 computeGradient_tb --fst=ondas_fst.fst --stop-time=50000ns