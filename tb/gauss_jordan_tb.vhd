-- ==============================================================================
-- @file    gauss_jordan_tb.vhd
-- @brief   Testbench para el coprocesador Gauss-Jordan
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.lib_config.all;

-- 1. IMPORTAR VUNIT
library vunit_lib;
context vunit_lib.vunit_context;

entity gauss_jordan_tb is
    generic (runner_cfg : string);
end entity gauss_jordan_tb;

architecture sim of gauss_jordan_tb is

    -- Configuración de la prueba
    constant N_ROWS            : integer := 3;
    constant N_COLS            : integer := 4;
    constant GJ_PARALLEL_UNITS : integer := 4;
    constant CLK_PERIOD        : time := 10 ns;

    -- Señales del DUT (Device Under Test)
    signal clk          : std_logic := '0';
    signal reset        : std_logic := '1';
    signal start        : std_logic := '0';
    signal done         : std_logic;
    
    signal matrix_in    : matrix_of_fp(0 to N_ROWS - 1)(0 to N_COLS - 1);
    signal pivot_row_in : integer range 0 to N_ROWS - 1;
    signal pivot_col_in : integer range 0 to N_COLS - 1;
    signal matrix_out   : matrix_of_fp(0 to N_ROWS - 1)(0 to N_COLS - 1);

    -- Función auxiliar para inyectar enteros fácilmente al formato Q8.24
    function to_fp(val : integer) return fp_type is
    begin
        return to_signed(val * (2**FRAC_WIDTH), TOTAL_WIDTH);
    end function;

begin

    -- Instanciación del módulo
    DUT: entity work.gauss_jordan
        generic map (
            N_ROWS            => N_ROWS,
            N_COLS            => N_COLS,
            GJ_PARALLEL_UNITS => GJ_PARALLEL_UNITS
        )
        port map (
            clk          => clk,
            reset        => reset,
            start        => start,
            matrix_in    => matrix_in,
            pivot_row_in => pivot_row_in,
            pivot_col_in => pivot_col_in,
            done         => done,
            matrix_out   => matrix_out
        );

    -- Generador de reloj
    clk_process: process
    begin
        clk <= '0';
        wait for CLK_PERIOD / 2;
        clk <= '1';
        wait for CLK_PERIOD / 2;
    end process;

    -- Proceso principal de estímulos y medición de rendimiento
    stim_process: process
        variable start_time : time;
        variable end_time   : time;
        variable cycles     : integer;
    begin
        test_runner_setup(runner, runner_cfg);

        -- 1. Inicialización
        reset <= '1';
        start <= '0';
        wait for CLK_PERIOD * 5;
        reset <= '0';
        wait for CLK_PERIOD * 2;

        -- 2. Cargar Matriz de prueba (Ejemplo clásico Simplex)
        -- Fila 0: [ 2.0,  4.0,  6.0, 18.0 ] (Pivotaremos en 0,0)
        -- Fila 1: [ 4.0,  5.0,  6.0, 24.0 ]
        -- Fila 2: [ 3.0,  1.0, -2.0,  4.0 ]
        matrix_in(0)(0) <= to_fp(2);  matrix_in(0)(1) <= to_fp(4);  matrix_in(0)(2) <= to_fp(6);  matrix_in(0)(3) <= to_fp(18);
        matrix_in(1)(0) <= to_fp(4);  matrix_in(1)(1) <= to_fp(5);  matrix_in(1)(2) <= to_fp(6);  matrix_in(1)(3) <= to_fp(24);
        matrix_in(2)(0) <= to_fp(3);  matrix_in(2)(1) <= to_fp(1);  matrix_in(2)(2) <= to_fp(-2); matrix_in(2)(3) <= to_fp(4);

        -- Configurar objetivo del pivote
        pivot_row_in <= 0;
        pivot_col_in <= 0;

        -- 3. Iniciar ejecución y capturar tiempo de inicio
        wait until rising_edge(clk);
        start_time := now;
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        -- 4. Esperar convergencia
        wait until done = '1';
        end_time := now;

        -- Comprobación del pivote (Fila 0, Columna 0 debe ser 1.0)
        assert matrix_out(0)(0) = to_fp(1)
            report "Error: El pivote no es 1.0. Valor obtenido: " & integer'image(to_integer(matrix_out(0)(0)))
            severity error;
            
        -- Comprobación de la eliminación (Fila 1, Columna 0 debe ser 0.0)
        assert matrix_out(1)(0) = FP_ZERO
            report "Error: No se eliminó el valor bajo el pivote."
            severity error;
        
        -- 5. Calcular e imprimir métricas de rendimiento
        cycles := (end_time - start_time) / CLK_PERIOD;
        report "===================================================";
        report "GAUSS-JORDAN EJECUCION COMPLETADA";
        report "N_ROWS: " & integer'image(N_ROWS) & ", N_COLS: " & integer'image(N_COLS);
        report "PARALLEL_UNITS: " & integer'image(GJ_PARALLEL_UNITS);
        report "LATENCIA TOTAL: " & integer'image(cycles) & " ciclos de reloj.";
        report "TIEMPO SIMULADO: " & time'image(end_time - start_time);
        report "===================================================";

        test_runner_cleanup(runner);
        -- Finalizar simulación
        wait;
    end process;

end architecture sim;

-- ghdl -a --std=08 ../hdl/lib_config.vhd
-- ghdl -a --std=08 ../hdl/math/fp_divider.vhd
-- ghdl -a --std=08 ../hdl/math/gauss_jordan.vhd
-- ghdl -a --std=08 gauss_jordan_tb.vhd
-- ghdl -e --std=08 gauss_jordan_tb
-- ghdl -r --std=08 gauss_jordan_tb --fst=ondas_fst.fst --stop-time=50000ns