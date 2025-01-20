from flask import Flask, jsonify
import subprocess

app = Flask(__name__)


@app.route('/build_mac_signed', methods=['POST'])
def build_mac_signed():
    try:
        script_path = "./build_mac_signed.sh"

        subprocess.run(["sh", script_path], check=True)

        return jsonify({"message": "macOS build and signing executed successfully!"}), 200
    except subprocess.CalledProcessError as e:
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    app.run(debug=True)
