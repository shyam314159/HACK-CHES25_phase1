# Bug Submission #2 - Debug Reset State Persistence

## Bug Information
**Team name**: Security Researchers  
**Bug number**: 2  
**Security feature bypassed**: Debug module reset and state isolation  

## Finding
The debug module interface (DMI) reset logic in `dmi_jtag.sv` contains a race condition that can allow debug state to persist across reset operations. The `dmi_clear` signal combines multiple reset sources using OR logic, creating timing windows where partial resets may occur, leaving sensitive debug state accessible.

The vulnerability occurs in the reset combination logic where `jtag_dmi_clear` and hardware-triggered `dmihardreset` are combined without proper synchronization, potentially allowing an attacker to maintain debug access across intended security reset boundaries.

## Location or code reference
`./hw/vendor/pulp_riscv_dbg/src/dmi_jtag.sv`; line 65

Vulnerable code:
```systemverilog
assign dmi_clear = jtag_dmi_clear || (dtmcs_select && update && dtmcs_q.dmihardreset);
```

## Detection method
Static analysis of reset logic combined with timing analysis of reset signal propagation paths. Identified through examination of reset source combination without proper synchronization.

## Security impact
This vulnerability allows an attacker to:
- Maintain debug access across security reset operations
- Bypass intended debug session termination
- Preserve debug authentication state when it should be cleared
- Access debug functionality after partial system reset
- Potentially recover from security error states that should lock the system

The impact is particularly severe in secure boot scenarios where debug access should be completely disabled after certain reset conditions.

## Adversary profile
**Physical attacker** - An attacker with physical access to JTAG interface who can manipulate reset timing to exploit race conditions in debug reset logic.

## Proposed mitigation
1. Implement proper reset synchronization for all debug reset sources
2. Add explicit state clearing for all debug registers on any reset condition
3. Use synchronized reset logic with proper timing constraints
4. Add reset completion verification before allowing debug operations

```systemverilog
// Proposed fix - synchronized reset with complete state clearing
logic dmi_clear_sync;
always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni) begin
    dmi_clear_sync <= 1'b1;
  end else begin
    dmi_clear_sync <= jtag_dmi_clear || (dtmcs_select && update && dtmcs_q.dmihardreset);
  end
end

// Ensure complete state clearing on any reset
always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni || dmi_clear_sync) begin
    // Clear ALL debug state registers
    dtmcs_q <= '0;
    dr_q <= '0;
    state_q <= Idle;
    error_q <= DMINoError;
  end
end
```

## CVSSv3.1 Base score and severity
**Medium (6.8)**

## CVSSv3.1 details
CVSS:3.1/AV:P/AC:H/PR:N/UI:N/S:U/C:H/I:H/A:L

- **Access Vector**: Physical (P) - Requires physical access to JTAG
- **Attack Complexity**: High (H) - Requires precise timing manipulation
- **Privileges Required**: None (N) - No authentication needed for timing attack
- **User Interaction**: None (N) - Automated exploitation possible
- **Scope**: Unchanged (U) - Limited to debug module scope
- **Confidentiality Impact**: High (H) - May expose debug authentication state
- **Integrity Impact**: High (H) - Can maintain unauthorized debug access
- **Availability Impact**: Low (L) - Limited impact on system availability

## Test Case
```systemverilog
// Test: Debug reset state persistence
initial begin
  // 1. Establish debug session
  establish_debug_session();
  set_debug_state(DEBUG_AUTHENTICATED);
  
  // 2. Trigger partial reset through timing manipulation
  fork
    begin
      // Assert JTAG reset
      jtag_dmi_clear = 1'b1;
      #10ns;
      jtag_dmi_clear = 1'b0;
    end
    begin
      // Simultaneously trigger hardware reset with precise timing
      #5ns;
      trigger_dmi_hard_reset();
    end
  join
  
  // 3. Verify if debug state persisted through reset race
  #100ns;
  assert(debug_state_preserved()) 
    else $error("Reset race condition test failed");
  
  // 4. Attempt debug operations that should be blocked
  result = attempt_debug_access();
  assert(result == ACCESS_GRANTED) 
    else $error("Debug access should be blocked after reset");
end
```