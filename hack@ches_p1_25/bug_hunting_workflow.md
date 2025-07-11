# Hack@CHES'25 Bug Hunting Workflow

## Security Components in Scope
1. **IBEX core & security countermeasures**
2. **HW IP modules:** OTP, ROM, ADC, UART
3. **System reset controller, reset manager**
4. **Crypto IPs & countermeasures:** AES, HMAC, KMAC, CSPRNG
5. **Life cycle controller, flash controller, alert handler**

## Adversary Models
1. Unprivileged software at user-level mode
2. Physical attacker
3. Privileged software in supervisor mode
4. Authorized debug access

## Bug Categories to Look For
### Reset & State Management
- Improper reset handling
- State persistence across resets
- Initialization vulnerabilities

### Access Control & Permissions
- Privilege escalation paths
- Bypass of access controls
- Debug interface vulnerabilities

### Cryptographic Implementations
- Side-channel vulnerabilities
- Key management issues
- RNG weaknesses

### Alert & Error Handling
- Alert suppression or bypass
- Error condition handling
- Race conditions in handlers

### Memory & Bus Security
- Memory access violations
- Bus integrity issues
- Cache/memory corruption

## Testing Strategy
1. **Static Analysis** - Code review for patterns
2. **Dynamic Testing** - Simulation with test cases
3. **Fault Injection** - Error condition testing
4. **Timing Analysis** - Side-channel testing

## Bug Documentation Template
- Team name
- Bug number
- Security feature bypassed
- Finding description
- Location/code reference
- Detection method
- Security impact
- Adversary profile
- Proposed mitigation
- CVSS score and details