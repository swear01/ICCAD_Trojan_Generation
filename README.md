# ICCAD Trojan Generation

This repository generates hardware Trojans for ICCAD research purposes. It creates basic circuits with corresponding interfaces (complete circuits) and inserts Trojan cores into them, while modifying Trojan core parameters such as internal cryptographic elements and Trojan IO bit widths. The process generates both clean circuits and Trojaned circuits for comparison and analysis.

## Overview

The system:
1. Generates base circuits with complete functionality and proper interfaces
2. Inserts Trojan cores with configurable parameters:
   - Internal cryptographic keys/ciphertext
   - Trojan IO bit widths
   - Other parametric configurations
3. Produces paired datasets of clean and Trojaned circuits

## Synthesis to minimal primitive library with Yosys

## Requirements
yosys in your PATH (with abc installed internally):
```bash
sudo apt install yosys
```

## Usage
configure the data paths in CONFIG of syn.py, then run:
```bash
python3 syn/syn.py
```

## Synthesized Dataset
- 0 ~ 19: trojaned, with node labels
- 20 ~ 29: non trojaned
- 30 ~ 2029: trojaned, no node labels
- 2030 ~ 3029: non trojaned