import os
import subprocess

from flask import Flask, jsonify, request

from BuildItem import BuildItem
from utils import extract_version

app = Flask(__name__)


@app.route('/build_mac', methods=['POST'])
def build_mac():
    try:
        branch_name = request.json.get('branchName')
        sign = request.json.get('sign')

        if not branch_name or sign is None:
            return jsonify({"error": "Missing required parameters: branchName and sign"}), 400

        if sign:
            script_path = f"./build_mac_signed.sh"
        else:
            script_path = f"./build_mac_signed_no_sign.sh"

        subprocess.run(["sh", script_path], check=True)

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


@app.route('/builds', methods=['GET'])
def get_builds():
    try:
        builds_folder = "/Users/denispopkov/Desktop/builds"

        if not os.path.exists(builds_folder):
            return jsonify({"error": f"The 'builds' folder does not exist in {builds_folder}"}), 404

        build_files = os.listdir(builds_folder)

        build_items = []
        build_id = 1

        for file_name in build_files:
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

        build_files = os.listdir(builds_folder)

        if build_id <= 0 or build_id > len(build_files):
            return jsonify(
                {"error": f"Invalid buildId: {build_id}. It should be between 1 and {len(build_files)}."}), 400

        selected_build_file = build_files[build_id - 1]

        build_file_path = os.path.join(builds_folder, selected_build_file)

        script_path = "./send.sh"
        subprocess.run(["sh", script_path, build_file_path], check=True)

        return jsonify({
            "message": f"Build {build_id} ({selected_build_file}) sent successfully!"
        }), 200

    except subprocess.CalledProcessError as e:
        return jsonify({"error": f"Failed to run send.sh: {str(e)}"}), 500
    except Exception as e:
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    app.run(debug=True, host='0.0.0.0', port=5001)
