"""
Pytest Configuration File for ICCAD Trojan Generation Tests
Provides fixtures and configuration for testing RTL files with Verilator
"""

import pytest
import subprocess
import shutil
from pathlib import Path

def pytest_configure(config):
    """Configure pytest with custom markers"""
    config.addinivalue_line(
        "markers", "verilator: mark test as requiring Verilator"
    )
    config.addinivalue_line(
        "markers", "clean: mark test for clean RTL files"  
    )
    config.addinivalue_line(
        "markers", "trojan: mark test for trojaned RTL files"
    )

@pytest.fixture(scope="session")
def base_dir():
    """Base directory fixture"""
    return Path("/home/swear/ICCAD_Trojan_Generation")

@pytest.fixture(scope="session") 
def verilator_available():
    """Check if Verilator is available"""
    try:
        result = subprocess.run(
            ["verilator", "--version"], 
            capture_output=True, 
            text=True,
            timeout=10
        )
        return result.returncode == 0
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False

@pytest.fixture(scope="session")
def generated_circuits_dir(base_dir):
    """Generated circuits directory fixture"""
    return base_dir / "generated_circuits"

@pytest.fixture(scope="session")
def trojan_core_dir(base_dir):
    """Trojan core directory fixture"""
    return base_dir / "trojan_core"

def pytest_collection_modifyitems(config, items):
    """Modify test collection to skip Verilator tests if not available"""
    if not shutil.which("verilator"):
        skip_verilator = pytest.mark.skip(reason="Verilator not available")
        for item in items:
            if "verilator" in item.keywords:
                item.add_marker(skip_verilator)