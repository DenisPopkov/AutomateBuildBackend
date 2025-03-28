import os
import subprocess
import sys

from flask import Flask, jsonify, request

app = Flask(__name__)


@app.route('/build_mac', methods=['POST'])
def build_mac():
    try:
        secret_file_path = "/Users/denispopkov/Desktop/secret.txt"
        secret_config = read_secret_file(secret_file_path)

        data = request.json
        branch_name = data.get('branchName')
        use_dev_analytics = data.get('isUseDevAnalytics', True)

        script_path = "./build_mac_signed.sh"
        log_file = "/tmp/build_error_log.txt"
        use_dev_analytics_flag = "true" if use_dev_analytics else "false"

        # Clear any previous log file
        with open(log_file, "w"):
            pass

        # Open the log file and execute the script
        with open(log_file, "w") as log:
            process = subprocess.Popen(
                ["sh", script_path, branch_name, use_dev_analytics_flag],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,  # Capture stderr as well
                text=True
            )

            # Read output and error streams
            for line in process.stdout:
                sys.stdout.write(line)
                sys.stdout.flush()
                log.write(line)

            for line in process.stderr:
                sys.stderr.write(line)
                sys.stderr.flush()
                log.write(line)

            process.wait()

            # Check for any errors in the process
            if process.returncode != 0:
                post_error_message(branch_name, secret_config)
                raise subprocess.CalledProcessError(process.returncode, script_path, output=line)

        return jsonify({
            "message": f"macOS build for branch {branch_name} signing executed successfully!"
        }), 200

    except subprocess.CalledProcessError:
        return jsonify({"error": "Build script failed. Check Slack for full logs."}), 500
    except Exception as e:
        return jsonify({"error": f"An unexpected error occurred: {str(e)}"}), 500


@app.route('/rebuild_dsp', methods=['POST'])
def rebuild_dsp():
    try:
        secret_file_path = "/Users/denispopkov/Desktop/secret.txt"
        secret_config = read_secret_file(secret_file_path)

        data = request.json
        branch_name = data.get('branchName')

        script_path = "./rebuild_dsp.sh"
        log_file = "/tmp/build_error_log.txt"

        # Clear any previous log file
        with open(log_file, "w"):
            pass

        # Open the log file and execute the script
        with open(log_file, "w") as log:
            process = subprocess.Popen(
                ["sh", script_path, branch_name],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,  # Capture stderr as well
                text=True
            )

            # Read and log both stdout and stderr streams
            for line in process.stdout:
                sys.stdout.write(line)
                sys.stdout.flush()
                log.write(line)

            for line in process.stderr:
                sys.stderr.write(line)
                sys.stderr.flush()
                log.write(line)

            process.wait()

            # Check if the script execution was successful
            if process.returncode != 0:
                post_error_message(branch_name, secret_config)
                raise subprocess.CalledProcessError(process.returncode, script_path)

        return jsonify({
            "message": f"macOS build for branch {branch_name} signing executed successfully!"
        }), 200

    except subprocess.CalledProcessError:
        return jsonify({"error": "Build script failed. Check Slack for full logs."}), 500
    except Exception as e:
        return jsonify({"error": f"An unexpected error occurred: {str(e)}"}), 500


@app.route('/rebuild_android_dsp', methods=['POST'])
def rebuild_android_dsp():
    try:
        secret_file_path = "/Users/denispopkov/Desktop/secret.txt"
        secret_config = read_secret_file(secret_file_path)

        data = request.json
        branch_name = data.get('branchName')

        script_path = "./rebuild_android_dsp.sh"
        log_file = "/tmp/build_error_log.txt"

        # Clear any previous log file
        with open(log_file, "w"):
            pass

        # Open the log file and execute the script
        with open(log_file, "w") as log:
            process = subprocess.Popen(
                ["sh", script_path, branch_name],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,  # Capture stderr as well
                text=True
            )

            # Read and log both stdout and stderr streams
            for line in process.stdout:
                sys.stdout.write(line)
                sys.stdout.flush()
                log.write(line)

            for line in process.stderr:
                sys.stderr.write(line)
                sys.stderr.flush()
                log.write(line)

            process.wait()

            # Check if the script execution was successful
            if process.returncode != 0:
                post_error_message(branch_name, secret_config)
                raise subprocess.CalledProcessError(process.returncode, script_path)

        return jsonify({
            "message": f"macOS build for branch {branch_name} signing executed successfully!"
        }), 200

    except subprocess.CalledProcessError:
        return jsonify({"error": "Build script failed. Check Slack for full logs."}), 500
    except Exception as e:
        return jsonify({"error": f"An unexpected error occurred: {str(e)}"}), 500


