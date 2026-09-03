#!/bin/bash
echo "Starting Backend API and Serve UI..."
python3 backend/server.py &
echo "System started. UI available at http://localhost:8000"
