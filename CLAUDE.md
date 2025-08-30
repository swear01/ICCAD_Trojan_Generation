# ICCAD Trojan Generation Project

## Project Overview
Hardware trojan generation and insertion project for ICCAD competition.

## Key Commands
- **Synthesis**: `python src/syn.py` (timeout: 10 seconds)
- **Lint check**: `verilator --lint-only`
- **Build**: Check synthesis results in generated directories

## Project Structure
- `trojan_core/` - Trojan and clean core implementations
- `host_circuit/` - Host circuit designs with trojan integration
- `configs/` - TOML configuration files for host parameters
- `src/syn.py` - Main synthesis script

## Important Notes
- Synthesis timeout set to 10 seconds for complex circuits
- All trojan cores use async reset: `always @(posedge clk or posedge rst)`
- **CRITICAL**: Fix all unexpected lint errors, never disable lint tools
- Write reasonable circuits with proper logic design
- Parameters should NOT contain bitwidth information
- Use `$clog2()` for proper bit width calculation in array indexing
- Explicit casting required for arithmetic: `16'(variable)` to avoid width warnings
