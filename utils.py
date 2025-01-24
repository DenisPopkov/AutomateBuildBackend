import re


def extract_version(file_name):
    version_pattern = r"(\d+\.\d+\.\d+(\.\d+)?)-\[(\d+)\]"

    match = re.search(version_pattern, file_name)
    if match:
        version = match.group(1)  # The version part, e.g., "3.5.11"
        build = match.group(3)  # The build number inside parentheses, e.g., "321"
        return f"{version} ({build})"
    return "unknown"
