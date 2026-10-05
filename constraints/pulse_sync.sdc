create_clock -name clk_src -period 14.000 [get_ports {clk_src}]
create_clock -name clk_dst -period 50.000 [get_ports {clk_dst}]

derive_clock_uncertainty

set_clock_groups -asynchronous \
    -group {clk_src} \
    -group {clk_dst}