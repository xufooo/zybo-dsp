# SPDX-License-Identifier: GPL-2.0-only


import os
import shutil
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OVERRIDE_DIR = os.path.join(ROOT, "rtl")

OVERRIDES = {
    "dsp_insert.v": "hdl/dsp_insert.v",
    "biquad_filter.v": "hdl/biquad_filter.v",
    "limiter.v": "hdl/limiter.v",
    "saturator.v": "hdl/saturator.v",
    "dsp_engine.v": "hdl/dsp_engine.v",
    "fir_bank.v": "hdl/fir_bank.v",
    "fir_bank_long.v": "hdl/fir_bank_long.v",

    "truepeak_limiter.v": "hdl/truepeak_limiter.v",
    "tp_log2.v": "hdl/tp_log2.v",
    "tp_exp2.v": "hdl/tp_exp2.v",
    "axi_i2s_adi_v1_2.vhd": "hdl/axi_i2s_adi_v1_2.vhd",
    "axi_i2s_adi_S_AXI.vhd": "hdl/axi_i2s_adi_S_AXI.vhd",
}

EXPECT_SIZE = {
    "dsp_insert.v": 6161,
    "biquad_filter.v": 2470,
    "limiter.v": 3282,
    "saturator.v": 666,

    "axi_i2s_adi_v1_2.vhd": 19949,

    "dsp_engine.v": 54918,
    "fir_bank.v": 6620,
    "fir_bank_long.v": 3795,

    "truepeak_limiter.v": 5492,
    "tp_log2.v": 7999,
    "tp_exp2.v": 8292,
    "axi_i2s_adi_S_AXI.vhd": 5553,
    "component.xml": 90977,
    "axi_i2s_adi_v1_2.tcl": 5508,
}

PORT_LITERAL_OLD = ('spirit:dependency="(spirit:decode(id(&apos;MODELPARAM_VALUE.'
                    'C_S00_AXI_ADDR_WIDTH&apos;)) - 1)">5</spirit:left>')
PORT_LITERAL_NEW = PORT_LITERAL_OLD.replace('">5<', '">6<')

VERILOG_FILES = ["hdl/dsp_insert.v", "hdl/biquad_filter.v",
                 "hdl/limiter.v", "hdl/saturator.v", "hdl/dsp_engine.v",

                 "hdl/fir_bank.v",
                 "hdl/fir_bank_long.v",
                 "hdl/truepeak_limiter.v", "hdl/tp_log2.v", "hdl/tp_exp2.v"]

FILE_BLOCK = """      <spirit:file>
        <spirit:name>{name}</spirit:name>
        <spirit:fileType>verilogSource</spirit:fileType>
      </spirit:file>
"""

PARAM_BLOCK = """    <spirit:parameter>
      <spirit:name>C_S00_AXI_ADDR_WIDTH</spirit:name>
      <spirit:displayName>AXI ADDR WIDTH</spirit:displayName>
      <spirit:value spirit:format="long" spirit:resolve="user" spirit:id="PARAM_VALUE.C_S00_AXI_ADDR_WIDTH" spirit:order="7">7</spirit:value>
    </spirit:parameter>
"""

TCL_ADDPARAM_ANCHOR = ('  ipgui::add_param $IPINST -name "C_HAS_RX" -parent ${Page_0} '
                       '-widget comboBox\n')
TCL_ADDPARAM_NEW = TCL_ADDPARAM_ANCHOR + \
    '  ipgui::add_param $IPINST -name "C_S00_AXI_ADDR_WIDTH" -parent ${Page_0}\n'

