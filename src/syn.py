#!/usr/bin/env python3
"""
Synthesis Script for ICCAD Trojan Generation
Synthesizes generated circuits to gate-level netlists using Yosys+ABC.
Shows progress bar by default, displays error logs only when synthesis fails.
Includes latch and large circuit (>60,000 gates) detection with warnings.

Usage:
# Generate clean gate-level circuits (with progress bar):
python src/syn.py --input generated_circuits/clean --output data/netlist/clean --labels data/label/clean --count-start 3001

# Generate trojan gate-level circuits (with progress bar):
python src/syn.py --input generated_circuits/trojan --output data/netlist/trojan --labels data/label/trojan --count-start 1001

# For detailed verbose output (no progress bar):
python src/syn.py --input generated_circuits/clean --output data/netlist/clean --labels data/label/clean --verbose

# For batch processing with progress tracking:
python src/syn.py --input generated_circuits/trojan --output data/netlist/trojan --labels data/label/trojan
"""

import os
import re
import subprocess
import sys
import tempfile
import argparse
from tqdm import tqdm

##################### DEFAULT CONFIG #####################
DEFAULT_LIB_PATH = "cell.lib"
DEFAULT_MAP_PATH = "map.v"  # Map file for ALDFF to DFF primitive
DEFAULT_SCRIPT_PATH = "syn.ys"
DEFAULT_COUNT_START = 201
DEFAULT_RTL_DIR = "generated_circuits/clean"
DEFAULT_NETLIST_OUT_DIR = "data/netlist/"
DEFAULT_LABEL_OUT_DIR = "data/label/"
################### END DEFAULT CONFIG ###################


def run_yosys(rtl_files, top, out_tmp, lib_path, map_path, script_path):
	"""Run Yosys + ABC flow using the provided liberty for mapping only to cells in cell.lib."""

	# Enhanced Yosys commands with aggressive optimization to eliminate unconnected wires
	# yosys_cmds = [
	# 	f"read_liberty -lib {lib_path}",
	# 	*[f"read_verilog -sv {f}" for f in rtl_files],
	# 	f"hierarchy -check -top {top}",
	# 	"proc; opt",
	# 	"flatten",
	# 	"# More aggressive optimization and cleanup to eliminate unconnected wires",
	# 	"opt -full",                       # Full optimization pass
	# 	"opt_clean -purge",               
	# 	"opt_dff -sat",                   # DFF optimization with SAT
	# 	"opt -full",
	# 	"techmap; opt -full",             # Aggressive optimization after techmap
	# 	"opt_clean -purge",               
	# 	f"techmap -map {map_path}",       # Map the ALDFF to the DFF primitive
	# 	"opt -full",                      # Full optimization after custom mapping
	# 	"opt_clean -purge",               
	# 	f"dfflibmap -liberty {lib_path}",
	# 	"opt -full",                      # Full optimization after DFF mapping
	# 	"opt_clean -purge",               
	# 	"opt -full",                      # Full optimization after buffer insertion
	# 	"opt_clean -purge",               
    #     "insbuf -buf buf A Y",            # Insert buffers to replace assign usage
	# 	"# Multiple ABC passes with different strategies",
	# 	f"abc -liberty {lib_path} -fast", # Fast ABC pass
	# 	"opt -full",
	# 	f"abc -liberty {lib_path}",       # Normal ABC pass for better optimization
	# 	"opt_merge; opt_clean; clean",    # Comprehensive cleanup
	# 	"opt -full",
	# 	"opt_clean -purge",
	# 	"# Final cleanup passes",
	# 	"wreduce -memx",                  # Word-level reduction
	# 	"opt -full",
	# 	"opt_clean -purge",
	# 	"check -noinit",                  # Check without initialization warnings
	# 	f"stat -liberty {lib_path}",
	# 	f"write_verilog -noattr -noexpr -nodec -defparam {out_tmp}",
	# ]
	
	yosys_cmds = [
		f"read_liberty -lib {lib_path}",
		*[f"read_verilog -sv {f}" for f in rtl_files],
		f"hierarchy -check -top {top}",
		f"proc; opt",
		f"flatten",
		f"techmap; opt",
        f"techmap -map {map_path}",         # Map the ALDFF to the DFF primitive
		f"dfflibmap -liberty {lib_path}",
		f"insbuf -buf buf A Y",             # Insert buffers to replace assign usage
		f"opt_clean -purge",
		f"abc -liberty {lib_path} -fast",   # ABC combinational mapping/optimization
		f"opt_merge; opt_clean; clean",
		f"stat -liberty {lib_path}",
		f"write_verilog -noattr -noexpr -nodec -defparam {out_tmp}",
	]

	# Write Yosys script
	script = "\n".join(yosys_cmds)
	with open(script_path, "w") as f:
		f.write(script)

	# Run Yosys script with 3-second timeout and capture output for analysis
	try:
		result = subprocess.run(
			["yosys", script_path], 
			capture_output=True, 
			text=True, 
			check=True,
			timeout=10.0  # 10-second timeout
		)
		
		# Return the captured output for analysis
		return result.stdout, result.stderr
		
	except subprocess.TimeoutExpired:
		raise RuntimeError(f"Synthesis timeout: exceeded 8 seconds for script {script_path}")


