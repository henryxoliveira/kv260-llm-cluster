# =============================================================================
# kv260_blinky.xdc — placeholder constraints for the Phase 0 blinky design.
#
# An XDC file tells Vivado two kinds of things:
#   1. Physical: which top-level port connects to which package pin, and at what
#      I/O voltage standard (PACKAGE_PIN, IOSTANDARD).
#   2. Timing: how fast each clock runs (create_clock), so the tools know what
#      "fast enough" means during place-and-route (timing closure).
#
# On the KV260, most designs get their clock from the PS (pl_clk0) through the
# Zynq block design, so Vivado derives that clock automatically and you often
# don't need create_clock here at all.
#
# TODO (Phase 0): look up the real pin for an LED/PMOD from the KV260 carrier
# card XDC published by AMD, and fill it in below. Do NOT guess pin numbers.
# =============================================================================

# set_property PACKAGE_PIN <TBD> [get_ports led_o]
# set_property IOSTANDARD  LVCMOS33 [get_ports led_o]