TCL_PROCS = '''
proc update_PARAM_VALUE.C_S00_AXI_ADDR_WIDTH { PARAM_VALUE.C_S00_AXI_ADDR_WIDTH } {
\t# Procedure called to update C_S00_AXI_ADDR_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_S00_AXI_ADDR_WIDTH { PARAM_VALUE.C_S00_AXI_ADDR_WIDTH } {
\t# Procedure called to validate C_S00_AXI_ADDR_WIDTH
\treturn true
}

proc update_MODELPARAM_VALUE.C_S00_AXI_ADDR_WIDTH { MODELPARAM_VALUE.C_S00_AXI_ADDR_WIDTH PARAM_VALUE.C_S00_AXI_ADDR_WIDTH } {
\t# Pass the user parameter through to the VHDL generic: without this, CONFIG.C_S00_AXI_ADDR_WIDTH has no effect in the BD
\tset_property value [get_property value ${PARAM_VALUE.C_S00_AXI_ADDR_WIDTH}] ${MODELPARAM_VALUE.C_S00_AXI_ADDR_WIDTH}
}

proc update_PARAM_VALUE.C_S00_AXI_BASEADDR { PARAM_VALUE.C_S00_AXI_BASEADDR } {'''
TCL_PROCS_ANCHOR = ('\nproc update_PARAM_VALUE.C_S00_AXI_BASEADDR '
                    '{ PARAM_VALUE.C_S00_AXI_BASEADDR } {')

def patch_xml(path, *, check):
    src = open(path, encoding="utf-8").read()
    problems = []

    n_old = src.count(PORT_LITERAL_OLD)
    n_new = src.count(PORT_LITERAL_NEW)
    if n_old == 2:
        if not check:
            src = src.replace(PORT_LITERAL_OLD, PORT_LITERAL_NEW)
    elif n_new == 2:
        pass
    else:
        problems.append(f"unexpected port width literal count: old {n_old} / new {n_new} (neither is 2)")

    MODEL_OLD = '<spirit:value spirit:format="long" spirit:resolve="immediate" spirit:id="MODELPARAM_VALUE.C_S00_AXI_ADDR_WIDTH" spirit:order="4" spirit:rangeType="long">6</spirit:value>'
    MODEL_NEW = MODEL_OLD.replace('>6<', '>7<')
    if MODEL_OLD in src:
        if not check:
            src = src.replace(MODEL_OLD, MODEL_NEW, 1)
    elif MODEL_NEW not in src:
        problems.append("the C_S00_AXI_ADDR_WIDTH modelParameter value was not found")

    if 'spirit:id="PARAM_VALUE.C_S00_AXI_ADDR_WIDTH"' not in src:

        anchor = "  <spirit:parameters>\n    <spirit:parameter>\n      <spirit:name>C_S00_AXI_BASEADDR</spirit:name>"
        if anchor not in src:
            problems.append("the top-level <spirit:parameters> insertion point was not found")
        elif not check:
            src = src.replace(
                anchor,
                "  <spirit:parameters>\n" + PARAM_BLOCK +
                "    <spirit:parameter>\n      <spirit:name>C_S00_AXI_BASEADDR</spirit:name>",
                1)

    missing = [f for f in VERILOG_FILES if f not in src]
    if missing:
        block = "".join(FILE_BLOCK.format(name=f) for f in missing)

        parts = src.split("    </spirit:fileSet>")
        touched = 0
        for i, part in enumerate(parts):
            if (("hdl/dsp_insert.v" in part) or ("hdl/axi_i2s_adi_S_AXI.vhd" in part)) and (missing[-1] not in part):
                parts[i] = part + block
                touched += 1
        if touched == 0:
            problems.append("no fileSet to backfill (no fileSet holding our Verilog, and no insertion point)")
        else:
            src = "    </spirit:fileSet>".join(parts)

    if problems:
        return problems
    if not check:
        open(path, "w", encoding="utf-8").write(src)
    return []

def patch_tcl(path, *, check):
    src = open(path, encoding="utf-8").read()
    problems = []

    if 'add_param $IPINST -name "C_S00_AXI_ADDR_WIDTH"' not in src:
        if TCL_ADDPARAM_ANCHOR not in src:
            problems.append("the add_param insertion point for C_HAS_RX was not found in the tcl")
        elif not check:
            src = src.replace(TCL_ADDPARAM_ANCHOR, TCL_ADDPARAM_NEW, 1)

    if "update_MODELPARAM_VALUE.C_S00_AXI_ADDR_WIDTH" not in src:
        if TCL_PROCS_ANCHOR not in src:
            problems.append("the update_PARAM_VALUE block insertion point was not found in the tcl")
        elif not check:
            src = src.replace(TCL_PROCS_ANCHOR, TCL_PROCS, 1)

    if problems:
        return problems
    if not check:
        open(path, "w", encoding="utf-8").write(src)
    return []

