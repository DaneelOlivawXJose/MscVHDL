library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use work.lib_config.all;

-- ALPHA MUST BE A MULTIPLE OF 2^-n

entity steepestGradient is
    generic (
        MAX_ITER : integer := 1000
    );
    port(
        clk         : in std_logic;
        reset       : in std_logic;
        start       : in std_logic;
        done        : out std_logic;

        start_point : in fp_type;
        result      : out fp_type;
        alpha       : in fp_type
    );
end entity steepestGradient;

architecture behavior of steepestGradient is
    type state_type is (IDLE, COMPUTE_GRADIENT, UPDATE_POINT, CHECK_CONVERGENCE, DONE_STATE);
    signal x : fp_type := FP_ZERO;
    signal grad : fp_type := FP_ZERO;
    signal iter : integer := 0;
    signal state : state_type := IDLE;
begin
    process(clk, reset)
    begin
        if reset = '1' then
            x <= FP_ZERO;
            grad <= FP_ZERO;
            iter <= 0;
            state <= IDLE;
            done <= '0';
        elsif rising_edge(clk) then
            case state is
                when IDLE =>
                    if start = '1' then
                        x <= start_point;
                        iter <= 0;
                        state <= COMPUTE_GRADIENT;
                    end if;

                when COMPUTE_GRADIENT =>
                    grad <= compute_gradient(x); -- You need to implement this function
                    state <= UPDATE_POINT;

                when UPDATE_POINT =>
                    -- Update the point using the gradient and alpha
                    x <= x - (alpha * grad);
                    iter <= iter + 1;
                    state <= CHECK_CONVERGENCE;

                when CHECK_CONVERGENCE =>
                    if iter >= MAX_ITER then
                        state <= DONE_STATE;
                    else
                        state <= COMPUTE_GRADIENT;
                    end if;

                when DONE_STATE =>
                    result <= x;
                    done <= '1';
                    state <= IDLE;

                when others =>
                    state <= IDLE;
            end case;
        end if;
    end process;

end behavior;