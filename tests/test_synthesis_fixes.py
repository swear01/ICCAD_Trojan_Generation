"""
Test synthesis functionality after RTL and tech mapping fixes.
Validates that previously failing circuits now synthesize correctly.
"""
import pytest
import os
import subprocess
import tempfile
import shutil
from pathlib import Path

# Test configurations for successfully fixed circuits
SUCCESSFUL_SYNTHESIS_CASES = [
    # UART hosts (fixed multiple driver issues)
    {
        "trojan": "trojan0",
        "host": "trojan0_uart_host", 
        "description": "UART host with fixed TX/RX bit counter separation"
    },
    {
        "trojan": "trojan1", 
        "host": "trojan1_uart_host",
        "description": "UART host with fixed multiple driver conflicts"
    },
    
    # DSP hosts (fixed port array syntax)
    {
        "trojan": "trojan0",
        "host": "trojan0_dsp_host",
        "description": "DSP host with fixed input port array syntax" 
    },
    
    # Network hosts (fixed memory array size)
    {
        "trojan": "trojan0",
        "host": "trojan0_network_host",
        "description": "Network host with reduced memory array size"
    },
    
    # Other working host types
    {
        "trojan": "trojan0",
        "host": "trojan0_memory_host",
        "description": "Memory host (should work consistently)"
    },
    {
        "trojan": "trojan1",
        "host": "trojan1_spi_host", 
        "description": "SPI host (should work consistently)"
    },
    {
        "trojan": "trojan0",
        "host": "trojan0_timer_host",
        "description": "Timer host (should work consistently)"
    }
]


@pytest.fixture
def temp_synthesis_dir():
    """Create temporary directory for synthesis testing."""
    temp_dir = tempfile.mkdtemp(prefix="synthesis_test_")
    yield temp_dir
    shutil.rmtree(temp_dir, ignore_errors=True)


@pytest.fixture
def yosys_script_template():
    """Template for Yosys synthesis script."""
    return """read_liberty -lib {lib_path}
read_verilog -sv {verilog_file}
hierarchy -check -top {top_module}
proc; opt
flatten
techmap; opt
techmap -map {map_file}
dfflibmap -liberty {lib_path}
insbuf -buf buf A Y
check
opt_clean -purge
abc -liberty {lib_path} -fast
opt_merge; opt_clean; clean
check -assert
stat -liberty {lib_path}
write_verilog -noattr -noexpr -nodec -defparam {output_file}
"""


def generate_test_circuit(trojan_name, host_name, output_dir, seed=12345):
    """Generate a single test circuit for synthesis testing."""
    from src.trojan_generator import main as trojan_main
    import sys
    
    # Temporarily modify sys.argv for trojan generator
    old_argv = sys.argv[:]
    sys.argv = [
        'trojan_generator.py',
        '--output-dir', str(output_dir), 
        '--num-circuits', '1',
        '--trojans', trojan_name,
        '--seed', str(seed)
    ]
    
    try:
        trojan_main()
        
        # Find the generated trojaned circuit
        circuit_path = Path(output_dir) / "trojan" / trojan_name / host_name
        if circuit_path.exists():
            files = list(circuit_path.glob(f"{trojan_name}_{host_name}_trojaned_*.v"))
            return files[0] if files else None
        return None
        
    finally:
        sys.argv = old_argv


def run_yosys_synthesis(verilog_file, temp_dir):
    """Run Yosys synthesis on a Verilog file."""
    project_root = Path(__file__).parent.parent
    lib_path = project_root / "cell.lib"
    map_path = project_root / "map.v"
    
    # Extract module name from file
    module_name = Path(verilog_file).stem
    
    # Create synthesis script
    script_content = f"""read_liberty -lib {lib_path}
read_verilog -sv {verilog_file}
hierarchy -check -top {module_name}
proc; opt
flatten
techmap; opt
techmap -map {map_path}
dfflibmap -liberty {lib_path}
insbuf -buf buf A Y  
check
opt_clean -purge
abc -liberty {lib_path} -fast
opt_merge; opt_clean; clean
check -assert
stat -liberty {lib_path}
"""
    
    script_path = Path(temp_dir) / "synthesis.ys"
    with open(script_path, 'w') as f:
        f.write(script_content)
    
    # Run Yosys
    try:
        result = subprocess.run(
            ["yosys", str(script_path)],
            cwd=project_root,
            capture_output=True,
            text=True,
            timeout=120
        )
        
        return {
            'success': result.returncode == 0,
            'stdout': result.stdout,
            'stderr': result.stderr,
            'returncode': result.returncode
        }
        
    except subprocess.TimeoutExpired:
        return {
            'success': False,
            'stdout': '',
            'stderr': 'Synthesis timeout after 120 seconds',
            'returncode': -1
        }
    except Exception as e:
        return {
            'success': False,
            'stdout': '',
            'stderr': f'Synthesis error: {str(e)}',
            'returncode': -1
        }


