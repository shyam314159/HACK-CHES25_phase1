#!/usr/bin/env python3
"""
Alert Handler Security Analysis for Hack@CHES'25
Focus on ping timer and alert processing vulnerabilities
"""

import re
from pathlib import Path

class AlertHandlerAnalyzer:
    def __init__(self, repo_root: str):
        self.repo_root = Path(repo_root)
        
    def analyze_ping_timing_vulnerability(self):
        """
        Analyze ping timer for timing-based vulnerabilities
        """
        findings = []
        ping_timer_path = self.repo_root / "hw/ip_templates/alert_handler/rtl/alert_handler_ping_timer.sv"
        
        try:
            with open(ping_timer_path, 'r') as f:
                lines = f.readlines()
                
            for i, line in enumerate(lines):
                # Look for ping timeout logic
                if 'timer_expired' in line and 'ping_fail' in line:
                    findings.append({
                        'file': str(ping_timer_path),
                        'line': i + 1,
                        'code': line.strip(),
                        'issue': 'Ping timeout may be exploitable through timing manipulation',
                        'severity': 'Medium',
                        'description': 'Attacker may manipulate ping timing to cause false failures'
                    })
                
                # Check for spurious ping detection
                if 'spurious' in line and 'ping' in line:
                    findings.append({
                        'file': str(ping_timer_path),
                        'line': i + 1,
                        'code': line.strip(),
                        'issue': 'Spurious ping detection may have bypass conditions',
                        'severity': 'High',
                        'description': 'Potential bypass of alert integrity checks'
                    })
                    
                # Look for state transition vulnerabilities
                if 'state_d' in line and ('timer_expired' in line or 'ping_ok' in line):
                    context = ''.join(lines[max(0, i-3):i+3])
                    if 'id_vld' not in context:
                        findings.append({
                            'file': str(ping_timer_path),
                            'line': i + 1,
                            'code': line.strip(),
                            'issue': 'State transition without proper validation',
                            'severity': 'High',
                            'description': 'State machine may transition without validating ping authenticity'
                        })
                        
        except Exception as e:
            print(f"Error analyzing {ping_timer_path}: {e}")
            
        return findings
    
    def analyze_alert_suppression_vulnerability(self):
        """
        Analyze alert handler for suppression vulnerabilities
        """
        findings = []
        alert_handler_path = self.repo_root / "hw/ip_templates/alert_handler/rtl/alert_handler.sv"
        
        try:
            with open(alert_handler_path, 'r') as f:
                lines = f.readlines()
                
            for i, line in enumerate(lines):
                # Look for alert enable logic
                if re.search(r'alert.*en.*=', line, re.IGNORECASE):
                    # Check if there's proper protection against disabling
                    context = ''.join(lines[max(0, i-5):i+5])
                    if not re.search(r'(regwen|lock|protect)', context, re.IGNORECASE):
                        findings.append({
                            'file': str(alert_handler_path),
                            'line': i + 1,
                            'code': line.strip(),
                            'issue': 'Alert enable may be disabled without proper protection',
                            'severity': 'High',
                            'description': 'Attacker may disable alerts to hide malicious activity'
                        })
                        
                # Look for ping enable bypass
                if 'ping_enable' in line and '==' in line:
                    findings.append({
                        'file': str(alert_handler_path),
                        'line': i + 1,
                        'code': line.strip(),
                        'issue': 'Ping enable check may be bypassable',
                        'severity': 'Medium',
                        'description': 'Ping mechanism could be disabled by attacker'
                    })
                    
        except Exception as e:
            print(f"Error analyzing {alert_handler_path}: {e}")
            
        return findings
    
    def analyze_escalation_bypass(self):
        """
        Analyze escalation logic for bypass vulnerabilities
        """
        findings = []
        
        # Check escalation timer implementation
        esc_timer_path = self.repo_root / "hw/ip_templates/alert_handler/rtl/alert_handler_esc_timer.sv"
        
        try:
            with open(esc_timer_path, 'r') as f:
                lines = f.readlines()
                
            for i, line in enumerate(lines):
                # Look for escalation state transitions
                if 'esc_state' in line and 'Idle' in line:
                    context = ''.join(lines[max(0, i-3):i+3])
                    if 'clear' in context or 'reset' in context:
                        findings.append({
                            'file': str(esc_timer_path),
                            'line': i + 1,
                            'code': line.strip(),
                            'issue': 'Escalation state may be reset inappropriately',
                            'severity': 'High',
                            'description': 'Attacker may reset escalation to prevent security response'
                        })
                        
                # Check for escalation counter manipulation
                if 'esc_cnt' in line and ('clr' in line or 'reset' in line):
                    findings.append({
                        'file': str(esc_timer_path),
                        'line': i + 1,
                        'code': line.strip(),
                        'issue': 'Escalation counter may be manipulated',
                        'severity': 'High',
                        'description': 'Counter reset could prevent escalation triggers'
                    })
                    
        except FileNotFoundError:
            print(f"File not found: {esc_timer_path}")
        except Exception as e:
            print(f"Error analyzing {esc_timer_path}: {e}")
            
        return findings
    
    def analyze_entropy_dependencies(self):
        """
        Analyze dependencies on entropy sources for vulnerabilities
        """
        findings = []
        ping_timer_path = self.repo_root / "hw/ip_templates/alert_handler/rtl/alert_handler_ping_timer.sv"
        
        try:
            with open(ping_timer_path, 'r') as f:
                lines = f.readlines()
                
            for i, line in enumerate(lines):
                # Look for entropy request logic
                if 'edn_req' in line and 'edn_ack' in line:
                    context = ''.join(lines[max(0, i-5):i+5])
                    if 'timeout' not in context and 'fallback' not in context:
                        findings.append({
                            'file': str(ping_timer_path),
                            'line': i + 1,
                            'code': line.strip(),
                            'issue': 'No fallback for entropy source failure',
                            'severity': 'Medium',
                            'description': 'System may fail if entropy source is unavailable'
                        })
                        
                # Check for LFSR seed handling
                if 'lfsr' in line.lower() and ('seed' in line.lower() or 'entropy' in line.lower()):
                    findings.append({
                        'file': str(ping_timer_path),
                        'line': i + 1,
                        'code': line.strip(),
                        'issue': 'LFSR entropy handling may be predictable',
                        'severity': 'Medium',
                        'description': 'Predictable ping timing could be exploited'
                    })
                    
        except Exception as e:
            print(f"Error analyzing {ping_timer_path}: {e}")
            
        return findings
    
    def run_comprehensive_analysis(self):
        """
        Run comprehensive alert handler security analysis
        """
        all_findings = []
        
        print("Analyzing ping timer vulnerabilities...")
        all_findings.extend(self.analyze_ping_timing_vulnerability())
        
        print("Analyzing alert suppression vulnerabilities...")
        all_findings.extend(self.analyze_alert_suppression_vulnerability())
        
        print("Analyzing escalation bypass vulnerabilities...")
        all_findings.extend(self.analyze_escalation_bypass())
        
        print("Analyzing entropy dependencies...")
        all_findings.extend(self.analyze_entropy_dependencies())
        
        return all_findings

if __name__ == "__main__":
    analyzer = AlertHandlerAnalyzer(".")
    findings = analyzer.run_comprehensive_analysis()
    
    print(f"\n=== Alert Handler Security Analysis Results ===")
    print(f"Total findings: {len(findings)}")
    
    high_severity = [f for f in findings if f['severity'] == 'High']
    medium_severity = [f for f in findings if f['severity'] == 'Medium']
    
    print(f"High severity: {len(high_severity)}")
    print(f"Medium severity: {len(medium_severity)}")
    
    for i, finding in enumerate(findings, 1):
        print(f"\nFinding #{i}:")
        print(f"Severity: {finding['severity']}")
        print(f"Issue: {finding['issue']}")
        print(f"File: {finding['file']}")
        print(f"Line: {finding['line']}")
        print(f"Code: {finding['code']}")
        print(f"Description: {finding['description']}")