-- ==============================================================================
-- @file    computeGradient.vhd
-- @brief   N-Dimensional Gradient Computation via Forward Finite Differences
-- @author  Jose Segura Montes (adapted for high-precision hardware)
-- @date    17/09/2026
--
-- @note    ALGORITHM DESCRIPTION:
--          Computes the gradient vector of an n-dimensional scalar function f(x).
--          It approximates the partial derivatives using the forward difference 
--          quotient: df/dxi ? (f(x1, ..., xi + h, ..., xn) - f(x)) / h.
--          To avoid expensive floating-point division, 'h' is constrained to be a 
--          power of 2 (e.g., 2^-5). Thus, the division is optimized into a simple 
--          logical left shift (H_SHIFT).
--
-- @note    HARDWARE ARCHITECTURE:
--          - Data Format: Q8.24 Signed Fixed-Point Arithmetic (can be changed in lib_config.vhd).
--          - Spatial Pipeline: The incremented input vectors (x + h) are computed
--            combinationally. 
--          - Parallel Execution: N_DIM + 1 instances of the function evaluator 
--            (fcn_2) are spawned to evaluate f(x) and all f(x_i + h) simultaneously.
--          - Extended Precision: The subtraction and shifting are performed using 
--            64-bit registers (fp_mult_type) to prevent overflow during intermediate 
--            calculations, ending with a saturation block to safely downcast back 
--            to the standard 32-bit fp_type
-- @note    HOW TO USE & CONFIGURE:
--          1. Protocol: Set the 'N_DIM' generic to match your function's variables.
--             Provide the input coordinate vector on 'x_start', pulse 'start' high 
--             for one clock cycle, and wait for the 'done' signal to assert.
--          2. CHANGING THE TARGET FUNCTION: VHDL requires static instantiation. 
--             To compute the gradient of a different mathematical module (e.g., 
--             'fcn_2' instead of 'fcn_1'), you MUST manually change the entity name 
--             in the architecture below. Search for "entity work.fcn_1" and replace 
--             it with your new function's name in both the 'calc_inst_normal' 
--             and 'calc_inst_h' instantiation blocks.
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.lib_config.all;

entity computeGradient is
    generic (
        N_DIM   : natural := 2; -- Number of dimensions for the input point
        -- Default H = 2^-5. In Q8.24, this is 2^(24-5) = 524288
        H       : fp_type := to_signed(2**(24-5), TOTAL_WIDTH); 
        H_SHIFT : natural := 5  -- Shift amount equivalent to dividing by H
    );
    port(
        clk         : in std_logic;
        reset       : in std_logic;
        start       : in std_logic;
        done        : out std_logic;

        x_start     : in array_of_fp(0 to N_DIM-1); 
        grad        : out array_of_fp(0 to N_DIM-1)
    );
end entity computeGradient;

architecture behavior of computeGradient is

    -- FSM States:
    -- IDLE      : Waiting for start pulse.
    -- WAIT_FCN  : Waiting for all parallel function evaluators to assert 'terminado'.
    -- CALC_GRAD : Performing high-precision subtraction, division (shift) and saturation.
    type state_type is (IDLE, WAIT_FCN, CALC_GRAD);
    signal state : state_type := IDLE;

    -- Custom types for N-dimensional matrix routing
    subtype point_t is array_of_fp(0 to N_DIM-1);
    type matrix_t is array(0 to N_DIM-1) of point_t;

    -- Internal data routing signals
    signal x_actual   : point_t := (others => FP_ZERO);
    signal x_plus_h   : matrix_t := (others => (others => FP_ZERO));

    -- Handshake and data signals for function instances
    signal start_fcn  : std_logic := '0';
    
    signal f_x        : fp_type;
    signal fcn_done   : std_logic := '0';

    signal res_fcn_h  : point_t := (others => FP_ZERO);
    signal fcn_h_done : std_logic_vector(0 to N_DIM-1) := (others => '0');

    -- Constant to easily evaluate if all N_DIM function instances are done
    constant ALL_ONES : std_logic_vector(0 to N_DIM-1) := (others => '1');

