"""
Auto_Claude 工具測試用極簡 Web App
用來驗證 Claude Preview / Chrome / Computer Use 的能力
"""
from http.server import HTTPServer, SimpleHTTPRequestHandler
import json
import os

PORT = 8099

class TestHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/':
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.end_headers()
            self.wfile.write(HTML.encode())
        elif self.path == '/api/status':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok", "version": "test-1.0"}).encode())
        elif self.path == '/api/echo':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"echo": "GET request received"}).encode())
        else:
            super().do_GET()

    def do_POST(self):
        if self.path == '/api/echo':
            length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(length).decode() if length else ''
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"echo": body, "method": "POST"}).encode())
        else:
            self.send_response(404)
            self.end_headers()

HTML = """<!DOCTYPE html>
<html lang="zh-TW">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Auto_Claude Tool Test</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, sans-serif; background: #f5f5f5; padding: 20px; }
        h1 { color: #0d9488; margin-bottom: 20px; }
        .card { background: white; border-radius: 8px; padding: 20px; margin-bottom: 16px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
        .card h2 { color: #334155; margin-bottom: 12px; font-size: 16px; }
        button { background: #0d9488; color: white; border: none; padding: 10px 20px; border-radius: 6px; cursor: pointer; margin: 4px; font-size: 14px; }
        button:hover { background: #0f766e; }
        button.danger { background: #dc2626; }
        button.secondary { background: #64748b; }
        input, textarea { border: 1px solid #d1d5db; border-radius: 6px; padding: 10px; width: 100%; margin: 4px 0; font-size: 14px; }
        #result { background: #f0fdf4; border: 1px solid #86efac; border-radius: 6px; padding: 12px; margin-top: 12px; min-height: 40px; white-space: pre-wrap; font-family: monospace; }
        .btn-row { display: flex; flex-wrap: wrap; gap: 8px; }
        select { border: 1px solid #d1d5db; border-radius: 6px; padding: 10px; font-size: 14px; }
        .counter { font-size: 24px; font-weight: bold; color: #0d9488; }
        #error-box { display: none; background: #fef2f2; border: 1px solid #fca5a5; border-radius: 6px; padding: 12px; margin-top: 12px; color: #dc2626; }
    </style>
</head>
<body>
    <h1>🧪 Auto_Claude Tool Test Page</h1>

    <!-- Card 1: Buttons -->
    <div class="card">
        <h2>1. Button Test</h2>
        <div class="btn-row">
            <button id="btn-ok" onclick="showResult('OK button clicked ✅')">OK</button>
            <button id="btn-action" onclick="showResult('Action executed 🚀')">Execute Action</button>
            <button id="btn-count" onclick="incrementCounter()">Count: <span id="counter">0</span></button>
            <button id="btn-danger" class="danger" onclick="showResult('⚠️ Danger action triggered')">Danger</button>
            <button id="btn-reset" class="secondary" onclick="resetAll()">Reset</button>
        </div>
        <div id="result">Click a button to see results here...</div>
    </div>

    <!-- Card 2: Form -->
    <div class="card">
        <h2>2. Form Test</h2>
        <input type="text" id="input-name" placeholder="Enter your name">
        <input type="email" id="input-email" placeholder="Enter your email">
        <select id="input-role">
            <option value="">Select role...</option>
            <option value="dev">Developer</option>
            <option value="reviewer">Reviewer</option>
            <option value="human">Human Operator</option>
        </select>
        <textarea id="input-message" rows="3" placeholder="Enter a message..."></textarea>
        <button id="btn-submit" onclick="submitForm()">Submit Form</button>
    </div>

    <!-- Card 3: API Test -->
    <div class="card">
        <h2>3. API Test</h2>
        <div class="btn-row">
            <button id="btn-api-get" onclick="callAPI('GET')">GET /api/status</button>
            <button id="btn-api-post" onclick="callAPI('POST')">POST /api/echo</button>
            <button id="btn-api-fail" class="danger" onclick="callAPI('FAIL')">GET /api/nonexistent (404)</button>
        </div>
        <div id="api-result" style="background:#f0fdf4;border:1px solid #86efac;border-radius:6px;padding:12px;margin-top:12px;font-family:monospace;white-space:pre-wrap;">API results appear here...</div>
    </div>

    <!-- Card 4: CSS Verification -->
    <div class="card">
        <h2>4. CSS Verification Target</h2>
        <p id="css-target" style="color: #0d9488; font-size: 18px; padding: 16px; background: #f0fdfa; border-radius: 8px; border-left: 4px solid #0d9488;">
            This text should be teal (#0d9488), 18px, with 16px padding and a left border.
        </p>
    </div>

    <div id="error-box"></div>

    <script>
        let count = 0;
        function showResult(msg) {
            document.getElementById('result').textContent = new Date().toLocaleTimeString() + ' — ' + msg;
        }
        function incrementCounter() {
            count++;
            document.getElementById('counter').textContent = count;
            showResult('Counter: ' + count);
        }
        function resetAll() {
            count = 0;
            document.getElementById('counter').textContent = '0';
            document.getElementById('result').textContent = 'Reset complete.';
            document.getElementById('input-name').value = '';
            document.getElementById('input-email').value = '';
            document.getElementById('input-role').value = '';
            document.getElementById('input-message').value = '';
            document.getElementById('api-result').textContent = 'API results appear here...';
        }
        function submitForm() {
            const data = {
                name: document.getElementById('input-name').value,
                email: document.getElementById('input-email').value,
                role: document.getElementById('input-role').value,
                message: document.getElementById('input-message').value
            };
            showResult('Form submitted: ' + JSON.stringify(data, null, 2));
        }
        async function callAPI(method) {
            const el = document.getElementById('api-result');
            try {
                let resp;
                if (method === 'GET') {
                    resp = await fetch('/api/status');
                } else if (method === 'POST') {
                    resp = await fetch('/api/echo', {method:'POST', body: JSON.stringify({test:true, time: Date.now()})});
                } else {
                    resp = await fetch('/api/nonexistent');
                }
                const text = await resp.text();
                el.textContent = method + ' ' + resp.status + '\\n' + text;
            } catch(e) {
                el.textContent = 'Error: ' + e.message;
            }
        }
    </script>
</body>
</html>
"""

if __name__ == '__main__':
    print(f"🧪 Test server running on http://localhost:{PORT}")
    HTTPServer(('0.0.0.0', PORT), TestHandler).serve_forever()
