library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use work.lib_config.all;

entity progLineal is 
    generic(
        N_VARIABLES     :       integer := 2;
        N_RESTRICTIONS  :       integer := 1
    );
    port (
        clk                 :           in std_logic;
        reset               :           in std_logic;
        funcObj             :           in array_of_fp(0 to N_VARIABLES - 1);
        restrictionsFuncs   :           in matrix_of_fp(0 to N_RESTRICTIONS)(0 to N_VARIABLES - 1)
    );
end entity progLineal;

architecture behav of progLineal is
    signal aux_matrix : matrix_of_fp; 
-- EJ numerico
-- 3x1 + 5x2 = 4
-- R1: 4x1 + x2 <= 3
-- R2: x1 - 6x2 <= 10
-- funcObj = [3 5 -4]
-- restrictionsFuncs[0] = [4 1 -3]
-- restrictionsFuncs[1] = [1 -6 -10]

-- Reorganizo en una matriz, primeras filas son restricciones, ultima funcion objetivo * (-1), añadir N_VARIABLES variables de holgura

begin
    process(clk, reset)
    begin
        if reset = '1' then
            -- aux_matrix <= (others => '0');
        elsif rising_edge(clk) then

        end if;
    end process;

end behav ; -- behav