def analyze_synthesis_output(stdout, stderr, netlist_content="", circuit_name=""):
	"""Analyze Yosys synthesis output for warnings and circuit statistics"""
	warnings = []
	
	full_output = stdout + stderr
	
	# Check for latch inference
	latch_patterns = [
		r"inferred latch",
		r"creating latch",
		r"latch for signal",
		r"PROC_DLATCH.*created.*latch"
	]
	
	for pattern in latch_patterns:
		matches = re.findall(pattern, full_output, re.IGNORECASE)
		if matches:
			warnings.append(f"LATCH_WARNING: {len(matches)} latch(es) inferred")
			break
	
	# Check for assign statements in the netlist content
	if netlist_content:
		assign_lines = []
		for i, line in enumerate(netlist_content.splitlines(), 1):
			if "assign" in line:
				assign_lines.append(f"Line {i}: {line.strip()}")
		
		if assign_lines:
			if circuit_name:
				warnings.append(f"ASSIGN_WARNING: Circuit '{circuit_name}' has {len(assign_lines)} assign statement(s) in netlist")
			else:
				warnings.append(f"ASSIGN_WARNING: {len(assign_lines)} assign statement(s) found in netlist")
			# Add detailed assign information to warnings
			for assign_line in assign_lines[:3]:  # Show first 3 assign statements
				warnings.append(f"  {assign_line}")
			if len(assign_lines) > 3:
				warnings.append(f"  ... and {len(assign_lines) - 3} more assign statements")
			warnings.append("  (This may indicate incomplete synthesis or optimization issues)")
	
	# Check for unconnected wires/ports - these indicate potentially problematic synthesis
	# Use more precise regex patterns to match signal names including complex hierarchical names
	unconnected_patterns = [
		r"Warning: Wire ([^\s]+(?:\s*\[[^\]]+\])?) is used but has no driver",
		r"Warning: ([^\s]+(?:\s*\[[^\]]+\])?) is not driven by any cell output",
		r"unused wire: ([^\s]+(?:\s*\[[^\]]+\])?)",
		r"undriven wire: ([^\s]+(?:\s*\[[^\]]+\])?)", 
		r"floating wire: ([^\s]+(?:\s*\[[^\]]+\])?)",
		r"Warning.*unconnected.*wire.*([^\s]+(?:\s*\[[^\]]+\])?)",
		r"Warning.*wire.*([^\s]+(?:\s*\[[^\]]+\])?).*not connected",
		r"Warning.*([^\s]+(?:\s*\[[^\]]+\])?).*has no driver",
		r"Warning: Port ([^\s]+(?:\s*\[[^\]]+\])?) of cell.*is unconnected"
	]
	
	unconnected_wires = set()
	for pattern in unconnected_patterns:
		matches = re.findall(pattern, full_output, re.IGNORECASE)
		for match in matches:
			if isinstance(match, tuple):
				# Handle regex groups
				for group in match:
					if group:
						unconnected_wires.add(group)
			else:
				unconnected_wires.add(match)
	
	# Check for specific Yosys warnings about optimization issues
	opt_warning_patterns = [
		r"Warning:.*removed \d+ unused.*",
		r"Warning:.*(\d+) wires.*unused",
		r"Warning: found \d+ undriven signals",
		r"Warning.*unused.*(\d+)"
	]
	
	unused_count = 0
	for pattern in opt_warning_patterns:
		matches = re.findall(pattern, full_output, re.IGNORECASE)
		if matches:
			for match in matches:
				if isinstance(match, str) and match.isdigit():
					unused_count += int(match)
				elif isinstance(match, tuple):
					for group in match:
						if isinstance(group, str) and group.isdigit():
							unused_count += int(group)
	
	
	# Report unconnected issues
	if unconnected_wires:
		wire_names = sorted(list(unconnected_wires))[:5]  # Show first 5 names
		if len(unconnected_wires) <= 5:
			warnings.append(f"UNCONNECTED_WARNING: {len(unconnected_wires)} unconnected wire(s): {', '.join(wire_names)}")
		else:
			warnings.append(f"UNCONNECTED_WARNING: {len(unconnected_wires)} unconnected wire(s): {', '.join(wire_names)} ...")
	
	if unused_count > 0:
		warnings.append(f"UNUSED_WARNING: {unused_count} unused/removed signal(s)")
	
	# Check circuit size - look for total cell count from stat command
	gate_count = 0
	# Pattern to match: "Number of cells:      12345"
	cell_match = re.search(r"Number of cells:\s*(\d+)", full_output)
	if cell_match:
		gate_count = int(cell_match.group(1))
	else:
		# Alternative pattern - count individual gates from stat output
		gate_patterns = [
			r"\$_AND_\s+(\d+)",
			r"\$_OR_\s+(\d+)",
			r"\$_NOT_\s+(\d+)",
			r"\$_NAND_\s+(\d+)",
			r"\$_NOR_\s+(\d+)",
			r"\$_XOR_\s+(\d+)",
			r"\$_XNOR_\s+(\d+)",
			r"\$_DFF_\w*\s+(\d+)",
			r"\$_DFFE_\w*\s+(\d+)"
		]
		
		for pattern in gate_patterns:
			matches = re.findall(pattern, full_output)
			for match in matches:
				gate_count += int(match)
	
	# Check if circuit is too large (>60,000 gates)
	if gate_count > 60000:
		warnings.append(f"LARGE_CIRCUIT_WARNING: Circuit has {gate_count} gates (>60,000)")
	
	return warnings, gate_count


