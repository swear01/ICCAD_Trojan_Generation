#!/usr/bin/env python3
"""
TOML Configuration Loader
Replaces the old Python-based trojan_configs.py with TOML-based configuration files.
"""

import ast
import operator as op
import random
import tomllib  # Python 3.11+
from pathlib import Path
from typing import Dict, List, Any


class ConfigLoader:
    def __init__(self, config_dir: str = "configs"):
        self.config_dir = Path(config_dir)
        self.configs = {}
        self.load_all_configs()
    
    def load_all_configs(self):
        """Load all TOML configuration files"""
        if not self.config_dir.exists():
            raise FileNotFoundError(f"Config directory not found: {self.config_dir}")
        
        # Load host configs
        for config_file in self.config_dir.glob("trojan*_hosts.toml"):
            host_config_id = config_file.stem
            with open(config_file, 'rb') as f:
                config_data = tomllib.load(f)
                self.configs[host_config_id] = config_data
    
    def get_config(self, trojan_id: str) -> Dict[str, Any]:
        """Get configuration for a specific trojan"""
        if trojan_id not in self.configs:
            raise KeyError(f"Configuration not found for {trojan_id}")
        return self.configs[trojan_id]
    
    def get_all_trojan_ids(self) -> List[str]:
        """Get list of all available trojan IDs"""
        return list(self.configs.keys())
    
    def generate_random_params(self, trojan_id: str) -> Dict[str, Any]:
        """Generate random parameters for a specific trojan.
        Uses unified host configuration approach only."""
        
        # Use host parameters for ALL trojans (unified approach)
        host_files = self.get_host_files(trojan_id)
        if host_files:
            # Use the first host file for parameter generation
            return self.generate_random_host_params(trojan_id, host_files[0])
        else:
            print(f"Warning: No host configuration found for {trojan_id}")
            return {}
    
    def generate_random_host_params(self, trojan_id: str, host_name: str) -> Dict[str, Any]:
        """Generate random parameters for a specific host circuit.
        All parameters (structural + crypto) are in the 'params' section only."""
        host_config = self.get_host_config(trojan_id, host_name)
        params = {}
        
        if 'params' not in host_config:
            return params
        
        # Two-pass approach: first generate parameters that others might depend on
        first_pass_params = {}  # Parameters that don't depend on others
        second_pass_params = {}  # Parameters that might depend on first pass
        
        # Categorize parameters by dependency
        for param_name, param_config in host_config['params'].items():
            if param_config['type'] in ['choice', 'range', 'random_int']:
                # These typically don't depend on other parameters
                first_pass_params[param_name] = param_config
            elif param_config['type'] == 'random_hex':
                # These might depend on other parameters (via bits expression)
                second_pass_params[param_name] = param_config
        
        # First pass: generate independent parameters
        for param_name, param_config in first_pass_params.items():
            if param_config['type'] == 'choice':
                params[param_name] = random.choice(param_config['values'])
            elif param_config['type'] == 'range':
                min_val = param_config['min']
                max_val = param_config['max']
                params[param_name] = random.randint(min_val, max_val)
            elif param_config['type'] == 'random_int':
                min_val = param_config['min']
                max_val = param_config['max']
                params[param_name] = random.randint(min_val, max_val)
        
        # Second pass: generate dependent parameters using first pass results
        for param_name, param_config in second_pass_params.items():
            if param_config['type'] == 'random_hex':
                bits_expr = param_config.get('bits', 32)
                bits = self._eval_bits(bits_expr, params)
                params[param_name] = self.get_random_hex(bits)
        
        return params
    
    def get_host_files(self, trojan_id: str) -> List[str]:
        """Get list of host file names for a trojan"""
        host_config_id = f"{trojan_id}_hosts"
        if host_config_id in self.configs:
            host_config = self.configs[host_config_id]
            return host_config['metadata']['host_files']
        return []
    
    def get_host_config(self, trojan_id: str, host_name: str) -> Dict[str, Any]:
        """Get configuration for a specific host circuit"""
        host_config_id = f"{trojan_id}_hosts"
        if host_config_id not in self.configs:
            raise KeyError(f"Host configuration not found for {trojan_id}")
        
        host_config = self.configs[host_config_id]
        if host_name not in host_config['hosts']:
            raise KeyError(f"Host {host_name} not found in {trojan_id} configuration")
        
        return host_config['hosts'][host_name]
    
    def get_host_file(self, trojan_id: str) -> str:
        """Get first host file name for a trojan (for backward compatibility)"""
        host_files = self.get_host_files(trojan_id)
        return f"{host_files[0]}.v" if host_files else ''
    
    def get_description(self, trojan_id: str) -> str:
        """Get description for a trojan"""
        # Since we use unified approach, get description from host config
        host_config_id = f"{trojan_id}_hosts"
        if host_config_id in self.configs:
            host_config = self.configs[host_config_id]
            return host_config['metadata']['description']
        else:
            # Fallback to old approach if host config doesn't exist
            try:
                config = self.get_config(trojan_id)
                return config['metadata']['description']
            except KeyError:
                return f"Description for {trojan_id}"
    
    def _eval_bits(self, expr, variables):
        """
        Safely evaluate bit width expressions that may depend on other parameters.
        Supports basic arithmetic: +, -, *, //, parentheses
        """
        if isinstance(expr, int):
            return expr
        if not isinstance(expr, str):
            return 32  # Default fallback
        
        # Supported operators
        ops = {
            ast.Add: op.add,
            ast.Sub: op.sub, 
            ast.Mult: op.mul,
            ast.FloorDiv: op.floordiv,
            ast.Div: op.floordiv  # Treat division as floor division for safety
        }
        
        def _eval_node(node):
            if isinstance(node, ast.Expression):
                return _eval_node(node.body)
            elif isinstance(node, ast.Num):  # For older Python versions
                return int(node.n)
            elif isinstance(node, ast.Constant):  # For newer Python versions
                return int(node.value)
            elif isinstance(node, ast.Name):
                if node.id in variables:
                    return int(variables[node.id])
                else:
                    raise ValueError(f"Variable '{node.id}' not found in parameters")
            elif isinstance(node, ast.BinOp) and type(node.op) in ops:
                left = _eval_node(node.left)
                right = _eval_node(node.right)
                return ops[type(node.op)](left, right)
            elif isinstance(node, ast.UnaryOp):
                if isinstance(node.op, ast.UAdd):
                    return +_eval_node(node.operand)
                elif isinstance(node.op, ast.USub):
                    return -_eval_node(node.operand)
                else:
                    raise ValueError("Unsupported unary operator")
            else:
                raise ValueError(f"Unsupported expression node: {type(node)}")
        
        try:
            # Parse and evaluate the expression safely
            parsed = ast.parse(expr, mode='eval')
            result = _eval_node(parsed)
            return max(1, int(result))  # Ensure positive bit width
        except Exception as e:
            print(f"Warning: Could not evaluate bit width expression '{expr}': {e}")
            print(f"Available variables: {list(variables.keys())}")
            return 32  # Fallback to 32 bits
    
    @staticmethod
    def get_random_hex(bits: int) -> int:
        """Generate random hex value with specified bit width"""
        return random.randint(0, (1 << bits) - 1)