@pytest.mark.synthesis
@pytest.mark.fixes
@pytest.mark.parametrize("test_case", SUCCESSFUL_SYNTHESIS_CASES, 
                        ids=lambda x: f"{x['trojan']}_{x['host']}")
def test_synthesis_success(test_case, temp_synthesis_dir):
    """Test that fixed circuits synthesize successfully."""
    trojan = test_case["trojan"]
    host = test_case["host"] 
    description = test_case["description"]
    
    # Generate test circuit
    circuit_file = generate_test_circuit(trojan, host, temp_synthesis_dir)
    
    assert circuit_file is not None, f"Failed to generate {trojan}+{host} circuit"
    assert Path(circuit_file).exists(), f"Generated circuit file does not exist: {circuit_file}"
    
    # Run synthesis
    result = run_yosys_synthesis(circuit_file, temp_synthesis_dir)
    
    # Check synthesis success
    assert result['success'], (
        f"Synthesis failed for {description}\n"
        f"Return code: {result['returncode']}\n"
        f"STDOUT: {result['stdout'][-1000:]}\n"  # Last 1000 chars
        f"STDERR: {result['stderr'][-1000:]}"
    )
    
    # Verify no critical errors in output
    critical_errors = [
        "multiple conflicting drivers",
        "Async reset.*yields non-constant value", 
        "syntax error",
        "Found.*problems in 'check -assert'"
    ]
    
    combined_output = result['stdout'] + result['stderr']
    for error_pattern in critical_errors:
        assert not any(error_pattern.lower() in line.lower() 
                      for line in combined_output.split('\n')), (
            f"Critical error found in synthesis output for {description}: "
            f"Pattern '{error_pattern}' detected"
        )


@pytest.mark.synthesis
@pytest.mark.fixes
def test_multiple_driver_fix():
    """Specific test for multiple driver fix in UART hosts."""
    with tempfile.TemporaryDirectory() as temp_dir:
        # Generate UART circuit
        circuit_file = generate_test_circuit("trojan0", "trojan0_uart_host", temp_dir)
        assert circuit_file is not None
        
        # Run synthesis and check for multiple driver errors
        result = run_yosys_synthesis(circuit_file, temp_dir)
        
        # Should not contain multiple conflicting drivers error
        output = result['stdout'] + result['stderr']
        assert "multiple conflicting drivers" not in output.lower(), (
            "Multiple driver error still present after fix"
        )
        
        assert result['success'], f"UART synthesis should succeed after multiple driver fix"


@pytest.mark.synthesis
@pytest.mark.fixes  
def test_dsp_port_array_fix():
    """Specific test for DSP port array syntax fix.""" 
    with tempfile.TemporaryDirectory() as temp_dir:
        # Generate DSP circuit
        circuit_file = generate_test_circuit("trojan0", "trojan0_dsp_host", temp_dir)
        assert circuit_file is not None
        
        # Run synthesis and check for syntax errors
        result = run_yosys_synthesis(circuit_file, temp_dir)
        
        # Should not contain syntax errors
        output = result['stdout'] + result['stderr']
        assert "syntax error, unexpected '['" not in output, (
            "Port array syntax error still present after fix"
        )
        
        assert result['success'], f"DSP synthesis should succeed after port array fix"


@pytest.mark.synthesis
@pytest.mark.fixes
def test_network_memory_size_fix():
    """Specific test for network host memory array size fix."""
    with tempfile.TemporaryDirectory() as temp_dir:
        # Generate network circuit  
        circuit_file = generate_test_circuit("trojan0", "trojan0_network_host", temp_dir)
        assert circuit_file is not None
        
        # Run synthesis and check for memory size errors
        result = run_yosys_synthesis(circuit_file, temp_dir)
        
        # Should not contain async reset non-constant value errors
        output = result['stdout'] + result['stderr']
        assert "yields non-constant value" not in output, (
            "Memory array size error still present after fix"
        )
        
        assert result['success'], f"Network synthesis should succeed after memory size fix"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])