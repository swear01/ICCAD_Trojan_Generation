#!/usr/bin/env python3
"""
Trojan Host Generator
Combines host circuits with trojan cores, generating circuits with randomized I/O widths 
and fully randomized cryptographic parameters.
"""

import os
import random
import argparse
import json
from pathlib import Path
from typing import Dict, List, Tuple, Any

from trojan_configs import TROJAN_CONFIGS, get_random_hex, get_random_int, get_choice, get_random_list


class TrojanHostGenerator:
    def __init__(self, output_dir: str = "../generated_circuits"):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(exist_ok=True)
        
        # Create clean and trojan subdirectories
        self.clean_dir = self.output_dir / "clean"
        self.trojan_dir = self.output_dir / "trojan"
        self.clean_dir.mkdir(exist_ok=True)
        self.trojan_dir.mkdir(exist_ok=True)
        
        self.configs = TROJAN_CONFIGS
    
    def generate_random_params(self, trojan_id: str) -> Dict[str, Any]:
        """Generate random parameters for a specific trojan"""
        config = self.configs[trojan_id]
        params = {}
        
        # Generate structural parameters first
        for param_name, param_config in config['params'].items():
            if param_config['type'] == 'choice':
                params[param_name] = get_choice(param_config['values'])
            elif param_config['type'] == 'range':
                min_val = param_config['min']
                max_val = param_config['max'] 
                params[param_name] = get_random_int(min_val, max_val)
        
        # Generate cryptographic variables (fully randomized)
        crypto_vars = {}
        for var_name, var_config in config['crypto_vars'].items():
            if var_config['type'] == 'random_hex':
                # Handle parameter-dependent bit widths
                bits = var_config['bits']
                if isinstance(bits, str) and bits in params:
                    bits = params[bits]
                elif isinstance(bits, str):
                    bits = 32  # Default fallback
                
                if 'fixed_value' in var_config:
                    # Use fixed value (for maintaining original behavior)
                    crypto_vars[var_name] = var_config['fixed_value']
                else:
                    crypto_vars[var_name] = get_random_hex(bits)
                    
            elif var_config['type'] == 'random_int':
                min_val = var_config['min']
                max_val = var_config['max']
                crypto_vars[var_name] = get_random_int(min_val, max_val)
                
            elif var_config['type'] == 'choice':
                crypto_vars[var_name] = get_choice(var_config['values'])
                
            elif var_config['type'] == 'random_list':
                count = var_config['count']
                element_type = var_config['element_type']
                
                if 'values' in var_config:
                    # Use predefined values (for instruction patterns etc.)
                    crypto_vars[var_name] = var_config['values'].copy()
                    random.shuffle(crypto_vars[var_name])
                else:
                    # Generate random list
                    list_kwargs = {k: v for k, v in var_config.items() 
                                 if k not in ['type', 'count', 'element_type', 'description']}
                    crypto_vars[var_name] = get_random_list(count, element_type, **list_kwargs)
        
        params['crypto_vars'] = crypto_vars
        return params
    
    def create_module_name(self, trojan_id: str, variant: str, instance_id: int) -> str:
        """Create unique module name"""
        return f"{trojan_id}_{variant}_inst_{instance_id:04d}"
    
    def format_hex_value(self, value: int, bits: int) -> str:
        """Format integer as Verilog hex literal"""
        if bits <= 8:
            return f"8'h{value:02X}"
        elif bits <= 16:
            return f"16'h{value:04X}"
        elif bits <= 32:
            return f"32'h{value:08X}"
        elif bits <= 64:
            return f"64'h{value:016X}"
        else:
            # For larger widths, use appropriate Verilog syntax
            hex_digits = (bits + 3) // 4
            return f"{bits}'h{value:0{hex_digits}X}"
    
    def read_host_circuit_template(self, trojan_id: str) -> str:
        """Read the host circuit template file"""
        host_file = f"../host_circuit/{self.configs[trojan_id]['host_file']}"
        try:
            with open(host_file, 'r') as f:
                return f.read()
        except FileNotFoundError:
            print(f"Warning: Host file {host_file} not found, using placeholder")
            return "// Host circuit template not found"
    
    def read_trojan_core(self, trojan_id: str, variant: str) -> str:
        """Read the trojan core file (trojaned or clean version)"""
        if variant == "clean":
            # Extract trojan number and use clean version
            trojan_num = trojan_id.replace('trojan', '')
            trojan_file = f"../trojan_core/clean{trojan_num}.v"
        else:
            trojan_file = f"../trojan_core/{trojan_id}.v"
            
        try:
            with open(trojan_file, 'r') as f:
                return f.read()
        except FileNotFoundError:
            print(f"Warning: Trojan file {trojan_file} not found, using placeholder")
            return "// Trojan core not found"
    
    def inject_trojan_parameters(self, trojan_core: str, trojan_id: str, params: Dict[str, Any], instance_id: int, variant: str) -> str:
        """Inject random parameters into trojan core instantiation"""
        import re
        
        struct_params = {k: v for k, v in params.items() if k != 'crypto_vars'}
        crypto_vars = params.get('crypto_vars', {})
        
        # Replace default parameter values with randomized ones
        if trojan_id == 'trojan0':
            # Replace KEY_WIDTH parameter
            trojan_core = re.sub(
                r'parameter KEY_WIDTH = \d+',
                f'parameter KEY_WIDTH = {struct_params.get("KEY_WIDTH", 128)}',
                trojan_core
            )
            
            # Replace LOAD_WIDTH parameter
            trojan_core = re.sub(
                r'parameter LOAD_WIDTH = \d+',
                f'parameter LOAD_WIDTH = {struct_params.get("LOAD_WIDTH", 64)}',
                trojan_core
            )
            
            # Replace crypto parameters with random values
            if 'key_init_value' in crypto_vars:
                key_width = struct_params.get('KEY_WIDTH', 128)
                hex_value = self.format_hex_value(crypto_vars['key_init_value'], key_width)
                trojan_core = re.sub(
                    r'parameter KEY_INIT_VALUE = \w+\'h[0-9A-F]+',
                    f'parameter KEY_INIT_VALUE = {hex_value}',
                    trojan_core
                )
            
            if 'lfsr_feedback_polynomial' in crypto_vars:
                hex_value = self.format_hex_value(crypto_vars['lfsr_feedback_polynomial'], 32)
                trojan_core = re.sub(
                    r'parameter LFSR_FEEDBACK_POLY = \w+\'h[0-9A-F]+',
                    f'parameter LFSR_FEEDBACK_POLY = {hex_value}',
                    trojan_core
                )
            
            if 'load_xor_mask' in crypto_vars:
                load_width = max(64, struct_params.get('LOAD_WIDTH', 64))  # At least 64 bits for mask
                hex_value = self.format_hex_value(crypto_vars['load_xor_mask'], load_width)
                trojan_core = re.sub(
                    r'parameter LOAD_XOR_MASK = \w+\'h[0-9A-F]+',
                    f'parameter LOAD_XOR_MASK = {hex_value}',
                    trojan_core
                )
                    
        elif trojan_id == 'trojan1':
            # Replace trigger threshold
            if 'trigger_threshold' in crypto_vars:
                trojan_core = re.sub(
                    r'parameter TRIGGER_THRESHOLD = \d+',
                    f'parameter TRIGGER_THRESHOLD = {crypto_vars["trigger_threshold"]}',
                    trojan_core
                )
            
            # Replace trigger pattern
            if 'payload_pattern' in crypto_vars:
                hex_value = self.format_hex_value(crypto_vars['payload_pattern'], 4)
                trojan_core = re.sub(
                    r'parameter TRIGGER_PATTERN = \w+\'h[0-9A-F]+',
                    f'parameter TRIGGER_PATTERN = {hex_value}',
                    trojan_core
                )
        
        return trojan_core
    
    def modify_host_circuit_names(self, host_circuit: str, trojan_id: str, instance_id: int) -> str:
        """Modify host circuit module names to add instance ID"""
        import re
        
        # Find the main host module name pattern
        host_module_pattern = f"{trojan_id}_.*?_host"
        
        # Replace module definition
        host_circuit = re.sub(
            f"module ({host_module_pattern})",
            f"module \\1_{instance_id:04d}",
            host_circuit
        )
        
        return host_circuit
    
    def generate_verilog_module(self, trojan_id: str, params: Dict[str, Any], 
                              variant: str, instance_id: int) -> str:
        """Generate complete Verilog module with host circuit and trojan"""
        config = self.configs[trojan_id]
        
        # Extract parameters
        struct_params = {k: v for k, v in params.items() if k != 'crypto_vars'}
        crypto_vars = params.get('crypto_vars', {})
        
        # Read host circuit and trojan core
        host_circuit = self.read_host_circuit_template(trojan_id)
        trojan_core = self.read_trojan_core(trojan_id, variant)
        
        # Modify host circuit module names to include instance ID
        host_circuit = self.modify_host_circuit_names(host_circuit, trojan_id, instance_id)
        
        # Inject parameters into trojan core
        trojan_core = self.inject_trojan_parameters(trojan_core, trojan_id, params, instance_id, variant)
        
        # Create complete circuit file header
        verilog_code = f"""// Generated {variant} circuit for {trojan_id}
// Description: {config['description']}
// Instance ID: {instance_id:04d}
// Structural Parameters: {struct_params}
// Crypto Variables: {crypto_vars}

`timescale 1ns/1ps

//==============================================================================
// HOST CIRCUIT DEFINITION ({'Clean Version' if variant == 'clean' else 'With Trojan'})
//==============================================================================

"""
        
        # Add parameter overrides as comments
        verilog_code += "// Parameter overrides for this instance:\n"
        for param_name, param_value in struct_params.items():
            verilog_code += f"// {param_name} = {param_value}\n"
        
        verilog_code += "// Cryptographic variables:\n"
        for var_name, var_value in crypto_vars.items():
            var_config = config['crypto_vars'][var_name]
            if isinstance(var_value, int):
                bits = var_config.get('bits', 32)
                if isinstance(bits, str) and bits in struct_params:
                    bits = struct_params[bits]
                elif isinstance(bits, str):
                    bits = 32
                verilog_code += f"// {var_name.upper()} = {self.format_hex_value(var_value, bits)}  // {var_config.get('description', '')}\n"
        
        verilog_code += "\n"
        
        # Add the modified host circuit
        verilog_code += host_circuit
        
        # Always add trojan core (clean or trojaned version)
        verilog_code += f"""

//==============================================================================
// TROJAN CORE DEFINITION ({'Dummy/Clean Version' if variant == 'clean' else 'Active Trojan'})
//==============================================================================

{trojan_core}
"""
        
        return verilog_code
    
    def generate_circuit_pair(self, trojan_id: str, instance_id: int) -> Tuple[str, str, Dict]:
        """Generate both clean and trojaned versions of a circuit"""
        params = self.generate_random_params(trojan_id)
        
        clean_code = self.generate_verilog_module(trojan_id, params, "clean", instance_id)
        trojaned_code = self.generate_verilog_module(trojan_id, params, "trojaned", instance_id)
        
        return clean_code, trojaned_code, params
    
    def generate_testbench(self, trojan_id: str, params: Dict[str, Any], instance_id: int) -> str:
        """Generate testbench for the circuit pair"""
        clean_module = self.create_module_name(trojan_id, "clean", instance_id)
        trojaned_module = self.create_module_name(trojan_id, "trojaned", instance_id)
        
        struct_params = {k: v for k, v in params.items() if k != 'crypto_vars'}
        data_width = struct_params.get('DATA_WIDTH', 32)
        
        # Generate parameter assignments for testbench
        clean_param_list = []
        trojaned_param_list = []
        for i, (k, v) in enumerate(struct_params.items()):
            if i == len(struct_params) - 1:  # Last parameter
                clean_param_list.append(f"        .{k}({v})")
                trojaned_param_list.append(f"        .{k}({v})")
            else:
                clean_param_list.append(f"        .{k}({v}),")
                trojaned_param_list.append(f"        .{k}({v}),")
        
        testbench = f"""// Testbench for {trojan_id} instance {instance_id:04d}
module tb_{trojan_id}_{instance_id:04d};
    
    // Parameters
{chr(10).join([f'    parameter {k} = {v};' for k, v in struct_params.items()])}
    
    // Signals
    reg clk, rst, enable;
    reg [DATA_WIDTH-1:0] data_in;
    wire [DATA_WIDTH-1:0] clean_data_out, trojaned_data_out;
    wire clean_valid, trojaned_valid;
    wire clean_ready, trojaned_ready;
    
    // Clock generation
    initial clk = 0;
    always #5 clk = ~clk;
    
    // DUT instances
    {clean_module} #(
{chr(10).join(clean_param_list)}
    ) clean_dut (
        .clk(clk), .rst(rst), .enable(enable),
        .data_in(data_in), .data_out(clean_data_out),
        .valid_out(clean_valid), .ready(clean_ready)
    );
    
    {trojaned_module} #(
{chr(10).join(trojaned_param_list)}
    ) trojaned_dut (
        .clk(clk), .rst(rst), .enable(enable),
        .data_in(data_in), .data_out(trojaned_data_out),
        .valid_out(trojaned_valid), .ready(trojaned_ready)
    );
    
    // Test sequence
    initial begin
        $dumpfile("{trojan_id}_{instance_id:04d}.vcd");
        $dumpvars(0, tb_{trojan_id}_{instance_id:04d});
        
        rst = 1; enable = 0; data_in = 0;
        #20 rst = 0;
        #10 enable = 1;
        
        repeat (100) begin
            data_in = $random;
            #10;
        end
        
        enable = 0;
        #50 $finish;
    end
    
    // Monitor differences
    always @(posedge clk) begin
        if (clean_valid && trojaned_valid) begin
            if (clean_data_out !== trojaned_data_out) begin
                $display("DIFFERENCE at time %t: Clean=%h, Trojaned=%h", 
                        $time, clean_data_out, trojaned_data_out);
            end
        end
    end
    
endmodule
"""
        return testbench
    
    def generate_batch(self, num_circuits: int = 10, trojans: List[str] = None, 
                      with_testbench: bool = False) -> None:
        """Generate a batch of circuit pairs"""
        if trojans is None:
            trojans = list(self.configs.keys())
        
        summary_data = []
        
        for trojan_id in trojans:
            # Create subdirectories for each trojan type in clean and trojan folders
            clean_trojan_dir = self.clean_dir / trojan_id
            trojan_trojan_dir = self.trojan_dir / trojan_id
            clean_trojan_dir.mkdir(exist_ok=True)
            trojan_trojan_dir.mkdir(exist_ok=True)
            
            print(f"\\nGenerating {num_circuits} instances for {trojan_id}...")
            
            for i in range(num_circuits):
                clean_code, trojaned_code, params = self.generate_circuit_pair(trojan_id, i)
                
                # Write clean version to clean directory
                clean_file = clean_trojan_dir / f"{trojan_id}_clean_{i:04d}.v"
                with open(clean_file, 'w') as f:
                    f.write(clean_code)
                
                # Write trojaned version to trojan directory
                trojaned_file = trojan_trojan_dir / f"{trojan_id}_trojaned_{i:04d}.v"
                with open(trojaned_file, 'w') as f:
                    f.write(trojaned_code)
                
                # Generate testbench if requested (put in testbench subdirectory)
                if with_testbench:
                    testbench_dir = self.output_dir / "testbench" / trojan_id
                    testbench_dir.mkdir(parents=True, exist_ok=True)
                    testbench_code = self.generate_testbench(trojan_id, params, i)
                    testbench_file = testbench_dir / f"tb_{trojan_id}_{i:04d}.v"
                    with open(testbench_file, 'w') as f:
                        f.write(testbench_code)
                
                # Record parameters with relative paths
                summary_data.append({
                    'trojan_id': trojan_id,
                    'instance_id': i,
                    'clean_file': f"clean/{trojan_id}/{trojan_id}_clean_{i:04d}.v",
                    'trojaned_file': f"trojan/{trojan_id}/{trojan_id}_trojaned_{i:04d}.v",
                    'parameters': params,
                    'description': self.configs[trojan_id]['description']
                })
                
                if (i + 1) % 10 == 0:
                    print(f"  Generated {i + 1}/{num_circuits} instances")
        
        # Write comprehensive summary
        summary_file = self.output_dir / "generation_summary.json"
        with open(summary_file, 'w') as f:
            json.dump(summary_data, f, indent=2)
        
        # Write parameter statistics
        stats_file = self.output_dir / "parameter_statistics.json"
        self.generate_statistics(summary_data, stats_file)
        
        print(f"\\n=== Generation Complete ===")
        print(f"Total circuit pairs: {len(summary_data)}")
        print(f"Total files generated: {len(summary_data) * 2}")
        print(f"Summary: {summary_file}")
        print(f"Statistics: {stats_file}")
    
    def generate_statistics(self, summary_data: List[Dict], stats_file: Path):
        """Generate parameter statistics"""
        stats = {}
        
        for trojan_id in self.configs.keys():
            trojan_data = [item for item in summary_data if item['trojan_id'] == trojan_id]
            if not trojan_data:
                continue
                
            stats[trojan_id] = {
                'count': len(trojan_data),
                'parameter_ranges': {},
                'crypto_var_ranges': {}
            }
            
            # Collect parameter statistics
            for param_name in self.configs[trojan_id]['params'].keys():
                values = [item['parameters'][param_name] for item in trojan_data]
                stats[trojan_id]['parameter_ranges'][param_name] = {
                    'min': min(values),
                    'max': max(values),
                    'unique_values': len(set(values)),
                    'distribution': dict(zip(*zip(*[(v, values.count(v)) for v in set(values)])))
                }
            
            # Collect crypto variable statistics  
            for var_name in self.configs[trojan_id]['crypto_vars'].keys():
                values = [item['parameters']['crypto_vars'][var_name] for item in trojan_data]
                if all(isinstance(v, int) for v in values):
                    stats[trojan_id]['crypto_var_ranges'][var_name] = {
                        'min': min(values),
                        'max': max(values),
                        'unique_values': len(set(values))
                    }
                else:
                    stats[trojan_id]['crypto_var_ranges'][var_name] = {
                        'type': 'mixed',
                        'unique_values': len(set(str(v) for v in values))
                    }
        
        with open(stats_file, 'w') as f:
            json.dump(stats, f, indent=2)


def main():
    parser = argparse.ArgumentParser(description="Generate Trojan-Host circuit combinations with randomized crypto parameters")
    parser.add_argument("--output-dir", default="../generated_circuits", 
                       help="Output directory for generated circuits")
    parser.add_argument("--num-circuits", type=int, default=10,
                       help="Number of circuit pairs to generate per trojan")
    parser.add_argument("--trojans", nargs="+", 
                       choices=['trojan0', 'trojan1', 'trojan2', 'trojan3', 'trojan4',
                               'trojan5', 'trojan6', 'trojan7', 'trojan8', 'trojan9'],
                       help="Specific trojans to generate (default: all)")
    parser.add_argument("--seed", type=int, help="Random seed for reproducible generation")
    parser.add_argument("--with-testbench", action="store_true", 
                       help="Generate testbenches for circuit pairs")
    
    args = parser.parse_args()
    
    if args.seed:
        random.seed(args.seed)
        print(f"Random seed set to: {args.seed}")
    
    generator = TrojanHostGenerator(args.output_dir)
    generator.generate_batch(args.num_circuits, args.trojans, args.with_testbench)


if __name__ == "__main__":
    main()