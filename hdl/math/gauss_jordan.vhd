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
        N_COLS      : integer := 4;
        GJ_PARALLEL_UNITS  : integer := 2  
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
        S_IDLE, 
        S_LOAD_MATRIX, 
        S_START_DIVIDE,   -- Inicia el divisor secuencial
        S_WAIT_DIVIDE,    -- Espera a que termine 1/pivot
        S_NORMALIZE_ROW,  -- Bucle por bloques usando multiplicaciones
        S_ELIMINATE,      -- Bucle por bloques usando multiplicaciones
        S_DONE
    );
    signal current_state : state_type;

    signal aux_matrix : matrix_of_fp(0 to N_ROWS - 1)(0 to N_COLS - 1);
    
    signal current_row : integer range 0 to N_ROWS;
    signal p_row       : integer range 0 to N_ROWS - 1;
    signal p_col       : integer range 0 to N_COLS - 1;
    
    -- Dedicated register to cache the pivot denominator, improving Fmax
    signal pivot_val   : fp_type;

    -- Señales para el divisor secuencial
    signal div_start   : std_logic := '0';
    signal div_done    : std_logic;
    signal pivot_inv   : fp_type; 
    
    -- Contador para el plegado espacial (Spatial Folding)
    signal current_col : integer range 0 to N_COLS := 0;
begin

    PIVOT_INVERSER: entity work.fp_divider
        port map (
            clk      => clk,
            reset    => reset,
            start    => div_start,
            dividend => FP_ONE,      -- Fijamos el dividendo a 1 en punto fijo
            divisor  => pivot_val,   -- El denominador es tu pivote actual
            quotient => pivot_inv,   -- El resultado se guarda en tu señal pivot_inv
            done     => div_done
        );

    process(clk)
        -- Double-width variables required to prevent overflow during fixed-point math
        variable temp_mult : signed((TOTAL_WIDTH * 2) - 1 downto 0);
        variable temp_num  : signed((TOTAL_WIDTH * 2) - 1 downto 0);

        variable idx       : integer;
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
                    -- 1. Cargamos el valor a invertir
                    when S_LOAD_MATRIX =>
                        pivot_val <= aux_matrix(p_row)(p_col);
                        current_state <= S_START_DIVIDE; -- ¡Cambiado!

                    -- 2. Damos la orden de arrancar al coprocesador de división
                    when S_START_DIVIDE =>
                        div_start <= '1';
                        current_state <= S_WAIT_DIVIDE;

                    -- 3. Esperamos a que termine (div_start debe bajar a '0' inmediatamente)
                    when S_WAIT_DIVIDE =>
                        div_start <= '0';
                        if div_done = '1' then
                            current_col <= 0; -- Preparamos el contador para el siguiente estado
                            current_state <= S_NORMALIZE_ROW;
                        end if;

                    -- Normalize the pivot row.
                    -- Operates on the entire row simultaneously (spatial parallelism).
                    when S_NORMALIZE_ROW =>
                        -- Bucle limitado al número de unidades paralelas
                        for j in 0 to GJ_PARALLEL_UNITS - 1 loop
                            -- Verificamos no salirnos de los límites de la matriz
                            idx := current_col + j;
                            if idx < N_COLS then
                                -- MULTIPLICAMOS por el inverso en vez de dividir
                                temp_mult := aux_matrix(p_row)(idx) * pivot_inv;
                                aux_matrix(p_row)(idx) <= resize(shift_right(temp_mult, FRAC_WIDTH), TOTAL_WIDTH);
                            end if;
                        end loop;
                    
                        -- ¿Hemos terminado toda la fila?
                        if current_col + GJ_PARALLEL_UNITS >= N_COLS then
                            current_col <= 0;
                            current_row <= 0;
                            current_state <= S_ELIMINATE;
                        else
                            -- Si no, avanzamos el bloque de columnas
                            current_col <= current_col + GJ_PARALLEL_UNITS;
                        end if;

                    -- Iterate through all matrix rows to eliminate the pivot column entries.
                    -- Uses temporal pipelining (one row processed per clock cycle).
                    when S_ELIMINATE =>
                        -- 1. Condición de salida general
                        if current_row = N_ROWS then
                            current_state <= S_DONE;
                        
                        -- 2. Saltar la fila pivote
                        elsif current_row = p_row then
                            current_row <= current_row + 1;
                        
                        -- 3. Eliminación por bloques (Chunks)
                        else
                            for j in 0 to GJ_PARALLEL_UNITS - 1 loop
                                idx := current_col + j;
                                if idx < N_COLS then
                                    temp_mult := aux_matrix(current_row)(p_col) * aux_matrix(p_row)(idx);
                                    aux_matrix(current_row)(idx) <= aux_matrix(current_row)(idx) - 
                                        resize(shift_right(temp_mult, FRAC_WIDTH), TOTAL_WIDTH);
                                end if;
                            end loop;

                            -- Control del flujo por la fila
                            if current_col + GJ_PARALLEL_UNITS >= N_COLS then
                                -- Fila terminada: saltamos a la siguiente fila y reseteamos columnas
                                current_col <= 0;
                                current_row <= current_row + 1;
                            else
                                -- Fila a medias: avanzamos el bloque de columnas en la misma fila
                                current_col <= current_col + GJ_PARALLEL_UNITS;
                            end if;
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