#!/usr/bin/env python3
"""
Synthesis Script for ICCAD Trojan Generation
Synthesizes generated circuits to gate-level netlists using Yosys+ABC.
Shows progress bar by default, displays error logs only when synthesis fails.

Usage:
# Generate clean gate-level circuits (with progress bar):
python3 syn.py --input generated_circuits/clean --output data/netlist/clean --labels data/label/clean --count-start 3001

# Generate trojan gate-level circuits (with progress bar):
python3 syn.py --input generated_circuits/trojan --output data/netlist/trojan --labels data/label/trojan --count-start 1001

# For detailed verbose output (no progress bar):
python3 syn.py --input generated_circuits/clean --output data/netlist/clean --labels data/label/clean --verbose

# For batch processing with progress tracking:
python3 syn.py --input generated_circuits/trojan --output data/netlist/trojan --labels data/label/trojan
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
DEFAULT_SCRIPT_PATH = "syn.ys"
DEFAULT_COUNT_START = 1
DEFAULT_RTL_DIR = "generated_circuits/clean"
DEFAULT_NETLIST_OUT_DIR = "data/netlist/clean"
DEFAULT_LABEL_OUT_DIR = "data/label/clean"
################### END DEFAULT CONFIG ###################


def run_yosys(rtl_files, top, out_tmp, lib_path, script_path):
	"""Run Yosys + ABC flow using the provided liberty for mapping only to cells in cell.lib."""

	# Yosys commands
	yosys_cmds = [
		f"read_liberty -lib {lib_path}",
		*[f"read_verilog -sv {f}" for f in rtl_files],
		f"hierarchy -check -top {top}",
		"proc; opt",
		"flatten",
		"techmap; opt",
		f"dfflibmap -liberty {lib_path}",
		"insbuf -buf buf A Y",          # Insert buffers to replace assign usage
		"opt_clean -purge",
		f"abc -liberty {lib_path} -fast",     # ABC combinational mapping/optimization
		"opt_merge; opt_clean; clean",
		f"stat -liberty {lib_path}",
		f"write_verilog -noattr -noexpr -nodec -defparam {out_tmp}",
	]
	
	# Write Yosys script
	script = "\n".join(yosys_cmds)
	with open(script_path, "w") as f:
		f.write(script)

	# Run Yosys script
	subprocess.run(["yosys", "-q", script_path], capture_output=True, text=True, check=True)


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

	def clean_ident(token: str) -> str:
		if token is None:
			return ""
		t = token.strip()
		# Remove a single leading escape backslash from Yosys, if present
		if t.startswith("\\"):
			t = t[1:].strip()
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
			out = clean_ident(ports.get("Y", ""))
			ain = clean_ident(ports.get("A", ""))
			binp_raw = ports.get("B")
			if gtype in {"not", "buf"}:
				return f"    {gtype} {inst}({out}, {ain});"
			if binp_raw is not None:
				binp = clean_ident(binp_raw)
				return f"    {gtype} {inst}({out}, {ain}, {binp});"
			# Fallback to two-pin if B missing
			return f"    {gtype} {inst}({out}, {ain});"
		# No named ports; assume positional already
		return re.sub(r"\s+", " ", full_text).strip()

	def format_dff(inst: str, full_text: str) -> str:
		ports = dict(re.findall(r"\.(\w+)\s*\(\s*([^\)]+)\s*\)", full_text))
		ordered = ["RN", "SN", "CK", "D", "Q"]
		parts = []
		for pin in ordered:
			if pin in ports:
				parts.append(f".{pin}({clean_ident(ports[pin])})")
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
			inst = clean_ident(m.group(2))
			full, next_i = collect_instance(lines, i)
			if gtype in primitive_types:
				out.append(format_primitive(gtype, inst, full))
			elif gtype == "dff" or "dff" in gtype:
				out.append(format_dff(inst, full))
			else:
				out.append(re.sub(r"\s+", " ", full).strip())
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


def synthesize(rtl_files, top, out_netlist, lib_path, script_path, show_progress=False):
	"""Main synthesis function"""

	os.makedirs(os.path.dirname(os.path.abspath(out_netlist)), exist_ok=True)

	with tempfile.TemporaryDirectory() as td:
		tmp_out = os.path.join(td, "netlist_tmp.v")
		
		# Run Yosys
		run_yosys(rtl_files, top, tmp_out, lib_path, script_path)
		
		with open(tmp_out, "r") as f:
			txt = f.read()
		
		# Format the netlist to the requested style
		formatted_txt = post_process_netlist(txt)
		
		# Write final formatted netlist to requested output path
		with open(out_netlist, "w") as f:
			f.write(formatted_txt)
	
	if show_progress:
		print(f"Wrote synthesized netlist to {out_netlist}")
	return True


def prep_data(rtl_dir, netlist_out_dir, label_out_dir, count_start, lib_path, script_path, batch_mode=False):
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
	for root, _dirs, files in os.walk(rtl_dir):
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
	
	for vf in progress_bar:
		base = os.path.splitext(os.path.basename(vf))[0]
		
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
		
		# Extract the actual top module name from the Verilog file
		top = None
		# Look for the first module declaration in the file
		module_match = re.search(r"^\s*module\s+(\w+)", src, re.MULTILINE)
		if module_match:
			top = module_match.group(1)
		else:
			# Fallback to filename-based logic
			if "_clean" in base:
				top = base.replace("_clean", "")
			elif "_trojaned" in base:
				top = base.replace("_trojaned", "")
			else:
				top = base
		
		type_match = None
		# Prefer explicit module definition
		m_mod = re.search(r"\bmodule\s+Trojan(\d+)\b", src)
		if m_mod:
			type_match = m_mod.group(1)
		else:
			# Fallback: instantiation like 'Trojan8 T8(' or 'Trojan12 u_t(' etc.
			m_inst = re.search(r"\bTrojan(\d+)\s+[A-Za-z_][\w$]*\s*\(", src)
			if m_inst:
				type_match = m_inst.group(1)
		
		is_trojaned = type_match is not None
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
			synthesize([vf], top, out_netlist, lib_path, script_path, show_progress=not batch_mode)
		except Exception as e:
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
	
	if errors:
		print(f"\nErrors encountered ({len(errors)} total):")
		for error in errors:
			print(f"  {error}")
	else:
		print("All files synthesized successfully!")


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
	script_path = os.path.abspath(args.script)
	
	if not os.path.exists(lib_path):
		print(f"Error: Liberty file not found: {lib_path}", file=sys.stderr)
		sys.exit(1)
	
	if args.verbose or not batch_mode:
		print(f"Synthesis Configuration:")
		print(f"  Input directory: {args.input}")
		print(f"  Output directory: {args.output}")
		print(f"  Labels directory: {args.labels}")
		print(f"  Count start: {args.count_start}")
		print(f"  Liberty file: {lib_path}")
		print(f"  Script file: {script_path}")
		print(f"  Batch mode: {batch_mode}")
		print("")
	
	prep_data(args.input, args.output, args.labels, args.count_start, 
			 lib_path, script_path, batch_mode)


if __name__ == "__main__":
	main()