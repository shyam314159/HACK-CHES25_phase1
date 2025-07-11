# Quick Setup Commands Reference

## Environment Setup Commands

### 1. Extract OpenTitan Source Code
```bash
# Extract the competition archive
cd attached_assets
tar -xzf hack@ches_p1_25.tar_1751455780111.gz
cd ..
cp -r attached_assets/hack@ches_p1_25 .
```

### 2. Set Up OpenTitan Environment
```bash
# Navigate to OpenTitan directory
cd hack@ches_p1_25

# Configure environment variables
source env.sh

# Verify setup
echo $REPO_TOP
```

### 3. Run Security Analysis Scripts
```bash
# Run comprehensive security analysis
python3 security_analysis.py

# Run debug-specific vulnerability tests
python3 test_debug_vulnerabilities.py

# Run alert handler analysis
python3 alert_handler_analysis.py
```

## Key File Locations

### Critical Security Components
```bash
# Debug module files
hw/vendor/pulp_riscv_dbg/src/dm_csrs.sv
hw/vendor/pulp_riscv_dbg/src/dmi_jtag.sv

# Alert handler files  
hw/ip_templates/alert_handler/rtl/alert_handler.sv
hw/ip_templates/alert_handler/rtl/alert_handler_ping_timer.sv

# Reset management
hw/ip/rstmgr/rtl/rstmgr.sv
```

### Analysis Results
```bash
# Comprehensive findings summary
comprehensive_security_findings.md

# Detailed technical guide (for VLSI background)
COMPLETE_SECURITY_ANALYSIS_GUIDE.md

# Beginner-friendly explanation
BEGINNER_FRIENDLY_SUMMARY.md

# Competition bug submissions
bug_submission_1.md
bug_submission_2.md
```

## Verification Commands

### Check Environment Setup
```bash
# Verify REPO_TOP is set correctly
echo "Repository root: $REPO_TOP"

# Check if key files exist
ls hw/vendor/pulp_riscv_dbg/src/dm_csrs.sv
ls hw/ip_templates/alert_handler/rtl/alert_handler.sv
```

### Run Analysis Verification
```bash
# Count total findings
grep -r "Severity:" . --include="*.md" | wc -l

# List high-severity issues
grep -r "High" . --include="*.md" | grep -i severity
```

## Understanding the Output

### Analysis Script Results Format
```
Finding #X:
Severity: High/Medium/Low
Issue: Brief description
File: Path to vulnerable file
Line: Line number
Code: Actual code snippet
Description: Detailed explanation
```

### CVSS Score Interpretation
- **8.0-10.0**: Critical severity - Immediate action required
- **7.0-7.9**: High severity - Significant risk
- **4.0-6.9**: Medium severity - Moderate risk
- **0.1-3.9**: Low severity - Minor risk

## Common Issues and Solutions

### Problem: "Permission denied" when running scripts
```bash
# Solution: Make scripts executable
chmod +x security_analysis.py
chmod +x test_debug_vulnerabilities.py
chmod +x alert_handler_analysis.py
```

### Problem: "Module not found" errors
```bash
# Solution: Ensure Python path is set correctly
export PYTHONPATH="$REPO_TOP:$PYTHONPATH"
```

### Problem: "File not found" errors
```bash
# Solution: Verify you're in the correct directory
pwd
# Should show: /path/to/your/workspace/hack@ches_p1_25
```

## Customizing the Analysis

### Adding New Vulnerability Patterns
Edit `security_analysis.py` and add patterns to the `vulnerability_patterns` list:
```python
vulnerability_patterns = [
    (r'your_pattern_here', 'Description of vulnerability type'),
    # Add more patterns as needed
]
```

### Focusing on Specific Components
```bash
# Analyze only debug module
grep -r "debug" hw/vendor/pulp_riscv_dbg/ --include="*.sv"

# Analyze only alert handler
grep -r "alert" hw/ip_templates/alert_handler/ --include="*.sv"
```

### Creating Custom Reports
```bash
# Generate CSV summary of all findings
python3 -c "
import glob
import re

findings = []
for file in glob.glob('*.md'):
    with open(file, 'r') as f:
        content = f.read()
        # Extract findings data and create CSV
"
```

This reference guide provides all the essential commands and file locations needed to reproduce the security analysis or extend it with additional research.