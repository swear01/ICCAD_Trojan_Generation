#!/usr/bin/env python3
"""
Comprehensive RTL Compilation Tests using pytest
Tests all RTL files in generated_circuits directory for compilation errors
"""

import pytest
import subprocess
import glob
import re
from pathlib import Path
from datetime import datetime


class TestRTLCompilation:
    """Test class for RTL compilation verification"""
    
    def extract_trojan_number(self, file_path):
        """Extract trojan number from file path"""
        match = re.search(r'trojan(\d+)', file_path)
        return match.group(1) if match else None
    
    def categorize_error(self, error_message):
        """Categorize error types for better analysis"""
        error_lower = error_message.lower()
        
        if "syntax" in error_lower or "parse" in error_lower:
            return "Syntax Error"
        elif "undefined" in error_lower or "not declared" in error_lower:
            return "Undefined Signal/Module"
        elif "port" in error_lower and ("mismatch" in error_lower or "connection" in error_lower):
            return "Port Connection Error"
        elif "width" in error_lower or "bit" in error_lower:
            return "Width Mismatch"
        elif "module" in error_lower and "not found" in error_lower:
            return "Missing Module"
        elif "duplicate" in error_lower:
            return "Duplicate Declaration"
        elif "assign" in error_lower:
            return "Assignment Error"
        elif "clock" in error_lower or "clk" in error_lower:
            return "Clock Domain Error"
        elif "reset" in error_lower or "rst" in error_lower:
            return "Reset Logic Error"
        else:
            return "Other Error"
    
    def test_single_rtl_file(self, rtl_file_path, trojan_core_dir):
        """Test a single RTL file with Verilator - helper method"""
        rtl_file = Path(rtl_file_path)
        trojan_num = self.extract_trojan_number(str(rtl_file))
        
        if trojan_num is None:
            pytest.fail(f"Could not extract trojan number from path: {rtl_file_path}")
        
        # Determine corresponding trojan core file
        if "clean" in str(rtl_file):
            trojan_core_file = trojan_core_dir / f"clean{trojan_num}.v"
        else:
            trojan_core_file = trojan_core_dir / f"trojan{trojan_num}.v"
        
        if not trojan_core_file.exists():
            pytest.fail(f"Trojan core file not found: {trojan_core_file}")
        
        # Extract top module name from file
        with open(rtl_file, 'r') as f:
            content = f.read()
            import re
            match = re.search(r'module\s+(\w+)\s*(?:#|\()', content)
            if match:
                top_module = match.group(1)
            else:
                pytest.fail(f"Could not find top module in {rtl_file}")
        
        # Run Verilator - generated files already include trojan core
        # Allow common warnings but fail on actual errors
        cmd = ["verilator", "--lint-only", f"--top-module", top_module, 
               "-Wno-WIDTHEXPAND", "-Wno-WIDTHTRUNC", "-Wno-MULTIDRIVEN", 
               "-Wno-UNUSED", "-Wno-UNDRIVEN", "-Wno-SELRANGE", 
               "-Wno-WIDTH", "-Wno-REDEFMACRO", "-Wno-CASEINCOMPLETE", 
               "-Wno-BLKLOOPINIT", "-Wno-SIDEEFFECT", str(rtl_file)]
        
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=30,
                cwd=rtl_file.parent.parent.parent.parent
            )
            
            # Check for actual errors (not just warnings)
            stderr_lines = result.stderr.strip().split('\n') if result.stderr.strip() else []
            stdout_lines = result.stdout.strip().split('\n') if result.stdout.strip() else []
            
            # Filter for actual errors
            error_lines = []
            for line in stderr_lines + stdout_lines:
                if line.strip() and ('Error:' in line or 'error:' in line or 'ERROR:' in line):
                    error_lines.append(line.strip())
            
            # If return code is non-zero or we found error lines, it's a failure
            if result.returncode != 0 or error_lines:
                error_output = '\n'.join(error_lines) if error_lines else result.stderr
                error_category = self.categorize_error(error_output)
                pytest.fail(f"Verilator compilation failed ({error_category}): {error_output}")
                
        except subprocess.TimeoutExpired:
            pytest.fail("Verilator timeout (>30s)")
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Verilator process error: {e}")
    
    @pytest.fixture
    def clean_rtl_files(self, generated_circuits_dir):
        """Fixture to get all clean RTL files"""
        clean_pattern = str(generated_circuits_dir / "clean" / "trojan*" / "*_host" / "*.v")
        return sorted(glob.glob(clean_pattern))
    
    @pytest.fixture
    def trojan_rtl_files(self, generated_circuits_dir):
        """Fixture to get all trojan RTL files"""
        trojan_pattern = str(generated_circuits_dir / "trojan" / "trojan*" / "*_host" / "*.v")
        return sorted(glob.glob(trojan_pattern))
    
    @pytest.mark.verilator
    @pytest.mark.clean
    def test_clean_rtl_files(self, rtl_file, trojan_core_dir):
        """Test all clean RTL files for compilation"""
        self.test_single_rtl_file(rtl_file, trojan_core_dir)
    
    @pytest.mark.verilator
    @pytest.mark.trojan
    def test_trojan_rtl_files(self, rtl_file, trojan_core_dir):
        """Test all trojan RTL files for compilation"""
        self.test_single_rtl_file(rtl_file, trojan_core_dir)


