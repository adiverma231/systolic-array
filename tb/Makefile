# Stage 0 PE unit-test runner.  Icarus Verilog is preferred when installed;
# Verilator is used as a fallback.  Override SIM=iverilog or SIM=verilator to
# select one explicitly, and RTL=/path/to/pe_os.sv to use another RTL location.

SIM ?= auto
RTL ?= ../rtl/pe_os.sv
TB ?= tb_pe_os.sv
TOP ?= tb_pe_os
BUILD_DIR ?= sim_build

IVERILOG := $(shell command -v iverilog 2>/dev/null)
VVP := $(shell command -v vvp 2>/dev/null)
VERILATOR := $(shell command -v verilator 2>/dev/null)

ifeq ($(SIM),auto)
  ifneq ($(strip $(IVERILOG)),)
    ifneq ($(strip $(VVP)),)
      SIM := iverilog
    else ifneq ($(strip $(VERILATOR)),)
      SIM := verilator
    else
      SIM := missing
    endif
  else ifneq ($(strip $(VERILATOR)),)
    SIM := verilator
  else
    SIM := missing
  endif
endif

.PHONY: run compile clean help

help:
	@echo "Usage: make run [SIM=iverilog|verilator] [RTL=../rtl/pe_os.sv]"
	@echo "The testbench assumes the Stage 0 pe_os interface documented in README.md."

ifeq ($(SIM),iverilog)
run: compile
	@vvp $(BUILD_DIR)/$(TOP).vvp

compile:
	@if [ ! -f "$(RTL)" ]; then echo "ERROR: PE RTL not found at $(RTL). Implement rtl/pe_os.sv first or pass RTL=/path/to/pe_os.sv." >&2; exit 2; fi
	@mkdir -p $(BUILD_DIR)
	@iverilog -g2012 -Wall -s $(TOP) -o $(BUILD_DIR)/$(TOP).vvp $(RTL) $(TB)
else ifeq ($(SIM),verilator)
run: compile
	@$(BUILD_DIR)/V$(TOP)

compile:
	@if [ ! -f "$(RTL)" ]; then echo "ERROR: PE RTL not found at $(RTL). Implement rtl/pe_os.sv first or pass RTL=/path/to/pe_os.sv." >&2; exit 2; fi
	@verilator --binary --timing -Wall --top-module $(TOP) --Mdir $(BUILD_DIR) $(RTL) $(TB)
else
run compile:
	@echo "ERROR: no supported open-source SystemVerilog simulator found. Install Icarus Verilog (iverilog + vvp) or Verilator, then rerun make run." >&2
	@exit 2
endif

clean:
	@rm -rf $(BUILD_DIR)
