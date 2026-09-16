library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use work.lib_config.all;

entity computeGradient is
    generic (
        N_DIM : integer := 2; -- Number of dimensions for the input point
        function f(x : array_of_fp) return fp_type; -- Function for which the gradient is computed
        H : fp_type
    );
    port(
        clk         : in std_logic;
        reset       : in std_logic;
        start       : in std_logic;
        done        : out std_logic;

        x_start           : in array_of_fp(0 to N_DIM-1); -- Input point for which the gradient is computed
        grad              : out array_of_fp(0 to N_DIM-1);
    );
end entity computeGradient;

architecture behavior of computeGradient is
    type state_type is (IDLE, SUM, F_PLUS, FINAL, DONE_STATE);
    signal state : state_type := IDLE;
    --signal x_2minus : array_of_fp(0 to N_DIM-1) := (others => FP_ZERO);
   -- signal x_minus : array_of_fp(0 to N_DIM-1) := (others => FP_ZERO);
    signal x_actual : array_of_fp(0 to N_DIM-1) := (others => FP_ZERO);
    signal grad_temp : array_of_fp(0 to N_DIM-1) := (others => FP_ZERO);
    signal partial_sums : array_of_fp(0 to N_DIM-1) := (others => FP_ZERO);
    signal res_fcn_h : array_of_fp(0 to N_DIM-1) := (others => FP_ZERO);
    signal f_x : fp_type;
    signal f_xplush : fp_type;
    signal fcn_h_done : std_logic_vector(0 to N_DIM-1) := (others => '0');
    signal fcn_done : std_logic := '0';
    signal start_f_h : std_logic_vector(0 to N_DIM-1) := (others => '0');
    signal start_f : std_logic := '0';
begin

    -- f(x,y)
    calc_inst_normal: entity work.fcn_1
            port map (
                clk       => clk,                 -- Conectamos el reloj global
                reset     => rst,                 -- Conectamos el reset global
                start     => start_f,
                entradas_h  => x_actual,              -- Pasamos el array de variables
                resultado => f_x,        -- La salida va directa al exterior
                terminado => fcn_done           -- La señal '1' va al exterior
            );

    -- f(x+h, y) // f(x, y + h)
    GEN_FCN: for i in 0 to N_DIM-1 generate
        calc_inst: entity work.fcn_1
            port map (
                clk       => clk,                 -- Conectamos el reloj global
                reset     => rst,                 -- Conectamos el reset global
                start     => start_f_h,
                entradas  => x_plus_grad(i),              -- Pasamos el array de variables
                resultado => res_fcn_h(i),        -- La salida va directa al exterior
                terminado => fcn_h_done(i)           -- La señal '1' va al exterior
            );
    end generate;

    process(clk, reset)
        variable x_plus_grad : matrix_of_fp(0 to N_DIM-1)(0 to N_DIM-1) := (others => FP_ZERO);
    begin
        if reset = '1' then
            grad <= (others => FP_ZERO);
            state <= IDLE;
            done <= '0';
            x_actual <= x_start;
        elsif rising_edge(clk) then
            case state is
                when IDLE =>
                    if start = '1' then
                        state <= SUM;
                    end if;

                when SUM =>
                    if fcn_done = '1' then
                        state <= F_PLUS;
                        fcn_done <= '0';
                    else 
                        for i in 0 to N_DIM-1 loop
                            partial_sums(i) <= x(i) + H;
                        end loop;
                        start_f <= '1';
                    end if;                   

                when F_PLUS =>
                    if fcn_h_done = (others => '1') then
                        state <= FINAL;
                        start_f_h <= (others => '0');
                    else 
                        for i in 0 to N_DIM-1 loop
                            x_plus_grad(i) := x_actual;
                            for j in 0 to N_DIM-1 loop
                                x_plus_grad(i)(j) := partial_sums(i);
                                start_f_h <= (others => '1');
                                ------
                            end loop;
                        end loop;
                    end if;

                when FINAL =>
                    -- / 2^-5 = * 2^5 = shift left
                    -- restar el grad y desplazar
                when DONE_STATE =>
                    done <= '1';
                    state <= IDLE;
                    grad <= grad_temp;
            end case;
        end if;
    end process;
end behavior;