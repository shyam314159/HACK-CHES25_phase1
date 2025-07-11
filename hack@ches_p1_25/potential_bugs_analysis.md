# Potential Security Bugs Analysis - Hack@CHES'25

## Analysis Framework
Based on the competition guidelines, focusing on:
- Reset handling vulnerabilities
- Debug interface security 
- State persistence issues
- Access control bypasses
- Alert/error handling flaws

## Target Components Analyzed
1. RISC-V Debug Module (`hw/vendor/pulp_riscv_dbg/src/dmi_jtag.sv`)
2. Alert Handler (`hw/ip_templates/alert_handler/rtl/`)
3. Reset Manager (`hw/ip_templates/rstmgr/rtl/`)
4. Life Cycle Controller
5. Crypto modules (AES, HMAC, KMAC)

## Initial Findings from DMI JTAG Module

### Area of Investigation: Debug Interface Reset Handling
File: `hw/vendor/pulp_riscv_dbg/src/dmi_jtag.sv`

**Key Observations:**
- Lines 64-65: DMI reset logic combines JTAG reset and hardware reset
- Line 253-255: Error state clearing on DMI reset
- Line 264-265: Data register clearing on dmi_clear

**Potential Vulnerability Pattern:**
The reset handling may not properly clear all state when certain combinations of resets occur. Need to investigate if state can persist across resets.

### Area of Investigation: Error State Management  
- Lines 244-255: Error state transitions
- Lines 252-255: Sticky error flag clearing

**Potential Issue:**
Error states might be manipulated or bypassed under specific timing conditions.

## Next Steps for Detailed Analysis
1. Create test scenarios for reset bypass
2. Analyze alert handler ping mechanism for timing vulnerabilities
3. Examine crypto module key management
4. Test debug access control mechanisms

## Test Strategy
- Manual RTL review for vulnerability patterns
- Create simulation test cases
- Develop exploitation proofs-of-concept