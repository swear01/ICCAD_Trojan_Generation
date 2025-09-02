# ICCAD Trojan Generation Project

## Project Overview
Hardware trojan generation and insertion project for ICCAD competition.

## Key Commands
- **Synthesis**: `python src/syn.py` (timeout: 10 seconds)
- **Lint check**: `verilator --lint-only`

## Project Structure
- `trojan_core/` - Trojan and clean core implementations
- `host_circuit/` - Rough Host circuit designs with trojan integration
- `dataset/` - Reviewed trojan host circuits
- `configs/` - TOML configuration files for host and core parameters
- `src/gtrjan_generator.py` - Combine trojan core and host circuit
- `src/syn.py` - Main synthesis script

## Important Notes
- Synthesis timeout set to 10 seconds for complex circuits
- All trojan cores use async reset: `always @(posedge clk or posedge rst)`
- **CRITICAL**: Fix all unexpected lint errors and warnings, never disable lint tools
- Write reasonable circuits with proper logic design
- Use `$clog2()` for proper bit width calculation in array indexing

## Current Task
- Please ReFerence The Trojan 7-9
- Every Trojan Core Should Have Bitwidth Parameter