def post_process_netlist(verilog_text: str) -> str:
	"""Format the Yosys netlist into design0.v style.

	- Primitive gates (and, or, nand, nor, xor, xnor, not, buf): positional pins (Y, A[, B]) on one line.
	- dff: explicit named pins (.RN, .SN, .CK, .D, .Q) on one line (order enforced if present).
	- Keep module/input/output/wire/endmodule as-is. Skip comments/defparam.
	"""

	# Strip comments (// and /* */) first
	text_no_block = re.sub(r"/\*.*?\*/", "", verilog_text, flags=re.S)
	text_no_comments = re.sub(r"//.*", "", text_no_block)

	# Convert all sized hex literals to binary
	def hex_to_bin_str(val: str) -> str:
		clean = val.replace("_", "").strip()
		bits = []
		for ch in clean:
			c = ch.lower()
			if c in "0123456789abcdef":
				bits.append(format(int(c, 16), "04b"))
			elif c in ("x", "?"):
				bits.append("x" * 4)
			elif c == "z":
				bits.append("z" * 4)
			else:
				# Unknown char, default to zeros
				bits.append("0000")
		return "".join(bits)

	def _hex_repl(m: re.Match) -> str:
		width = m.group("width")
		val = m.group("val")
		b = hex_to_bin_str(val)
		if width:
			w = int(width)
			if len(b) < w:
				b = b.rjust(w, "0")
			elif len(b) > w:
				b = b[-w:]
			return f"{w}'b{b}"
		return f"'b{b}"

	text_converted = re.sub(r"(?:(?P<width>\d+)\s*)'\s*[hH]\s*(?P<val>[0-9a-fA-F_xXzZ?]+)", _hex_repl, text_no_comments)

	# From here on, operate on the cleaned/converted text
	verilog_text = text_converted

	primitive_types = {"and", "or", "nand", "nor", "xor", "xnor", "not", "buf"}

	def clean_cell_ident(token: str) -> str:
		"""Clean cell/gate or instance identifiers: drop leading \\ or $ only.
		Signal names should not use this cleaner.
		"""
		if token is None:
			return ""
		t = token.strip()
		# Remove a single leading escape backslash and/or leading '$' for cell/inst names
		if t.startswith("\\"):
			t = t[1:].strip()
		if t.startswith("$"):
			t = t[1:].strip()
		return t

	def clean_signal(token: str) -> str:
		"""Clean signal/net identifiers: preserve leading \\; normalize bracket spacing.
		- Collapse patterns like "] [" -> "][]"
		- Remove spaces before '[', right after '[', and right before ']'
		"""
		if token is None:
			return ""
		t = token.strip()
		# Merge separated bus indices and remove internal spaces around brackets
		t = re.sub(r"\s+\[", "[", t)
		t = re.sub(r"\]\s+\[", "][", t)
		t = re.sub(r"\[\s+", "[", t)
		t = re.sub(r"\s+\]", "]", t)
		return t

	def collect_instance(all_lines, start_index):
		buf = []
		line = all_lines[start_index].strip()
		buf.append(line)
		balance = line.count("(") - line.count(")")
		j = start_index + 1
		while j < len(all_lines) and balance > 0:
			nl = all_lines[j].strip()
			buf.append(nl)
			balance += nl.count("(") - nl.count(")")
			j += 1
		full = " ".join(buf)
		return full, j

	def format_primitive(gtype: str, inst: str, full_text: str) -> str:
		# Prefer named pins if present
		ports = dict(re.findall(r"\.(\w+)\s*\(\s*([^\)]+)\s*\)", full_text))
		if ports:
			out = clean_signal(ports.get("Y", ""))
			ain = clean_signal(ports.get("A", ""))
			binp_raw = ports.get("B")
			if gtype in {"not", "buf"}:
				return f"    {gtype} {inst}({out}, {ain});"
			if binp_raw is not None:
				binp = clean_signal(binp_raw)
				return f"    {gtype} {inst}({out}, {ain}, {binp});"
			# Fallback to two-pin if B missing
			return f"    {gtype} {inst}({out}, {ain});"
		# No named ports; normalize positional pins and clean signals
		m = re.search(r"\((.*)\)", full_text)
		if m:
			raw_list = m.group(1)
			nets = [clean_signal(p.strip()) for p in raw_list.split(',')]
			return f"    {gtype} {inst}({', '.join(nets)});"
		# Fallback
		return re.sub(r"\s+", " ", full_text).strip()

	def format_dff(inst: str, full_text: str) -> str:
		ports = dict(re.findall(r"\.(\w+)\s*\(\s*([^\)]+)\s*\)", full_text))
		ordered = ["RN", "SN", "CK", "D", "Q"]
		parts = []
		for pin in ordered:
			if pin in ports:
				parts.append(f".{pin}({clean_signal(ports[pin])})")
		joined = ", ".join(parts)
		return f"    dff {inst}({joined});"

	lines = verilog_text.splitlines()
	out = []
	i = 0
	while i < len(lines):
		raw = lines[i]
		line = raw.strip()

		if not line:
			out.append(raw)
			i += 1
			continue

		if (line.startswith("module") or line.startswith("input") or line.startswith("output")
				or line.startswith("wire") or line.startswith("endmodule")):
			out.append(raw)
			i += 1
			continue

		if line.startswith("//") or line.startswith("defparam"):
			i += 1
			continue

		m = re.match(r"^\s*\\?\$?(\w+)\s+([^\s(]+)\s*\(", raw)
		if m:
			gtype = m.group(1).lower()
			inst = clean_cell_ident(m.group(2))
			full, next_i = collect_instance(lines, i)
			if gtype in primitive_types:
				out.append(format_primitive(gtype, inst, full))
			elif gtype == "dff" or "dff" in gtype:
				out.append(format_dff(inst, full))
			else:
				# For non-primitive cells, still normalize instance name formatting
				full_norm = re.sub(r"\s+", " ", full).strip()
				out.append(full_norm)
			i = next_i
			continue

		out.append(raw)
		i += 1

	result = "\n".join(out)
	# Remove up to 2 empty lines at the top of the file
	lines = result.split('\n')
	while len(lines) > 0 and lines[0].strip() == "" and len([l for l in lines[:2] if l.strip() == ""]) > 0:
		lines.pop(0)
		if len(lines) > 0 and lines[0].strip() == "":
			lines.pop(0)
			break
	return "\n".join(lines)


