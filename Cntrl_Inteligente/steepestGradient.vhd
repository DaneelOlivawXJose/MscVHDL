-- @file    steepestGradient.vhd
-- @brief   Hardware Implementation of the Steepest Gradient Descent Algorithm
-- @author  Jose Segura Montes
-- @date    17/09/2026
--
-- @note    ALGORITHM DESCRIPTION:
--          This module implements the steepest descent (gradient descent) optimization 
--          algorithm to iteratively find the local minimum of an N-dimensional function.
--          Starting from an initial point, it updates the coordinates by taking steps 
--          proportional to the negative of the gradient at the current point.
--          The equation per dimension is: x_new = x_old - (alpha * gradient).
--          Convergence is achieved when the L1 norm (sum of absolute values) of the 
--          gradient falls below a predefined error threshold (MAX_ERR) or when the 
--          maximum number of iterations (MAX_ITER) is reached.
--
-- @note    HARDWARE ARCHITECTURE:
--          - Data Format: Q8.24 Signed Fixed-Point Arithmetic.
--          - FSM Controller: A 5-state Finite State Machine orchestrates the iterative 
--            process, handling the handshake protocol with the gradient calculation core.
--          - Division Optimization: The learning rate (alpha) is restricted to powers of 2. 
--            Multiplying by alpha is executed as an arithmetic right shift (ALPHA_SHIFT), 
--            bypassing the need for resource-heavy DSP multipliers.
--          - Combinational L1 Norm: The error metric is computed combinatorially within 
--            a single clock cycle using an unrolled loop and hardware absolute value logic.
--
-- @note    HOW TO USE:
--          Instantiate this module, provide the starting coordinates via 'start_point', 
--          and pulse the 'start' signal for one clock cycle. The module will drive the 
--          'done' signal high once the algorithm converges, presenting the final optimized 
--          coordinates on the 'result' port.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.lib_config.all;

entity steepestGradient is
    generic (
        -- Maximum allowed algorithmic iterations to prevent infinite loops
        MAX_ITER    : natural := 1000;
        -- Number of variables/dimensions in the mathematical function
        N_DIM       : natural := 2;
        -- Finite difference increment for the gradient calculation (e.g., 2^-5)
        H           : fp_type := to_signed(2**(24-5), TOTAL_WIDTH); 
        -- Bit-shift equivalent of dividing by H
        H_SHIFT     : natural := 5; 
        -- Bit-shift equivalent of multiplying by the learning rate alpha (e.g., 2^-5)
        ALPHA_SHIFT : natural := 5;
        -- L1 Norm error tolerance threshold for convergence (10000 in Q8.24 is approx 0.0006)
        MAX_ERR     : fp_type := to_signed(10000, TOTAL_WIDTH) 
    );
    port(
        clk         : in std_logic;
        reset       : in std_logic;
        start       : in std_logic;
        done        : out std_logic;

        start_point : in array_of_fp;
        result      : out array_of_fp
    );
end entity steepestGradient;

architecture behavior of steepestGradient is
    -- FSM States definition for the optimization loop
    type state_type is (IDLE, COMPUTE_GRADIENT, UPDATE_POINT, CHECK_CONVERGENCE, DONE_STATE);
    signal state : state_type := IDLE;
    
    -- Internal registers to hold current coordinates and the calculated gradient
    signal x         : array_of_fp(0 to N_DIM-1) := (others => FP_ZERO);
    signal grad_temp : array_of_fp(0 to N_DIM-1) := (others => FP_ZERO);
    
    -- Register to hold the calculated L1 norm of the current gradient
    signal err       : fp_type := (others => '0');
    
    -- Counter for the current iteration number
    signal iter      : natural := 0;

    -- Handshake signals to interface with the computeGradient submodule
    signal start_grad   : std_logic := '0';
    signal done_grad    : std_logic; 
begin

    -- Instantiation of the gradient calculation IP core
    GRAD: entity work.computeGradient
        generic map (
            N_DIM   => N_DIM,
            H       => H,
            H_SHIFT => H_SHIFT
        )
        port map (
            clk     => clk,
            reset   => reset,
            start   => start_grad,
            done    => done_grad,
            x_start => x,
            grad    => grad_temp
        );

    process(clk, reset)
        -- Variable used to combinationally accumulate the L1 norm within a single clock cycle
        variable temp_err : fp_type; 
    begin
        if reset = '1' then
            iter       <= 0;
            state      <= IDLE;
            done       <= '0';
            start_grad <= '0';
            err        <= (others => '0');
            x          <= (others => FP_ZERO);
            result     <= (others => FP_ZERO);
            
        elsif rising_edge(clk) then
            case state is
                when IDLE =>
                    done <= '0';
                    if start = '1' then
                        -- Latch the initial coordinates and reset loop metrics
                        x          <= start_point;
                        iter       <= 0;
                        err        <= (others => '0');
                        
                        -- Trigger the first gradient computation
                        start_grad <= '1'; 
                        state      <= COMPUTE_GRADIENT;
                    end if;

                when COMPUTE_GRADIENT =>
                    -- De-assert the start trigger immediately to create a 1-cycle pulse
                    start_grad <= '0'; 
                    
                    -- Wait synchronously for the sub-module to finish its math pipeline
                    if done_grad = '1' then
                        state <= UPDATE_POINT;
                    end if;
                    
                when UPDATE_POINT =>
                    -- Initialize the combinational accumulator variable
                    temp_err := (others => '0');
                    
                    for i in 0 to N_DIM-1 loop
                        -- 1. Descent Step: x(i) = x(i) - (gradient(i) * alpha)
                        -- The arithmetic right shift effectively scales down the gradient by alpha
                        x(i) <= x(i) - shift_right(grad_temp(i), ALPHA_SHIFT);
                        
                        -- 2. Error Calculation: Accumulate the L1 Norm of the gradient
                        -- The hardware abs() function prevents opposite signs from canceling out
                        temp_err := temp_err + abs(grad_temp(i));
                    end loop;
                    
                    -- Commit the combinationally calculated L1 norm to the error register
                    err <= temp_err; 
                    state <= CHECK_CONVERGENCE;

                when CHECK_CONVERGENCE =>
                    -- Stop condition: Hard iteration limit reached OR gradient is sufficiently flat
                    if iter >= MAX_ITER - 1 or err <= MAX_ERR then
                        state <= DONE_STATE;
                    else
                        -- Continue to the next step: increment counter and re-trigger gradient math
                        iter       <= iter + 1;
                        start_grad <= '1'; 
                        state      <= COMPUTE_GRADIENT;
                    end if;

                when DONE_STATE =>
                    -- Expose the final optimized coordinates to the output port
                    result <= x;
                    
                    -- Assert the done flag to signal external modules
                    done   <= '1';
                    
                    -- Full handshake protocol: Wait for the master to acknowledge by lowering 'start'
                    if start = '0' then 
                        state <= IDLE;
                    end if;
                    
            end case;
        end if;
    end process;

end behavior;