@app.route('/build_win', methods=['POST'])
def build_win():
    try:
        secret_file_path = "/Users/denispopkov/Desktop/secret.txt"
        secret_config = read_secret_file(secret_file_path)

        data = request.json
        branch_name = data.get('branchName')
        log_file = "/tmp/build_error_log.txt"
        use_dev_analytics = data.get('isUseDevAnalytics', True)

        if not branch_name:
            print("Error: Missing required parameter: branchName")
            return jsonify({"error": "Missing required parameter: branchName"}), 400

        script_path = ".\\build_win.ps1"
        use_dev_analytics_flag = "true" if use_dev_analytics else "false"

        os.chdir("C:\\Users\\BlackBricks\\PycharmProjects\\AutomateBuildBackend")

        # Construct PowerShell command
        command = [
            "powershell", "-ExecutionPolicy", "Bypass", "-File", script_path,
            "-BRANCH_NAME", branch_name,
            "-USE_DEV_ANALYTICS", use_dev_analytics_flag
        ]

        # Capture logs and errors using subprocess
        with open(log_file, "w") as log:
            process = subprocess.Popen(
                command,  # Running PowerShell script
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,  # Capture both stdout and stderr
                text=True
            )

            # Capture and write stdout and stderr to both console and log file
            for line in process.stdout:
                sys.stdout.write(line)
                sys.stdout.flush()
                log.write(line)

            for line in process.stderr:
                sys.stderr.write(line)
                sys.stderr.flush()
                log.write(line)

            process.wait()

        # If the process fails (non-zero exit code), send error message
        if process.returncode != 0:
            post_error_message(branch_name, secret_config)
            raise subprocess.CalledProcessError(process.returncode, script_path)

        return jsonify({
            "message": f"Windows build for branch {branch_name} executed successfully!"
        }), 200

    except subprocess.CalledProcessError as e:
        return jsonify({"error": f"Build failed: {e}"}), 500
    except Exception as e:
        return jsonify({"error": f"Unexpected error: {str(e)}"}), 500


@app.route('/build_android', methods=['POST'])
def build_android():
    try:
        secret_file_path = "/Users/denispopkov/Desktop/secret.txt"
        secret_config = read_secret_file(secret_file_path)

        data = request.json
        branch_name = data.get('branchName')
        use_dev_analytics = data.get('isUseDevAnalytics', True)

        if not branch_name:
            return jsonify({"error": "Missing required parameter: branchName"}), 400

        script_path = "./build_android.sh"
        log_file = "/tmp/build_error_log.txt"

        # Set the flags based on the 'use_dev_analytics' parameter
        is_bundle_to_build_flag = "false" if use_dev_analytics else "true"
        use_dev_analytics_flag = "true" if use_dev_analytics else "false"

        # Clear any previous log file
        with open(log_file, "w"):
            pass

        # Open log file and execute the script
        with open(log_file, "w") as log:
            process = subprocess.Popen(
                ["sh", script_path, branch_name, is_bundle_to_build_flag, use_dev_analytics_flag],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,  # Capture stderr explicitly
                text=True
            )

            # Capture and log both stdout and stderr
            for line in process.stdout:
                sys.stdout.write(line)
                sys.stdout.flush()
                log.write(line)

            for line in process.stderr:
                sys.stderr.write(line)
                sys.stderr.flush()
                log.write(line)

            process.wait()

        # Check for any errors in the process return code
        if process.returncode != 0:
            post_error_message(branch_name, secret_config)
            raise subprocess.CalledProcessError(process.returncode, script_path)

        return jsonify({
            "message": f"Android build for branch {branch_name} executed successfully!"
        }), 200

    except subprocess.CalledProcessError:
        return jsonify({"error": "Build script failed. Check Slack for full logs."}), 500
    except Exception as e:
        return jsonify({"error": f"Unexpected error: {str(e)}"}), 500


