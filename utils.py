def extract_version(file_name):
    parts = file_name.split('-')
    if len(parts) > 2:
        version = parts[1]
        build = parts[2]
        return f"{version} ({build})"
    return "unknown"
