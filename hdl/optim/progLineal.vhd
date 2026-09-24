-- ==============================================================================
-- @file    progLineal.vhd
-- @brief   Linear Programming Solver via Simplex Method (Hardware Implementation)
-- @author  Jose Segura Montes
-- @date    16/09/2026
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.lib_config.all;

entity progLineal is 
    generic(
        N_VARIABLES       : integer := 2;
        N_RESTRICTIONS    : integer := 1;
        GJ_PARALLEL_UNITS : integer := 2
    );
    port (
        clk                 : in std_logic;
        reset               : in std_logic;
        start               : in std_logic;
        done                : out std_logic;
        result              : out array_of_fp(0 to N_VARIABLES - 1);
        funcObj             : in array_of_fp(0 to N_VARIABLES - 1);
        restrictionsFuncs   : in matrix_of_fp(0 to N_RESTRICTIONS - 1)(0 to N_VARIABLES) 
    );
end entity progLineal;

architecture behav of progLineal is
    
    type state is (
        IDLE,
        DO_MATRIX,
        TRIGGER_GJ,
        WAIT_GJ,
        FIND_PIVOT_COL,
        FIND_PIVOT_ROW_START,
        FIND_PIVOT_ROW_WAIT,
        DONE_STATE
    );
    signal current_state : state := IDLE;

    signal gj_start     : std_logic := '0';
    signal gj_done      : std_logic;
    
    signal gj_mat_in    : matrix_of_fp(0 to N_RESTRICTIONS)(0 to N_VARIABLES + N_RESTRICTIONS) := (others => (others => FP_ZERO));
    signal gj_mat_out   : matrix_of_fp(0 to N_RESTRICTIONS)(0 to N_VARIABLES + N_RESTRICTIONS);
    
    signal gj_piv_row   : integer range 0 to N_RESTRICTIONS := 0;
    signal gj_piv_col   : integer range 0 to N_VARIABLES + N_RESTRICTIONS := 0;

    signal ratio_start  : std_logic := '0';
    signal ratio_done   : std_logic;
    signal ratio_num    : fp_type := FP_ZERO;
    signal ratio_den    : fp_type := FP_ZERO;
    signal ratio_res    : fp_type;
    
    signal current_row_check : integer range 0 to N_RESTRICTIONS := 0;

    -- REGISTRO DE VARIABLES BÁSICAS (Rastreo de la Identidad)
    type integer_array is array (0 to N_RESTRICTIONS - 1) of integer;
    signal basic_vars : integer_array := (others => 0);

