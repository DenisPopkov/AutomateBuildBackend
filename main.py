import datetime
import os
import subprocess
from flask import Flask, jsonify, request

from BuildItem import BuildItem
from utils import extract_version

app = Flask(__name__)


@app.route('/build_mac', methods=['POST'])
def build_mac():
    try:
        data = request.json
        branch_name = data.get('branchName')
        sign = data.get('sign')
        bump_version = data.get('bumpVersion', False)
        use_dev_analytics = data.get('isUseDevAnalytics', True)

        if not branch_name or sign is None:
            return jsonify({"error": "Missing required parameters: branchName and sign"}), 400

        script_path = "./build_mac_signed.sh" if sign else "./build_mac_no_sign.sh"
        bump_version_flag = "true" if bump_version else "false"
        use_dev_analytics_flag = "true" if use_dev_analytics else "false"

        subprocess.run(["sh", script_path, branch_name, bump_version_flag, use_dev_analytics_flag], check=True)

        return jsonify({
            "message": f"macOS build for branch {branch_name} {'with' if sign else 'without'} signing executed successfully with bumpVersion={bump_version_flag}!"
        }), 200

    except subprocess.CalledProcessError as e:
        return jsonify({"error": str(e)}), 500
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route('/build_win', methods=['POST'])
def build_win():
    try:
        print("Received request to /build_win")
        data = request.json
        branch_name = data.get('branchName')
        bump_version = data.get('bumpVersion', False)
        use_dev_analytics = data.get('isUseDevAnalytics', True)

        print(
            f"Parsed data: branchName={branch_name}, bumpVersion={bump_version}, isUseDevAnalytics={use_dev_analytics}")

        if not branch_name:
            print("Error: Missing required parameter: branchName")
            return jsonify({"error": "Missing required parameter: branchName"}), 400

        # Define the script path and flags
        script_path = ".\\build_win.ps1"
        bump_version_flag = "true" if bump_version else "false"
        use_dev_analytics_flag = "true" if use_dev_analytics else "false"

        print("Changing working directory...")
        os.chdir("C:\\Users\\BlackBricks\\PycharmProjects\\AutomateBuildBackend")
        print("Current working directory:", os.getcwd())

        # Construct command
        command = [
            "powershell", "-ExecutionPolicy", "Bypass", "-File", script_path,
            "-BRANCH_NAME", branch_name,
            "-BUMP_VERSION", bump_version_flag,
            "-USE_DEV_ANALYTICS", use_dev_analytics_flag
        ]

        print(f"Executing command: {' '.join(command)}")

        # Run the PowerShell script
        result = subprocess.run(command, check=True, capture_output=True, text=True)

        print(f"Script output: {result.stdout}")
        if result.stderr:
            print(f"Script error output: {result.stderr}")

        return jsonify({
            "message": f"Windows build for branch {branch_name} executed successfully with bumpVersion={bump_version_flag}!"
        }), 200

    except subprocess.CalledProcessError as e:
        print(f"Subprocess failed: {e}")
        return jsonify({"error": f"Build failed: {e}"}), 500
    except Exception as e:
        print(f"Unexpected error: {e}")
        return jsonify({"error": f"Unexpected error: {str(e)}"}), 500


@app.route('/build_android', methods=['POST'])
def build_android():
    try:
        data = request.json
        branch_name = data.get('branchName')
        bump_version = data.get('bumpVersion', False)
        is_bundle_to_build = data.get('isBundleToBuild', False)
        use_dev_analytics = data.get('isUseDevAnalytics', True)

        if not branch_name:
            return jsonify({"error": "Missing required parameter: branchName"}), 400

        script_path = "./build_android.sh"
        bump_version_flag = "true" if bump_version else "false"
        is_bundle_to_build_flag = "true" if is_bundle_to_build else "false"
        use_dev_analytics_flag = "true" if use_dev_analytics else "false"

        subprocess.run(
            ["sh", script_path, branch_name, bump_version_flag, is_bundle_to_build_flag, use_dev_analytics_flag],
            check=True)

        return jsonify({
            "message": f"Android build for branch {branch_name} executed successfully with bumpVersion={bump_version_flag}!"}), 200

    except subprocess.CalledProcessError as e:
        return jsonify({"error": str(e)}), 500
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

        use_dev_analytics_flag = "true" if use_dev_analytics else "false"

        script_path = "./build_ios.sh"
        subprocess.run(["sh", script_path, branch_name, use_dev_analytics_flag], check=True)

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
            creation_timestamp = file["creation_time"]
            creation_date = datetime.datetime.fromtimestamp(creation_timestamp).strftime("%d.%m.%y")

            if file_name.endswith(".pkg"):
                version = extract_version(file_name)
                build_items.append(BuildItem(id=build_id, version=version, platform_name="MacOS", date=creation_date))
            elif file_name.endswith(".apk"):
                version = extract_version(file_name)
                build_items.append(BuildItem(id=build_id, version=version, platform_name="Android", date=creation_date))
            elif file_name.endswith(".aab"):
                version = extract_version(file_name)
                build_items.append(BuildItem(id=build_id, version=version, platform_name="Android", date=creation_date))
            elif file_name.endswith(".msi"):
                version = extract_version(file_name)
                build_items.append(BuildItem(id=build_id, version=version, platform_name="Windows", date=creation_date))

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
