# Stage 0 PE unit-test runner.  Icarus Verilog is preferred when installed;
# Verilator is used as a fallback.  Override SIM=iverilog or SIM=verilator to
# select one explicitly, and RTL=/path/to/pe_os.sv to use another RTL location.

SIM ?= auto
RTL ?= ../rtl/pe_os.sv
TB ?= tb_pe_os.sv
TOP ?= tb_pe_os
BUILD_DIR ?= sim_build

ARRAY_RTL ?= ../rtl/pe_os.sv ../rtl/skew_feeder.sv ../rtl/systolic_array.sv
ARRAY_TB ?= tb_systolic_array.sv
ARRAY_TOP ?= tb_systolic_array
N ?= 4
K ?= $(N)
ARRAY_BUILD_DIR ?= sim_build_array_n$(N)_k$(K)

TILE_RTL ?= ../rtl/pe_os.sv ../rtl/skew_feeder.sv ../rtl/systolic_array.sv ../rtl/input_buffer.sv ../rtl/output_buffer.sv ../rtl/control_fsm.sv ../rtl/pe_ws.sv ../rtl/ws_skew_feeder.sv ../rtl/systolic_array_ws.sv ../rtl/output_buffer_ws.sv ../rtl/control_fsm_ws.sv ../rtl/top.sv
TILE_TB ?= tb_top.sv
TILE_TEST_TOP ?= tb_top
TILE_BUILD_DIR ?= sim_build_top_n$(N)_k$(K)

WS_TILE_RTL ?= $(TILE_RTL)
WS_TILE_TB ?= tb_top.sv tb_top_ws.sv
WS_TILE_TEST_TOP ?= tb_top_ws
WS_TILE_BUILD_DIR ?= sim_build_top_ws_n$(N)_k$(K)

WS_PE_RTL ?= ../rtl/pe_ws.sv
WS_PE_TB ?= tb_pe_ws.sv
WS_PE_TOP ?= tb_pe_ws
WS_PE_BUILD_DIR ?= sim_build_pe_ws

WS_ARRAY_RTL ?= ../rtl/pe_ws.sv ../rtl/ws_skew_feeder.sv ../rtl/systolic_array_ws.sv ../rtl/output_buffer_ws.sv
WS_ARRAY_TB ?= tb_systolic_array_ws.sv
WS_ARRAY_TOP ?= tb_systolic_array_ws
WS_ARRAY_BUILD_DIR ?= sim_build_array_ws_n$(N)

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
	@echo "PE:        make run SIM=iverilog"
	@echo "OS array:  make array-regression SIM=iverilog"
	@echo "OS top:    make top-regression SIM=iverilog"
	@echo "WS direct: make ws-regression SIM=iverilog"
	@echo "WS top:    make top-ws-regression SIM=iverilog"
	@echo "Use SIM=verilator and an explicit N/K with any *-run target as needed."

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

.PHONY: array-run array-regression array-clean top-run top-regression top-clean top-ws-run top-ws-regression top-ws-clean ws-pe-run ws-pe-clean ws-array-run ws-array-regression ws-array-clean ws-regression

ifeq ($(SIM),iverilog)
array-run:
	@if [ ! -f "$(ARRAY_TB)" ]; then echo "ERROR: array testbench not found: $(ARRAY_TB)" >&2; exit 2; fi
	@mkdir -p $(ARRAY_BUILD_DIR)
	@iverilog -g2012 -Wall -s $(ARRAY_TOP) -P$(ARRAY_TOP).N=$(N) -P$(ARRAY_TOP).K=$(K) -o $(ARRAY_BUILD_DIR)/$(ARRAY_TOP).vvp $(ARRAY_RTL) $(ARRAY_TB)
	@vvp $(ARRAY_BUILD_DIR)/$(ARRAY_TOP).vvp
else ifeq ($(SIM),verilator)
array-run:
	@if [ ! -f "$(ARRAY_TB)" ]; then echo "ERROR: array testbench not found: $(ARRAY_TB)" >&2; exit 2; fi
	@verilator --binary --timing -Wall --top-module $(ARRAY_TOP) -GN=$(N) -GK=$(K) --Mdir $(ARRAY_BUILD_DIR) $(ARRAY_RTL) $(ARRAY_TB)
	@$(ARRAY_BUILD_DIR)/V$(ARRAY_TOP)
else
array-run:
	@echo "ERROR: no supported open-source SystemVerilog simulator found. Install Icarus Verilog (iverilog + vvp) or Verilator, then rerun make array-run." >&2
	@exit 2
endif

array-regression:
	@set -e; for size in 2 4 8; do $(MAKE) --no-print-directory array-run SIM=$(SIM) N=$$size K=$$size; done

array-clean:
	@rm -rf $(ARRAY_BUILD_DIR)

ifeq ($(SIM),iverilog)
top-run:
	@if [ ! -f "$(TILE_TB)" ]; then echo "ERROR: tile-level testbench not found: $(TILE_TB)" >&2; exit 2; fi
	@mkdir -p $(TILE_BUILD_DIR)
	@iverilog -g2012 -Wall -s $(TILE_TEST_TOP) -P$(TILE_TEST_TOP).N=$(N) -P$(TILE_TEST_TOP).K=$(K) -o $(TILE_BUILD_DIR)/$(TILE_TEST_TOP).vvp $(TILE_RTL) $(TILE_TB)
	@vvp $(TILE_BUILD_DIR)/$(TILE_TEST_TOP).vvp
