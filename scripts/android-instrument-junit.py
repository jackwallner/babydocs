#!/usr/bin/env python3
"""Convert raw `am instrument -r` output files into one JUnit XML report.

Usage: android-instrument-junit.py OUT.xml RAW1.txt [RAW2.txt ...]
Each raw file is the output of one instrumentation run. A test counts as passed
only when its status block carries INSTRUMENTATION_STATUS_CODE: 0.
"""
import re
import sys
import xml.etree.ElementTree as ET


def parse(raw: str) -> list[dict]:
    results, block = [], {}
    for line in raw.splitlines():
        m = re.match(r"INSTRUMENTATION_STATUS: (\w+)=(.*)", line)
        if m:
            block[m.group(1)] = m.group(2)
            continue
        m = re.match(r"INSTRUMENTATION_STATUS_CODE: (-?\d+)", line)
        if m:
            if int(m.group(1)) != 1 and "test" in block:
                results.append({"cls": block.get("class", ""), "name": block["test"],
                                "code": int(m.group(1)), "stack": block.get("stack", "")})
            block = {}
    return results


def main() -> int:
    out, files = sys.argv[1], sys.argv[2:]
    cases = [r for f in files for r in parse(open(f, errors="replace").read())]
    failures = [c for c in cases if c["code"] != 0]
    suite = ET.Element("testsuite", name="SmokeTest", tests=str(len(cases)),
                       failures=str(len(failures)), errors="0", skipped="0")
    for c in cases:
        case = ET.SubElement(suite, "testcase", classname=c["cls"], name=c["name"])
        if c["code"] != 0:
            ET.SubElement(case, "failure", message=c["stack"].splitlines()[0] if c["stack"] else "failed").text = c["stack"]
    ET.ElementTree(suite).write(out, encoding="utf-8", xml_declaration=True)
    print(f"{len(cases)} tests, {len(failures)} failures -> {out}")
    return 0 if cases and not failures else 1


if __name__ == "__main__":
    sys.exit(main())
