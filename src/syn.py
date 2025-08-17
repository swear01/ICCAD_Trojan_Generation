import os
import re
import subprocess
import sys
import tempfile

##################### CONFIG #####################
LIB_PATH = "cell.lib"
SCRIPT_PATH = "syn.ys"

COUNT_START = 2031            # configure this to the desired starting index of the netlists
RTL_DIR = "rtl/clean"    # configure this to the directory containing the RTL files
NETLIST_OUT_DIR = "data/netlist"
LABEL_OUT_DIR = "data/label"
################### END CONFIG ###################


def run_yosys(rtl_files, top, out_tmp):
	"""Run Yosys + ABC flow using the provided liberty for mapping only to cells in cell.lib."""

	# Yosys commands
	yosys_cmds = [
		f"read_liberty -lib {LIB_PATH}",
		*[f"read_verilog -sv {f}" for f in rtl_files],
		f"hierarchy -check -top {top}",
		"proc; opt",
		"flatten",
		"techmap; opt",
		f"dfflibmap -liberty {LIB_PATH}",
		"insbuf -buf buf A Y",          # Insert buffers to replace assign usage
		"opt_clean -purge",
		f"abc -liberty {LIB_PATH} -fast",     # ABC combinational mapping/optimization
		"opt_merge; opt_clean; clean",
		f"stat -liberty {LIB_PATH}",
		f"write_verilog -noattr -noexpr -nodec -defparam {out_tmp}",
	]
	
	# Write Yosys script
	script = "\n".join(yosys_cmds)
	with open(SCRIPT_PATH, "w") as f:
		f.write(script)

	# Run Yosys script
	subprocess.run(["yosys", "-q", SCRIPT_PATH], capture_output=True, text=True, check=True)


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


def synthesize(rtl_files, top, out_netlist):
	"""Main synthesis function"""

	os.makedirs(os.path.dirname(os.path.abspath(out_netlist)), exist_ok=True)

	with tempfile.TemporaryDirectory() as td:
		tmp_out = os.path.join(td, "netlist_tmp.v")
		
		# Run Yosys
		run_yosys(rtl_files, top, tmp_out)
		
		with open(tmp_out, "r") as f:
			txt = f.read()
		
		# Format the netlist to the requested style
		formatted_txt = post_process_netlist(txt)
		
		# Write final formatted netlist to requested output path
		with open(out_netlist, "w") as f:
			f.write(formatted_txt)
	
	print(f"Wrote synthesized netlist to {out_netlist}")
	return True


def prep_data():
	"""Prepare dataset by synthesizing each RTL file and generating labels.
	
	For each .v in RTL_DIR (recursively, sorted):
	- Determine top name: basename without .v; if contains "_clean", strip that suffix for top.
	- Detect trojan type X by searching for module or instantiation of TrojanX.
	- Synthesize to NETLIST_OUT_DIR/design{count}.v with sequential count starting at COUNT_START.
	- Write label to LABEL_OUT_DIR/result{count}.txt per spec.
	"""
	
	if not os.path.isdir(RTL_DIR):
		print(f"Error: RTL_DIR does not exist: {RTL_DIR}", file=sys.stderr)
		sys.exit(1)
	
	os.makedirs(NETLIST_OUT_DIR, exist_ok=True)
	os.makedirs(LABEL_OUT_DIR, exist_ok=True)
	
	# Collect files
	verilog_files = []
	for root, _dirs, files in os.walk(RTL_DIR):
		for fname in files:
			if fname.lower().endswith(".v"):
				verilog_files.append(os.path.join(root, fname))
	verilog_files.sort()
	
	if not verilog_files:
		print(f"No .v files found in {RTL_DIR}")
		return
	
	count = COUNT_START
	for vf in verilog_files:
		base = os.path.splitext(os.path.basename(vf))[0]
		# Determine top per rule
		if "_clean" in base:
			top = base.replace("_clean", "")
		else:
			top = base
		
		# Detect trojan type X
		try:
			with open(vf, "r", encoding="utf-8", errors="ignore") as f:
				src = f.read()
		except Exception as e:
			print(f"Warning: cannot read {vf}: {e}", file=sys.stderr)
			src = ""
		
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
		out_netlist = os.path.join(NETLIST_OUT_DIR, f"design{count}.v")
		label_path = os.path.join(LABEL_OUT_DIR, f"result{count}.txt")
		
		print(f"[{count}] Synthesizing {vf} (top={top}) -> {out_netlist}")
		synthesize([vf], top, out_netlist)
		
		# Write label file
		with open(label_path, "w") as lf:
			if not is_trojaned:
				lf.write("NO_TROJAN\n")
			else:
				lf.write("TROJANED\n")
				lf.write(f"Trojan{trojan_type}\n")
		
		count += 1
	
	print(f"Prepared {len(verilog_files)} design(s) into {NETLIST_OUT_DIR} and {LABEL_OUT_DIR}")


if __name__ == "__main__":
	prep_data()