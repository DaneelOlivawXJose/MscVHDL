-- ==============================================================================
-- @file    progLineal.vhd
-- @brief   Linear Programming Solver via Simplex Method (Hardware Implementation)
-- @author  Jose Segura Montes
-- @date    16/09/2026
--
-- @note    ALGORITHM DESCRIPTION:
--          Implements the Simplex algorithm for computational linear programming.
--          The module constructs a Simplex Tableau by converting inequalities 
--          into equations via slack variables. It currently acts as a controller 
--          that formats the constraint matrix and objective function, then 
--          delegates the mathematical reduction (pivoting) to an external 
--          Gauss-Jordan coprocessor.
--
-- @note    HARDWARE ARCHITECTURE:
--          Designed as a Finite State Machine (FSM) that controls data flow 
--          and handshake protocols with the 'gauss_jordan' computational core.
--          Data format: Q8.24 Signed Fixed-Point Arithmetic (defined in lib_config).
--          The FSM parallelizes the matrix construction (Spatial Pipeline) before
--          triggering the sequential elimination process.
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.lib_config.all;

entity progLineal is 
    generic(
        N_VARIABLES     : integer := 2;  -- Number of decision variables
        N_RESTRICTIONS  : integer := 1;   -- Number of constraints
        GJ_PARALLEL_UNITS  : integer := 2
    );
    port (
        clk                 : in std_logic;
        reset               : in std_logic;
        start               : in std_logic;
        done                : out std_logic;
        
        -- Extracted solution vector (currently maps the RHS of the tableau)
        result              : out array_of_fp(0 to N_VARIABLES - 1);
        
        -- Objective function coefficients (to be maximized)
        funcObj             : in array_of_fp(0 to N_VARIABLES - 1);
        
        -- Constraint matrix (Includes coefficients and the RHS constraint bound)
        restrictionsFuncs   : in matrix_of_fp(0 to N_RESTRICTIONS - 1)(0 to N_VARIABLES) 
    );
end entity progLineal;

architecture behav of progLineal is
    
    -- FSM State Definition
    type state is (
        IDLE,        -- Waiting for start signal
        DO_MATRIX,   -- Constructing the Simplex Tableau (adding slack variables)
        TRIGGER_GJ,  -- Sending the start pulse to the Gauss-Jordan core
        WAIT_GJ,     -- Polling for the 'done' signal from the coprocessor
        DONE_STATE   -- Extracting results and asserting 'done' output
    );
    signal current_state : state := IDLE;

    -- Coprocessor Interface Signals (Gauss-Jordan Core)
    signal gj_start     : std_logic := '0';
    signal gj_done      : std_logic;
    
    -- Extended matrix: Variables + Slack Variables + RHS Bound
    signal gj_mat_in    : matrix_of_fp(0 to N_RESTRICTIONS)(0 to N_VARIABLES + N_RESTRICTIONS) := (others => (others => FP_ZERO));
    signal gj_mat_out   : matrix_of_fp(0 to N_RESTRICTIONS)(0 to N_VARIABLES + N_RESTRICTIONS);
    
    -- Pivot coordinates (Currently hardcoded for a single predefined iteration)
    signal gj_piv_row   : integer range 0 to N_RESTRICTIONS := 0;
    signal gj_piv_col   : integer range 0 to N_VARIABLES + N_RESTRICTIONS := 0;

