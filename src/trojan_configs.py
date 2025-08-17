#!/usr/bin/env python3
"""
Trojan Configuration File
Defines parameter ranges and cryptographic variables for each trojan type.
"""

# Trojan configuration dictionary
TROJAN_CONFIGS = {
    'trojan0': {
        'host_file': 'trojan0_datapath_host.v',
        'description': 'Datapath host with LFSR-based key generation',
        'params': {
            'DATA_WIDTH': {
                'type': 'choice',
                'values': [8, 16, 32, 64]
            },
            'ADDR_WIDTH': {
                'type': 'choice', 
                'values': [8, 16, 24, 32]
            },
            'KEY_WIDTH': {
                'type': 'choice',
                'values': [32, 64, 128, 256]
            },
            'LOAD_WIDTH': {
                'type': 'choice',
                'values': [16, 32, 64, 128]
            }
        },
        'crypto_vars': {
            'key_init_value': {
                'type': 'random_hex',
                'bits': 'KEY_WIDTH',  # Use parameter value
                'description': 'Initial value for LFSR key generator'
            },
            'lfsr_feedback_polynomial': {
                'type': 'random_hex', 
                'bits': 32,
                'description': 'LFSR feedback polynomial for key generation'
            },
            'load_xor_mask': {
                'type': 'random_hex',
                'bits': 'LOAD_WIDTH',
                'description': 'XOR mask applied to load output'
            }
        }
    },
    
    'trojan1': {
        'host_file': 'trojan1_fsm_router_host.v',
        'description': 'FSM router with trigger-based payload',
        'params': {
            'DATA_WIDTH': {
                'type': 'choice',
                'values': [16, 32, 48, 64]
            },
            'ADDR_WIDTH': {
                'type': 'choice',
                'values': [4, 8, 12, 16]
            },
            'NUM_PORTS': {
                'type': 'choice',
                'values': [2, 4, 6, 8]
            }
        },
        'crypto_vars': {
            'trigger_threshold': {
                'type': 'random_int',
                'min': 4,
                'max': 32,
                'description': 'Counter threshold for trigger activation'
            },
            'payload_pattern': {
                'type': 'random_hex',
                'bits': 8,
                'description': 'Payload pattern injected when triggered'
            }
        }
    },
    
    'trojan2': {
        'host_file': 'trojan2_pipeline_host.v',
        'description': '3-stage pipeline with sequence-triggered reset',
        'params': {
            'DATA_WIDTH': {
                'type': 'choice',
                'values': [16, 24, 32, 48, 64]
            },
            'PIPELINE_DEPTH': {
                'type': 'choice',
                'values': [3, 4, 5, 6, 7]
            }
        },
        'crypto_vars': {
            'trigger_sequence_1': {
                'type': 'random_hex',
                'bits': 8,
                'fixed_value': 0xAA,  # First part of sequence from original
                'description': 'First byte of trigger sequence'
            },
            'trigger_sequence_2': {
                'type': 'random_hex', 
                'bits': 8,
                'fixed_value': 0x55,  # Second part of sequence from original
                'description': 'Second byte of trigger sequence'
            },
            'reset_delay_cycles': {
                'type': 'random_int',
                'min': 1,
                'max': 10,
                'description': 'Delay cycles before force reset'
            }
        }
    },
    
    'trojan3': {
        'host_file': 'trojan3_crossbar_host.v',
        'description': 'Crossbar switch with data manipulation',
        'params': {
            'DATA_WIDTH': {
                'type': 'choice',
                'values': [8, 16, 24, 32]
            },
            'NUM_INPUTS': {
                'type': 'choice',
                'values': [2, 3, 4, 6, 8]
            },
            'NUM_OUTPUTS': {
                'type': 'choice', 
                'values': [2, 3, 4, 6, 8]
            }
        },
        'crypto_vars': {
            'data_increment': {
                'type': 'random_int',
                'min': 1,
                'max': 16,
                'description': 'Value added to data when triggered'
            },
            'trigger_counter_threshold': {
                'type': 'random_int',
                'min': 100,
                'max': 500,
                'description': 'Counter cycles before trigger'
            }
        }
    },
    
    'trojan4': {
        'host_file': 'trojan4_mac_host.v',
        'description': 'MAC unit with key-based data leakage',
        'params': {
            'DATA_WIDTH': {
                'type': 'choice',
                'values': [16, 24, 32, 40, 48]
            },
            'COEFF_WIDTH': {
                'type': 'choice',
                'values': [8, 12, 16, 20, 24]
            },
            'ACCUM_WIDTH': {
                'type': 'choice',
                'values': [32, 48, 64, 80]
            },
            'KEY_WIDTH': {
                'type': 'choice',
                'values': [32, 64, 96, 128]
            },
            'LEAK_WIDTH': {
                'type': 'choice',
                'values': [16, 32, 64, 96, 128]
            }
        },
        'crypto_vars': {
            'secret_key': {
                'type': 'random_hex',
                'bits': 'KEY_WIDTH',
                'description': 'Secret key for encryption/leakage'
            },
            'lfsr_polynomial': {
                'type': 'choice',
                'values': [0x8005, 0x1021, 0x8404, 0xA001, 0xAC9A],
                'description': 'LFSR polynomial for key generation'
            },
            'leak_mask': {
                'type': 'random_hex',
                'bits': 'LEAK_WIDTH',
                'description': 'Mask applied to leaked data'
            }
        }
    },
    
    'trojan5': {
        'host_file': 'trojan5_lfsr_host.v',
        'description': 'LFSR/CRC with program counter manipulation',
        'params': {
            'DATA_WIDTH': {
                'type': 'choice',
                'values': [16, 24, 32, 48, 64]
            },
            'LFSR_WIDTH': {
                'type': 'choice',
                'values': [8, 12, 16, 20, 24]
            },
            'CRC_POLY': {
                'type': 'choice',
                'values': [0x8005, 0x1021, 0x8404, 0xA001]
            }
        },
        'crypto_vars': {
            'instruction_patterns': {
                'type': 'random_list',
                'count': 9,  # From original trojan5 logic
                'element_type': 'hex',
                'bits': 4,
                'values': [0b1000, 0b1001, 0b1010, 0b1011, 0b0100, 0b0101, 0b0110, 0b0111, 0b1100],
                'description': 'Instruction patterns that trigger PC offset'
            },
            'pc_offset': {
                'type': 'random_int',
                'min': 1,
                'max': 8,
                'description': 'Offset added to program counter'
            }
        }
    },
    
    'trojan6': {
        'host_file': 'trojan6_barrel_shifter_host.v', 
        'description': 'Barrel shifter with state-based payload injection',
        'params': {
            'DATA_WIDTH': {
                'type': 'choice',
                'values': [16, 24, 32, 48, 64]
            },
            'SHIFT_BITS': {
                'type': 'choice',
                'values': [4, 5, 6]
            }
        },
        'crypto_vars': {
            'trigger_state_1': {
                'type': 'random_hex',
                'bits': 32,
                'description': 'First trigger state pattern'
            },
            'trigger_state_2': {
                'type': 'random_hex',
                'bits': 32, 
                'description': 'Second trigger state pattern'
            },
            'trigger_state_3': {
                'type': 'random_hex',
                'bits': 32,
                'description': 'Third trigger state pattern'
            },
            'payload_bits': {
                'type': 'random_hex',
                'bits': 2,
                'description': 'Payload bits injected in LSB'
            }
        }
    },
    
    'trojan7': {
        'host_file': 'trojan7_axi_host.v',
        'description': 'AXI-lite with wishbone address/data trigger',
        'params': {
            'ADDR_WIDTH': {
                'type': 'choice',
                'values': [16, 20, 24, 28, 32]
            },
            'DATA_WIDTH': {
                'type': 'choice',
                'values': [16, 24, 32, 48, 64]
            },
            'NUM_SLAVES': {
                'type': 'choice',
                'values': [4, 8, 12, 16]
            }
        },
        'crypto_vars': {
            'wb_data_trigger': {
                'type': 'random_hex',
                'bits': 32,
                'description': 'Wishbone data trigger pattern (wb_data_i)'
            },
            's0_data_trigger': {
                'type': 'random_hex',
                'bits': 32,
                'description': 'Slave 0 data trigger pattern (s0_data_i)'
            },
            'xor_mask': {
                'type': 'random_hex',
                'bits': 4,
                'description': 'XOR mask applied to slave select when triggered'
            }
        }
    },
    
    'trojan8': {
        'host_file': 'trojan8_matrix_mult_host.v',
        'description': 'Matrix multiplier with computation path injection',
        'params': {
            'MATRIX_SIZE': {
                'type': 'choice',
                'values': [2, 3, 4, 5, 6]
            },
            'DATA_WIDTH': {
                'type': 'choice',
                'values': [4, 6, 8, 10, 12]
            },
            'RESULT_WIDTH': {
                'type': 'choice',
                'values': [8, 12, 16, 20, 24]
            }
        },
        'crypto_vars': {
            'computation_masks': {
                'type': 'random_list',
                'count': 7,  # Number of intermediate terms
                'element_type': 'hex',
                'bits': 16,
                'description': 'Masks for computation path modification'
            },
            'selection_weights': {
                'type': 'random_list',
                'count': 8,  # Number of selection cases
                'element_type': 'int',
                'min': 1,
                'max': 4,
                'description': 'Weights for selection logic'
            }
        }
    },
    
    'trojan9': {
        'host_file': 'trojan9_cordic_host.v',
        'description': 'CORDIC processor with mode-based computation alteration',
        'params': {
            'DATA_WIDTH': {
                'type': 'choice',
                'values': [12, 16, 20, 24]
            },
            'ANGLE_WIDTH': {
                'type': 'choice',
                'values': [12, 16, 18, 20]
            },
            'ITERATIONS': {
                'type': 'choice',
                'values': [6, 8, 10, 12]
            }
        },
        'crypto_vars': {
            'mode_patterns': {
                'type': 'random_list',
                'count': 4,  # 4 different modes
                'element_type': 'hex',
                'bits': 2,
                'description': 'Mode patterns that affect computation'
            },
            'computation_bias': {
                'type': 'random_hex',
                'bits': 16,
                'description': 'Bias value added to computation results'
            },
            'angle_offset': {
                'type': 'random_hex',
                'bits': 'ANGLE_WIDTH',
                'description': 'Offset added to angle computations'
            }
        }
    }
}

# Helper functions for parameter generation
def get_random_hex(bits: int) -> int:
    """Generate random hex value with specified bit width"""
    import random
    return random.randint(0, (1 << bits) - 1)

def get_random_int(min_val: int, max_val: int) -> int:
    """Generate random integer in range"""
    import random
    return random.randint(min_val, max_val)

def get_choice(values: list):
    """Get random choice from list"""
    import random
    return random.choice(values)

def get_random_list(count: int, element_type: str, **kwargs):
    """Generate list of random values"""
    import random
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