@app.route('/build_ios', methods=['POST'])
def build_ios():
    try:
        secret_file_path = "/Users/denispopkov/Desktop/secret.txt"
        secret_config = read_secret_file(secret_file_path)

        data = request.json
        branch_name = data.get('branchName')
        use_dev_analytics = data.get('isUseDevAnalytics', True)

        if not branch_name:
            return jsonify({"error": "Missing required parameter: branchName"}), 400

        script_path = "./build_ios.sh"
        log_file = "/tmp/build_error_log.txt"
        use_dev_analytics_flag = "true" if use_dev_analytics else "false"

        # Clear any previous log file
        with open(log_file, "w"):
            pass

        # Open log file and execute the script
        with open(log_file, "w") as log:
            process = subprocess.Popen(
                ["sh", script_path, branch_name, use_dev_analytics_flag],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,  # Explicitly capture stderr as well
                text=True
            )

            # Capture and log both stdout and stderr
            for line in process.stdout:
                sys.stdout.write(line)
                sys.stdout.flush()
                log.write(line)

            for line in process.stderr:
                sys.stderr.write(line)
                sys.stderr.flush()
                log.write(line)

            process.wait()

        # If the process fails (non-zero exit code), send error message
        if process.returncode != 0:
            post_error_message(branch_name, secret_config)
            raise subprocess.CalledProcessError(process.returncode, script_path)

        return jsonify({"message": f"iOS build for branch {branch_name} executed successfully!"}), 200

    except subprocess.CalledProcessError:
        return jsonify({"error": "Build script failed. Check Slack for full logs."}), 500
    except Exception as e:
        return jsonify({"error": f"Unexpected error: {str(e)}"}), 500


@app.route('/remote_branches', methods=['GET'])
def get_remote_branches():
    try:
        repo_path = "/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform"
        if not os.path.exists(repo_path):
            return jsonify({"error": f"The repository does not exist at {repo_path}"}), 404

        subprocess.run(["git", "-C", repo_path, "fetch", "--all"], check=True)

        result = subprocess.run(
            ["git", "-C", repo_path, "for-each-ref", "--sort=-committerdate", "--format=%(refname:short)",
             "refs/remotes/origin/"],
            check=True,
            stdout=subprocess.PIPE,
            text=True
        )

        branches = result.stdout.strip().split("\n")
        branch_names = [branch.replace("origin/", "") for branch in branches]

        prioritized_branches = ["develop", "soundcheck_develop"]
        sorted_branches = [b for b in prioritized_branches if b in branch_names] + [b for b in branch_names if
                                                                                    b not in prioritized_branches]

        return jsonify({"branches": sorted_branches}), 200

    except subprocess.CalledProcessError as e:
        return jsonify({"error": f"Failed to fetch branches: {str(e)}"}), 500
    except Exception as e:
        return jsonify({"error": str(e)}), 500


def read_secret_file(secret_file_path):
    config = {}
    try:
        with open(secret_file_path, 'r') as secret_file:
            for line in secret_file:
                key, value = line.strip().split('=', 1)
                config[key.strip()] = value.strip()
    except Exception as e:
        print(f"Error reading secret file: {e}")
    return config


def post_error_message(branch_name, secret_config):
    try:
        SLACK_BOT_TOKEN = secret_config.get("SLACK_BOT_TOKEN")
        SLACK_CHANNEL = secret_config.get("SLACK_CHANNEL")
        ERROR_LOG_FILE = "/tmp/build_error_log.txt"

        message = f":x: Failed to update DSP library on `{branch_name}`"

        subprocess.run(
            ["/bin/bash", "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/slack_upload.sh",
             SLACK_BOT_TOKEN, SLACK_CHANNEL, message, "upload", ERROR_LOG_FILE],
            check=True
        )
    except subprocess.CalledProcessError as e:
        print(f"Error sending error message to Slack: {e}")
    except Exception as e:
        print(f"Error in post_error_message: {e}")


if __name__ == "__main__":
    app.run(debug=True, host='0.0.0.0', port=5001)