begin

    U_GAUSS_JORDAN : entity work.gauss_jordan
        generic map (
            N_ROWS            => N_RESTRICTIONS + 1,            
            N_COLS            => N_VARIABLES + N_RESTRICTIONS + 1,
            GJ_PARALLEL_UNITS => GJ_PARALLEL_UNITS
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

    FP_DIVIDER: entity work.fp_divider
        port map (
            clk      => clk,
            reset    => reset,
            start    => ratio_start,
            dividend => ratio_num,
            divisor  => ratio_den,
            quotient => ratio_res,
            done     => ratio_done
        );

    process(clk)
        variable min_val     : fp_type;
        variable min_ratio   : fp_type;
        variable best_col    : integer;
        variable temp_result : array_of_fp(0 to N_VARIABLES - 1);
    begin
        if rising_edge(clk) then
            if reset = '1' then
                current_state <= IDLE;
                gj_start      <= '0';
                done          <= '0';
                gj_piv_row    <= 0;
                gj_piv_col    <= 0;
                ratio_start   <= '0';
            else
                case current_state is
                    
                    when IDLE =>
                        done     <= '0';
                        gj_start <= '0';
                        if start = '1' then
                            current_state <= DO_MATRIX;
                        end if;

                    when DO_MATRIX =>
                        for i in 0 to N_RESTRICTIONS - 1 loop
                            -- Inicializar variables básicas como las variables de holgura
                            basic_vars(i) <= N_VARIABLES + i;
                            
                            if restrictionsFuncs(i)(N_VARIABLES) < FP_ZERO then 
                                for j in 0 to N_VARIABLES - 1 loop
                                    gj_mat_in(i)(j) <= -restrictionsFuncs(i)(j);
                                end loop;
                                gj_mat_in(i)(N_VARIABLES + N_RESTRICTIONS) <= -restrictionsFuncs(i)(N_VARIABLES); 

                                for k in 0 to N_RESTRICTIONS - 1 loop
                                    if k = i then
                                        gj_mat_in(i)(N_VARIABLES + k) <= -FP_ONE;
                                    else
                                        gj_mat_in(i)(N_VARIABLES + k) <= FP_ZERO;
                                    end if;
                                end loop;
                            else
                                for j in 0 to N_VARIABLES - 1 loop
                                    gj_mat_in(i)(j) <= restrictionsFuncs(i)(j);
                                end loop;
                                gj_mat_in(i)(N_VARIABLES + N_RESTRICTIONS) <= restrictionsFuncs(i)(N_VARIABLES); 

                                for k in 0 to N_RESTRICTIONS - 1 loop
                                    if k = i then
                                        gj_mat_in(i)(N_VARIABLES + k) <= FP_ONE;
                                    else
                                        gj_mat_in(i)(N_VARIABLES + k) <= FP_ZERO;
                                    end if;
                                end loop;
                            end if;
                        end loop;

                        for j in 0 to N_VARIABLES - 1 loop
                            gj_mat_in(N_RESTRICTIONS)(j) <= -funcObj(j); 
                        end loop;
                        
                        for k in 0 to N_RESTRICTIONS - 1 loop
                            gj_mat_in(N_RESTRICTIONS)(N_VARIABLES + k) <= FP_ZERO;
                        end loop;
                        
                        gj_mat_in(N_RESTRICTIONS)(N_VARIABLES + N_RESTRICTIONS) <= FP_ZERO;

                        current_state <= FIND_PIVOT_COL;

                    -- STATE: FIND_PIVOT_COL
                    when FIND_PIVOT_COL =>
                        min_val  := FP_ZERO; -- Cero estricto
                        best_col := -1;
                        
                        for j in 0 to N_VARIABLES + N_RESTRICTIONS - 1 loop
                            if gj_mat_in(N_RESTRICTIONS)(j) < min_val then
                                min_val  := gj_mat_in(N_RESTRICTIONS)(j);
                                best_col := j;
                            end if;
                        end loop;

                        if best_col /= -1 then
                            gj_piv_col        <= best_col;
                            current_row_check <= 0;
                            min_ratio         := to_signed(2147483647, TOTAL_WIDTH);
                            current_state     <= FIND_PIVOT_ROW_START;
                        else
                            -- Si no hay negativos, es el estado óptimo (FIN)
                            current_state     <= DONE_STATE;
                        end if;

                    -- STATE: FIND_PIVOT_ROW_START (Minimum Ratio Test)
                    when FIND_PIVOT_ROW_START =>
                        if current_row_check = N_RESTRICTIONS then
                            current_state <= TRIGGER_GJ;
                        elsif gj_mat_in(current_row_check)(gj_piv_col) <= FP_ZERO then
                            -- Ignoramos divisores negativos o cero
                            current_row_check <= current_row_check + 1;
                        else
                            ratio_num   <= gj_mat_in(current_row_check)(N_VARIABLES + N_RESTRICTIONS);
                            ratio_den   <= gj_mat_in(current_row_check)(gj_piv_col);
                            ratio_start <= '1';
                            current_state <= FIND_PIVOT_ROW_WAIT;
                        end if;

                    when FIND_PIVOT_ROW_WAIT =>
                        ratio_start <= '0';
                        if ratio_done = '1' then
                            if ratio_res < min_ratio then
                                min_ratio  := ratio_res;
                                gj_piv_row <= current_row_check;
                            end if;
                            current_row_check <= current_row_check + 1;
                            current_state     <= FIND_PIVOT_ROW_START;
                        end if;

                    when TRIGGER_GJ =>
                        -- Registrar el cambio de Base (la columna pivote ahora es dueña de la fila pivote)
                        basic_vars(gj_piv_row) <= gj_piv_col;
                        
                        gj_start      <= '1';
                        current_state <= WAIT_GJ;

                    when WAIT_GJ =>
                        gj_start <= '0';
                        if gj_done = '1' then
                            gj_mat_in     <= gj_mat_out; 
                            current_state <= FIND_PIVOT_COL;
                        end if;

                    when DONE_STATE =>
                        done <= '1';
                        
                        -- Extracción mediante registro de Base (100% inmune a ruido)
                        for j in 0 to N_VARIABLES - 1 loop
                            temp_result(j) := FP_ZERO;
                        end loop;
                        
                        for i in 0 to N_RESTRICTIONS - 1 loop
                            if basic_vars(i) < N_VARIABLES then
                                temp_result(basic_vars(i)) := gj_mat_in(i)(N_VARIABLES + N_RESTRICTIONS);
                            end if;
                        end loop;
                        
                        for j in 0 to N_VARIABLES - 1 loop
                            result(j) <= temp_result(j);
                        end loop;
                        
                        current_state <= IDLE;

                end case;
            end if;
        end if;
    end process;
end behav;