create_clock -name clk_wr -period 20.000 [get_ports {clk_wr}]
create_clock -name clk_rd -period 25.000 [get_ports {clk_rd}]

derive_clock_uncertainty

set wr_gray_sync1_data [get_pins -hierarchical {*wr_gray_sync1*|d *wr_gray_sync1*|asdata}]

set rd_gray_sync1_data [get_pins -hierarchical {*rd_gray_sync1*|d *rd_gray_sync1*|asdata}]

set_max_skew \
    -to $wr_gray_sync1_data \
    -get_skew_value_from_clock_period src_clock_period \
    -skew_value_multiplier 0.900

set_max_skew \
    -to $rd_gray_sync1_data \
    -get_skew_value_from_clock_period src_clock_period \
    -skew_value_multiplier 0.900

# wr_gray: clk_wr -> clk_rd
# source period = 20 ns
set_max_delay \
    -from [get_clocks {clk_wr}] \
    -to $wr_gray_sync1_data \
    20.000

# rd_gray: clk_rd -> clk_wr
# source period = 25 ns
set_max_delay \
    -from [get_clocks {clk_rd}] \
    -to $rd_gray_sync1_data \
    25.000

set_min_delay \
    -from [get_clocks {clk_wr}] \
    -to $wr_gray_sync1_data \
    0.000

set_min_delay \
    -from [get_clocks {clk_rd}] \
    -to $rd_gray_sync1_data \
    0.000