else ifeq ($(SIM),verilator)
top-run:
	@if [ ! -f "$(TILE_TB)" ]; then echo "ERROR: tile-level testbench not found: $(TILE_TB)" >&2; exit 2; fi
	@verilator --binary --timing -Wall --top-module $(TILE_TEST_TOP) -GN=$(N) -GK=$(K) --Mdir $(TILE_BUILD_DIR) $(TILE_RTL) $(TILE_TB)
	@$(TILE_BUILD_DIR)/V$(TILE_TEST_TOP)
else
top-run:
	@echo "ERROR: no supported open-source SystemVerilog simulator found. Install Icarus Verilog (iverilog + vvp) or Verilator, then rerun make top-run." >&2
	@exit 2
endif

top-regression:
	@set -e; for size in 1 2 4 8; do $(MAKE) --no-print-directory top-run SIM=$(SIM) N=$$size K=$$size; done

top-clean:
	@rm -rf $(TILE_BUILD_DIR)

ifeq ($(SIM),iverilog)
top-ws-run:
	@for tb in $(WS_TILE_TB); do if [ ! -f "$$tb" ]; then echo "ERROR: WS tile-level testbench not found: $$tb" >&2; exit 2; fi; done
	@mkdir -p $(WS_TILE_BUILD_DIR)
	@iverilog -g2012 -Wall -s $(WS_TILE_TEST_TOP) -P$(WS_TILE_TEST_TOP).N=$(N) -P$(WS_TILE_TEST_TOP).K=$(K) -o $(WS_TILE_BUILD_DIR)/$(WS_TILE_TEST_TOP).vvp $(WS_TILE_RTL) $(WS_TILE_TB)
	@vvp $(WS_TILE_BUILD_DIR)/$(WS_TILE_TEST_TOP).vvp
else ifeq ($(SIM),verilator)
top-ws-run:
	@for tb in $(WS_TILE_TB); do if [ ! -f "$$tb" ]; then echo "ERROR: WS tile-level testbench not found: $$tb" >&2; exit 2; fi; done
	@verilator --binary --timing -Wall --top-module $(WS_TILE_TEST_TOP) -GN=$(N) -GK=$(K) --Mdir $(WS_TILE_BUILD_DIR) $(WS_TILE_RTL) $(WS_TILE_TB)
	@$(WS_TILE_BUILD_DIR)/V$(WS_TILE_TEST_TOP)
else
top-ws-run:
	@echo "ERROR: no supported open-source SystemVerilog simulator found. Install Icarus Verilog (iverilog + vvp) or Verilator, then rerun make top-ws-run." >&2
	@exit 2
endif

top-ws-regression:
	@set -e; for size in 1 2 4 8; do $(MAKE) --no-print-directory top-ws-run SIM=$(SIM) N=$$size K=$$size; done

top-ws-clean:
	@rm -rf $(WS_TILE_BUILD_DIR)

ifeq ($(SIM),iverilog)
ws-pe-run:
	@if [ ! -f "$(WS_PE_TB)" ]; then echo "ERROR: WS PE testbench not found: $(WS_PE_TB)" >&2; exit 2; fi
	@mkdir -p $(WS_PE_BUILD_DIR)
	@iverilog -g2012 -Wall -s $(WS_PE_TOP) -o $(WS_PE_BUILD_DIR)/$(WS_PE_TOP).vvp $(WS_PE_RTL) $(WS_PE_TB)
	@vvp $(WS_PE_BUILD_DIR)/$(WS_PE_TOP).vvp

ws-array-run:
	@if [ ! -f "$(WS_ARRAY_TB)" ]; then echo "ERROR: WS array testbench not found: $(WS_ARRAY_TB)" >&2; exit 2; fi
	@mkdir -p $(WS_ARRAY_BUILD_DIR)
	@iverilog -g2012 -Wall -s $(WS_ARRAY_TOP) -P$(WS_ARRAY_TOP).N=$(N) -o $(WS_ARRAY_BUILD_DIR)/$(WS_ARRAY_TOP).vvp $(WS_ARRAY_RTL) $(WS_ARRAY_TB)
	@vvp $(WS_ARRAY_BUILD_DIR)/$(WS_ARRAY_TOP).vvp
else ifeq ($(SIM),verilator)
ws-pe-run:
	@if [ ! -f "$(WS_PE_TB)" ]; then echo "ERROR: WS PE testbench not found: $(WS_PE_TB)" >&2; exit 2; fi
	@verilator --binary --timing -Wall --top-module $(WS_PE_TOP) --Mdir $(WS_PE_BUILD_DIR) $(WS_PE_RTL) $(WS_PE_TB)
	@$(WS_PE_BUILD_DIR)/V$(WS_PE_TOP)

ws-array-run:
	@if [ ! -f "$(WS_ARRAY_TB)" ]; then echo "ERROR: WS array testbench not found: $(WS_ARRAY_TB)" >&2; exit 2; fi
	@verilator --binary --timing -Wall --top-module $(WS_ARRAY_TOP) -GN=$(N) --Mdir $(WS_ARRAY_BUILD_DIR) $(WS_ARRAY_RTL) $(WS_ARRAY_TB)
	@$(WS_ARRAY_BUILD_DIR)/V$(WS_ARRAY_TOP)
else
ws-pe-run ws-array-run:
	@echo "ERROR: no supported open-source SystemVerilog simulator found. Install Icarus Verilog (iverilog + vvp) or Verilator, then rerun the requested WS target." >&2
	@exit 2
endif

ws-array-regression:
	@set -e; for size in 2 4 8; do $(MAKE) --no-print-directory ws-array-run SIM=$(SIM) N=$$size; done

ws-regression: ws-pe-run ws-array-regression

ws-pe-clean:
	@rm -rf $(WS_PE_BUILD_DIR)

ws-array-clean:
	@rm -rf $(WS_ARRAY_BUILD_DIR)
