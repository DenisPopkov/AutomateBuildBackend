import os
import shutil
import sys
import xml.etree.ElementTree as ET

if len(sys.argv) < 2:
    print("[ERROR] Usage: python clean_aip_app_runtime.py <path_to_aip>")
    sys.exit(1)

aip_path = sys.argv[1]
if not os.path.isfile(aip_path):
    print(f"[ERROR] File not found: {aip_path}")
    sys.exit(1)

backup_path = aip_path + ".bak"
shutil.copy2(aip_path, backup_path)
print(f"[INFO] Backup saved to {backup_path}")

tree = ET.parse(aip_path)
root = tree.getroot()

keywords = ["app", "runtime"]
deleted = 0


def should_delete(row_elem):
    for attr in row_elem.attrib.values():
        if any(k in attr for k in keywords):
            return True
    for child in row_elem:
        if any(k in (child.text or '') for k in keywords):
            return True
    return False


for comp in root.findall(".//COMPONENT"):
    rows = comp.findall("ROW")
    for row in rows:
        if should_delete(row):
            comp.remove(row)
            deleted += 1

print(f"[INFO] Deleted {deleted} <ROW> elements containing 'app' or 'runtime'.")
tree.write(aip_path, encoding="utf-8", xml_declaration=True)
print(f"[INFO] Cleaned .aip saved to {aip_path}")
