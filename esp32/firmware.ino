#include <WiFi.h>
#include <WebServer.h>
#include <ArduinoJson.h>

// ─── Network Credentials ──────────────────────────
const char *ssid = "WESTO_BIN_01";
const char *password = "password123";

// ─── Web Server ───────────────────────────────────
WebServer server(80);

// ─── State ────────────────────────────────────────
String lastPayload = "{}";
unsigned long lastUpdate = 0;

// ─── HTML Dashboard ───────────────────────────────
// A sleek, dark dashboard matching the Flutter app's aesthetics
const char *htmlDashboard = R"rawliteral(
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>WESTO ESP32 Dashboard</title>
  <style>
    @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap');
    body {
      background-color: #000;
      color: #fff;
      font-family: 'Inter', sans-serif;
      margin: 0;
      padding: 0;
      display: flex;
      justify-content: center;
      align-items: center;
      min-height: 100vh;
      overflow: hidden;
    }
    /* Ambient Glows */
    .glow-cyan {
      position: absolute;
      top: -100px;
      right: -50px;
      width: 300px;
      height: 300px;
      background: rgba(0, 176, 255, 0.15);
      border-radius: 50%;
      filter: blur(80px);
      z-index: 1;
    }
    .glow-green {
      position: absolute;
      bottom: 50px;
      left: -100px;
      width: 250px;
      height: 250px;
      background: rgba(0, 230, 118, 0.15);
      border-radius: 50%;
      filter: blur(80px);
      z-index: 1;
    }
    .container {
      position: relative;
      z-index: 2;
      width: 100%;
      max-width: 400px;
      padding: 24px;
    }
    .card {
      background: rgba(255, 255, 255, 0.05);
      backdrop-filter: blur(20px);
      -webkit-backdrop-filter: blur(20px);
      border: 1px solid rgba(255, 255, 255, 0.1);
      border-radius: 24px;
      padding: 32px 24px;
      text-align: center;
      box-shadow: 0 8px 32px 0 rgba(0, 0, 0, 0.37);
    }
    h1 {
      font-size: 24px;
      margin: 0 0 8px 0;
      font-weight: 700;
      letter-spacing: -0.5px;
    }
    p {
      color: rgba(255, 255, 255, 0.6);
      font-size: 14px;
      margin: 0 0 24px 0;
    }
    .data-box {
      background: rgba(0, 0, 0, 0.3);
      border: 1px solid rgba(255, 255, 255, 0.05);
      border-radius: 16px;
      padding: 16px;
      margin-bottom: 16px;
      text-align: left;
    }
    .data-label {
      font-size: 12px;
      color: rgba(255, 255, 255, 0.4);
      text-transform: uppercase;
      letter-spacing: 1px;
      margin-bottom: 4px;
    }
    .data-value {
      font-size: 18px;
      font-weight: 600;
      color: #00E676;
    }
    .data-value.primary {
      font-size: 28px;
    }
    .status {
      display: inline-flex;
      align-items: center;
      background: rgba(0, 230, 118, 0.1);
      border: 1px solid rgba(0, 230, 118, 0.3);
      color: #00E676;
      padding: 6px 12px;
      border-radius: 20px;
      font-size: 12px;
      font-weight: 600;
      margin-bottom: 24px;
    }
    .status-dot {
      width: 8px;
      height: 8px;
      background: #00E676;
      border-radius: 50%;
      margin-right: 8px;
      box-shadow: 0 0 8px #00E676;
    }
  </style>