def synthesize(rtl_files, top, out_netlist, lib_path, map_path, script_path, show_progress=False):
	"""Main synthesis function"""

	os.makedirs(os.path.dirname(os.path.abspath(out_netlist)), exist_ok=True)

	with tempfile.TemporaryDirectory() as td:
		tmp_out = os.path.join(td, "netlist_tmp.v")
		
		# Run Yosys and capture output
		stdout, stderr = run_yosys(rtl_files, top, tmp_out, lib_path, map_path, script_path)
		
		with open(tmp_out, "r") as f:
			txt = f.read()
		
		# Analyze synthesis output for warnings (including assign statement check)
		warnings, gate_count = analyze_synthesis_output(stdout, stderr, txt, top)
		
		# Format the netlist to the requested style
		formatted_txt = post_process_netlist(txt)
		
		# Write final formatted netlist to requested output path
		with open(out_netlist, "w") as f:
			f.write(formatted_txt)
	
	if show_progress:
		print(f"Wrote synthesized netlist to {out_netlist}")
		if gate_count > 0:
			print(f"  Circuit size: {gate_count} gates")
	
	# Return success status and any warnings
	return True, warnings, gate_count


def prep_data(rtl_dir, netlist_out_dir, label_out_dir, count_start, lib_path, map_path, script_path, batch_mode=False):
	"""Prepare dataset by synthesizing each RTL file and generating labels.
	
	For each .v in rtl_dir (recursively, sorted):
	- Determine top name: basename without .v; if contains "_clean" or "_trojaned", strip that suffix for top.
	- Detect trojan type X by searching for module or instantiation of TrojanX.
	- Synthesize to netlist_out_dir/design{count}.v with sequential count starting at count_start.
	- Write label to label_out_dir/result{count}.txt per spec.
	"""
	
	if not os.path.isdir(rtl_dir):
		print(f"Error: RTL directory does not exist: {rtl_dir}", file=sys.stderr)
		sys.exit(1)
	
	os.makedirs(netlist_out_dir, exist_ok=True)
	os.makedirs(label_out_dir, exist_ok=True)
	
	# Collect files
	verilog_files = []
	for root, dirs, files in os.walk(rtl_dir):
		for fname in files:
			if fname.lower().endswith(".v"):
				verilog_files.append(os.path.join(root, fname))
	verilog_files.sort()
	
	if not verilog_files:
		print(f"No .v files found in {rtl_dir}")
		return
	
	# Use progress bar for synthesis
	progress_bar = tqdm(verilog_files, desc="Synthesizing", unit="file", 
						disable=not batch_mode, leave=True)
	
	count = count_start
	errors = []
	warnings_log = []
	large_circuits = []
	
	for vf in progress_bar:
		# Read file first to extract module name
		try:
			with open(vf, "r", encoding="utf-8", errors="ignore") as f:
				src = f.read()
		except Exception as e:
			error_msg = f"Warning: cannot read {vf}: {e}"
			errors.append(error_msg)
			if not batch_mode:
				print(error_msg, file=sys.stderr)
			src = ""
		
        # Remove the leading "trojan{x}_" from top
		top = os.path.splitext(os.path.basename(vf))[0]
		trojan_prefix_match = re.search(r'^trojan\d+_', top, re.IGNORECASE)
		if trojan_prefix_match:
			top = top[len(trojan_prefix_match.group(0)):]

		# Determine top per rule
		if "_clean" in top:
			top = top.replace("_clean", "")
			is_trojaned = False
		elif "_trojaned" in top:
			top = top.replace("_trojaned", "")
			is_trojaned = True
		else:
			raise ValueError(f"Unknown file: {vf}")

		# Detect trojan type X
		with open(vf, "r", encoding="utf-8", errors="ignore") as f:
			src = f.read()
		
		type_match = None
		m_mod = re.search(r"\bmodule\s+Trojan(\d+)\b", src)
		if m_mod:
			type_match = m_mod.group(1)
		
		trojan_type = type_match if is_trojaned else None
		
		# Paths
		out_netlist = os.path.join(netlist_out_dir, f"design{count}.v")
		label_path = os.path.join(label_out_dir, f"result{count}.txt")
		
		# Update progress bar description with current file
		if batch_mode:
			filename = os.path.basename(vf)
			progress_bar.set_description(f"Synthesizing {filename}")
		else:
			print(f"[{count}] Synthesizing {vf} (top={top}) -> {out_netlist}")
		
		try:
			success, warnings, gate_count = synthesize([vf], top, out_netlist, lib_path, map_path, script_path, show_progress=not batch_mode)
			success = success  # Use the variable to avoid Pylance warning
			
			# Handle warnings
			if warnings:
				warning_msg = f"{os.path.basename(vf)}: {', '.join(warnings)}"
				warnings_log.append(warning_msg)
				if batch_mode:
					progress_bar.write(f"⚠️  {warning_msg}")
				else:
					print(f"⚠️  Warning: {warning_msg}")
			
			# Track large circuits separately
			if gate_count > 60000:
				large_circuits.append(f"{os.path.basename(vf)}: {gate_count} gates")
			
		except Exception as e:
			# Special handling for timeout errors
			if "timeout" in str(e).lower() or "exceeded 8 seconds" in str(e):
				error_msg = f"Error synthesizing {vf}: Synthesis timeout (>8s) - circuit too complex"
			else:
				error_msg = f"Error synthesizing {vf}: {e}"
			
			errors.append(error_msg)
			if batch_mode:
				# Pause progress bar to show error
				progress_bar.write(error_msg)
			else:
				print(error_msg, file=sys.stderr)
			continue
		
		# Write label file
		with open(label_path, "w") as lf:
			if not is_trojaned:
				lf.write("NO_TROJAN\n")
			else:
				lf.write("TROJANED\n")
				lf.write(f"Trojan{trojan_type}\n")
		
		count += 1
	
	progress_bar.close()
	
	# Summary
	successful = count - count_start
	total = len(verilog_files)
	print(f"\nSynthesis completed: {successful}/{total} files successful")
	
	# Show warnings summary
	if warnings_log:
		print(f"\n⚠️  Warnings encountered ({len(warnings_log)} files):")
		for warning in warnings_log:
			print(f"  {warning}")
	
	# Show large circuits summary
	if large_circuits:
		print(f"\n🔍 Large circuits detected ({len(large_circuits)} files):")
		for large_circuit in large_circuits:
			print(f"  {large_circuit}")
	
	if errors:
		print(f"\nErrors encountered ({len(errors)} total):")
		for error in errors:
			print(f"  {error}")
	elif not warnings_log and not large_circuits:
		print("All files synthesized successfully with no warnings!")


