# RTL Compilation Tests

This directory contains comprehensive pytest-based tests for the ICCAD Trojan Generation project.

## Test Structure

- `conftest.py` - Pytest configuration and fixtures
- `test_rtl_compilation.py` - RTL compilation tests using Verilator
- `test_generator.py` - Tests for the TrojanGenerator class
- `pytest.ini` - Pytest configuration file
- `requirements.txt` - Python testing dependencies

## Running Tests

### Prerequisites

1. Install Python testing dependencies:
```bash
pip install -r tests/requirements.txt
```

2. Ensure Verilator is installed and available in PATH:
```bash
verilator --version
```

### Running All Tests

```bash
# Run all tests
pytest tests/

# Run with verbose output
pytest tests/ -v

# Run specific test file
pytest tests/test_rtl_compilation.py -v

# Run only Verilator-related tests
pytest tests/ -m verilator

# Run only clean file tests
pytest tests/ -m clean

# Run only trojan file tests  
pytest tests/ -m trojan
```

### Running Tests in Parallel

```bash
# Run tests in parallel (requires pytest-xdist)
pytest tests/ -n auto
```

### Generating Test Reports

```bash
# Generate HTML report
pytest tests/ --html=test_report.html --self-contained-html

# Generate coverage report
pytest tests/ --cov=src --cov-report=html
```

## Test Categories

### RTL Compilation Tests (`test_rtl_compilation.py`)

Tests all generated RTL files for Verilator compilation:

- **Clean RTL Tests**: Verify all clean circuit files compile without errors
- **Trojan RTL Tests**: Verify all trojaned circuit files compile without errors
- **File Structure Tests**: Verify proper file organization and naming
- **Directory Tests**: Verify required directories exist

### Generator Tests (`test_generator.py`)

Tests the TrojanGenerator functionality:

- **Initialization Tests**: Verify proper generator setup
- **Parameter Formatting**: Test parameter value formatting
- **Module Name Handling**: Test instance ID injection
- **File Reading**: Test trojan core and host file reading
- **Integration Tests**: Test small batch generation

## Test Markers

- `@pytest.mark.verilator` - Tests requiring Verilator
- `@pytest.mark.clean` - Tests for clean RTL files
- `@pytest.mark.trojan` - Tests for trojaned RTL files
- `@pytest.mark.slow` - Long-running tests

## Error Categories

The tests categorize compilation errors into:

- Syntax Error
- Undefined Signal/Module
- Port Connection Error
- Width Mismatch
- Missing Module
- Duplicate Declaration
- Assignment Error
- Clock Domain Error
- Reset Logic Error
- Other Error

## Expected Test Results

For a properly configured system:
- All RTL files should compile without errors
- File structure should be organized correctly
- Generator should create matching clean/trojan pairs
- Configuration files should be complete

If tests fail, check:
1. Verilator installation
2. File paths and directory structure
3. Trojan core files existence
4. Host circuit files syntax