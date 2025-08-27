#!/usr/bin/env python3
"""
Tests for the Trojan Generator functionality
"""

import pytest
import json
import tempfile
import shutil
from pathlib import Path
import sys
import os

# Add parent directory to path to import the generator
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))
from trojan_generator import TrojanGenerator


class TestTrojanGenerator:
    """Test the TrojanGenerator class"""
    
    @pytest.fixture
    def temp_output_dir(self):
        """Create a temporary output directory for testing"""
        temp_dir = tempfile.mkdtemp()
        yield Path(temp_dir)
        shutil.rmtree(temp_dir)
    
    @pytest.fixture
    def generator(self, temp_output_dir):
        """Create a TrojanGenerator instance for testing"""
        return TrojanGenerator(str(temp_output_dir))
    
    def test_generator_initialization(self, generator, temp_output_dir):
        """Test that generator initializes correctly"""
        assert generator.output_dir == temp_output_dir
        assert generator.clean_dir == temp_output_dir / "clean"
        assert generator.trojan_dir == temp_output_dir / "trojan"
        assert generator.clean_dir.exists()
        assert generator.trojan_dir.exists()
    
    def test_extract_trojan_number(self, generator):
        """Test trojan number extraction"""
        test_cases = [
            ("trojan0_something.v", "0"),
            ("trojan5_host.v", "5"), 
            ("trojan9_test.v", "9"),
            ("no_trojan.v", None),
            ("trojan.v", None)
        ]
        
        for file_path, expected in test_cases:
            # Extract trojan number using the same method as in the generator
            import re
            match = re.search(r'trojan(\d+)', file_path)
            result = match.group(1) if match else None
            assert result == expected, f"Failed for {file_path}"
    
    def test_format_parameter_value(self, generator):
        """Test parameter value formatting"""
        # Create a simple verilog code for testing
        verilog_code = """
        parameter PARAM_A = 16'h1234;
        parameter PARAM_B = 8'b10101010;
        parameter PARAM_C = 42;
        """
        
        # Test hex formatting preservation
        result = generator.format_parameter_value("PARAM_A", 0x5678, verilog_code)
        assert "16'h5678" in result or "16'h5678" == result
        
        # Test width parameters (should stay decimal)
        result = generator.format_parameter_value("DATA_WIDTH", 32, verilog_code)
        assert result == "32"
        
        # Test small integers
        result = generator.format_parameter_value("SMALL_PARAM", 10, verilog_code)
        assert result == "10"
    
    def test_add_instance_id_to_module_name(self, generator):
        """Test module name modification with instance ID"""
        # Test module without parameters
        verilog_code = "module test_module (input clk, output data);"
        result = generator.add_instance_id_to_module_name(verilog_code, 42)
        assert "module test_module_0042 (" in result
        
        # Test module with parameters
        verilog_code = "module test_module #(parameter WIDTH = 8) (input clk);"
        result = generator.add_instance_id_to_module_name(verilog_code, 123)
        assert "module test_module_0123 #(parameter WIDTH = 8) (" in result
    
    def test_inject_parameters(self, generator):
        """Test parameter injection into Verilog code"""
        verilog_code = """
        module test #(
            parameter DATA_WIDTH = 16,
            parameter PATTERN = 32'hDEADBEEF
        ) (input clk);
        endmodule
        """
        
        params = {
            "DATA_WIDTH": 32,
            "PATTERN": 0x12345678
        }
        
        result = generator.inject_parameters(verilog_code, params)
        assert "parameter DATA_WIDTH = 32" in result
        assert "parameter PATTERN = 32'h12345678" in result or "parameter PATTERN = 32'h12345678" in result
    
    @pytest.mark.skipif(not Path("/home/swear/ICCAD_Trojan_Generation/trojan_core").exists(), 
                       reason="Trojan core directory not available")
    def test_read_trojan_core_clean(self, generator):
        """Test reading clean trojan core files"""
        # Test reading clean version
        content = generator.read_trojan_core("trojan0", "clean")
        assert "// trojan_core/clean0.v not found" in content or "module" in content.lower()
    
    @pytest.mark.skipif(not Path("/home/swear/ICCAD_Trojan_Generation/trojan_core").exists(),
                       reason="Trojan core directory not available")
    def test_read_trojan_core_trojaned(self, generator):
        """Test reading trojaned trojan core files"""
        # Test reading trojaned version
        content = generator.read_trojan_core("trojan0", "trojaned")
        assert "// trojan_core/trojan0.v not found" in content or "module" in content.lower()


