# constraints/timing.sdc
# Ràng buộc thời gian. Một miền xung nhịp duy nhất 27.0 MHz (REQ-C-03).
# Ngưỡng REQ-P-01: F_max sau P&R phải >= 27.0 MHz.
create_clock -name clk_27m -period 37.037 [get_ports {clk_27m}]
