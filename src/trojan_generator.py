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
        host_path = f"host_circuit/{host_file}"
        
        try:
            with open(host_path, 'r') as f:
                return f.read()
        except FileNotFoundError:
            print(f"Warning: Host file {host_path} not found")
            return f"// {host_path} not found"
    
    def format_parameter_value(self, param_name: str, param_value: Any, original_verilog: str, all_params: Dict[str, Any] = None) -> str:
        """Format parameter value preserving original format when possible"""
        import re
        
        # Extract original parameter format from verilog code
        pattern = rf"parameter\s+{param_name}\s*=\s*([^,\)\s]+)"
        match = re.search(pattern, original_verilog)
        
        if match and isinstance(param_value, int):
            original_value = match.group(1)
            
            # If original was hex format
            if re.match(r"\d+'h[0-9A-Fa-f]+", original_value):
                # For dependent width parameters like TRIGGER_SEQUENCE, use the dependent parameter's value
                if all_params and param_name.startswith('TRIGGER_SEQUENCE') and 'DATA_WIDTH' in all_params:
                    # Get the actual decimal value of DATA_WIDTH, not the parameter format
                    data_width_value = all_params['DATA_WIDTH']
                    # If DATA_WIDTH is passed as hex (like 8'h10), we need the actual decimal value
                    if isinstance(data_width_value, int):
                        bit_width = data_width_value
                    else:
                        # Parse hex format like "8'h10" to get decimal value 16
                        import re as inner_re
                        hex_match = inner_re.match(r"\d+'h([0-9A-Fa-f]+)", str(data_width_value))
                        if hex_match:
                            bit_width = int(hex_match.group(1), 16)
                        else:
                            bit_width = int(data_width_value)
                else:
                    # Extract bit width from original
                    width_match = re.match(r"(\d+)'h", original_value)
                    bit_width = int(width_match.group(1)) if width_match else 32
                
                hex_digits = (bit_width + 3) // 4
                return f"{bit_width}'h{param_value:0{hex_digits}X}"
            
            # If original was binary format
            elif re.match(r"\d+'b[01]+", original_value):
                # For dependent width parameters
                if all_params and param_name.startswith('TRIGGER_SEQUENCE') and 'DATA_WIDTH' in all_params:
                    bit_width = all_params['DATA_WIDTH']
                else:
                    # Extract bit width from original
                    width_match = re.match(r"(\d+)'b", original_value)
                    bit_width = int(width_match.group(1)) if width_match else 32
                
                return f"{bit_width}'b{param_value:0{bit_width}b}"
        
        # Default formatting for int values
        if isinstance(param_value, int):
            # For width/size parameters, keep as decimal
            if param_name.endswith('_WIDTH') or param_name.endswith('_BITS') or param_name.endswith('_SIZE'):
                return f"{param_value}"
            elif param_value >= 0 and param_value <= 15:
                return f"{param_value}"
            else:
                # Determine bit width needed for hex formatting
                bit_width = max(1, param_value.bit_length())
                if bit_width <= 4:
                    return f"4'h{param_value:X}"
                elif bit_width <= 8:
                    return f"8'h{param_value:02X}"
                elif bit_width <= 16:
                    return f"16'h{param_value:04X}"
                elif bit_width <= 32:
                    return f"32'h{param_value:08X}"
                else:
                    return f"64'h{param_value:016X}"
        
        return str(param_value)

    def inject_parameters(self, verilog_code: str, params: Dict[str, Any]) -> str:
        """Inject parameters into Verilog code"""
        import re
        
        struct_params = {k: v for k, v in params.items() if k != 'crypto_vars'}
        crypto_vars = params.get('crypto_vars', {})
        all_params = {**struct_params, **crypto_vars}
        
        # Inject parameters into parameter list
        for param_name, param_value in all_params.items():
            # Format parameter value preserving original format
            param_str = self.format_parameter_value(param_name, param_value, verilog_code, all_params)
            
            # Replace parameter default values
            pattern = rf"parameter\s+{param_name}\s*=\s*[^,\)\s]+"
            replacement = f"parameter {param_name} = {param_str}"
            verilog_code = re.sub(pattern, replacement, verilog_code)
        
        return verilog_code

    def add_instance_id_to_module_name(self, verilog_code: str, instance_id: int) -> str:
        """Add instance ID to module name"""
        import re
        
        # Find module declaration and add instance ID
        pattern = r'module\s+(\w+)\s*#?\s*\('
        def replacement(match):
            module_name = match.group(1)
            return f'module {module_name}_{instance_id:04d} #('
        
        return re.sub(pattern, replacement, verilog_code)

    def generate_verilog_module(self, trojan_id: str, host_name: str, trojan_params: Dict[str, Any], 
                              host_params: Dict[str, Any], variant: str, instance_id: int) -> str:
        """Generate complete circuit with host and trojan core"""
        trojan_struct_params = {k: v for k, v in trojan_params.items() if k != 'crypto_vars'}
        trojan_crypto_vars = trojan_params.get('crypto_vars', {})
        host_struct_params = {k: v for k, v in host_params.items() if k != 'crypto_vars'}
        host_crypto_vars = host_params.get('crypto_vars', {})
        
        # Read host circuit and trojan core
        host_circuit = self.read_host_circuit(trojan_id, host_name)
        trojan_core = self.read_trojan_core(trojan_id, variant)
        
        # Inject parameters into host and trojan core separately
        host_circuit = self.inject_parameters(host_circuit, host_params)
        trojan_core = self.inject_parameters(trojan_core, trojan_params)
        
        # Add instance ID to host circuit module name
        host_circuit = self.add_instance_id_to_module_name(host_circuit, instance_id)
        
        # Combine host circuit and trojan core
        verilog_code = f"""// Generated {variant} circuit for {trojan_id} with {host_name}
// Instance ID: {instance_id:04d}
// Trojan Parameters: {trojan_struct_params}
// Trojan Crypto Variables: {trojan_crypto_vars}
// Host Parameters: {host_struct_params}
// Host Crypto Variables: {host_crypto_vars}

`timescale 1ns/1ps

// Host Circuit
{host_circuit}

// Trojan Core
{trojan_core}
"""
        
        return verilog_code
    
    def generate_circuit_pair(self, trojan_id: str, host_name: str, instance_id: int) -> tuple:
        """Generate both clean and trojaned versions of a circuit"""
        trojan_params = self.config_loader.generate_random_params(trojan_id)
        host_params = self.config_loader.generate_random_host_params(trojan_id, host_name)
        
        clean_code = self.generate_verilog_module(trojan_id, host_name, trojan_params, host_params, "clean", instance_id)
        trojaned_code = self.generate_verilog_module(trojan_id, host_name, trojan_params, host_params, "trojaned", instance_id)
        
        return clean_code, trojaned_code, trojan_params, host_params
    
    def generate_batch(self, num_circuits: int = 10, trojans: List[str] = None) -> None:
        """Generate a batch of circuit pairs"""
        if trojans is None:
            # Get trojan IDs that have corresponding trojan core configs (not host configs)
            all_configs = self.config_loader.get_all_trojan_ids()
            trojans = [tid for tid in all_configs if not tid.endswith('_hosts')]
        
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