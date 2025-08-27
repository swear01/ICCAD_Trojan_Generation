# RTL Compilation and Synthesis Tests

This directory contains comprehensive pytest-based tests for the ICCAD Trojan Generation project, including RTL compilation, synthesis verification, and fix validation.

## Test Structure

- `conftest.py` - Pytest configuration and fixtures
- `test_rtl_compilation.py` - RTL compilation tests using Verilator
- `test_generator.py` - Tests for the TrojanGenerator class
- `test_synthesis_fixes.py` - Synthesis tests for specific fixes applied
- `test_synthesis_integration.py` - End-to-end synthesis workflow tests
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

3. Ensure Yosys is installed for synthesis tests:
```bash
yosys --version
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

# Run only synthesis tests
pytest tests/ -m synthesis

# Run only fix verification tests
pytest tests/ -m fixes

# Run integration tests
pytest tests/ -m integration

# Skip slow tests
pytest tests/ -m "not slow"
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

### Synthesis Fix Tests (`test_synthesis_fixes.py`)

Tests for specific RTL and tech mapping fixes:

- **Multiple Driver Fix**: Verify UART bit_counter separation works
- **DSP Port Array Fix**: Verify input port array syntax correction
- **Network Memory Fix**: Verify memory array size reduction
- **Successful Synthesis**: Test that fixed circuits synthesize correctly

### Synthesis Integration Tests (`test_synthesis_integration.py`)

End-to-end synthesis workflow tests:

- **End-to-End Workflow**: Complete generation → synthesis pipeline
- **Performance Benchmarks**: Synthesis throughput and success rate metrics
- **Critical Error Detection**: Ensure fixed error patterns don't return
- **Fixed Host Validation**: Verify high success rates for corrected hosts

## Test Markers

- `@pytest.mark.verilator` - Tests requiring Verilator
- `@pytest.mark.synthesis` - Tests requiring Yosys synthesis
- `@pytest.mark.clean` - Tests for clean RTL files
- `@pytest.mark.trojan` - Tests for trojaned RTL files
- `@pytest.mark.slow` - Long-running tests (>30 seconds)
- `@pytest.mark.integration` - End-to-end integration tests
- `@pytest.mark.fixes` - Tests verifying specific bug fixes

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

### RTL Compilation (Verilator)
- All RTL files should compile without errors
- File structure should be organized correctly
- Generator should create matching clean/trojan pairs

### Synthesis Tests (Yosys) 
- Fixed circuits should synthesize successfully (>70% success rate for known fixes)
- No critical synthesis errors should be present:
  - No "multiple conflicting drivers" errors  
  - No "syntax error, unexpected '['" errors
  - No "yields non-constant value" memory errors
- Integration tests should show >50% overall success rate

### Performance Benchmarks
- Synthesis throughput should be >0.1 circuits/second
- Fixed host types should show significantly higher success rates than baseline

## Troubleshooting Test Failures

If tests fail, check:

### RTL Compilation Failures
1. Verilator installation and PATH
2. File paths and directory structure  
3. Trojan core files existence
4. Host circuit files syntax

### Synthesis Test Failures  
1. Yosys installation and availability
2. Library files (cell.lib, map.v) existence
3. Circuit generation working properly
4. Host file fixes applied correctly

### Performance/Integration Failures
1. System resources (memory, disk space)
2. Timeout settings in pytest.ini
3. Network connectivity (if applicable)
4. Temporary directory permissions