#!/bin/bash
# restart_server.sh
pkill -f "flask run"  # Kill the running Flask server
flask run --host=0.0.0.0 --port=5001 &  # Restart Flask server
