"""
Integration tests for synthesis workflow after fixes.
Tests the complete flow from circuit generation to successful synthesis.
"""
import pytest
import subprocess
import tempfile
import shutil
from pathlib import Path
import json


class TestSynthesisIntegration:
    """Integration tests for synthesis workflow"""
    
    @pytest.fixture(autouse=True)
    def setup(self):
        """Setup test environment"""
        self.project_root = Path(__file__).parent.parent
        self.lib_path = self.project_root / "cell.lib"
        self.map_path = self.project_root / "map.v"
        
        # Verify required files exist
        assert self.lib_path.exists(), f"Library file not found: {self.lib_path}"
        assert self.map_path.exists(), f"Map file not found: {self.map_path}"
    
    def run_circuit_generation(self, output_dir, trojans=None, num_circuits=2):
        """Generate test circuits"""
        if trojans is None:
            trojans = ["trojan0"]
            
        cmd = [
            "python", "src/trojan_generator.py",
            "--output-dir", str(output_dir),
            "--num-circuits", str(num_circuits),
            "--trojans"] + trojans + [
            "--seed", "888"
        ]
        
        result = subprocess.run(
            cmd, 
            cwd=self.project_root,
            capture_output=True, 
            text=True
        )
        
        assert result.returncode == 0, f"Circuit generation failed: {result.stderr}"
        return result
    
    def run_synthesis_batch(self, input_dir, output_dir, labels_dir):
        """Run synthesis on a batch of circuits"""
        cmd = [
            "python", "src/syn.py",
            "--input", str(input_dir),
            "--output", str(output_dir), 
            "--labels", str(labels_dir),
            "--count-start", "9000"
        ]
        
        result = subprocess.run(
            cmd,
            cwd=self.project_root,
            capture_output=True,
            text=True,
            timeout=600  # 10 minute timeout
        )
        
        return {
            'returncode': result.returncode,
            'stdout': result.stdout,
            'stderr': result.stderr
        }
    
    def parse_synthesis_results(self, output):
        """Parse synthesis results from output"""
        lines = output.split('\n')
        
        success_count = 0
        total_count = 0
        errors = []
        warnings = []
        
        for line in lines:
            if "Synthesis completed:" in line:
                # Extract success/total from "Synthesis completed: X/Y files successful"
                parts = line.split()
                if len(parts) >= 3:
                    fraction = parts[2] 
                    if '/' in fraction:
                        success_str, total_str = fraction.split('/')
                        success_count = int(success_str)
                        total_count = int(total_str)
            elif "Error synthesizing" in line:
                errors.append(line.strip())
            elif "⚠️" in line and "UNCONNECTED_WARNING" in line:
                warnings.append(line.strip())
        
        return {
            'success_count': success_count,
            'total_count': total_count,
            'success_rate': (success_count / total_count * 100) if total_count > 0 else 0,
            'errors': errors,
            'warnings': warnings
        }
    
    @pytest.mark.synthesis
    @pytest.mark.integration
    @pytest.mark.slow
    def test_end_to_end_synthesis_workflow(self):
        """Test complete workflow from generation to synthesis"""
        with tempfile.TemporaryDirectory(prefix="e2e_synthesis_") as temp_dir:
            temp_path = Path(temp_dir)
            
            # Generate circuits
            self.run_circuit_generation(
                temp_path,
                trojans=["trojan0", "trojan1"],
                num_circuits=3
            )
            
            # Verify circuits were generated
            trojan_dir = temp_path / "trojan"
            assert trojan_dir.exists(), "Trojan circuits directory not created"
            
            circuit_files = list(trojan_dir.rglob("*.v"))
            assert len(circuit_files) > 0, "No circuit files generated"
            
            # Run synthesis
            output_dir = temp_path / "synthesis_output"
            labels_dir = temp_path / "synthesis_labels" 
            
            result = self.run_synthesis_batch(trojan_dir, output_dir, labels_dir)
            
            # Parse results
            synthesis_stats = self.parse_synthesis_results(result['stdout'])
            
            # Verify reasonable success rate (should be > 50% after fixes)
            assert synthesis_stats['success_count'] > 0, "No circuits synthesized successfully"
            assert synthesis_stats['success_rate'] >= 50.0, (
                f"Synthesis success rate too low: {synthesis_stats['success_rate']:.1f}%\n"
                f"Expected: >= 50%\n"
                f"Successful: {synthesis_stats['success_count']}/{synthesis_stats['total_count']}"
            )
    
    @pytest.mark.synthesis
    @pytest.mark.fixes
    def test_fixed_hosts_synthesis(self):
        """Test synthesis of specifically fixed host types"""
        with tempfile.TemporaryDirectory(prefix="fixed_hosts_") as temp_dir:
            temp_path = Path(temp_dir)
            
            # Generate circuits with known fixed hosts
            self.run_circuit_generation(
                temp_path,
                trojans=["trojan0"],  # Focus on trojan0 which has most fixes
                num_circuits=5
            )
            
            # Run synthesis 
            trojan_dir = temp_path / "trojan"
            output_dir = temp_path / "synthesis_output"
            labels_dir = temp_path / "synthesis_labels"
            
            result = self.run_synthesis_batch(trojan_dir, output_dir, labels_dir)
            synthesis_stats = self.parse_synthesis_results(result['stdout'])
            
            # For fixed hosts, expect high success rate
            expected_min_rate = 70.0  # Should be higher for fixed hosts
            assert synthesis_stats['success_rate'] >= expected_min_rate, (
                f"Fixed hosts synthesis rate too low: {synthesis_stats['success_rate']:.1f}%\n"
                f"Expected: >= {expected_min_rate}%\n"
                f"This suggests fixes may not be working properly"
            )
    
    @pytest.mark.synthesis
    @pytest.mark.fixes
    def test_no_critical_synthesis_errors(self):
        """Test that critical synthesis errors are not present"""
        with tempfile.TemporaryDirectory(prefix="error_check_") as temp_dir:
            temp_path = Path(temp_dir)
            
            # Generate small batch for error checking
            self.run_circuit_generation(
                temp_path,
                trojans=["trojan0"],
                num_circuits=2
            )
            
            # Run synthesis
            trojan_dir = temp_path / "trojan"
            output_dir = temp_path / "synthesis_output" 
            labels_dir = temp_path / "synthesis_labels"
            
            result = self.run_synthesis_batch(trojan_dir, output_dir, labels_dir)
            
            # Check for specific critical errors that we fixed
            output = result['stdout'] + result['stderr']
            
            critical_error_patterns = [
                "multiple conflicting drivers",
                "syntax error, unexpected '['", 
                "yields non-constant value.*packet_buffer"
            ]
            
            for pattern in critical_error_patterns:
                assert pattern not in output, (
                    f"Critical error pattern found in synthesis output: '{pattern}'\n"
                    f"This suggests a fix was not properly applied"
                )
    
    @pytest.mark.synthesis
    @pytest.mark.slow
    def test_synthesis_performance_benchmark(self):
        """Benchmark synthesis performance after fixes"""
        with tempfile.TemporaryDirectory(prefix="benchmark_") as temp_dir:
            temp_path = Path(temp_dir)
            
            # Generate benchmark circuits
            self.run_circuit_generation(
                temp_path, 
                trojans=["trojan0", "trojan1", "trojan2"],
                num_circuits=10
            )
            
            # Run synthesis and measure
            import time
            start_time = time.time()
            
            trojan_dir = temp_path / "trojan"
            output_dir = temp_path / "synthesis_output"
            labels_dir = temp_path / "synthesis_labels"
            
            result = self.run_synthesis_batch(trojan_dir, output_dir, labels_dir)
            synthesis_stats = self.parse_synthesis_results(result['stdout'])
            
            end_time = time.time()
            synthesis_time = end_time - start_time
            
            # Performance expectations
            circuits_per_second = synthesis_stats['total_count'] / synthesis_time
            
            # Log performance metrics
            print(f"\n=== Synthesis Performance Benchmark ===")
            print(f"Total circuits: {synthesis_stats['total_count']}")
            print(f"Successful: {synthesis_stats['success_count']}")
            print(f"Success rate: {synthesis_stats['success_rate']:.1f}%")
            print(f"Total time: {synthesis_time:.1f}s")
            print(f"Throughput: {circuits_per_second:.2f} circuits/second")
            
            # Basic performance assertions  
            assert circuits_per_second > 0.1, "Synthesis throughput too slow"
            assert synthesis_stats['success_rate'] >= 40.0, "Success rate below acceptable threshold"