def copy_overrides(ip_dir, *, check):
    problems = []
    if not os.path.isdir(OVERRIDE_DIR):
        return [f"the hdl override directory {OVERRIDE_DIR} is missing"]
    for name, rel in OVERRIDES.items():
        s = os.path.join(OVERRIDE_DIR, name)
        if not os.path.isfile(s):
            problems.append(f"the override layer is missing the file: {name}")
            continue
        want = EXPECT_SIZE.get(name)
        got = os.path.getsize(s)
        if want and got != want:
            problems.append(f"{name} size {got} ≠ fingerprint {want} (has the override layer been modified?)")
        if not check:
            dst = os.path.join(ip_dir, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(s, dst)
    return problems

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    ip_dir = os.path.abspath(sys.argv[1])
    check = "--check" in sys.argv

    if not os.path.isfile(os.path.join(ip_dir, "component.xml")):
        print(f"✗ {ip_dir} has no component.xml (fetch the pristine upstream first)")
        return 1

    problems = []
    problems += patch_xml(os.path.join(ip_dir, "component.xml"), check=check)
    tcls = [f for f in os.listdir(os.path.join(ip_dir, "xgui"))
            if f.endswith(".tcl")] if os.path.isdir(os.path.join(ip_dir, "xgui")) else []
    if not tcls:
        problems.append("there is no tcl under xgui/")
    for t in tcls:
        problems += patch_tcl(os.path.join(ip_dir, "xgui", t), check=check)
    problems += copy_overrides(ip_dir, check=check)

    if not check and not problems:
        for name in ("dsp_insert.v", "biquad_filter.v", "limiter.v", "saturator.v",
                     "dsp_engine.v", "truepeak_limiter.v", "tp_log2.v", "tp_exp2.v",
                     "axi_i2s_adi_v1_2.vhd", "axi_i2s_adi_S_AXI.vhd"):
            p = os.path.join(ip_dir, "hdl", name)
            want = EXPECT_SIZE[name]
            if not os.path.isfile(p):
                problems.append(f"missing file hdl/{name}")
            elif os.path.getsize(p) != want:
                problems.append(f"hdl/{name} is {os.path.getsize(p)} bytes ≠ fingerprint {want}")

        xml = open(os.path.join(ip_dir, "component.xml"), encoding="utf-8").read()
        for needle, desc in (
            ('spirit:id="PARAM_VALUE.C_S00_AXI_ADDR_WIDTH"', "the C_S00_AXI_ADDR_WIDTH user parameter"),
            ('spirit:id="MODELPARAM_VALUE.C_S00_AXI_ADDR_WIDTH" spirit:order="4" spirit:rangeType="long">7<', "modelParameter value = 7"),
            ('">6</spirit:left>', "the port width cache literal 6"),
            ("hdl/dsp_insert.v", "the dsp_insert.v file entry"),
            ("hdl/limiter.v", "the limiter.v file entry"),
        ):
            if needle not in xml:
                problems.append(f"component.xml is missing {desc}")

        tcl_path = os.path.join(ip_dir, "xgui", tcls[0])
        tcl = open(tcl_path, encoding="utf-8").read()
        for needle, desc in (
            ('add_param $IPINST -name "C_S00_AXI_ADDR_WIDTH"', "add_param"),
            ("update_MODELPARAM_VALUE.C_S00_AXI_ADDR_WIDTH", "the modelparam pass-through"),
        ):
            if needle not in tcl:
                problems.append(f"xgui is missing {desc}")

    if problems:
        print("✗ patching failed:")
        for p in problems:
            print("   -", p)
        return 1
    print("✓ IP patch complete" + (" (verify only)" if check else "") +
          ": the C_S00_AXI_ADDR_WIDTH user parameter + 4 Verilog files + 2 modified VHDL files")
    return 0

if __name__ == "__main__":
    sys.exit(main())