def pytest_generate_tests(metafunc):
    """Generate test parameters dynamically"""
    if "rtl_file" in metafunc.fixturenames:
        base_dir = Path("/home/swear/ICCAD_Trojan_Generation")
        generated_circuits_dir = base_dir / "generated_circuits"
        
        if "clean" in metafunc.function.__name__:
            # Generate clean file tests
            clean_pattern = str(generated_circuits_dir / "clean" / "trojan*" / "*_host" / "*.v")
            clean_files = sorted(glob.glob(clean_pattern))
            metafunc.parametrize("rtl_file", clean_files, ids=lambda x: Path(x).name)
        elif "trojan" in metafunc.function.__name__:
            # Generate trojan file tests
            trojan_pattern = str(generated_circuits_dir / "trojan" / "trojan*" / "*_host" / "*.v") 
            trojan_files = sorted(glob.glob(trojan_pattern))
            metafunc.parametrize("rtl_file", trojan_files, ids=lambda x: Path(x).name)


@pytest.mark.verilator
def test_verilator_available(verilator_available):
    """Test that Verilator is available"""
    if not verilator_available:
        pytest.skip("Verilator not available")
    
    # Get Verilator version
    result = subprocess.run(["verilator", "--version"], capture_output=True, text=True)
    print(f"Verilator version: {result.stdout.strip()}")
    assert result.returncode == 0


@pytest.mark.verilator
def test_directories_exist(generated_circuits_dir, trojan_core_dir):
    """Test that required directories exist"""
    assert generated_circuits_dir.exists(), f"Generated circuits directory not found: {generated_circuits_dir}"
    assert trojan_core_dir.exists(), f"Trojan core directory not found: {trojan_core_dir}"
    
    # Check for clean and trojan subdirectories
    clean_dir = generated_circuits_dir / "clean"
    trojan_dir = generated_circuits_dir / "trojan"
    assert clean_dir.exists(), f"Clean directory not found: {clean_dir}"
    assert trojan_dir.exists(), f"Trojan directory not found: {trojan_dir}"


class TestRTLFileStructure:
    """Test RTL file structure and organization"""
    
    def test_file_count_matches(self, generated_circuits_dir):
        """Test that clean and trojan file counts match"""
        clean_pattern = str(generated_circuits_dir / "clean" / "trojan*" / "*_host" / "*.v")
        trojan_pattern = str(generated_circuits_dir / "trojan" / "trojan*" / "*_host" / "*.v")
        
        clean_files = glob.glob(clean_pattern)
        trojan_files = glob.glob(trojan_pattern)
        
        assert len(clean_files) == len(trojan_files), \
            f"Clean files ({len(clean_files)}) and trojan files ({len(trojan_files)}) count mismatch"
    
    def test_file_naming_convention(self, generated_circuits_dir):
        """Test that files follow proper naming convention"""
        all_pattern = str(generated_circuits_dir / "*" / "trojan*" / "*_host" / "*.v")
        all_files = glob.glob(all_pattern)
        
        naming_pattern = re.compile(r'trojan\d+_\w+_host_(clean|trojaned)_\d{4}\.v$')
        
        for file_path in all_files:
            file_name = Path(file_path).name
            assert naming_pattern.search(file_name), \
                f"File {file_name} doesn't follow naming convention"
    
    def test_trojan_core_files_exist(self, trojan_core_dir):
        """Test that all required trojan core files exist"""
        # Check for trojan core files (0-9)
        for i in range(10):
            trojan_file = trojan_core_dir / f"trojan{i}.v"
            clean_file = trojan_core_dir / f"clean{i}.v"
            
            assert trojan_file.exists(), f"Trojan core file missing: {trojan_file}"
            assert clean_file.exists(), f"Clean core file missing: {clean_file}"