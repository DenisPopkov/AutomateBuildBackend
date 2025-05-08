import os
import subprocess
import sys
from datetime import datetime

from flask import Flask, jsonify, request

app = Flask(__name__)


@app.route('/rebuild_dsp', methods=['POST'])
def rebuild_dsp():
    try:
        data = request.json
        branch_name = data.get('branchName')

        if not branch_name:
            return jsonify({"error": "Missing required parameter: branchName"}), 400

        git_bash_path = r"C:\Program Files\Git\bin\bash.exe"
        base_dir = r"C:\Users\BlackBricks\PycharmProjects\AutomateBuildBackend"
        working_dir = f"/{base_dir[0].lower()}{base_dir[2:].replace('\\', '/')}"
        script_path = f"{working_dir}/rebuild_dsp.sh"
        log_file = r"C:\Users\BlackBricks\AppData\Local\Temp\rebuild_dsp_log.txt"

        os.makedirs(os.path.dirname(log_file), exist_ok=True)

        with open(log_file, 'w') as f:
            f.write(f"Build started at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"Branch: {branch_name}\n\n")

        command = [
            git_bash_path,
            "-c",
            f"cd {working_dir} && "
            f"ERROR_LOG_FILE='/tmp/build_error_log.txt' "
            f"./rebuild_dsp.sh {branch_name}"
        ]

        with open(log_file, 'a') as log:
            process = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                universal_newlines=True
            )

            for line in process.stdout:
                sys.stdout.write(line)
                sys.stdout.flush()
                log.write(line)

            process.wait()

        if process.returncode != 0:
            with open(log_file, 'r') as f:
                log_content = f.read()
            raise subprocess.CalledProcessError(
                process.returncode,
                command,
                output=log_content
            )

        return jsonify({
            "status": "success",
            "message": f"macOS build for branch {branch_name} completed successfully",
            "log_file": log_file
        }), 200

    except subprocess.CalledProcessError as e:
        error_msg = f"Build failed with return code {e.returncode}"

        return jsonify({
            "status": "error",
            "message": error_msg,
            "return_code": e.returncode,
            "log_file": log_file,
            "output": e.output
        }), 500

    except Exception as e:
        error_msg = f"Unexpected error: {str(e)}"

        return jsonify({
            "status": "error",
            "message": error_msg,
            "log_file": log_file if 'log_file' in locals() else 'not created'
        }), 500


@app.route('/build_win', methods=['POST'])
def build_win():
    try:
        data = request.json
        branch_name = data.get('branchName')
        use_dev_analytics = data.get('isUseDevAnalytics', True)

        if not branch_name:
            return jsonify({"error": "Missing required parameter: branchName"}), 400

        git_bash_path = r"C:\Program Files\Git\bin\bash.exe"
        base_dir = r"C:\Users\BlackBricks\PycharmProjects\AutomateBuildBackend"
        working_dir = f"/{base_dir[0].lower()}{base_dir[2:].replace('\\', '/')}"
        script_path = f"{working_dir}/build_win.sh"
        log_file = r"C:\Users\BlackBricks\AppData\Local\Temp\build_win_log.txt"
        use_dev_analytics_flag = "true" if use_dev_analytics else "false"

        os.makedirs(os.path.dirname(log_file), exist_ok=True)

        with open(log_file, 'w') as f:
            f.write(f"Build started at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"Branch: {branch_name}\n")
            f.write(f"Dev Analytics: {use_dev_analytics_flag}\n\n")

        command = [
            git_bash_path,
            "-c",
            f"cd {working_dir} && "
            f"ERROR_LOG_FILE='/tmp/build_error_log.txt' "
            f"./build_win.sh {branch_name} {use_dev_analytics_flag}"
        ]

        with open(log_file, 'a') as log:
            process = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                universal_newlines=True
            )

            for line in process.stdout:
                sys.stdout.write(line)
                sys.stdout.flush()
                log.write(line)

            process.wait()

        if process.returncode != 0:
            with open(log_file, 'r') as f:
                log_content = f.read()
            raise subprocess.CalledProcessError(
                process.returncode,
                command,
                output=log_content
            )

        return jsonify({
            "status": "success",
            "message": f"Windows build for branch {branch_name} completed",
            "analytics": "dev" if use_dev_analytics else "prod",
            "log_file": log_file
        }), 200

    except subprocess.CalledProcessError as e:
        error_msg = f"Build failed with return code {e.returncode}"

        return jsonify({
            "status": "error",
            "message": error_msg,
            "return_code": e.returncode,
            "log_file": log_file,
            "output": e.output
        }), 500

    except Exception as e:
        error_msg = f"Unexpected error: {str(e)}"

        return jsonify({
            "status": "error",
            "message": error_msg,
            "log_file": log_file if 'log_file' in locals() else 'not created'
        }), 500


if __name__ == "__main__":
    app.run(debug=True, host='0.0.0.0', port=5002)
