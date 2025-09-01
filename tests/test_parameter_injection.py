#!/usr/bin/env python3
"""
Parameter Injection Verification Script

This script verifies that all parameters in generated circuits match the 
configurations defined in their respective TOML files.

Usage:
    python test_parameter_injection.py [--verbose] [--trojan TROJAN_ID]
"""

import argparse
import re
import sys
import tomllib
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional
import json

class ParameterVerifier:
    def __init__(self, verbose: bool = False):
        self.verbose = verbose
        # Get paths relative to the project root (one level up from tests/)
        self.project_root = Path(__file__).parent.parent
        self.configs_dir = self.project_root / "configs"
        self.generated_dir = self.project_root / "generated_circuits"
        self.errors = []
        self.warnings = []
        self.verified_count = 0
        
    def log_verbose(self, message: str):
        """Log verbose message if verbose mode is enabled"""
        if self.verbose:
            print(f"[VERBOSE] {message}")
    
    def log_error(self, message: str):
        """Log error message"""
        self.errors.append(message)
        print(f"[ERROR] {message}")
    
    def log_warning(self, message: str):
        """Log warning message"""
        self.warnings.append(message)
        print(f"[WARNING] {message}")
    
    def load_toml_config(self, trojan_id: str) -> Optional[Dict[str, Any]]:
        """Load TOML configuration for a specific trojan"""
        config_file = self.configs_dir / f"{trojan_id}_hosts.toml"
        if not config_file.exists():
            self.log_error(f"Config file not found: {config_file}")
            return None
        
        try:
            with open(config_file, 'rb') as f:
                config = tomllib.load(f)
                self.log_verbose(f"Loaded config for {trojan_id}")
                return config
        except Exception as e:
            self.log_error(f"Failed to load config {config_file}: {e}")
            return None
    
    def extract_parameters_from_verilog(self, verilog_content: str) -> Dict[str, str]:
        """Extract parameter declarations from Verilog content"""
        parameters = {}
        
        # Pattern to match parameter declarations
        # Handles: parameter NAME = VALUE, parameter [WIDTH:0] NAME = VALUE
        pattern = r'parameter\s+(?:\[[^\]]+\]\s+)?(\w+)\s*=\s*([^,\)\n;]+)'
        
        matches = re.finditer(pattern, verilog_content, re.MULTILINE)
        for match in matches:
            param_name = match.group(1).strip()
            param_value = match.group(2).strip()
            parameters[param_name] = param_value
            
        return parameters
    
    def get_expected_parameter_format(self, param_name: str, param_config: Dict[str, Any], 
                                    all_params: Dict[str, Any]) -> str:
        """Get the expected parameter format based on configuration"""
        param_type = param_config.get('type', 'unknown')
        
        if param_type in ['choice', 'random_int', 'range']:
            # These should be plain decimal values
            return "decimal"
        elif param_type == 'random_hex':
            # These should have bit width notation
            bits_expr = param_config.get('bits', 32)
            return f"sized_decimal:{bits_expr}"
        else:
            return "unknown"
    
    def evaluate_bits_expression(self, bits_expr: Any, variables: Dict[str, Any]) -> int:
        """Evaluate bit width expression similar to config_loader._eval_bits"""
        if isinstance(bits_expr, int):
            return bits_expr
        if not isinstance(bits_expr, str):
            return 32
        
        # Simple evaluation for expressions like "INPUT_WIDTH*2"
        try:
            # Replace variable names with their values
            expr = str(bits_expr)
            for var_name, var_value in variables.items():
                if isinstance(var_value, int):
                    expr = expr.replace(var_name, str(var_value))
            
            # Evaluate simple arithmetic expressions
            result = eval(expr, {"__builtins__": {}}, {})
            return max(1, int(result))
        except Exception:
            return 32  # Fallback
    
    def validate_parameter_value(self, param_name: str, actual_value: str, 
                                param_config: Dict[str, Any], all_params: Dict[str, Any]) -> bool:
        """Validate that parameter value matches expected format"""
        param_type = param_config.get('type', 'unknown')
        
        if param_type in ['choice', 'random_int', 'range']:
            # Should be plain decimal
            if re.match(r'^\d+$', actual_value):
                self.log_verbose(f"✓ {param_name}: {actual_value} (plain decimal)")
                return True
            else:
                self.log_error(f"Parameter {param_name} should be plain decimal, got: {actual_value}")
                return False
                
        elif param_type == 'random_hex':
            # Should be in format: WIDTH'd<value>
            bits_expr = param_config.get('bits', 32)
            expected_width = self.evaluate_bits_expression(bits_expr, all_params)
            
            pattern = rf"^{expected_width}'d\d+$"
            if re.match(pattern, actual_value):
                self.log_verbose(f"✓ {param_name}: {actual_value} (sized decimal, width={expected_width})")
                return True
            else:
                self.log_error(f"Parameter {param_name} should be {expected_width}'d<value>, got: {actual_value}")
                return False
        else:
            self.log_warning(f"Unknown parameter type '{param_type}' for {param_name}")
            return True  # Don't fail on unknown types
    
    def verify_file(self, file_path: Path, trojan_id: str, host_name: str, 
                   config: Dict[str, Any]) -> bool:
        """Verify parameter injection in a single generated file"""
        self.log_verbose(f"Verifying {file_path}")
        
        try:
            with open(file_path, 'r') as f:
                verilog_content = f.read()
        except Exception as e:
            self.log_error(f"Failed to read {file_path}: {e}")
            return False
        
        # Get host configuration
        if host_name not in config.get('hosts', {}):
            self.log_error(f"Host {host_name} not found in config for {trojan_id}")
            return False
        
        host_config = config['hosts'][host_name]
        expected_params = host_config.get('params', {})
        
        if not expected_params:
            self.log_verbose(f"No parameters expected for {host_name}, skipping verification")
            return True
        
        # Extract actual parameters from Verilog
        actual_params = self.extract_parameters_from_verilog(verilog_content)
        
        # Parse the comment to get generated parameter values
        generated_values = {}
        comment_match = re.search(r'// Structural Parameters: ({.*?})', verilog_content)
        if comment_match:
            try:
                structural_params = eval(comment_match.group(1))
                generated_values.update(structural_params)
            except:
                pass
        
        comment_match = re.search(r'// Crypto Parameters: ({.*?})', verilog_content)
        if comment_match:
            try:
                crypto_params = eval(comment_match.group(1))
                generated_values.update(crypto_params)
            except:
                pass
        
        success = True
        
        # Verify each expected parameter
        for param_name, param_config in expected_params.items():
            if param_name not in actual_params:
                self.log_error(f"Parameter {param_name} missing in {file_path}")
                success = False
                continue
            
            actual_value = actual_params[param_name]
            
            # Validate parameter format
            if not self.validate_parameter_value(param_name, actual_value, param_config, generated_values):
                success = False
                continue
            
            # Check if parameter was actually injected (not original value)
            if param_name in generated_values:
                # Extract numeric value from actual parameter
                numeric_match = re.search(r"(\d+)(?:'d)?(\d+)?", actual_value)
                if numeric_match:
                    if numeric_match.group(2):  # Sized format like "16'd12345"
                        actual_numeric = int(numeric_match.group(2))
                    else:  # Plain decimal like "12345"
                        actual_numeric = int(numeric_match.group(1))
                    
                    expected_numeric = generated_values[param_name]
                    if actual_numeric != expected_numeric:
                        self.log_error(f"Parameter {param_name} value mismatch: expected {expected_numeric}, got {actual_numeric}")
                        success = False
                    else:
                        self.log_verbose(f"✓ {param_name}: value {expected_numeric} correctly injected")
        
        # Check for unexpected parameters (ones not in config)
        for param_name in actual_params:
            if param_name not in expected_params:
                # This might be a localparam or inherited parameter, just warn
                self.log_verbose(f"Unexpected parameter {param_name} found (might be localparam)")
        
        if success:
            self.verified_count += 1
        
        return success
    
    def verify_trojan(self, trojan_id: str) -> bool:
        """Verify all generated files for a specific trojan"""
        self.log_verbose(f"Verifying trojan {trojan_id}")
        
        # Load configuration
        config = self.load_toml_config(trojan_id)
        if not config:
            return False
        
        # Get expected host files
        host_files = config.get('metadata', {}).get('host_files', [])
        if not host_files:
            self.log_warning(f"No host files defined for {trojan_id}")
            return True
        
        success = True
        
        # Check both clean and trojan directories
        for variant in ['clean', 'trojan']:
            variant_dir = self.generated_dir / variant / trojan_id
            if not variant_dir.exists():
                self.log_warning(f"Directory not found: {variant_dir}")
                continue
            
            # Verify each host
            for host_name in host_files:
                host_dir = variant_dir / host_name
                if not host_dir.exists():
                    self.log_warning(f"Host directory not found: {host_dir}")
                    continue
                
                # Verify all .v files in the host directory
                v_files = list(host_dir.glob("*.v"))
                if not v_files:
                    self.log_warning(f"No .v files found in {host_dir}")
                    continue
                
                for v_file in v_files:
                    if not self.verify_file(v_file, trojan_id, host_name, config):
                        success = False
        
        return success
    
    def verify_all(self, specific_trojan: Optional[str] = None) -> bool:
        """Verify all trojans or a specific trojan"""
        if specific_trojan:
            trojans = [specific_trojan]
        else:
            # Find all trojan config files
            config_files = list(self.configs_dir.glob("trojan*_hosts.toml"))
            trojans = [f.stem.replace('_hosts', '') for f in config_files]
            trojans.sort()
        
        overall_success = True
        
        print(f"Verifying parameter injection for {len(trojans)} trojan(s)...")
        
        for trojan_id in trojans:
            print(f"\n--- Verifying {trojan_id} ---")
            if not self.verify_trojan(trojan_id):
                overall_success = False
        
        return overall_success
    
    def print_summary(self):
        """Print verification summary"""
        print(f"\n{'='*60}")
        print("PARAMETER INJECTION VERIFICATION SUMMARY")
        print(f"{'='*60}")
        print(f"Files verified: {self.verified_count}")
        print(f"Errors: {len(self.errors)}")
        print(f"Warnings: {len(self.warnings)}")
        
        if self.errors:
            print(f"\n{len(self.errors)} ERROR(S) FOUND:")
            for error in self.errors:
                print(f"  - {error}")
        
        if self.warnings:
            print(f"\n{len(self.warnings)} WARNING(S):")
            for warning in self.warnings:
                print(f"  - {warning}")
        
        if not self.errors:
            print(f"\n✅ All parameter injections verified successfully!")
        else:
            print(f"\n❌ Parameter injection verification failed!")


def main():
    parser = argparse.ArgumentParser(description="Verify parameter injection in generated circuits")
    parser.add_argument("--verbose", "-v", action="store_true", 
                       help="Enable verbose output")
    parser.add_argument("--trojan", "-t", type=str,
                       help="Verify specific trojan only (e.g., trojan0)")
    
    args = parser.parse_args()
    
    verifier = ParameterVerifier(verbose=args.verbose)
    success = verifier.verify_all(args.trojan)
    verifier.print_summary()
    
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