</head>
<body>
  <div class="glow-cyan"></div>
  <div class="glow-green"></div>
  
  <div class="container">
    <div class="card">
      <div class="status"><div class="status-dot"></div> AP Active</div>
      <h1>Live Detection</h1>
      <p>Awaiting payload from Flutter app...</p>
      
      <div class="data-box">
        <div class="data-label">Detected Waste</div>
        <div class="data-value primary" id="wasteLabel">--</div>
      </div>
      
      <div style="display: flex; gap: 16px;">
        <div class="data-box" style="flex: 1;">
          <div class="data-label">Category</div>
          <div class="data-value" style="color: #fff;" id="binName">--</div>
        </div>
        <div class="data-box" style="flex: 1;">
          <div class="data-label">Confidence</div>
          <div class="data-value" style="color: #00B0FF;" id="confidence">--%</div>
        </div>
      </div>
      
      <div style="display: flex; gap: 16px;">
        <div class="data-box" style="flex: 1;">
          <div class="data-label">Direction</div>
          <div class="data-value" style="color: #fff;" id="direction">--</div>
        </div>
        <div class="data-box" style="flex: 1;">
          <div class="data-label">Distance</div>
          <div class="data-value" style="color: #FFD740;" id="distance">-- cm</div>
        </div>
      </div>
      
      <div style="display: flex; gap: 16px;">
        <div class="data-box" style="flex: 1;">
          <div class="data-label">Grid Cell</div>
          <div class="data-value" style="color: #00E676;" id="gridCell">--</div>
        </div>
        <div class="data-box" style="flex: 1;">
          <div class="data-label">X Coord</div>
          <div class="data-value" style="color: #00B0FF;" id="coordX">--</div>
        </div>
        <div class="data-box" style="flex: 1;">
          <div class="data-label">Y Coord</div>
          <div class="data-value" style="color: #00B0FF;" id="coordY">--</div>
        </div>
      </div>
      
      <div style="display: flex; gap: 16px;">
        <div class="data-box" style="flex: 1;">
          <div class="data-label">Pixel X</div>
          <div class="data-value" style="color: #E040FB;" id="pixelX">--</div>
        </div>
        <div class="data-box" style="flex: 1;">
          <div class="data-label">Pixel Y</div>
          <div class="data-value" style="color: #E040FB;" id="pixelY">--</div>
        </div>
      </div>
    </div>
  </div>

  <script>
    function fetchData() {
      fetch('/api/latest')
        .then(response => response.json())
        .then(data => {
          if (data.label) {
            document.getElementById('wasteLabel').innerText = data.label;
            document.getElementById('binName').innerText = data.binName;
            
            const conf = parseFloat(data.confidence) * 100;
            document.getElementById('confidence').innerText = conf.toFixed(1) + '%';
            
            document.getElementById('direction').innerText = data.direction;
            
            const dist = parseFloat(data.distanceCm);
            document.getElementById('distance').innerText = dist > 0 ? dist.toFixed(1) + ' cm' : 'N/A';
            
            // Grid cell and coordinates
            document.getElementById('gridCell').innerText = data.gridCell || '--';
            
            const cx = parseFloat(data.coordX);
            document.getElementById('coordX').innerText = !isNaN(cx) ? cx.toFixed(2) : '--';
            
            const cy = parseFloat(data.coordY);
            document.getElementById('coordY').innerText = !isNaN(cy) ? cy.toFixed(2) : '--';
            
            // Pixel coordinates
            const px = parseInt(data.pixelX);
            document.getElementById('pixelX').innerText = !isNaN(px) ? px : '--';
            
            const pyVal = parseInt(data.pixelY);
            document.getElementById('pixelY').innerText = !isNaN(pyVal) ? pyVal : '--';
          }
        })
        .catch(err => console.error(err));
    }
    
    // Poll every 1 second
    setInterval(fetchData, 1000);
  </script>
</body>
</html>
)rawliteral";

// ─── Handlers ─────────────────────────────────────

void handleRoot()
{
  server.send(200, "text/html", htmlDashboard);
}

void handlePing()
{
  // Simple check for the app connection screen
  server.send(200, "text/plain", "pong");
}

void handleDataPost()
{
  if (server.hasArg("plain") == false)
  {
    server.send(400, "text/plain", "Body not received");
    return;
  }

  // Store payload
  lastPayload = server.arg("plain");
  lastUpdate = millis();

  // Acknowledge receipt
  server.send(200, "application/json", "{\"status\":\"success\"}");
  Serial.println("Received Payload:");
  Serial.println(lastPayload);
}

void handleUpdatePost()
{
  if (!server.hasArg("plain"))
  {
    server.send(400, "application/json", "{\"status\":\"error\",\"message\":\"No body\"}");
    return;
  }

  String body = server.arg("plain");

  StaticJsonDocument<128> doc;
  DeserializationError err = deserializeJson(doc, body);

  if (err)
  {
    Serial.print("JSON parse error: ");
    Serial.println(err.c_str());
    server.send(400, "application/json", "{\"status\":\"error\",\"message\":\"Invalid JSON\"}");
    return;
  }

  if (!doc.containsKey("bin_type"))
  {
    server.send(400, "application/json", "{\"status\":\"error\",\"message\":\"Missing bin_type\"}");
    return;
  }

  int binType = doc["bin_type"].as<int>();

  if (binType != 0 && binType != 1)
  {
    server.send(400, "application/json", "{\"status\":\"error\",\"message\":\"Invalid bin_type\"}");
    return;
  }

  // Process the bin classification.
  // TODO: Actuate servo, relay, LED, etc. based on binType.
  const char *binName = (binType == 0) ? "Paper" : "Plastic";
  Serial.print("Bin Update: ");
  Serial.print(binName);
  Serial.print(" (bin_type=");
  Serial.print(binType);
  Serial.println(")");

  lastUpdate = millis();

  String response = "{\"status\":\"success\",\"bin_type\":";
  response += String(binType);
  response += ",\"bin_name\":\"";
  response += binName;
  response += "\"}";

  server.send(200, "application/json", response);
}

void handleLatestData()
{
  // Serve the last received payload to the dashboard UI
  server.send(200, "application/json", lastPayload);
}

// ─── Setup & Loop ─────────────────────────────────

void setup()
{
  Serial.begin(115200);

  // Start Access Point
  Serial.println("Starting SoftAP...");
  WiFi.softAP(ssid, password);

  IPAddress IP = WiFi.softAPIP();
  Serial.print("AP IP address: ");
  Serial.println(IP); // Usually 192.168.4.1

  // Routing
  server.on("/", HTTP_GET, handleRoot);
  server.on("/ping", HTTP_GET, handlePing);
  server.on("/data", HTTP_POST, handleDataPost);
  server.on("/update", HTTP_POST, handleUpdatePost);
  server.on("/api/latest", HTTP_GET, handleLatestData);

  // Start server
  server.begin();
  Serial.println("HTTP server started");
}

void loop()
{
  server.handleClient();
  delay(10);
}
