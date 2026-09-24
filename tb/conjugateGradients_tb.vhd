library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all; -- Para usar tipo 'real' en la simulación
use work.lib_config.all;

entity conjugateGradients_tb is
end entity conjugateGradients_tb;

architecture sim of conjugateGradients_tb is

    -- Constantes del reloj
    constant CLK_PERIOD : time := 10 ns;

    -- Señales del DUT (Device Under Test)
    signal clk         : std_logic := '0';
    signal reset       : std_logic := '1';
    signal start       : std_logic := '0';
    signal done        : std_logic;
    
    -- Los puertos de datos usan el N_DIM por defecto (2)
    signal start_point : array_of_fp(0 to 1) := (others => FP_ZERO);
    signal result      : array_of_fp(0 to 1);

    -- Función auxiliar para convertir de Real a Q8.24 solo en simulación
    function real_to_fp(val : real) return fp_type is
    begin
        return to_signed(integer(val * (2.0**FRAC_WIDTH)), TOTAL_WIDTH);
    end function;

    -- Función auxiliar para convertir de Q8.24 a Real (para imprimir en consola)
    function fp_to_real(val : fp_type) return real is
    begin
        return real(to_integer(val)) / (2.0**FRAC_WIDTH);
    end function;

begin

    -- Instanciación del módulo principal
    DUT: entity work.conjugateGradient
        generic map (
            MAX_ITER    => 2000, -- Le damos más margen por si acaso
            N_DIM       => 2,
            ALPHA_SHIFT => 5,
            
            -- ¡AQUÍ ESTÁ LA CLAVE! Actualizamos AMBOS sincronizados
            H           => to_signed(2**(24-10), 32),
            H_SHIFT     => 10
        )
        port map (
            clk         => clk,
            reset       => reset,
            start       => start,
            done        => done,
            start_point => start_point,
            result      => result
        );

    -- Generador de Reloj
    clk_process : process
    begin
        clk <= '0';
        wait for CLK_PERIOD/2;
        clk <= '1';
        wait for CLK_PERIOD/2;
    end process;

    -- Proceso de Estímulos (Test Cases)
    stim_process : process
        variable res_x, res_y : real;
    begin
        -- 1. Reset inicial
        reset <= '1';
        start <= '0';
        wait for CLK_PERIOD * 5;
        reset <= '0';
        wait for CLK_PERIOD * 5;

        report "--- INICIANDO SIMULACION DEL GRADIENTE CONJUGADO ---";

        -------------------------------------------------------------
        -- EJEMPLO 1: Empezando en un cuadrante positivo/negativo
        -------------------------------------------------------------
        report "CASO 1: Punto de inicio (2.5, -1.8)";
        start_point(0) <= real_to_fp(2.5);
        start_point(1) <= real_to_fp(-1.8);
        
        -- Handshake: Mandar Start
        wait until rising_edge(clk);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        -- Esperar a que el algoritmo converja
        wait until done = '1';
        
        -- Leer y mostrar el resultado
        res_x := fp_to_real(result(0));
        res_y := fp_to_real(result(1));
        report "FIN CASO 1. Resultado Obtenido: X = " & real'image(res_x) & ", Y = " & real'image(res_y);
        
        wait for CLK_PERIOD * 10;

        -------------------------------------------------------------
        -- EJEMPLO 2: Empezando lejos del origen
        -------------------------------------------------------------
        report "CASO 2: Punto de inicio (-5.2, 4.7)";
        start_point(0) <= real_to_fp(-5.2);
        start_point(1) <= real_to_fp(4.7);
        
        -- Handshake: Mandar Start
        wait until rising_edge(clk);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        -- Esperar a que el algoritmo converja
        wait until done = '1';
        
        -- Leer y mostrar el resultado
        res_x := fp_to_real(result(0));
        res_y := fp_to_real(result(1));
        report "FIN CASO 2. Resultado Obtenido: X = " & real'image(res_x) & ", Y = " & real'image(res_y);

        -------------------------------------------------------------
        -- Fin de la simulación
        -------------------------------------------------------------
        report "--- SIMULACION TERMINADA ---";
        wait; -- Detener el proceso
    end process;

end architecture sim;

-- ghdl -a --std=08 ../lib_config.vhd
-- ghdl -a --std=08 ../Fcn_example/fcn_1.vhd
-- ghdl -a --std=08 ../ops_varias/computeGradient.vhd
-- ghdl -a --std=08 ../ops_varias/fp_divider.vhd
-- ghdl -a --std=08 ../ops_varias/multVectCol.vhd
-- ghdl -a --std=08 ../Cntrl_Inteligente/conjugateGradients.vhd
-- ghdl -a --std=08 conjugateGradients_tb.vhd
-- ghdl -e --std=08 conjugateGradients_tb
-- ghdl -r --std=08 conjugateGradients_tb --fst=ondas_fst.fst --stop-time=500000ns