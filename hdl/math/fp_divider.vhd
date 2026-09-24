-- @file    fp_divider.vhd
-- @brief   Sequential Radix-2 Restoring Divider for Fixed-Point Signed Arithmetic
-- @note    Format: Q8.24 (32 bits total, 24 bits fractional) defined in lib_config

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.lib_config.all;

entity fp_divider is
    port (
        clk      : in  std_logic;
        reset    : in  std_logic;
        
        -- Señales de control (Handshake)
        start    : in  std_logic;
        done     : out std_logic;
        
        -- Operandos
        dividend : in  fp_type;
        divisor  : in  fp_type;
        
        -- Resultado
        quotient : out fp_type
    );
end entity fp_divider;

architecture rtl of fp_divider is

    -- FSM States
    type state_t is (IDLE, DIVIDING, DONE_STATE);
    signal state : state_t := IDLE;
    
    -- Contador de iteraciones (Se requieren 64 para dividendos desplazados a 64 bits)
    signal count : integer range 0 to TOTAL_WIDTH * 2;
    
    -- Registros principales del algoritmo
    signal Q_reg : unsigned((TOTAL_WIDTH * 2) - 1 downto 0); -- Cociente / Dividendo desplazado
    signal R_reg : unsigned(TOTAL_WIDTH downto 0);           -- Resto (1 bit extra para evitar overflow)
    signal D_reg : unsigned(TOTAL_WIDTH downto 0);           -- Divisor absoluto
    
    -- Registro para guardar el signo final del resultado
    signal out_sign : std_logic := '0';

begin

    process(clk, reset)
        variable r_shift : unsigned(TOTAL_WIDTH downto 0);
        variable abs_num : unsigned(TOTAL_WIDTH - 1 downto 0);
        variable abs_den : unsigned(TOTAL_WIDTH - 1 downto 0);
    begin
        if reset = '1' then
            state    <= IDLE;
            done     <= '0';
            quotient <= FP_ZERO;
            count    <= 0;
            Q_reg    <= (others => '0');
            R_reg    <= (others => '0');
            D_reg    <= (others => '0');
            out_sign <= '0';
            
        elsif rising_edge(clk) then
            case state is
                
                when IDLE =>
                    done <= '0';
                    
                    if start = '1' then
                        -- 1. Determinar el signo del resultado (XOR de los bits de signo)
                        out_sign <= dividend(TOTAL_WIDTH-1) xor divisor(TOTAL_WIDTH-1);
                        
                        -- 2. Extraer valores absolutos
                        if dividend(TOTAL_WIDTH-1) = '1' then
                            abs_num := unsigned(-dividend);
                        else
                            abs_num := unsigned(dividend);
                        end if;
                        
                        if divisor(TOTAL_WIDTH-1) = '1' then
                            abs_den := unsigned(-divisor);
                        else
                            abs_den := unsigned(divisor);
                        end if;
                        
                        -- 3. Protección contra División por Cero
                        -- 3. Protección contra División por Cero
                            if abs_den = 0 then
                                -- Saturar al valor máximo positivo o negativo directamente en bits
                                if dividend(TOTAL_WIDTH-1) = '0' then
                                    -- Máximo positivo: '0' seguido de todo '1's
                                    quotient <= (TOTAL_WIDTH-1 => '0', others => '1');
                                else
                                    -- Máximo negativo: '1' seguido de todo '0's
                                    quotient <= (TOTAL_WIDTH-1 => '1', others => '0');
                                end if;
                            
                            done  <= '1';
                            state <= DONE_STATE;
                            
                        else
                            -- 4. Inicializar registros para la división iterativa
                            D_reg <= '0' & abs_den;
                            R_reg <= (others => '0');
                            
                            -- Alinear el dividendo para el punto fijo (Numerador * 2^FRAC_WIDTH)
                            Q_reg <= (others => '0');
                            Q_reg(TOTAL_WIDTH + FRAC_WIDTH - 1 downto FRAC_WIDTH) <= abs_num;
                            
                            -- Número de bits a procesar (64 bits totales)
                            count <= TOTAL_WIDTH * 2;
                            state <= DIVIDING;
                        end if;
                    end if;
                    
                when DIVIDING =>
                    -- Algoritmo Shift-and-Subtract
                    
                    -- A. Desplazar Resto (R) y Cociente/Dividendo (Q) a la izquierda 1 bit
                    r_shift := R_reg(TOTAL_WIDTH-1 downto 0) & Q_reg(Q_reg'high);
                    
                    -- B. Evaluar resta
                    if r_shift >= D_reg then
                        R_reg <= r_shift - D_reg;                    -- Restaura tras la resta
                        Q_reg <= Q_reg(Q_reg'high-1 downto 0) & '1'; -- Añade '1' al cociente
                    else
                        R_reg <= r_shift;                            -- Mantiene el valor desplazado
                        Q_reg <= Q_reg(Q_reg'high-1 downto 0) & '0'; -- Añade '0' al cociente
                    end if;
                    
                    -- C. Control del bucle
                    if count = 1 then
                        state <= DONE_STATE;
                    else
                        count <= count - 1;
                    end if;
                    
                when DONE_STATE =>
                    -- Asignar el valor final al puerto de salida, restaurando el signo
                    if out_sign = '1' then
                        quotient <= -signed(Q_reg(TOTAL_WIDTH-1 downto 0));
                    else
                        quotient <= signed(Q_reg(TOTAL_WIDTH-1 downto 0));
                    end if;
                    
                    done <= '1';
                    
                    -- Handshake: Esperar a que el maestro baje la señal de start 
                    -- (O si ya es un pulso de un ciclo, salir inmediatamente)
                    if start = '0' then
                        state <= IDLE;
                    end if;
                    
            end case;
        end if;
    end process;

end architecture rtl;