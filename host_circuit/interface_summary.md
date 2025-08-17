# Host Circuit Interface Summary

This document describes the parameterizable interfaces for each Trojan host circuit.

## Trojan0 - Datapath Host
**File**: `trojan0_datapath_host.v`
**Type**: ALU + Multiplier + Shifter datapath
**Parameters**:
- `DATA_WIDTH = 32` - Main data path width
- `ADDR_WIDTH = 16` - Address width  
- `KEY_WIDTH = 128` - Trojan key input width (configurable)
- `LOAD_WIDTH = 64` - Trojan load output width (configurable)

**Trojan Interface**: `key[KEY_WIDTH-1:0] -> load[LOAD_WIDTH-1:0]`

## Trojan1 - FSM Router Host  
**File**: `trojan1_fsm_router_host.v`
**Type**: Packet router with FSM control
**Parameters**:
- `DATA_WIDTH = 32` - Packet data width
- `ADDR_WIDTH = 8` - Address width
- `NUM_PORTS = 4` - Number of output ports
- `TRIGGER_WIDTH = 1` - Trigger signal width (always 1 bit)

**Trojan Interface**: `r1 -> trigger` (both single bits)

## Trojan2 - Pipeline Host
**File**: `trojan2_pipeline_host.v` 
**Type**: 3-stage streaming pipeline
**Parameters**:
- `DATA_WIDTH = 32` - Pipeline data width
- `PIPELINE_DEPTH = 3` - Number of pipeline stages
- Trojan uses 8-bit data input and 1-bit force_reset (fixed width)

**Trojan Interface**: `data_in[7:0] -> force_reset`

## Trojan3 - Crossbar Host
**File**: `trojan3_crossbar_host.v`
**Type**: Simple crossbar switch
**Parameters**:
- `DATA_WIDTH = 16` - Data path width (configurable, affects trojan interface)
- `NUM_INPUTS = 4` - Number of input ports
- `NUM_OUTPUTS = 4` - Number of output ports

**Trojan Interface**: `data_in[15:0] -> data_out[15:0]` (adapts to DATA_WIDTH)

## Trojan4 - MAC Host
**File**: `trojan4_mac_host.v`
**Type**: Multiply-Accumulate unit
**Parameters**:
- `DATA_WIDTH = 32` - Input data width
- `COEFF_WIDTH = 16` - Coefficient width  
- `ACCUM_WIDTH = 48` - Accumulator width
- `KEY_WIDTH = 64` - Trojan key input width (configurable)
- `LEAK_WIDTH = 64` - Trojan leak output width (configurable)

**Trojan Interface**: `key[KEY_WIDTH-1:0] -> leak[LEAK_WIDTH-1:0]`

## Trojan5 - LFSR Host
**File**: `trojan5_lfsr_host.v`
**Type**: LFSR/CRC generator
**Parameters**:
- `DATA_WIDTH = 32` - Data width (affects trojan interface adaptation)
- `LFSR_WIDTH = 16` - LFSR register width
- `CRC_POLY = 16'h8005` - CRC polynomial

**Trojan Interface**: `pon_rst_n_i, prog_dat_i[13:0], pc_reg[12:0] -> prog_adr_o[12:0]`

## Trojan6 - Barrel Shifter Host
**File**: `trojan6_barrel_shifter_host.v`
**Type**: Multi-mode barrel shifter  
**Parameters**:
- `DATA_WIDTH = 32` - Data width (affects trojan interface adaptation)
- `SHIFT_BITS = 5` - Shift amount width

**Trojan Interface**: `m0_data_o[31:0], i_s15_data_o[31:0] -> i_s15_data_o_TrojanPayload[31:0]`

## Trojan7 - AXI Host
**File**: `trojan7_axi_host.v` 
**Type**: AXI-lite/DMA controller
**Parameters**:
- `ADDR_WIDTH = 32` - Address width (affects trojan interface adaptation)
- `DATA_WIDTH = 32` - Data width (affects trojan interface adaptation)
- `NUM_SLAVES = 16` - Number of slave devices

**Trojan Interface**: `wb_addr_i[31:0], wb_data_i[31:0], s0_data_i[31:0] -> slv_sel[3:0]`

## Trojan8 - Matrix Multiplication Host
**File**: `trojan8_matrix_mult_host.v`
**Type**: Bit matrix multiplier
**Parameters**:
- `MATRIX_SIZE = 4` - Matrix dimensions
- `DATA_WIDTH = 8` - Matrix element width
- `RESULT_WIDTH = 16` - Result width

**Trojan Interface**: `a[7:0], b[7:0], c[7:0], d[7:0], e[7:0], sel[2:0] -> y[15:0]` (fixed width)

## Trojan9 - CORDIC Host  
**File**: `trojan9_cordic_host.v`
**Type**: Pipelined CORDIC processor
**Parameters**:
- `DATA_WIDTH = 16` - CORDIC data width (affects trojan interface adaptation)
- `ANGLE_WIDTH = 16` - Angle representation width
- `ITERATIONS = 8` - CORDIC pipeline depth

**Trojan Interface**: `a[7:0], b[7:0], c[7:0], d[7:0], e[7:0], mode[1:0] -> y[15:0]`

## Width Adaptation Strategy

For Trojans with fixed interfaces (original design), the host circuits use:
1. **Generate blocks** to conditionally instantiate width adaptation logic
2. **Width extension/truncation** for signals wider/narrower than expected
3. **Zero-padding** for unused bits in wider interfaces
4. **Bit selection** for narrower target interfaces

This allows the same host circuit to work with different Trojan interface widths while maintaining compatibility with the original Trojan core designs.