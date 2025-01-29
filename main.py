import os
import subprocess
from itertools import count

from flask import Flask, jsonify, request

from BuildItem import BuildItem
from utils import extract_version, get_pid, kill_process

app = Flask(__name__)


@app.route('/stop_process', methods=['POST'])
def stop_process():
    try:
        process_name = request.json.get("processName")

        if not process_name:
            return jsonify({"error": "Missing required parameter: processName"}), 400

        pids = get_pid(process_name)

        for pid in pids:
            result = kill_process(pid)
            if result != 0:
                return jsonify({"message": f"Failed to stop process with PID {pid}"}), 500

        return jsonify({"message": f"Successfully stopped all processes for {process_name}"}), 200

    except ValueError as e:
        return jsonify({"message": str(e)}), 404
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route('/build_mac', methods=['POST'])
def build_mac():
    try:
        branch_name = request.json.get('branchName')
        sign = request.json.get('sign')
        if not branch_name or sign is None:
            return jsonify({"error": "Missing required parameters: branchName and sign"}), 400
        script_path = f"./build_mac_signed.sh" if sign else f"./build_mac_no_sign.sh"
        subprocess.run(["sh", script_path, branch_name], check=True)
        return jsonify({
            "message": f"macOS build for branch {branch_name} {'with' if sign else 'without'} signing executed successfully!"}), 200
    except subprocess.CalledProcessError as e:
        return jsonify({"error": str(e)}), 500
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route('/build_android', methods=['POST'])
def build_android():
    try:
        branch_name = request.json.get('branchName')
        if not branch_name:
            return jsonify({"error": "Missing required parameter: branchName"}), 400
        script_path = "./build_android.sh"
        subprocess.run(["sh", script_path, branch_name], check=True)
        return jsonify({"message": f"Android build for branch {branch_name} executed successfully!"}), 200
    except subprocess.CalledProcessError as e:
        return jsonify({"error": str(e)}), 500
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route('/build_ios', methods=['POST'])
def build_ios():
    try:
        branch_name = request.json.get('branchName')
        if not branch_name:
            return jsonify({"error": "Missing required parameter: branchName"}), 400
        script_path = "./build_ios.sh"
        subprocess.run(["sh", script_path, branch_name], check=True)
        return jsonify({"message": f"iOS build for branch {branch_name} executed successfully!"}), 200
    except subprocess.CalledProcessError as e:
        return jsonify({"error": str(e)}), 500
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route('/builds', methods=['GET'])
def get_builds():
    try:
        builds_folder = "/Users/denispopkov/Desktop/builds"
        if not os.path.exists(builds_folder):
            return jsonify({"error": f"The 'builds' folder does not exist in {builds_folder}"}), 404
        build_files = [
            {
                "file_name": f,
                "creation_time": os.path.getctime(os.path.join(builds_folder, f))
            }
            for f in os.listdir(builds_folder)
            if os.path.isfile(os.path.join(builds_folder, f))
        ]
        build_files = sorted(build_files, key=lambda x: x["creation_time"], reverse=True)
        build_items = []
        build_id = 1
        for file in build_files:
            file_name = file["file_name"]
            if file_name.endswith(".pkg"):
                version = extract_version(file_name)
                build_items.append(BuildItem(id=build_id, version=version, platform_name="macOS"))
                build_id += 1
            elif file_name.endswith(".apk"):
                version = extract_version(file_name)
                build_items.append(BuildItem(id=build_id, version=version, platform_name="Android"))
                build_id += 1
            elif file_name.endswith(".msi"):
                version = extract_version(file_name)
                build_items.append(BuildItem(id=build_id, version=version, platform_name="Windows"))
                build_id += 1
        return jsonify([item.to_dict() for item in build_items])
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route('/send_build', methods=['POST'])
def send_build():
    try:
        build_id = request.json.get('buildId')
        if not build_id:
            return jsonify({"error": "Missing required parameter: buildId"}), 400
        builds_folder = "/Users/denispopkov/Desktop/builds"
        if not os.path.exists(builds_folder):
            return jsonify({"error": f"The 'builds' folder does not exist in {builds_folder}"}), 404
        valid_extensions = ['.apk', '.pkg', '.msi']
        build_files = [
            f for f in os.listdir(builds_folder)
            if os.path.isfile(os.path.join(builds_folder, f)) and f.lower().endswith(tuple(valid_extensions))
        ]
        build_files = sorted(build_files, key=lambda f: os.path.getmtime(os.path.join(builds_folder, f)), reverse=True)
        if build_id <= 0 or build_id > len(build_files):
            return jsonify(
                {"error": f"Invalid buildId: {build_id}. It should be between 1 and {len(build_files)}."}), 400
        selected_build_file = build_files[build_id - 1]
        build_file_path = os.path.join(builds_folder, selected_build_file)
        script_path = "./send.sh"
        subprocess.run(["sh", script_path, build_file_path], check=True)
        return jsonify({"message": f"Build {build_id} ({selected_build_file}) sent successfully!"}), 200
    except subprocess.CalledProcessError as e:
        return jsonify({"error": f"Failed to run send.sh: {str(e)}"}), 500
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
            ["git", "-C", repo_path, "branch", "-r"],
            check=True,
            stdout=subprocess.PIPE,
            text=True
        )

        branches = result.stdout.strip().split("\n")
        branch_names = [branch.strip().replace("origin/", "") for branch in branches if
                        branch.strip().startswith("origin/")]

        prioritized_branches = ["develop", "soundcheck_develop"]
        sorted_branches = [b for b in prioritized_branches if b in branch_names] + [b for b in branch_names if
                                                                                    b not in prioritized_branches]

        # Append the size of the list as the last item
        sorted_branches.append(str(len(sorted_branches)))

        return jsonify({"branches": sorted_branches}), 200

    except subprocess.CalledProcessError as e:
        return jsonify({"error": f"Failed to fetch branches: {str(e)}"}), 500
    except Exception as e:
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    app.run(debug=True, host='0.0.0.0', port=5001)
