library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package lib_config is 
    -- Constant parameters for fixed-point representation
    constant TOTAL_WIDTH : natural := 32;
    constant FRAC_WIDTH  : natural := 24;

    -- FP types
    subtype fp_type        is signed(TOTAL_WIDTH-1 downto 0);
    subtype fp_mult_type   is signed((TOTAL_WIDTH*2)-1 downto 0);
    constant FP_ONE        : fp_type := to_signed(2**FRAC_WIDTH, TOTAL_WIDTH);
    constant FP_ZERO       : fp_type := to_signed(0, TOTAL_WIDTH);
    constant FP_HALF_MULT  : fp_mult_type := to_signed(2**(FRAC_WIDTH-1), TOTAL_WIDTH*2);
    
    -- Constante '3' en formato de punto fijo
    constant FP_THREE      : fp_type := to_signed(3 * (2**FRAC_WIDTH), TOTAL_WIDTH);

    -- Array types
    type array_of_fp        is array (natural range <>) of fp_type;
    type array_of_std_logic is array (natural range <>) of std_logic;
    type matrix_of_fp       is array (natural range <>) of array_of_fp;

    -- Record para devolver el valor en punto fijo y el estado de terminado
    type t_eval_result is record
        valor_resultado : fp_type;
        terminado       : std_logic;
    end record;

    function fp_mult(a, b : fp_type) return fp_type;

end package lib_config;

package body lib_config is
    
    function fp_mult(a, b : fp_type) return fp_type is
        variable m : fp_mult_type;
    begin
        m := a * b;
        return resize(shift_right(m, FRAC_WIDTH), TOTAL_WIDTH);
    end function;

end package body lib_config;