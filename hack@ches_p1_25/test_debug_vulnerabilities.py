#!/usr/bin/env python3
"""
Debug Interface Security Analysis for Hack@CHES'25
Focus on RISC-V debug module vulnerabilities
"""

import os
import re
from pathlib import Path

class DebugSecurityAnalyzer:
    def __init__(self, repo_root: str):
        self.repo_root = Path(repo_root)
        self.debug_files = [
            "hw/vendor/pulp_riscv_dbg/src/dmi_jtag.sv",
            "hw/vendor/pulp_riscv_dbg/src/dm_top.sv",
            "hw/vendor/pulp_riscv_dbg/src/dm_csrs.sv",
            "hw/vendor/pulp_riscv_dbg/src/dm_mem.sv"
        ]
        
    def analyze_reset_vulnerability(self):
        """
        Potential Bug #1: Debug state persistence across resets
        """
        findings = []
        dmi_jtag_path = self.repo_root / "hw/vendor/pulp_riscv_dbg/src/dmi_jtag.sv"
        
        try:
            with open(dmi_jtag_path, 'r') as f:
                lines = f.readlines()
                
            # Look for reset handling patterns
            for i, line in enumerate(lines):
                if 'dmi_clear' in line and 'jtag_dmi_clear' in line:
                    findings.append({
                        'file': str(dmi_jtag_path),
                        'line': i + 1,
                        'code': line.strip(),
                        'issue': 'DMI clear logic combines multiple reset sources',
                        'severity': 'Medium',
                        'description': 'Potential race condition in reset handling'
                    })
                
                # Check for state register reset behavior
                if re.search(r'always_ff.*reset.*begin', line, re.IGNORECASE):
                    # Look at next few lines for incomplete reset
                    context = ''.join(lines[i:i+10])
                    if 'dtmcs_q' in context and not re.search(r'dtmcs_q\s*<=.*0', context):
                        findings.append({
                            'file': str(dmi_jtag_path),
                            'line': i + 1,
                            'code': line.strip(),
                            'issue': 'Potentially incomplete state reset',
                            'severity': 'High',
                            'description': 'Debug state may persist across resets'
                        })
        except Exception as e:
            print(f"Error analyzing {dmi_jtag_path}: {e}")
            
        return findings
    
    def analyze_access_control(self):
        """
        Potential Bug #2: Debug access control bypass
        """
        findings = []
        dm_csrs_path = self.repo_root / "hw/vendor/pulp_riscv_dbg/src/dm_csrs.sv"
        
        try:
            with open(dm_csrs_path, 'r') as f:
                content = f.read()
                lines = content.split('\n')
                
            # Look for authentication/authorization checks
            for i, line in enumerate(lines):
                # Check for missing privilege checks
                if re.search(r'(dmactive|haltreq|resumereq)', line, re.IGNORECASE):
                    # Look for privilege validation in surrounding context
                    context_start = max(0, i-5)
                    context_end = min(len(lines), i+10)
                    context = '\n'.join(lines[context_start:context_end])
                    
                    if not re.search(r'(auth|priv|perm|access)', context, re.IGNORECASE):
                        findings.append({
                            'file': str(dm_csrs_path),
                            'line': i + 1,
                            'code': line.strip(),
                            'issue': 'Missing access control check',
                            'severity': 'High',
                            'description': 'Debug operation may bypass privilege checks'
                        })
                        
        except FileNotFoundError:
            print(f"File not found: {dm_csrs_path}")
        except Exception as e:
            print(f"Error analyzing {dm_csrs_path}: {e}")
            
        return findings
    
    def analyze_error_handling(self):
        """
        Potential Bug #3: Error state manipulation
        """
        findings = []
        dmi_jtag_path = self.repo_root / "hw/vendor/pulp_riscv_dbg/src/dmi_jtag.sv"
        
        try:
            with open(dmi_jtag_path, 'r') as f:
                lines = f.readlines()
                
            for i, line in enumerate(lines):
                # Look for error state clearing logic
                if 'dmireset' in line and 'error_d' in line:
                    findings.append({
                        'file': str(dmi_jtag_path),
                        'line': i + 1,
                        'code': line.strip(),
                        'issue': 'Error state can be cleared without proper validation',
                        'severity': 'Medium',
                        'description': 'Attacker may clear error states to hide attacks'
                    })
                    
                # Check for race conditions in error handling
                if 'error_dmi_busy' in line and 'update' in line:
                    findings.append({
                        'file': str(dmi_jtag_path),
                        'line': i + 1,
                        'code': line.strip(),
                        'issue': 'Potential race condition in error handling',
                        'severity': 'Medium',
                        'description': 'Timing attack may bypass busy state detection'
                    })
                    
        except Exception as e:
            print(f"Error analyzing {dmi_jtag_path}: {e}")
            
        return findings
    
    def generate_test_vectors(self):
        """
        Generate test vectors for identified vulnerabilities
        """
        tests = []
        
        # Test 1: Reset state persistence
        tests.append({
            'name': 'debug_reset_persistence_test',
            'description': 'Test if debug state persists across different reset combinations',
            'test_sequence': [
                'Enable debug mode',
                'Set debug registers',
                'Assert jtag_dmi_clear',
                'Check if debug state persists',
                'Assert dmi_clear',
                'Verify complete state reset'
            ]
        })
        
        # Test 2: Error state manipulation
        tests.append({
            'name': 'debug_error_manipulation_test',
            'description': 'Test error state clearing vulnerabilities',
            'test_sequence': [
                'Trigger DMI busy error',
                'Attempt to clear error via dmireset',
                'Verify error is properly cleared',
                'Test timing-based error clearing'
            ]
        })
        
        return tests
    
    def run_comprehensive_analysis(self):
        """
        Run all analysis methods
        """
        all_findings = []
        
        print("Analyzing debug interface reset vulnerabilities...")
        all_findings.extend(self.analyze_reset_vulnerability())
        
        print("Analyzing debug access control...")
        all_findings.extend(self.analyze_access_control())
        
        print("Analyzing debug error handling...")
        all_findings.extend(self.analyze_error_handling())
        
        return all_findings

if __name__ == "__main__":
    analyzer = DebugSecurityAnalyzer(".")
    findings = analyzer.run_comprehensive_analysis()
    
    print(f"\n=== Debug Security Analysis Results ===")
    print(f"Total findings: {len(findings)}")
    
    for i, finding in enumerate(findings, 1):
        print(f"\nFinding #{i}:")
        print(f"File: {finding['file']}")
        print(f"Line: {finding['line']}")
        print(f"Severity: {finding['severity']}")
        print(f"Issue: {finding['issue']}")
        print(f"Code: {finding['code']}")
        print(f"Description: {finding['description']}")
    
    # Generate test vectors
    tests = analyzer.generate_test_vectors()
    print(f"\n=== Generated Test Vectors ===")
    for test in tests:
        print(f"\nTest: {test['name']}")
        print(f"Description: {test['description']}")
        print("Test sequence:")
        for step in test['test_sequence']:
            print(f"  - {step}")