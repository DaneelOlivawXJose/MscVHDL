-- ==============================================================================
-- @file    gauss_jordan.vhd
-- @brief   Gauss-Jordan Elimination Coprocessor for Simplex Algorithm
-- @author  Jose Segura Montes
-- @date    16/09/2026
--
-- @note    ALGORITHM DESCRIPTION:
--          Executes a single pivoting step of the Gauss-Jordan elimination 
--          process. Given a targeted pivot row and column, it normalizes the 
--          pivot row to have a value of 1 at the pivot coordinate, and performs 
--          row operations to zero out all other entries in the pivot column.
--
-- @note    HARDWARE ARCHITECTURE:
--          Implemented as a Finite State Machine (FSM) acting as a mathematical 
--          slave coprocessor. It uses spatial parallelism to update entire rows 
--          simultaneously and temporal pipelining to iterate through the matrix.
--          Operations utilize Q8.24 Signed Fixed-Point arithmetic (defined in 
--          lib_config), applying bit-shifting to maintain fractional resolution 
--          during multiplications and divisions.
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.lib_config.all;

entity gauss_jordan is 
    generic(
        N_ROWS      : integer := 3; 
        N_COLS      : integer := 4  
    );
    port (
        clk                 : in std_logic;
        reset               : in std_logic;
        start               : in std_logic;
        
        matrix_in           : in matrix_of_fp(0 to N_ROWS - 1)(0 to N_COLS - 1);
        pivot_row_in        : in integer range 0 to N_ROWS - 1; 
        pivot_col_in        : in integer range 0 to N_COLS - 1;
        
        done                : out std_logic;
        matrix_out          : out matrix_of_fp(0 to N_ROWS - 1)(0 to N_COLS - 1)
    );
end entity gauss_jordan;

architecture behav of gauss_jordan is

    type state_type is (
        S_IDLE, S_LOAD_MATRIX, S_DIVIDE_PIVOT, S_ELIMINATE, S_DONE
    );
    signal current_state : state_type;

    signal aux_matrix : matrix_of_fp(0 to N_ROWS - 1)(0 to N_COLS - 1);
    
    signal current_row : integer range 0 to N_ROWS;
    signal p_row       : integer range 0 to N_ROWS - 1;
    signal p_col       : integer range 0 to N_COLS - 1;
    
    -- Dedicated register to cache the pivot denominator, improving Fmax
    signal pivot_val   : fp_type; 

begin
    process(clk)
        -- Double-width variables required to prevent overflow during fixed-point math
        variable temp_mult : signed((TOTAL_WIDTH * 2) - 1 downto 0);
        variable temp_num  : signed((TOTAL_WIDTH * 2) - 1 downto 0);
    begin
        if rising_edge(clk) then
            if reset = '1' then
                current_state <= S_IDLE;
                done <= '0';
                current_row <= 0;
            else
                case current_state is
                    
                    -- Wait for the master controller to assert the start signal.
                    -- Latch all inputs to isolate the coprocessor from external changes.
                    when S_IDLE =>
                        done <= '0';
                        if start = '1' then
                            aux_matrix <= matrix_in;
                            p_row <= pivot_row_in;
                            p_col <= pivot_col_in;
                            current_state <= S_LOAD_MATRIX;
                        end if;

                    -- Fetch the pivot value into a dedicated register.
                    -- This breaks the combinational path to the division logic.
                    when S_LOAD_MATRIX =>
                        pivot_val <= aux_matrix(p_row)(p_col);
                        current_state <= S_DIVIDE_PIVOT;

                    -- Normalize the pivot row.
                    -- Operates on the entire row simultaneously (spatial parallelism).
                    when S_DIVIDE_PIVOT =>
                        for j in 0 to N_COLS - 1 loop
                            -- Fixed-point division: Left-shift the numerator by the fractional 
                            -- width before dividing to preserve decimal resolution.
                            temp_num := shift_left(resize(aux_matrix(p_row)(j), TOTAL_WIDTH * 2), FRAC_WIDTH);
                            aux_matrix(p_row)(j) <= resize(temp_num / pivot_val, TOTAL_WIDTH);
                        end loop;
                        
                        current_row <= 0;
                        current_state <= S_ELIMINATE;

                    -- Iterate through all matrix rows to eliminate the pivot column entries.
                    -- Uses temporal pipelining (one row processed per clock cycle).
                    when S_ELIMINATE =>
                        
                        -- Check if all rows have been processed
                        if current_row = N_ROWS then
                            current_state <= S_DONE;
                        
                        -- Skip the pivot row since it was already normalized
                        elsif current_row = p_row then
                            current_row <= current_row + 1;
                        
                        -- Perform the Gauss-Jordan elimination step for the current row
                        else
                            for j in 0 to N_COLS - 1 loop
                                -- Fixed-point multiplication generates a double-width result.
                                temp_mult := aux_matrix(current_row)(p_col) * aux_matrix(p_row)(j);
                                
                                -- Right-shift by the fractional width to restore the standard Q format
                                -- before subtracting it from the current matrix cell.
                                aux_matrix(current_row)(j) <= aux_matrix(current_row)(j) - 
                                    resize(shift_right(temp_mult, FRAC_WIDTH), TOTAL_WIDTH);
                            end loop;
                            
                            current_row <= current_row + 1;
                        end if;

                    -- Assert the done flag and output the processed matrix
                    when S_DONE =>
                        done <= '1';
                        matrix_out <= aux_matrix;
                        current_state <= S_IDLE;

                end case;
            end if;
        end if;
    end process;
end architecture behav;