begin

    -- 1. COMBINATIONAL MATRIX GENERATION (Spatial preparation)
    -- Generates a 2D matrix where row 'i' contains the input vector 'x' 
    -- with the scalar 'H' added exclusively to the i-th dimension.
    process(x_actual)
    begin
        for i in 0 to N_DIM-1 loop
            for j in 0 to N_DIM-1 loop
                if i = j then
                    x_plus_h(i)(j) <= x_actual(j) + H;
                else
                    x_plus_h(i)(j) <= x_actual(j);
                end if;
            end loop;
        end loop;
    end process;

    -- 2. PARALLEL FUNCTION INSTANTIATION
    -- Spawns all required function evaluators to run concurrently.
    
    -- Evaluates the unshifted base point: f(x)
    calc_inst_normal: entity work.fcn_2
        port map (
            clk       => clk,
            reset     => reset,
            start     => start_fcn,
            entradas  => x_actual,  
            resultado => f_x,
            terminado => fcn_done
        );

    -- Evaluates the shifted points: f(x + h_i)
    GEN_FCN: for i in 0 to N_DIM-1 generate
        calc_inst_h: entity work.fcn_2
            port map (
                clk       => clk,
                reset     => reset,
                start     => start_fcn,
                entradas  => x_plus_h(i), 
                resultado => res_fcn_h(i),
                terminado => fcn_h_done(i)
            );
    end generate;

    -- 3. FSM & HIGH-PRECISION GRADIENT CALCULATOR
    -- Controls execution flow and performs extended-precision arithmetic
    -- to avoid truncation loss and arithmetic overflow.
    process(clk, reset)
        -- Variables for 64-bit extended precision operations
        variable ext_f_x     : fp_mult_type;
        variable ext_f_h     : fp_mult_type;
        variable ext_diff    : fp_mult_type;
        variable ext_shifted : fp_mult_type;
        
        -- Variables for saturation logic
        variable sign_bit    : std_logic;
        variable upper_bits  : signed((TOTAL_WIDTH*2)-1 downto TOTAL_WIDTH-1);
    begin
        if reset = '1' then
            state     <= IDLE;
            done      <= '0';
            start_fcn <= '0';
            grad      <= (others => FP_ZERO);
            x_actual  <= (others => FP_ZERO);
            
        elsif rising_edge(clk) then
            case state is
                when IDLE =>
                    done <= '0';
                    if start = '1' then
                        x_actual  <= x_start; 
                        start_fcn <= '1';     -- Trigger parallel functions
                        state     <= WAIT_FCN;
                    end if;

                when WAIT_FCN =>
                    start_fcn <= '0'; -- Clear trigger
                    
                    -- Await completion of base f(x) AND all partial derivatives
                    if fcn_done = '1' and fcn_h_done = ALL_ONES then
                        state <= CALC_GRAD;
                    end if;

                when CALC_GRAD =>
                    -- Process each partial derivative using 64-bit precision
                    for i in 0 to N_DIM-1 loop
                        -- 1. Cast to 64-bit (Sign extension)
                        ext_f_x  := resize(f_x, TOTAL_WIDTH*2);
                        ext_f_h  := resize(res_fcn_h(i), TOTAL_WIDTH*2);
                        
                        -- 2. Subtract safely without overflow risk
                        ext_diff := ext_f_h - ext_f_x;
                        
                        -- 3. Divide by H (equivalent to shifting left by H_SHIFT)
                        ext_shifted := shift_left(ext_diff, H_SHIFT);
                        
                        -- 4. Safe Downcast & Saturation Check
                        -- Extract the bits that will be discarded plus the new sign bit
                        upper_bits := ext_shifted((TOTAL_WIDTH*2)-1 downto TOTAL_WIDTH-1);
                        
                        -- If upper bits are all '0' (positive) or all '1' (negative), it fits cleanly
                        if upper_bits = (upper_bits'range => '0') or upper_bits = (upper_bits'range => '1') then
                            grad(i) <= resize(ext_shifted, TOTAL_WIDTH);
                        else
                            -- Hardware Overflow: Saturate to max positive or max negative
                            sign_bit := ext_shifted((TOTAL_WIDTH*2)-1);
                            if sign_bit = '0' then
                                -- Saturation Positive: 0111...111
                                grad(i) <= (TOTAL_WIDTH-1 => '0', others => '1');
                            else
                                -- Saturation Negative: 1000...000
                                grad(i) <= (TOTAL_WIDTH-1 => '1', others => '0');
                            end if;
                        end if;
                    end loop;
                    
                    done  <= '1'; 
                    state <= IDLE;
            end case;
        end if;
    end process;

end behavior;