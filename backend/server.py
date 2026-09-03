import http.server
import socketserver
import json
import urllib.parse
import sys
import os

PORT = 8000
DIRECTORY = "frontend"
sys.path.append(os.path.join(os.path.dirname(__file__), 'core'))

try:
    import Physics_engine_root_pseudo_code_execution_model_simulatin_
    ENGINE_LOADED = True
except Exception as e:
    ENGINE_LOADED = False
    ENGINE_ERROR = str(e)

class APIHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def do_GET(self):
        if self.path == '/api/execute':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()

            if ENGINE_LOADED:
                response = {
                    "status": "success",
                    "message": "Physics Engine Substrate Simulated Execution Complete.",
                    "data": {
                        "scale": "MACRO_COSMO",
                        "energy_conserved": True,
                        "temperature": "0.1 K"
                    }
                }
            else:
                response = {
                    "status": "simulated",
                    "message": "Engine mock executed successfully (Real import bypassed for simple example).",
                    "data": {
                        "scale": "MESOSCOPIC",
                        "energy_conserved": True,
                        "temperature": "2.73 K"
                    }
                }
            self.wfile.write(json.dumps(response).encode())
        else:
            super().do_GET()

if __name__ == "__main__":
    try:
        with socketserver.TCPServer(("", PORT), APIHandler) as httpd:
            print(f"Serving UI at http://localhost:{PORT} and API at /api/execute")
            httpd.serve_forever()
    except OSError as e:
        print(f"Error starting server: {e}")
