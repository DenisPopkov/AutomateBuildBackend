import os
import subprocess
import sys

from flask import Flask, jsonify, request

app = Flask(__name__)


@app.route('/build_mac', methods=['POST'])
def build_mac():
    try:
        data = request.json
        branch_name = data.get('branchName')
        use_dev_analytics = data.get('isUseDevAnalytics', True)

        script_path = "./build_mac_signed.sh"
        log_file = "/tmp/build_error_log.txt"
        use_dev_analytics_flag = "true" if use_dev_analytics else "false"

        with open(log_file, "w"):
            pass

        with open(log_file, "w") as log:
            process = subprocess.Popen(
                ["sh", script_path, branch_name, use_dev_analytics_flag],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True
            )

            for line in process.stdout:
                sys.stdout.write(line)
                sys.stdout.flush()
                log.write(line)

            process.wait()

        if process.returncode != 0:
            raise subprocess.CalledProcessError(process.returncode, script_path)

        return jsonify({
            "message": f"macOS build for branch {branch_name} signing executed successfully!"
        }), 200

    except subprocess.CalledProcessError:
        return jsonify({"error": "Build script failed. Check Slack for full logs."}), 500
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route('/rebuild_dsp', methods=['POST'])
def rebuild_dsp():
    try:
        data = request.json
        branch_name = data.get('branchName')

        script_path = "./rebuild_dsp.sh"
        log_file = "/tmp/build_error_log.txt"

        with open(log_file, "w"):
            pass

        with open(log_file, "w") as log:
            process = subprocess.Popen(
                ["sh", script_path, branch_name],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True
            )

            for line in process.stdout:
                sys.stdout.write(line)
                sys.stdout.flush()
                log.write(line)

            process.wait()

        if process.returncode != 0:
            raise subprocess.CalledProcessError(process.returncode, script_path)

        return jsonify({
            "message": f"macOS build for branch {branch_name} signing executed successfully!"
        }), 200

    except subprocess.CalledProcessError:
        return jsonify({"error": "Build script failed. Check Slack for full logs."}), 500
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route('/rebuild_windows_dsp', methods=['POST'])
def rebuild_windows_dsp():
    try:
        data = request.json
        branch_name = data.get('branchName')

        script_path = "./rebuild_windows_dsp.sh"

        process = subprocess.Popen(
            ["sh", script_path, branch_name],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True
        )

        if process.returncode != 0:
            raise subprocess.CalledProcessError(process.returncode, script_path)

        return jsonify({
            "message": f"macOS build for branch {branch_name} signing executed successfully!"
        }), 200

    except subprocess.CalledProcessError:
        return jsonify({"error": "Build script failed. Check Slack for full logs."}), 500
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route('/rebuild_android_dsp', methods=['POST'])
def rebuild_android_dsp():
    try:
        data = request.json
        branch_name = data.get('branchName')

        script_path = "./rebuild_android_dsp.sh"
        log_file = "/tmp/build_error_log.txt"

        with open(log_file, "w"):
            pass

        with open(log_file, "w") as log:
            process = subprocess.Popen(
                ["sh", script_path, branch_name],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                errors="replace"
            )

            for line in process.stdout:
                sys.stdout.write(line)
                sys.stdout.flush()
                log.write(line)

            process.wait()

        if process.returncode != 0:
            with open(log_file, "r") as log:
                error_logs = log.read()
            return jsonify({
                "error": "Build script failed. Check Slack for full logs.",
                "logs": error_logs[-500:]  # Return last 500 chars of logs for debugging
            }), 500

        return jsonify({
            "message": f"macOS build for branch {branch_name} signing executed successfully!"
        }), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route('/build_win', methods=['POST'])
def build_win():
    try:
        data = request.json
        branch_name = data.get('branchName')
        use_dev_analytics = data.get('isUseDevAnalytics', True)

        if not branch_name:
            return jsonify({"error": "Missing required parameter: branchName"}), 400

        script_path = "./build_win.sh"
        use_dev_analytics_flag = "true" if use_dev_analytics else "false"

        process = subprocess.Popen(
            ["sh", script_path, branch_name, use_dev_analytics_flag],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True
        )

        if process.returncode != 0:
            raise subprocess.CalledProcessError(process.returncode, script_path)

        return jsonify({
            "message": f"Windows build executed successfully!"
        }), 200

    except subprocess.CalledProcessError:
        return jsonify({"error": "Build script failed. Check Slack for full logs."}), 500
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route('/build_android', methods=['POST'])
def build_android():
    try:
        data = request.json
        branch_name = data.get('branchName')
        use_dev_analytics = data.get('isUseDevAnalytics', True)

        if not branch_name:
            return jsonify({"error": "Missing required parameter: branchName"}), 400

        script_path = "./build_android.sh"
        log_file = "/tmp/build_error_log.txt"
        use_dev_analytics_flag = "true" if use_dev_analytics else "false"

        with open(log_file, "w"):
            pass

        with open(log_file, "w") as log:
            process = subprocess.Popen(
                ["sh", script_path, branch_name, use_dev_analytics_flag],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True
            )

            for line in process.stdout:
                sys.stdout.write(line)
                sys.stdout.flush()
                log.write(line)

            process.wait()

        if process.returncode != 0:
            raise subprocess.CalledProcessError(process.returncode, script_path)

        return jsonify({
            "message": f"Android build for branch {branch_name} executed successfully!"
        }), 200

    except subprocess.CalledProcessError:
        return jsonify({"error": "Build script failed. Check Slack for full logs."}), 500
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route('/build_ios', methods=['POST'])
def build_ios():
    try:
        data = request.json
        branch_name = data.get('branchName')
        use_dev_analytics = data.get('isUseDevAnalytics', True)

        if not branch_name:
            return jsonify({"error": "Missing required parameter: branchName"}), 400

        script_path = "./build_ios.sh"
        log_file = "/tmp/build_error_log.txt"
        use_dev_analytics_flag = "true" if use_dev_analytics else "false"

        with open(log_file, "w"):
            pass

        with open(log_file, "w") as log:
            process = subprocess.Popen(
                ["sh", script_path, branch_name, use_dev_analytics_flag],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True
            )

            for line in process.stdout:
                sys.stdout.write(line)
                sys.stdout.flush()
                log.write(line)

            process.wait()

        if process.returncode != 0:
            raise subprocess.CalledProcessError(process.returncode, script_path)

        return jsonify({"message": f"iOS build for branch {branch_name} executed successfully!"}), 200

    except subprocess.CalledProcessError:
        return jsonify({"error": "Build script failed. Check Slack for full logs."}), 500
    except Exception as e:
        return jsonify({"error": str(e)}), 500


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


if __name__ == "__main__":
    app.run(debug=True, host='0.0.0.0', port=5001)
