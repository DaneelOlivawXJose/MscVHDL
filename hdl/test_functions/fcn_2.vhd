library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.lib_config.all;

entity fcn_2 is
    port(
        clk       : in  std_logic;
        reset     : in  std_logic;
        start     : in  std_logic;
        entradas  : in  array_of_fp; 
        resultado : out fp_type;
        terminado : out std_logic
    );
end entity fcn_2;

architecture rtl of fcn_2 is

    function fp_mult(a, b : fp_type) return fp_type is
        variable m : fp_mult_type;
    begin
        m := a * b;
        return resize(shift_right(m, FRAC_WIDTH), TOTAL_WIDTH);
    end function;

    -- Registros Etapa 1
    signal term_x0_sq : fp_type := (others => '0');
    signal term_x1_sq : fp_type := (others => '0');
    signal reg_x1     : fp_type := (others => '0');
    signal valid_s1   : std_logic := '0';

    -- Registros Etapa 2
    signal term_part1 : fp_type := (others => '0');
    signal term_part2 : fp_type := (others => '0');
    signal valid_s2   : std_logic := '0';

begin

    process(clk, reset)
    begin
        if reset = '1' then
            term_x0_sq <= (others => '0');
            term_x1_sq <= (others => '0');
            reg_x1     <= (others => '0');
            term_part1 <= (others => '0');
            term_part2 <= (others => '0');
            resultado  <= (others => '0');
            valid_s1   <= '0';
            valid_s2   <= '0';
            terminado  <= '0';
            
        elsif rising_edge(clk) then
            
            -- ==========================================
            -- ETAPA 1: Primeros cuadrados
            -- ==========================================
            if start = '1' then
                term_x0_sq <= fp_mult(entradas(0), entradas(0)); -- x0^2
                term_x1_sq <= fp_mult(entradas(1), entradas(1)); -- x1^2
                reg_x1     <= entradas(1);                       -- Guardamos x1 para la etapa 2
            end if;
            valid_s1 <= start;

            -- ==========================================
            -- ETAPA 2: Multiplicaciones cruzadas
            -- ==========================================
            if valid_s1 = '1' then
                term_part1 <= fp_mult(term_x0_sq, reg_x1);       -- x0^2 * x1
                term_part2 <= shift_left(term_x1_sq, 1);         -- 2 * x1^2 (Multiplicar por 2 es desplazar 1 bit)
            end if;
            valid_s2 <= valid_s1;

            -- ==========================================
            -- ETAPA 3: Suma Final
            -- ==========================================
            if valid_s2 = '1' then
                resultado <= term_part1 + term_part2;            -- (x0^2 * x1) + (2 * x1^2)
            end if;
            terminado <= valid_s2;
            
        end if;
    end process;

end architecture rtl;