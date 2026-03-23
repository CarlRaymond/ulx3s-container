TOP     = blinker
PACKAGE = CABGA381
SPEED   = 6

SRCS    = blinker.v

all: $(TOP).bit

$(TOP).json: $(SRCS)
	yosys -p "synth_ecp5 -top $(TOP) -json $@" $(SRCS)

$(TOP)_routed.config: $(TOP).json blinker.lpf
	nextpnr-ecp5 \
		--12k \
		--package $(PACKAGE) \
		--speed $(SPEED) \
		--lpf blinker.lpf \
		--json $(TOP).json \
		--textcfg $@

$(TOP).bit: $(TOP)_routed.config
	ecppack --svf $(TOP).svf $< $@

flash: $(TOP).bit
	openFPGALoader -b ulx3s --freq 1000000 $(TOP).bit

flash-persistent: $(TOP).bit
	openFPGALoader -b ulx3s --freq 1000000 --unprotect-flash  --write-flash $(TOP).bit

clean:
	rm -f *.json *.config *.bit *.svf

.PHONY: all flash flash-persistent clean
