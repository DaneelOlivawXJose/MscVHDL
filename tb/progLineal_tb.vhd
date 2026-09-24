library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use work.lib_config.all;

entity progLineal_tb is
end entity progLineal_tb;

architecture sim of progLineal_tb is

    -- Usamos 2 variables y 3 restricciones para poder reutilizar el mismo componente
    constant C_VARS  : integer := 2;
    constant C_REST  : integer := 3;
    constant CLK_PER : time := 10 ns;
    constant GJ_PARALLEL_UNITS : integer := 2;

    signal clk               : std_logic := '0';
    signal reset             : std_logic := '1';
    signal start             : std_logic := '0';
    signal done              : std_logic;
    signal result            : array_of_fp(0 to C_VARS - 1);
    
    -- Señales dinámicas para poder cambiarlas en ejecución
    signal funcObj           : array_of_fp(0 to C_VARS - 1) := (others => FP_ZERO);
    signal restrictionsFuncs : matrix_of_fp(0 to C_REST - 1)(0 to C_VARS) := (others => (others => FP_ZERO));

begin

    UUT : entity work.progLineal
        generic map (
            N_VARIABLES    => C_VARS,
            N_RESTRICTIONS => C_REST,
            GJ_PARALLEL_UNITS => GJ_PARALLEL_UNITS
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
        variable start_time : time;
        variable end_time   : time;
        variable cycles     : integer;
    begin
        
        -- =================================================================
        -- CASO DE ESTUDIO 1:
        -- Max Z = 3x1 + 4x2
        -- Sujeto a:
        -- 1x1 + 2x2 <= 14
        -- 3x1 - 1x2 <= 0
        -- 1x1 - 1x2 <= 2
        -- Solución Óptima Real: x1 = 2.0, x2 = 6.0  (Beneficio Z = 30)
        -- =================================================================
        report "---------------------------------------------------";
        report "Iniciando CASO 1: Simplex Matriz 2x3...";
        
        -- Cargar Datos del Caso 1
        funcObj(0) <= to_fp(3.0); funcObj(1) <= to_fp(4.0);
        
        restrictionsFuncs(0)(0) <= to_fp(1.0); restrictionsFuncs(0)(1) <= to_fp(2.0);  restrictionsFuncs(0)(2) <= to_fp(14.0);
        restrictionsFuncs(1)(0) <= to_fp(3.0); restrictionsFuncs(1)(1) <= to_fp(-1.0); restrictionsFuncs(1)(2) <= to_fp(0.0);
        restrictionsFuncs(2)(0) <= to_fp(1.0); restrictionsFuncs(2)(1) <= to_fp(-1.0); restrictionsFuncs(2)(2) <= to_fp(2.0);
        
        reset <= '1';
        start <= '0';
        wait for CLK_PER * 5;
        reset <= '0';
        wait for CLK_PER * 2;
        
        -- Disparo
        wait until rising_edge(clk);
        start_time := now;
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        -- Esperar fin
        wait until done = '1';
        wait for CLK_PER * 3;
        end_time := now;

        -- Tolerancia para punto fijo (usamos 1000 unidades binarias de margen por los redondeos)
        assert abs(to_integer(result(0)) - to_integer(to_fp(2.0))) < 1000
            report "ERROR CASO 1: x1 incorrecto. Obtenido: " & integer'image(to_integer(result(0))) severity error;
            
        assert abs(to_integer(result(1)) - to_integer(to_fp(6.0))) < 1000
            report "ERROR CASO 1: x2 incorrecto. Obtenido: " & integer'image(to_integer(result(1))) severity error;
        
        cycles := (end_time - start_time) / CLK_PER;
        report "CASO 1 COMPLETADO CON EXITO EN " & integer'image(cycles) & " ciclos.";


        wait for CLK_PER * 20; -- Margen visual para GTKWave


        -- =================================================================
        -- CASO DE ESTUDIO 2:
        -- Max Z = 5x1 + 2x2
        -- Sujeto a:
        -- 2x1 + 1x2 <= 8
        -- 1x1 + 2x2 <= 7
        -- 1x1 + 0x2 <= 3
        -- Solución Óptima Real: x1 = 3.0, x2 = 2.0  (Beneficio Z = 19)
        -- =================================================================
        report "---------------------------------------------------";
        report "Iniciando CASO 2: Nueva Matriz 2x3...";
        
        -- Sobrescribir Datos del Caso 2
        funcObj(0) <= to_fp(5.0); funcObj(1) <= to_fp(2.0);
        
        restrictionsFuncs(0)(0) <= to_fp(2.0); restrictionsFuncs(0)(1) <= to_fp(1.0); restrictionsFuncs(0)(2) <= to_fp(8.0);
        restrictionsFuncs(1)(0) <= to_fp(1.0); restrictionsFuncs(1)(1) <= to_fp(2.0); restrictionsFuncs(1)(2) <= to_fp(7.0);
        restrictionsFuncs(2)(0) <= to_fp(1.0); restrictionsFuncs(2)(1) <= to_fp(0.0); restrictionsFuncs(2)(2) <= to_fp(3.0);
        
        -- Reset estricto para reiniciar la Máquina de Estados
        reset <= '1';
        wait for CLK_PER * 5;
        reset <= '0';
        wait for CLK_PER * 2;
        
        -- Disparo
        wait until rising_edge(clk);
        start_time := now;
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        
        -- Esperar fin
        wait until done = '1';
        wait for CLK_PER * 3;
        end_time := now;

        -- Comprobación Matemática
        assert abs(to_integer(result(0)) - to_integer(to_fp(3.0))) < 1000
            report "ERROR CASO 2: x1 incorrecto. Obtenido: " & integer'image(to_integer(result(0))) severity error;
            
        assert abs(to_integer(result(1)) - to_integer(to_fp(2.0))) < 1000
            report "ERROR CASO 2: x2 incorrecto. Obtenido: " & integer'image(to_integer(result(1))) severity error;

        cycles := (end_time - start_time) / CLK_PER;
        report "CASO 2 COMPLETADO CON EXITO EN " & integer'image(cycles) & " ciclos.";
        
        report "===================================================";
        report "TESTBENCH COMPLETADO EXITOSAMENTE (AMBOS CASOS)";
        report "===================================================";

        wait;
    end process;

end architecture sim;