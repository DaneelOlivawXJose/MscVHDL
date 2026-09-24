library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.lib_config.all;

entity multVectCol is 
    generic (
        N_WIDTH : integer := 3 -- Número de elementos (ej. 3 significa índices 0, 1, 2)
    );
    port(
        clk         : in std_logic;
        reset       : in std_logic;
        start       : in std_logic;
        done        : out std_logic;

        v1          : in array_of_fp;
        v2          : in array_of_fp;
        v_sal       : out fp_type
    );
end multVectCol;

architecture rtl of multVectCol is
    -- Corregido el nombre a IDLE
    type FSM is (IDLE, COMPUTE, END_CYCLE);
    signal state : FSM; 

    signal n : integer range 0 to N_WIDTH;
    signal v_sal_temp : fp_type;
begin

    process (clk, reset)
    begin
        -- 1. Lógica de Reset asíncrono (CRÍTICO)
        if reset = '1' then
            state <= IDLE;
            n <= 0;
            v_sal_temp <= FP_ZERO;
            done <= '0';
            -- No reseteamos v_sal para mantener el último valor válido
            
        elsif rising_edge(clk) then
            case state is 
                when IDLE => 
                    done <= '0'; -- Aseguramos que done baja
                    if start = '1' then
                        n <= 0;
                        v_sal_temp <= FP_ZERO;
                        state <= COMPUTE;
                    end if;

                when COMPUTE => 
                    -- Acumulación (MAC)
                    v_sal_temp <= v_sal_temp + fp_mult(v1(n), v2(n));

                    -- 4. Corrección del índice: paramos en N_WIDTH - 1
                    if n = N_WIDTH - 1 then
                        state <= END_CYCLE;
                    else 
                        n <= n + 1;
                    end if;

                when END_CYCLE => 
                    v_sal <= v_sal_temp;
                    done <= '1';
                    
                    -- 3. Volver al inicio para permitir futuros cálculos
                    state <= IDLE; 
                    
            end case;
        end if;
    end process;

end architecture;