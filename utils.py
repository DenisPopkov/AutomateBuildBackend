import re
import subprocess
import subprocess as sub


def extract_version(file_name):
    version_pattern = r"(\d+\.\d+\.\d+(\.\d+)?)-\[(\d+)\]"

    match = re.search(version_pattern, file_name)
    if match:
        version = match.group(1)  # The version part, e.g., "3.5.11"
        build = match.group(3)  # The build number inside parentheses, e.g., "321"
        return f"{version} ({build})"
    return "unknown"


def get_pid(process_name: str) -> list[int]:
    cmd = ['pgrep', '-f', process_name]

    with sub.Popen(cmd, stdout=sub.PIPE) as proc:
        result = proc.communicate()[0]

    result = result.decode().strip()

    if not result:
        raise ValueError(f"Process name {process_name} not found.")

    return list(map(int, result.splitlines()))


def kill_process(pid: int | str) -> bool:
    cmd = ['kill', str(pid)]
    with subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as proc:
        err = proc.communicate()[1]
    return bool(err)


def stop_process_by_name(process_name: str) -> str:
    try:
        pid = get_pid(process_name)
        if kill_process(pid):
            return f"Failed to stop process: {process_name}"
        return f"Process {process_name} stopped successfully"
    except ValueError as e:
        return str(e)
