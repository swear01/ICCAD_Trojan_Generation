#!/usr/bin/env python3
"""
Simplified Trojan Generator
Generates parameterized trojan circuits with randomized parameters.
"""

import random
import argparse
import json
from pathlib import Path
from typing import Dict, List, Any

from config_loader import get_config_loader


class TrojanGenerator:
    def __init__(self, output_dir):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(exist_ok=True)
        
        # Create clean and trojan subdirectories
        self.clean_dir = self.output_dir / "clean"
        self.trojan_dir = self.output_dir / "trojan"
        self.clean_dir.mkdir(exist_ok=True)
        self.trojan_dir.mkdir(exist_ok=True)
        
        self.config_loader = get_config_loader()
    
    def read_trojan_core(self, trojan_id: str, variant: str) -> str:
        """Read the trojan core file (trojaned or clean version)"""
        if variant == "clean":
            trojan_num = trojan_id.replace('trojan', '')
            trojan_file = f"trojan_core/clean{trojan_num}.v"
        else:
            trojan_file = f"trojan_core/{trojan_id}.v"
        
        try:
            with open(trojan_file, 'r') as f:
                return f.read()
        except FileNotFoundError:
            print(f"Warning: Trojan file {trojan_file} not found")
            return f"// {trojan_file} not found"
    
    def read_host_circuit(self, trojan_id: str, host_name: str) -> str:
        """Read the host circuit file"""
        host_config = self.config_loader.get_host_config(trojan_id, host_name)
        host_file = host_config['file']
        host_path = f"dataset/{host_file}"
        
        try:
            with open(host_path, 'r') as f:
                return f.read()
        except FileNotFoundError:
            print(f"Warning: Host file {host_path} not found")
            return f"// {host_path} not found"
    
    def format_parameter_value(self, param_name: str, param_value: Any, param_config: Dict[str, Any] = None, all_params: Dict[str, Any] = None) -> str:
        """Format parameter value based on parameter type"""
        if not isinstance(param_value, int):
            return str(param_value)
        
        # Check parameter type - only use bit width notation for random_hex type
        if param_config and 'type' in param_config:
            param_type = param_config['type']
            if param_type in ['choice', 'random_int', 'range']:
                # For these types, just return the plain decimal value
                return str(param_value)
            elif param_type == 'random_hex':
                # For random_hex type, use bit width notation
                if 'bits' in param_config:
                    bits_expr = param_config['bits']
                    if all_params:
                        # Evaluate the bit width expression using other parameter values
                        bit_width = self.config_loader._eval_bits(bits_expr, all_params)
                    else:
                        # Fallback: if it's a simple integer, use it directly
                        try:
                            bit_width = int(bits_expr)
                        except (ValueError, TypeError):
                            bit_width = max(1, param_value.bit_length())
                else:
                    # Default: use minimum bits needed for the value
                    bit_width = max(1, param_value.bit_length())
                
                return f"{bit_width}'d{param_value}"
        
        # Fallback: if no type specified, use plain decimal
        return str(param_value)

    def inject_parameters(self, verilog_code: str, params: Dict[str, Any], param_configs: Dict[str, Any] = None) -> str:
        """Inject parameters into Verilog code"""
        import re
        
        if param_configs is None:
            param_configs = {}
        
        struct_params = {k: v for k, v in params.items() if k != 'crypto_vars'}
        crypto_vars = params.get('crypto_vars', {})
        all_params = {**struct_params, **crypto_vars}
        
        # Inject parameters into parameter list
        for param_name, param_value in all_params.items():
            # Get parameter configuration for bit width
            param_config = param_configs.get(param_name, {})
            param_str = self.format_parameter_value(param_name, param_value, param_config, all_params)
            
            # Pattern to match parameter declarations: parameter [WIDTH:0] NAME = VALUE
            pattern = rf"parameter\s+(\[[^\]]+\]\s+)?{re.escape(param_name)}\s*=\s*[^,\)\n;]+"
            
            # Replace with simple parameter declaration without width specification
            replacement = f"parameter {param_name} = {param_str}"
            
            # Use count=1 to replace only the first occurrence
            verilog_code = re.sub(pattern, replacement, verilog_code, count=1)
        
        return verilog_code

    def add_instance_id_to_module_name(self, verilog_code: str, instance_id: int) -> str:
        """Add instance ID to module name"""
        import re
        
        # Find module declaration and add instance ID
        pattern = r'module\s+(\w+)\s*(#.*?)?\s*\('
        def replacement(match):
            module_name = match.group(1)
            param_part = match.group(2)  # Captures #(...) if it exists
            if param_part:
                # Module already has parameters, keep them
                return f'module {module_name}_{instance_id:04d} {param_part} ('
            else:
                # Module has no parameters, don't add empty parameter list
                return f'module {module_name}_{instance_id:04d} ('
        
        return re.sub(pattern, replacement, verilog_code)
    
    def create_trojan_parameter_mapping(self, trojan_id: str, host_params: Dict[str, Any]) -> Dict[str, Any]:
        """Create parameter mapping from host parameters to trojan parameters"""
        trojan_params = {}
        
        # Common mappings for all trojans
        if 'INPUT_WIDTH' in host_params:
            trojan_params['INPUT_WIDTH'] = host_params['INPUT_WIDTH']
        
        # Generic mapping approach: if host param starts with TROJ_, map to parameter without TROJ_ prefix
        for param_name, param_value in host_params.items():
            if param_name.startswith('TROJ_'):
                trojan_param_name = param_name[5:]  # Remove 'TROJ_' prefix
                trojan_params[trojan_param_name] = param_value
        
        return trojan_params

    def generate_verilog_module(self, trojan_id: str, host_name: str, params: Dict[str, Any], 
                              variant: str, instance_id: int) -> str:
        """Generate complete circuit with host and trojan core"""
        
        # Separate structural from crypto parameters by naming convention
        structural_params = {}
        crypto_params = {}
        
        for param_name, param_value in params.items():
            # Structural parameters are typically: WIDTH, STAGES, SEED, etc.
            # Crypto parameters are typically: MASK, TRIGGER, THRESHOLD, etc. or have TROJ_ prefix
            if (param_name.endswith('_WIDTH') or param_name.endswith('_STAGES') or 
                param_name.endswith('_SEED') or param_name in ['INPUT_WIDTH', 'PIPELINE_STAGES']):
                structural_params[param_name] = param_value
            else:
                crypto_params[param_name] = param_value
        
        # Read host circuit and trojan core
        host_circuit = self.read_host_circuit(trojan_id, host_name)
        trojan_core = self.read_trojan_core(trojan_id, variant)
        
        # Get parameter configurations for bit width information
        host_config = self.config_loader.get_host_config(trojan_id, host_name)
        param_configs = host_config.get('params', {})
        
        # Inject parameters into host circuit
        host_circuit = self.inject_parameters(host_circuit, params, param_configs)
        
        # Create trojan parameters by mapping host parameters to trojan parameters
        trojan_inject_params = self.create_trojan_parameter_mapping(trojan_id, params)
        
        # Create trojan parameter configs by mapping the original configs
        trojan_param_configs = {}
        for param_name, param_value in trojan_inject_params.items():
            # Map trojan parameter names back to host parameter configs
            # For TROJ_ prefix parameters, use the original config
            if f'TROJ_{param_name}' in param_configs:
                trojan_param_configs[param_name] = param_configs[f'TROJ_{param_name}']
            # For parameters like INPUT_WIDTH that are passed through directly
            elif param_name in param_configs:
                trojan_param_configs[param_name] = param_configs[param_name]
        
        trojan_core = self.inject_parameters(trojan_core, trojan_inject_params, trojan_param_configs)
        
        # Add instance ID to host circuit module name
        host_circuit = self.add_instance_id_to_module_name(host_circuit, instance_id)
        
        # Combine host circuit and trojan core
        verilog_code = f"""// Generated {variant} circuit for {trojan_id} with {host_name}
// Instance ID: {instance_id:04d}
// Structural Parameters: {structural_params}
// Crypto Parameters: {crypto_params}

// Host Circuit
{host_circuit}

// Trojan Core
{trojan_core}
"""
        
        return verilog_code
    
    def generate_circuit_pair(self, trojan_id: str, host_name: str, instance_id: int) -> tuple:
        """Generate both clean and trojaned versions of a circuit"""
        
        # Unified approach: all parameters come from the host configuration
        # generate_random_params now uses host configs for ALL trojans
        params = self.config_loader.generate_random_params(trojan_id)
        
        clean_code = self.generate_verilog_module(trojan_id, host_name, params, "clean", instance_id)
        trojaned_code = self.generate_verilog_module(trojan_id, host_name, params, "trojaned", instance_id)
        
        return clean_code, trojaned_code, params, params
    
    def generate_batch(self, num_circuits: int = 10, trojans: List[str] = None) -> None:
        """Generate a batch of circuit pairs"""
        if trojans is None:
            # Get trojan IDs from host configs (unified approach - no core configs anymore)
            all_configs = self.config_loader.get_all_trojan_ids()
            trojans = [tid.replace('_hosts', '') for tid in all_configs if tid.endswith('_hosts')]
        
        summary_data = []
        
        for trojan_id in trojans:
            # Get available host circuits for this trojan
            host_files = self.config_loader.get_host_files(trojan_id)
            if not host_files:
                print(f"Warning: No host circuits found for {trojan_id}, skipping...")
                continue
            
            for host_name in host_files:
                # Create subdirectories for each trojan-host combination
                clean_combo_dir = self.clean_dir / trojan_id / host_name
                trojan_combo_dir = self.trojan_dir / trojan_id / host_name
                clean_combo_dir.mkdir(parents=True, exist_ok=True)
                trojan_combo_dir.mkdir(parents=True, exist_ok=True)
                
                print(f"Generating {num_circuits} instances for {trojan_id} + {host_name}...")
                
                for i in range(num_circuits):
                    clean_code, trojaned_code, trojan_params, host_params = self.generate_circuit_pair(trojan_id, host_name, i)
                    
                    # Write clean version
                    clean_file = clean_combo_dir / f"{trojan_id}_{host_name}_clean_{i:04d}.v"
                    with open(clean_file, 'w') as f:
                        f.write(clean_code)
                    
                    # Write trojaned version
                    trojaned_file = trojan_combo_dir / f"{trojan_id}_{host_name}_trojaned_{i:04d}.v"
                    with open(trojaned_file, 'w') as f:
                        f.write(trojaned_code)
                    
                    # Record parameters
                    summary_data.append({
                        'trojan_id': trojan_id,
                        'host_name': host_name,
                        'instance_id': i,
                        'clean_file': f"clean/{trojan_id}/{host_name}/{trojan_id}_{host_name}_clean_{i:04d}.v",
                        'trojaned_file': f"trojan/{trojan_id}/{host_name}/{trojan_id}_{host_name}_trojaned_{i:04d}.v",
                        'trojan_parameters': trojan_params,
                        'host_parameters': host_params,
                        'trojan_description': self.config_loader.get_description(trojan_id),
                        'host_description': self.config_loader.get_host_config(trojan_id, host_name)['description']
                    })
        
        # Write summary
        summary_file = self.output_dir / "generation_summary.json"
        with open(summary_file, 'w') as f:
            json.dump(summary_data, f, indent=2)
        
        print(f"Generated {len(summary_data)} circuit pairs")
        print(f"Summary: {summary_file}")


def main():
    parser = argparse.ArgumentParser(description="Generate Trojan circuits with randomized parameters")
    parser.add_argument("--output-dir", default="generated_circuits", 
                       help="Output directory for generated circuits")
    parser.add_argument("--num-circuits", type=int, default=1,
                       help="Number of circuit pairs to generate per trojan")
    parser.add_argument("--trojans", nargs="+", 
                       help="Specific trojans to generate (default: all)")
    parser.add_argument("--seed", type=int, help="Random seed for reproducible generation")
    
    args = parser.parse_args()
    
    if args.seed:
        random.seed(args.seed)
        print(f"Random seed set to: {args.seed}")
    
    generator = TrojanGenerator(args.output_dir)
    generator.generate_batch(args.num_circuits, args.trojans)


if __name__ == "__main__":
    main()