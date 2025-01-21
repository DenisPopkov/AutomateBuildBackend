from flask import Flask, jsonify, request
import subprocess

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

        return jsonify({"message": f"macOS build for branch {branch_name} {'with' if sign else 'without'} signing executed successfully!"}), 200

    except subprocess.CalledProcessError as e:
        return jsonify({"error": str(e)}), 500
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == "__main__":
    app.run(debug=True)