def main():
	parser = argparse.ArgumentParser(description="Synthesize ICCAD Trojan circuits to gate-level netlists")
	parser.add_argument("--input", "-i", default=DEFAULT_RTL_DIR,
					   help=f"Input directory containing RTL files (default: {DEFAULT_RTL_DIR})")
	parser.add_argument("--output", "-o", default=DEFAULT_NETLIST_OUT_DIR,
					   help=f"Output directory for netlists (default: {DEFAULT_NETLIST_OUT_DIR})")
	parser.add_argument("--labels", "-l", default=DEFAULT_LABEL_OUT_DIR,
					   help=f"Output directory for labels (default: {DEFAULT_LABEL_OUT_DIR})")
	parser.add_argument("--count-start", "-c", type=int, default=DEFAULT_COUNT_START,
					   help=f"Starting index for design numbering (default: {DEFAULT_COUNT_START})")
	parser.add_argument("--lib", default=DEFAULT_LIB_PATH,
					   help=f"Path to liberty file (default: {DEFAULT_LIB_PATH})")
	parser.add_argument("--map", default=DEFAULT_MAP_PATH,
					   help=f"Path to techmap file (default: {DEFAULT_MAP_PATH})")
	parser.add_argument("--script", default=DEFAULT_SCRIPT_PATH,
					   help=f"Path for Yosys script (default: {DEFAULT_SCRIPT_PATH})")
	parser.add_argument("--batch", action="store_true", default=True,
					   help="Enable batch mode with progress bar (default: True)")
	parser.add_argument("--verbose", "-v", action="store_true",
					   help="Enable verbose mode with detailed output")
	
	args = parser.parse_args()
	
	# Override batch mode if verbose is requested
	batch_mode = args.batch and not args.verbose
	
	# Convert to absolute paths
	lib_path = os.path.abspath(args.lib)
	map_path = os.path.abspath(args.map)
	script_path = os.path.abspath(args.script)
	
	if not os.path.exists(lib_path):
		print(f"Error: Liberty file not found: {lib_path}", file=sys.stderr)
		sys.exit(1)
	
	if not os.path.exists(map_path):
		print(f"Error: Map file not found: {map_path}", file=sys.stderr)
		sys.exit(1)
	
	if args.verbose or not batch_mode:
		print(f"Synthesis Configuration:")
		print(f"  Input directory: {args.input}")
		print(f"  Output directory: {args.output}")
		print(f"  Labels directory: {args.labels}")
		print(f"  Count start: {args.count_start}")
		print(f"  Liberty file: {lib_path}")
		print(f"  Map file: {map_path}")
		print(f"  Script file: {script_path}")
		print(f"  Batch mode: {batch_mode}")
		print("")
	
	prep_data(args.input, args.output, args.labels, args.count_start, 
			 lib_path, map_path, script_path, batch_mode)


if __name__ == "__main__":
	main()