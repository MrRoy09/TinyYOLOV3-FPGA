# ============================================================================
# Testbench Makefile
# ============================================================================
# Targets:
#   make tb_<name>    - Run individual testbench (e.g., make tb_conv_pe)
#   make unit_tests   - Run all unit testbenches (fast, focused tests)
#   make all_tests    - Run all testbenches with summary report
#   make clean        - Remove simulation artifacts
#
# Simulators:
#   SIM=vivado  - Use Vivado xvlog/xelab/xsim (default)
#   SIM=iverilog - Use Icarus Verilog
#
# Example:
#   make tb_conv_pe SIM=vivado
#   make all_tests 2>&1 | tee regression.log
# ============================================================================

# Default simulator
SIM ?= vivado

# Directories
HDL_DIR      := ..
LIB_DIR      := ../lib
TB_DIR       := .
STIMULUS_DIR := ../../scripts/stimulus
WORK_DIR     := work
AXI_DIR      := ../../TinyYOLOV3_HW_Complete_ex/imports

# Source files (order matters for dependencies)
LIB_SRCS := \
    $(LIB_DIR)/delay_line.sv \
    $(LIB_DIR)/line_buffer.sv \
    $(LIB_DIR)/weight_bank.sv

# AXI master modules (from Vitis RTL kernel wizard)
AXI_SRCS := \
    $(AXI_DIR)/TinyYOLOV3_HW_Complete_example_counter.sv \
    $(AXI_DIR)/TinyYOLOV3_HW_Complete_example_axi_read_master.sv \
    $(AXI_DIR)/TinyYOLOV3_HW_Complete_example_axi_write_master.sv

CORE_SRCS := \
    $(HDL_DIR)/conv_pe.sv \
    $(HDL_DIR)/conv_3x3.sv \
    $(HDL_DIR)/kernel_window.sv \
    $(HDL_DIR)/weights_manager.sv \
    $(HDL_DIR)/bias_store.sv \
    $(HDL_DIR)/quantizer.sv \
    $(HDL_DIR)/maxpool.sv \
    $(HDL_DIR)/conv_controller.sv \
    $(HDL_DIR)/conv_top.sv \
    $(HDL_DIR)/axi_conv_wrapper.sv

ALL_SRCS := $(LIB_SRCS) $(AXI_SRCS) $(CORE_SRCS)

# Unit testbenches (fast, focused tests)
UNIT_TBS := \
    tb_delay_line \
    tb_line_buffer \
    tb_conv_pe \
    tb_conv_3x3_nhwc \
    tb_quantizer \
    tb_maxpool \
    tb_kernel_window \
    tb_weight_bank \
    tb_weight_manager \
    tb_bias_store

# Integration testbenches (slower, more comprehensive)
INTEGRATION_TBS := \
    tb_conv_controller \
    tb_wt_conv_integration \
    tb_conv_top_batch \
    tb_conv_top_1x1 \
    tb_conv_top_multi_og \
    tb_bias_store_batch

# E2E testbenches (full system tests with stimulus files)
E2E_TBS := \
    tb_conv_top_e2e_batch \
    tb_axi_conv_wrapper

# All testbenches
ALL_TBS := $(UNIT_TBS) $(INTEGRATION_TBS) $(E2E_TBS)

