def extract_version(file_name):
    parts = file_name.split('_')
    if len(parts) > 1:
        version_part = parts[1].split('.')[0:3]
        return '.'.join(version_part)
    return "unknown"