# Helper functions for backward compatibility
def get_random_hex(bits: int) -> int:
    """Generate random hex value with specified bit width"""
    return random.randint(0, (1 << bits) - 1)

def get_random_int(min_val: int, max_val: int) -> int:
    """Generate random integer in range"""
    return random.randint(min_val, max_val)

def get_choice(values: list):
    """Get random choice from list"""
    return random.choice(values)

def get_random_list(count: int, element_type: str, **kwargs):
    """Generate list of random values"""
    result = []
    for _ in range(count):
        if element_type == 'hex':
            bits = kwargs.get('bits', 8)
            if 'values' in kwargs:
                result.append(random.choice(kwargs['values']))
            else:
                result.append(get_random_hex(bits))
        elif element_type == 'int':
            min_val = kwargs.get('min', 0)
            max_val = kwargs.get('max', 100)
            result.append(get_random_int(min_val, max_val))
    return result


# Create a global instance for backward compatibility
_config_loader = None

def get_config_loader():
    """Get global config loader instance"""
    global _config_loader
    if _config_loader is None:
        _config_loader = ConfigLoader()
    return _config_loader

def get_trojan_configs():
    """Get all trojan configurations in old format for backward compatibility"""
    loader = get_config_loader()
    old_format_configs = {}
    
    # Use host configurations instead of core configurations
    for trojan_id in loader.get_all_trojan_ids():
        if trojan_id.endswith('_hosts'):
            continue  # Skip host config IDs
        
        try:
            # Try to get host configuration first
            host_files = loader.get_host_files(trojan_id)
            if host_files:
                host_config = loader.get_host_config(trojan_id, host_files[0])
                old_format_configs[trojan_id] = {
                    'host_file': host_config.get('file', ''),
                    'description': host_config.get('description', f'Configuration for {trojan_id}'),
                    'params': host_config.get('params', {})
                }
            else:
                # Fallback to core config if host config doesn't exist
                config = loader.get_config(trojan_id)
                old_format_configs[trojan_id] = {
                    'host_file': config['metadata'].get('host_file', ''),
                    'description': config['metadata']['description'],
                    'params': config.get('params', {})
                }
        except KeyError:
            continue
    
    return old_format_configs

# For backward compatibility
TROJAN_CONFIGS = get_trojan_configs()