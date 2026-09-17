library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.lib_config.all;

entity fcn_1 is
    port(
        clk       : in  std_logic;
        reset     : in  std_logic;
        start     : in  std_logic;
        entradas  : in  array_of_fp;         -- <--- SOLUCIÓN: Sin límites (Unconstrained)
        resultado : out fp_type;
        terminado : out std_logic
    );
end entity fcn_1;

architecture rtl of fcn_1 is

    function fp_mult(a, b : fp_type) return fp_type is
        variable m : fp_mult_type;
    begin
        m := a * b;
        return resize(shift_right(m, FRAC_WIDTH), TOTAL_WIDTH);
    end function;

    constant FP_THREE : fp_type := to_signed(3 * (2**FRAC_WIDTH), TOTAL_WIDTH);

    -- Registros de la etapa 1
    signal term1, term2, term3 : fp_type;
    signal valid_s1            : std_logic;

begin

    -- Pipeline unificado en un solo proceso (más compacto)
    process(clk, reset)
    begin
        if reset = '1' then
            term1     <= (others => '0');
            term2     <= (others => '0');
            term3     <= (others => '0');
            resultado <= (others => '0');
            valid_s1  <= '0';
            terminado <= '0';
        elsif rising_edge(clk) then
            
            -- ETAPA 1: Multiplicación (solo calcula si hay un 'start')
            -- ETAPA 1: Multiplicación
            if start = '1' then
                term1 <= fp_mult(entradas(0), entradas(0));
                term2 <= fp_mult(entradas(1), entradas(1));
                term3 <= (others => '0'); -- Anulamos el uso de entradas(2)
            end if;
            valid_s1 <= start; -- El 'start' viaja a la siguiente etapa como 'valid'

            -- ETAPA 2: Suma final (solo actualiza si el dato de la etapa 1 es válido)
            if valid_s1 = '1' then
                resultado <= term1 + term2 + term3;
            end if;
            terminado <= valid_s1; -- El 'valid' se convierte en el 'terminado' final
            
        end if;
    end process;

end architecture rtl;