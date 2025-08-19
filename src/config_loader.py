#!/usr/bin/env python3
"""
TOML Configuration Loader
Replaces the old Python-based trojan_configs.py with TOML-based configuration files.
"""

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
        
        # Load trojan core configs
        for config_file in self.config_dir.glob("trojan[0-9].toml"):
            trojan_id = config_file.stem
            with open(config_file, 'rb') as f:
                config_data = tomllib.load(f)
                self.configs[trojan_id] = config_data
        
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
        """Generate random parameters for a specific trojan core"""
        config = self.get_config(trojan_id)
        params = {}
        
        # Generate structural parameters first
        if 'params' in config:
            for param_name, param_config in config['params'].items():
                if param_config['type'] == 'choice':
                    params[param_name] = random.choice(param_config['values'])
                elif param_config['type'] == 'range':
                    min_val = param_config['min']
                    max_val = param_config['max']
                    params[param_name] = random.randint(min_val, max_val)
        
        # Generate cryptographic variables (fully randomized)
        crypto_vars = {}
        if 'crypto_vars' in config:
            for var_name, var_config in config['crypto_vars'].items():
                if var_config['type'] == 'random_hex':
                    # Handle parameter-dependent bit widths
                    bits = var_config['bits']
                    if isinstance(bits, str) and bits in params:
                        bits = params[bits]
                    elif isinstance(bits, str):
                        bits = 32  # Default fallback
                    
                    crypto_vars[var_name] = self.get_random_hex(bits)
                        
                elif var_config['type'] == 'random_int':
                    min_val = var_config['min']
                    max_val = var_config['max']
                    crypto_vars[var_name] = random.randint(min_val, max_val)
                    
                elif var_config['type'] == 'choice':
                    crypto_vars[var_name] = random.choice(var_config['values'])
        
        params['crypto_vars'] = crypto_vars
        return params
    
    def generate_random_host_params(self, trojan_id: str, host_name: str) -> Dict[str, Any]:
        """Generate random parameters for a specific host circuit"""
        host_config = self.get_host_config(trojan_id, host_name)
        params = {}
        
        # Generate structural parameters
        if 'params' in host_config:
            for param_name, param_config in host_config['params'].items():
                if param_config['type'] == 'choice':
                    params[param_name] = random.choice(param_config['values'])
                elif param_config['type'] == 'range':
                    min_val = param_config['min']
                    max_val = param_config['max']
                    params[param_name] = random.randint(min_val, max_val)
        
        # Generate crypto variables for host
        crypto_vars = {}
        if 'crypto_vars' in host_config:
            for var_name, var_config in host_config['crypto_vars'].items():
                if var_config['type'] == 'random_hex':
                    bits = var_config['bits']
                    crypto_vars[var_name] = self.get_random_hex(bits)
                elif var_config['type'] == 'random_int':
                    min_val = var_config['min']
                    max_val = var_config['max']
                    crypto_vars[var_name] = random.randint(min_val, max_val)
                elif var_config['type'] == 'choice':
                    crypto_vars[var_name] = random.choice(var_config['values'])
        
        params['crypto_vars'] = crypto_vars
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
        config = self.get_config(trojan_id)
        return config['metadata']['description']
    
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
    
    for trojan_id in loader.get_all_trojan_ids():
        config = loader.get_config(trojan_id)
        old_format_configs[trojan_id] = {
            'host_file': config['metadata'].get('host_file', ''),  # Handle missing host_file
            'description': config['metadata']['description'],
            'params': config.get('params', {}),
            'crypto_vars': config.get('crypto_vars', {})
        }
    
    return old_format_configs

# For backward compatibility
TROJAN_CONFIGS = get_trojan_configs()