# Colors for output (disable if not supported)
RED    := \033[31m
GREEN  := \033[32m
YELLOW := \033[33m
RESET  := \033[0m

# ============================================================================
# Vivado Simulator Rules
# ============================================================================
ifeq ($(SIM),vivado)

XVLOG_FLAGS := -sv --incr --relax -work $(WORK_DIR)
XELAB_FLAGS := -debug typical -s sim_snapshot -timescale 1ns/1ps -L xpm
XSIM_FLAGS  := -runall

# Compile all sources
$(WORK_DIR)/.compiled: $(ALL_SRCS)
	@mkdir -p $(WORK_DIR)
	xvlog $(XVLOG_FLAGS) $(ALL_SRCS) tb_macros.svh
	@touch $@

# Generic testbench rule
define TB_RULE
.PHONY: $(1)
$(1): $(WORK_DIR)/.compiled
	@echo "================================================"
	@echo "Running $(1)"
	@echo "================================================"
	xvlog $(XVLOG_FLAGS) $(TB_DIR)/$(1).sv
	xelab $(XELAB_FLAGS) $(1) -L $(WORK_DIR)
	xsim sim_snapshot $(XSIM_FLAGS) 2>&1 | tee $(WORK_DIR)/$(1).log
	@if grep -q "PASSED\|ALL TESTS PASSED" $(WORK_DIR)/$(1).log; then \
		echo "$(GREEN)[PASSED]$(RESET) $(1)"; \
	elif grep -q "FAILED\|ERROR" $(WORK_DIR)/$(1).log; then \
		echo "$(RED)[FAILED]$(RESET) $(1)"; \
	else \
		echo "$(YELLOW)[UNKNOWN]$(RESET) $(1) - check log"; \
	fi
endef

# Generate rules for each testbench
$(foreach tb,$(ALL_TBS),$(eval $(call TB_RULE,$(tb))))

endif

# ============================================================================
# Icarus Verilog Rules
# ============================================================================
ifeq ($(SIM),iverilog)

IVERILOG_FLAGS := -g2012 -I$(TB_DIR) -Wall
VVP_FLAGS      :=

# Generic testbench rule
define TB_RULE_IV
.PHONY: $(1)
$(1):
	@echo "================================================"
	@echo "Running $(1) (Icarus)"
	@echo "================================================"
	@mkdir -p $(WORK_DIR)
	iverilog $(IVERILOG_FLAGS) -o $(WORK_DIR)/$(1).vvp \
		$(ALL_SRCS) $(TB_DIR)/$(1).sv
	vvp $(VVP_FLAGS) $(WORK_DIR)/$(1).vvp 2>&1 | tee $(WORK_DIR)/$(1).log
	@if grep -q "PASSED\|ALL TESTS PASSED" $(WORK_DIR)/$(1).log; then \
		echo "$(GREEN)[PASSED]$(RESET) $(1)"; \
	elif grep -q "FAILED\|ERROR" $(WORK_DIR)/$(1).log; then \
		echo "$(RED)[FAILED]$(RESET) $(1)"; \
	else \
		echo "$(YELLOW)[UNKNOWN]$(RESET) $(1) - check log"; \
	fi
endef

$(foreach tb,$(ALL_TBS),$(eval $(call TB_RULE_IV,$(tb))))

endif

# ============================================================================
# Batch Run Targets
# ============================================================================

.PHONY: unit_tests integration_tests e2e_tests all_tests clean help

# Run all unit tests
unit_tests:
	@echo "================================================"
	@echo "Running Unit Tests ($(words $(UNIT_TBS)) tests)"
	@echo "================================================"
	@PASS=0; FAIL=0; \
	for tb in $(UNIT_TBS); do \
		$(MAKE) --no-print-directory $$tb SIM=$(SIM) && PASS=$$((PASS+1)) || FAIL=$$((FAIL+1)); \
	done; \
	echo ""; \
	echo "================================================"; \
	echo "Unit Tests Summary: $$PASS passed, $$FAIL failed"; \
	echo "================================================"; \
	[ $$FAIL -eq 0 ]

# Run all integration tests
integration_tests:
	@echo "================================================"
	@echo "Running Integration Tests ($(words $(INTEGRATION_TBS)) tests)"
	@echo "================================================"
	@PASS=0; FAIL=0; \
	for tb in $(INTEGRATION_TBS); do \
		$(MAKE) --no-print-directory $$tb SIM=$(SIM) && PASS=$$((PASS+1)) || FAIL=$$((FAIL+1)); \
	done; \
	echo ""; \
	echo "================================================"; \
	echo "Integration Tests Summary: $$PASS passed, $$FAIL failed"; \
	echo "================================================"; \
	[ $$FAIL -eq 0 ]

# Run E2E tests
e2e_tests:
	@echo "================================================"
	@echo "Running E2E Tests ($(words $(E2E_TBS)) tests)"
	@echo "================================================"
	@PASS=0; FAIL=0; \
	for tb in $(E2E_TBS); do \
		$(MAKE) --no-print-directory $$tb SIM=$(SIM) && PASS=$$((PASS+1)) || FAIL=$$((FAIL+1)); \
	done; \
	echo ""; \
	echo "================================================"; \
	echo "E2E Tests Summary: $$PASS passed, $$FAIL failed"; \
	echo "================================================"; \
	[ $$FAIL -eq 0 ]

# Run all tests with detailed summary
all_tests:
	@echo "================================================"
	@echo "Running Full Test Suite ($(words $(ALL_TBS)) tests)"
	@echo "================================================"
	@echo ""
	@PASS=0; FAIL=0; RESULTS=""; \
	for tb in $(ALL_TBS); do \
		echo "Running $$tb..."; \
		if $(MAKE) --no-print-directory $$tb SIM=$(SIM) > /dev/null 2>&1; then \
			if grep -q "PASSED\|ALL TESTS PASSED" $(WORK_DIR)/$$tb.log 2>/dev/null; then \
				PASS=$$((PASS+1)); \
				RESULTS="$$RESULTS\n$(GREEN)[PASSED]$(RESET) $$tb"; \
			elif grep -q "FAILED\|ERROR" $(WORK_DIR)/$$tb.log 2>/dev/null; then \
				FAIL=$$((FAIL+1)); \
				RESULTS="$$RESULTS\n$(RED)[FAILED]$(RESET) $$tb"; \
			else \
				RESULTS="$$RESULTS\n$(YELLOW)[???]$(RESET)    $$tb"; \
			fi; \
		else \
			FAIL=$$((FAIL+1)); \
			RESULTS="$$RESULTS\n$(RED)[FAILED]$(RESET) $$tb (compile error)"; \
		fi; \
	done; \
	echo ""; \
	echo "================================================"; \
	echo "           TEST RESULTS SUMMARY"; \
	echo "================================================"; \
	echo -e "$$RESULTS"; \
	echo ""; \
	echo "================================================"; \
	echo "Total: $$((PASS+FAIL)) tests, $$PASS passed, $$FAIL failed"; \
	if [ $$FAIL -eq 0 ]; then \
		echo "$(GREEN)ALL TESTS PASSED$(RESET)"; \
	else \
		echo "$(RED)SOME TESTS FAILED$(RESET)"; \
	fi; \
	echo "================================================"; \
	[ $$FAIL -eq 0 ]

# Clean simulation artifacts
clean:
	rm -rf $(WORK_DIR)
	rm -rf xsim.dir
	rm -f *.jou *.log *.pb *.wdb
	rm -f *.vcd
	rm -f webtalk*.jou webtalk*.log

# Help
help:
	@echo "Testbench Makefile"
	@echo ""
	@echo "Usage:"
	@echo "  make tb_<name>        Run individual testbench"
	@echo "  make unit_tests       Run all unit tests"
	@echo "  make integration_tests Run integration tests"
	@echo "  make e2e_tests        Run end-to-end tests"
	@echo "  make all_tests        Run all tests with summary"
	@echo "  make clean            Remove simulation artifacts"
	@echo ""
	@echo "Options:"
	@echo "  SIM=vivado    Use Vivado simulator (default)"
	@echo "  SIM=iverilog  Use Icarus Verilog"
	@echo ""
	@echo "Examples:"
	@echo "  make tb_conv_pe"
	@echo "  make unit_tests SIM=iverilog"
	@echo "  make all_tests 2>&1 | tee regression.log"
	@echo ""
	@echo "Available testbenches:"
	@echo "  Unit: $(UNIT_TBS)"
	@echo "  Integration: $(INTEGRATION_TBS)"
	@echo "  E2E: $(E2E_TBS)"
