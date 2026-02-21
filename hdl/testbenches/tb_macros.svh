`ifndef TB_MACROS_SVH
`define TB_MACROS_SVH

// ============================================================================
// Common Testbench Macros
// ============================================================================
// Shared infrastructure for all testbenches to ensure consistent:
// - Timeout handling
// - Error tracking
// - Test case formatting
// - Pass/fail reporting
// ============================================================================

// ----------------------------------------------------------------------------
// Timeout Macro
// Usage: `TB_TIMEOUT(100us)
// Prevents runaway simulations - always include in testbenches
// ----------------------------------------------------------------------------
`define TB_TIMEOUT(LIMIT) \
    initial begin \
        #(LIMIT); \
        $display("[%0t] ERROR: TIMEOUT after %s", $time, `"LIMIT`"); \
        $finish; \
    end

// ----------------------------------------------------------------------------
// Test Header/Footer
// Usage: `TB_HEADER("conv_pe")
//        `TB_FOOTER(errors)
// Provides consistent formatting for test start/end
// ----------------------------------------------------------------------------
`define TB_HEADER(NAME) \
    $display("\n========================================="); \
    $display("  %s Testbench", NAME); \
    $display("=========================================");

`define TB_FOOTER(ERRORS) \
    $display("\n========================================="); \
    if (ERRORS == 0) \
        $display("  PASSED: All tests passed"); \
    else \
        $display("  FAILED: %0d errors", ERRORS); \
    $display("=========================================\n");

// ----------------------------------------------------------------------------
// Assertions (don't halt, increment counter)
// Usage: `CHECK_EQ(got, expected, "output value", errors)
//        `CHECK_EQ_HEX(got, expected, "data_out", errors)
// These allow multiple errors to be detected in a single run
// ----------------------------------------------------------------------------
`define CHECK_EQ(GOT, EXPECTED, MSG, ERRORS) \
    if ((GOT) !== (EXPECTED)) begin \
        $display("[%0t] ERROR: %s - got %0d, expected %0d", $time, MSG, GOT, EXPECTED); \
        ERRORS = ERRORS + 1; \
    end

`define CHECK_EQ_HEX(GOT, EXPECTED, MSG, ERRORS) \
    if ((GOT) !== (EXPECTED)) begin \
        $display("[%0t] ERROR: %s - got %h, expected %h", $time, MSG, GOT, EXPECTED); \
        ERRORS = ERRORS + 1; \
    end

// Signed version for checking signed values
`define CHECK_EQ_SIGNED(GOT, EXPECTED, MSG, ERRORS) \
    if ($signed(GOT) !== $signed(EXPECTED)) begin \
        $display("[%0t] ERROR: %s - got %0d, expected %0d", $time, MSG, $signed(GOT), $signed(EXPECTED)); \
        ERRORS = ERRORS + 1; \
    end

// Check with tolerance (useful for floating-point-like comparisons)
`define CHECK_EQ_TOL(GOT, EXPECTED, TOL, MSG, ERRORS) \
    if (((GOT) > (EXPECTED) + (TOL)) || ((GOT) < (EXPECTED) - (TOL))) begin \
        $display("[%0t] ERROR: %s - got %0d, expected %0d (tol=%0d)", $time, MSG, GOT, EXPECTED, TOL); \
        ERRORS = ERRORS + 1; \
    end

// Boolean check
`define CHECK_TRUE(COND, MSG, ERRORS) \
    if (!(COND)) begin \
        $display("[%0t] ERROR: %s - condition false", $time, MSG); \
        ERRORS = ERRORS + 1; \
    end

`define CHECK_FALSE(COND, MSG, ERRORS) \
    if (COND) begin \
        $display("[%0t] ERROR: %s - condition true (expected false)", $time, MSG); \
        ERRORS = ERRORS + 1; \
    end

// ----------------------------------------------------------------------------
// Test Case Marker
// Usage: `TEST_CASE(1, "Single ci_group convolution")
// Provides clear visual separation between test cases
// ----------------------------------------------------------------------------
`define TEST_CASE(NUM, DESC) \
    $display("\n--- Test %0d: %s ---", NUM, DESC);

// ----------------------------------------------------------------------------
// Success/Info Messages
// Usage: `TEST_OK("output matches expected")
//        `TEST_INFO("Processing %0d pixels", count)
// ----------------------------------------------------------------------------
`define TEST_OK(MSG) \
    $display("[%0t] OK: %s", $time, MSG)

`define TEST_INFO(MSG) \
    $display("[%0t] INFO: %s", $time, MSG)

// ----------------------------------------------------------------------------
// VCD Dump Setup (optional convenience macro)
// Usage: `TB_VCD_SETUP("tb_conv_pe")
// Creates VCD file with module name
// ----------------------------------------------------------------------------
`define TB_VCD_SETUP(NAME) \
    initial begin \
        $dumpfile({NAME, ".vcd"}); \
        $dumpvars(0, NAME); \
    end

`endif // TB_MACROS_SVH