begin

    -- INSTANTIATION: Gauss-Jordan Mathematical Coprocessor
    U_GAUSS_JORDAN : entity work.gauss_jordan
        generic map (
            -- Total rows = Constraints + 1 (Objective Function Row)
            N_ROWS => N_RESTRICTIONS + 1,            
            -- Total columns = Decision Vars + Slack Vars + 1 (RHS Column)
            N_COLS => N_VARIABLES + N_RESTRICTIONS + 1,
            GJ_PARALLEL_UNITS  => GJ_PARALLEL_UNITS
        )
        port map (
            clk          => clk,
            reset        => reset,
            start        => gj_start,
            matrix_in    => gj_mat_in,
            pivot_row_in => gj_piv_row,
            pivot_col_in => gj_piv_col,
            done         => gj_done,
            matrix_out   => gj_mat_out
        );

    -- PROCESS: Main FSM Controller
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                current_state <= IDLE;
                gj_start <= '0';
                done <= '0';
            else
                case current_state is
                    
                    -- STATE: IDLE
                    -- Waits for the system to issue a start command.
                    when IDLE =>
                        done <= '0';
                        gj_start <= '0';
                        
                        -- Hardcoded pivot coordinates for initial testing
                        gj_piv_row <= 0;
                        gj_piv_col <= 0;
                        
                        if start = '1' then
                            current_state <= DO_MATRIX;
                        end if;

                    -- STATE: DO_MATRIX
                    -- Assembles the standard Simplex Tableau. In hardware, for-loops
                    -- here synthesize as parallel combinational routing logic.
                    when DO_MATRIX =>
                        
                        -- Phase 1: Populate Constraint Rows
                        for i in 0 to N_RESTRICTIONS - 1 loop
                            
                            -- Check if the constraint bound (RHS) is negative.
                            -- If so, multiply the entire row by -1 to maintain feasibility (b >= 0).
                            if restrictionsFuncs(i)(N_VARIABLES) < FP_ZERO then 
                                
                                -- 1.1 Invert original decision variables
                                for j in 0 to N_VARIABLES - 1 loop
                                    gj_mat_in(i)(j) <= -restrictionsFuncs(i)(j);
                                end loop;
                                
                                -- 1.2 Invert and place the RHS bound at the end of the row
                                gj_mat_in(i)(N_VARIABLES + N_RESTRICTIONS) <= -restrictionsFuncs(i)(N_VARIABLES); 

                                -- 1.3 Generate Identity Matrix for Slack Variables (inverted)
                                for k in 0 to N_RESTRICTIONS - 1 loop
                                    if k = i then
                                        gj_mat_in(i)(N_VARIABLES + k) <= -FP_ONE;
                                    else
                                        gj_mat_in(i)(N_VARIABLES + k) <= FP_ZERO;
                                    end if;
                                end loop;

                            else
                                -- 1.1 Transfer original decision variables directly
                                for j in 0 to N_VARIABLES - 1 loop
                                    gj_mat_in(i)(j) <= restrictionsFuncs(i)(j);
                                end loop;
                                
                                -- 1.2 Place the RHS bound at the end of the row
                                gj_mat_in(i)(N_VARIABLES + N_RESTRICTIONS) <= restrictionsFuncs(i)(N_VARIABLES); 

                                -- 1.3 Generate Identity Matrix for Slack Variables (standard)
                                for k in 0 to N_RESTRICTIONS - 1 loop
                                    if k = i then
                                        gj_mat_in(i)(N_VARIABLES + k) <= FP_ONE;
                                    else
                                        gj_mat_in(i)(N_VARIABLES + k) <= FP_ZERO;
                                    end if;
                                end loop;
                            end if;
                        end loop;

                        -- Phase 2: Populate the Objective Function Row (Z-Row)
                        -- Simplex requires inverting the signs of the objective coefficients.
                        for j in 0 to N_VARIABLES - 1 loop
                            gj_mat_in(N_RESTRICTIONS)(j) <= -funcObj(j); 
                        end loop;
                        
                        -- Slack variables have a 0 coefficient in the objective function
                        for k in 0 to N_RESTRICTIONS - 1 loop
                            gj_mat_in(N_RESTRICTIONS)(N_VARIABLES + k) <= FP_ZERO;
                        end loop;
                        
                        -- Initial Z-value (Profit/Cost) is 0
                        gj_mat_in(N_RESTRICTIONS)(N_VARIABLES + N_RESTRICTIONS) <= FP_ZERO;

                        current_state <= TRIGGER_GJ;

                    -- STATE: TRIGGER_GJ
                    -- Issues a single-cycle high pulse to start the coprocessor.
                    when TRIGGER_GJ =>
                        gj_start <= '1';
                        current_state <= WAIT_GJ;

                    -- STATE: WAIT_GJ
                    -- Drops the start signal and stalls until the coprocessor 
                    -- asserts its 'done' flag.
                    when WAIT_GJ =>
                        gj_start <= '0';
                        if gj_done = '1' then
                            current_state <= DONE_STATE;
                        end if;

                    -- STATE: DONE_STATE
                    -- Extracts the mathematical results from the output matrix
                    -- and signals the parent system.
                    when DONE_STATE =>
                        done <= '1';
                        
                        -- Temporary extraction logic: Reads the RHS column values.
                        -- Note: A full Simplex implementation would require checking 
                        -- which columns form the identity matrix (basis) to map results properly.
                        for i in 0 to N_VARIABLES - 1 loop
                            if i < N_RESTRICTIONS then
                                result(i) <= gj_mat_out(i)(N_VARIABLES + N_RESTRICTIONS);
                            else
                                result(i) <= FP_ZERO;
                            end if;
                        end loop;
                        
                        current_state <= IDLE;

                end case;
            end if;
        end if;
    end process;
end behav;