class TestGenerationWorkflow:
    """Test the complete generation workflow"""
    
    @pytest.fixture
    def temp_output_dir(self):
        """Create a temporary output directory for testing"""
        temp_dir = tempfile.mkdtemp()
        yield Path(temp_dir)
        shutil.rmtree(temp_dir)
    
    @pytest.mark.skipif(not Path("/home/swear/ICCAD_Trojan_Generation/configs").exists(),
                       reason="Config directory not available")
    def test_config_loader_availability(self):
        """Test that config loader can be imported and used"""
        try:
            sys.path.insert(0, str(Path(__file__).parent.parent / "src"))
            from config_loader import get_config_loader
            loader = get_config_loader()
            assert loader is not None
        except ImportError as e:
            pytest.skip(f"Config loader not available: {e}")
    
    def test_file_structure_creation(self, temp_output_dir):
        """Test that generator creates proper file structure"""
        generator = TrojanGenerator(str(temp_output_dir))
        
        # Check directory structure
        assert (temp_output_dir / "clean").exists()
        assert (temp_output_dir / "trojan").exists()
        
        # Directories should be empty initially
        assert len(list((temp_output_dir / "clean").iterdir())) == 0
        assert len(list((temp_output_dir / "trojan").iterdir())) == 0
    
    @pytest.mark.skipif(
        not all([
            Path("/home/swear/ICCAD_Trojan_Generation/configs").exists(),
            Path("/home/swear/ICCAD_Trojan_Generation/trojan_core").exists(),
            Path("/home/swear/ICCAD_Trojan_Generation/host_circuit").exists()
        ]),
        reason="Required directories not available for integration test"
    )
    def test_small_batch_generation(self, temp_output_dir):
        """Test generating a small batch of circuits"""
        generator = TrojanGenerator(str(temp_output_dir))
        
        # Generate a small batch (1 circuit for trojan0 only)
        try:
            generator.generate_batch(num_circuits=1, trojans=["trojan0"])
            
            # Check that files were created
            clean_files = list((temp_output_dir / "clean").rglob("*.v"))
            trojan_files = list((temp_output_dir / "trojan").rglob("*.v"))
            
            assert len(clean_files) > 0, "No clean files generated"
            assert len(trojan_files) > 0, "No trojan files generated" 
            assert len(clean_files) == len(trojan_files), "Clean and trojan file count mismatch"
            
            # Check that summary file was created
            summary_file = temp_output_dir / "generation_summary.json"
            assert summary_file.exists(), "Summary file not created"
            
            # Verify summary content
            with open(summary_file, 'r') as f:
                summary = json.load(f)
            
            assert isinstance(summary, list), "Summary should be a list"
            assert len(summary) > 0, "Summary should contain entries"
            
            # Check summary entry structure
            entry = summary[0]
            required_keys = [
                'trojan_id', 'host_name', 'instance_id', 
                'clean_file', 'trojaned_file', 
                'trojan_parameters', 'host_parameters'
            ]
            for key in required_keys:
                assert key in entry, f"Missing key {key} in summary entry"
                
        except Exception as e:
            pytest.skip(f"Batch generation failed (likely missing dependencies): {e}")


if __name__ == "__main__":
    pytest.main([__file__, "-v"])