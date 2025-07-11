#!/usr/bin/env python3
"""
Security Analysis Framework for Hack@CHES'25 OpenTitan Bug Hunt
Systematic analysis of security-critical components
"""

import os
import re
import subprocess
from pathlib import Path
from typing import List, Dict, Tuple

class SecurityAnalyzer:
    def __init__(self, repo_root: str):
        self.repo_root = Path(repo_root)
        self.security_patterns = [
            # Reset vulnerabilities
            (r'(?i)reset.*(?:bypass|skip|ignore)', 'Reset bypass vulnerability'),
            (r'(?i)(?:rst_n|reset).*(?:state|persist)', 'Reset state persistence'),
            
            # Access control issues
            (r'(?i)debug.*(?:enable|unlock|bypass)', 'Debug access vulnerability'),
            (r'(?i)privilege.*(?:escalat|bypass)', 'Privilege escalation'),
            
            # Crypto vulnerabilities
            (r'(?i)key.*(?:leak|expose|hardcode)', 'Key exposure vulnerability'),
            (r'(?i)random.*(?:seed|predict)', 'RNG predictability'),
            
            # Alert handler issues
            (r'(?i)alert.*(?:suppress|disable|bypass)', 'Alert suppression'),
            (r'(?i)ping.*(?:fail|timeout|bypass)', 'Ping mechanism bypass'),
            
            # Memory/Bus security
            (r'(?i)buffer.*(?:overflow|underflow)', 'Buffer overflow'),
            (r'(?i)(?:bus|memory).*(?:integrity|corrupt)', 'Memory corruption'),
        ]
        
        self.critical_files = [
            # Core security components
            'hw/ip/rv_core_ibex/rtl/*.sv',
            'hw/ip_templates/alert_handler/rtl/*.sv',
            'hw/ip/rstmgr/rtl/*.sv',
            'hw/ip/pwrmgr/rtl/*.sv',
            'hw/ip/lc_ctrl/rtl/*.sv',
            
            # Crypto components
            'hw/ip/aes/rtl/*.sv',
            'hw/ip/hmac/rtl/*.sv',
            'hw/ip/kmac/rtl/*.sv',
            'hw/ip/csrng/rtl/*.sv',
            
            # Memory/Storage
            'hw/ip/flash_ctrl/rtl/*.sv',
            'hw/ip/otp_ctrl/rtl/*.sv',
            'hw/ip/rom_ctrl/rtl/*.sv',
        ]

    def find_files_by_pattern(self, pattern: str) -> List[Path]:
        """Find files matching a pattern"""
        files = []
        for path in self.repo_root.rglob(pattern):
            if (path.is_file() and 
                not path.name.startswith('.') and 
                not path.name.startswith('._') and
                path.suffix in ['.sv', '.v']):
                files.append(path)
        return files

    def analyze_file_for_patterns(self, filepath: Path) -> List[Tuple[int, str, str]]:
        """Analyze a file for security vulnerability patterns"""
        findings = []
        try:
            with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                lines = f.readlines()
                
            for line_num, line in enumerate(lines, 1):
                for pattern, description in self.security_patterns:
                    if re.search(pattern, line):
                        findings.append((line_num, line.strip(), description))
        except Exception as e:
            print(f"Error analyzing {filepath}: {e}")
            
        return findings

    def analyze_reset_handling(self) -> Dict[str, List]:
        """Specific analysis for reset handling vulnerabilities"""
        reset_files = []
        for pattern in ['**/rtl/*reset*.sv', '**/rtl/*rst*.sv']:
            reset_files.extend(self.find_files_by_pattern(pattern))
            
        reset_vulnerabilities = {}
        for filepath in reset_files:
            findings = self.analyze_file_for_patterns(filepath)
            if findings:
                reset_vulnerabilities[str(filepath)] = findings
                
        return reset_vulnerabilities

    def analyze_debug_interfaces(self) -> Dict[str, List]:
        """Analyze debug interface security"""
        debug_files = []
        for pattern in ['**/rtl/*debug*.sv', '**/rtl/*jtag*.sv', '**/rtl/*dmi*.sv']:
            debug_files.extend(self.find_files_by_pattern(pattern))
            
        debug_vulnerabilities = {}
        for filepath in debug_files:
            findings = self.analyze_file_for_patterns(filepath)
            if findings:
                debug_vulnerabilities[str(filepath)] = findings
                
        return debug_vulnerabilities

    def run_comprehensive_analysis(self) -> Dict[str, Dict]:
        """Run comprehensive security analysis"""
        results = {
            'reset_vulnerabilities': self.analyze_reset_handling(),
            'debug_vulnerabilities': self.analyze_debug_interfaces(),
            'general_patterns': {}
        }
        
        # Analyze all critical files
        for pattern in self.critical_files:
            files = self.find_files_by_pattern(pattern.split('/')[-1])
            for filepath in files:
                if any(comp in str(filepath) for comp in pattern.split('/')[:-1]):
                    findings = self.analyze_file_for_patterns(filepath)
                    if findings:
                        results['general_patterns'][str(filepath)] = findings
        
        return results

    def generate_report(self, results: Dict) -> str:
        """Generate a security analysis report"""
        report = []
        report.append("# OpenTitan Security Analysis Report")
        report.append("Generated for Hack@CHES'25 Competition\n")
        
        total_findings = 0
        for category, findings in results.items():
            if findings:
                report.append(f"## {category.replace('_', ' ').title()}")
                for filepath, file_findings in findings.items():
                    report.append(f"\n### {filepath}")
                    for line_num, line, description in file_findings:
                        report.append(f"- **Line {line_num}**: {description}")
                        report.append(f"  ```{line}```")
                        total_findings += 1
                report.append("")
        
        report.insert(2, f"**Total potential findings: {total_findings}**\n")
        return "\n".join(report)

if __name__ == "__main__":
    analyzer = SecurityAnalyzer(".")
    results = analyzer.run_comprehensive_analysis()
    report = analyzer.generate_report(results)
    
    with open("security_analysis_report.md", "w") as f:
        f.write(report)
    
    print("Security analysis complete. Report saved to security_analysis_report.md")
    print(f"Found potential issues in {sum(len(v) for v in results.values() if isinstance(v, dict))} files")