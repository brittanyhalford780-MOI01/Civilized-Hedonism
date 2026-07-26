/**
 * MOI01.VIP — Server Automated Unit & Integration Tests
 * Uses Node.js native test runner (node:test) and assertion module (node:assert)
 */

"use strict";

const { test, before, after } = require("node:test");
const assert = require("node:assert");
const http = require("node:http");

// Set environment for test mode
process.env.PORT = "0"; // 0 tells the OS to assign an available ephemeral port
process.env.WEBHOOK_URL = "";
process.env.API_KEY = "";

const { app } = require("../src/server.js");
let serverInstance;
let BASE_URL = "http://127.0.0.1:0"; // Will be updated dynamically in before()

// ── Helper Function for HTTP Requests ─────────────────────────────────────────

function makeRequest(pathName, method = "GET", body = null, extraHeaders = {}) {
  return new Promise((resolve, reject) => {
    const url = new URL(pathName, BASE_URL);
    const bodyStr = body !== null ? (typeof body === "string" ? body : JSON.stringify(body)) : null;

    const options = {
      hostname: url.hostname,
      port: url.port,
      path: url.pathname + url.search,
      method,
      headers: {
        // Automatically attach headers if a body is present
        ...(bodyStr !== null ? { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(bodyStr) } : {}),
        ...extraHeaders,
      },
    };

    const req = http.request(options, (res) => {
      let responseBody = "";
      res.on("data", (chunk) => { responseBody += chunk; });
      res.on("end", () => {
        let json = null;
        try {
          json = JSON.parse(responseBody);
        } catch {
          // Not JSON
        }
        resolve({ statusCode: res.statusCode, headers: res.headers, rawBody: responseBody, json });
      });
    });

    req.on("error", reject);
    if (bodyStr !== null) {
      req.write(bodyStr);
    }
    req.end();
  });
}

// ── Test Lifecycle ─────────────────────────────────────────────────────────────

before((_, done) => {
  // Listen on port 0 to get a random available port
  serverInstance = app.listen(0, "127.0.0.1", () => {
    const { port } = serverInstance.address();
    BASE_URL = `http://127.0.0.1:${port}`;
    done();
  });
});

after((_, done) => {
  if (serverInstance) {
    serverInstance.close(() => done());
  } else {
    done();
  }
});

// ── Test Cases ─────────────────────────────────────────────────────────────────

test("GET /health returns HTTP 200 and valid status payload", async () => {
  const res = await makeRequest("/health");
  assert.strictEqual(res.statusCode, 200);
  assert.ok(res.json);
  assert.strictEqual(res.json.status, "ok");
  assert.ok(typeof res.json.uptime === "number");
});

test("GET / serves static frontend index.html", async () => {
  const res = await makeRequest("/");
  assert.strictEqual(res.statusCode, 200);
  assert.ok(res.rawBody.includes("MOI01.VIP"));
  assert.ok(res.rawBody.includes("Zero-Knowledge Ephemeral Vault"));
});

test("POST /api/submit processes valid JSON payload in RAM", async () => {
  const payload = { test: true, data: "compliance_audit_payload", id: 12345 };
  const res = await makeRequest("/api/submit", "POST", payload);
  assert.strictEqual(res.statusCode, 200);
  assert.strictEqual(res.json.status, "received");
  assert.ok(res.json.bytesProcessed > 0);
});

test("POST /api/submit rejects empty JSON payload with HTTP 400", async () => {
  const res = await makeRequest("/api/submit", "POST", {});
  assert.strictEqual(res.statusCode, 400);
  assert.strictEqual(res.json.error, "EMPTY_PAYLOAD");
});

test("POST /api/submit rejects malformed JSON with HTTP 400", async () => {
  // Note: makeRequest automatically sets Content-Type to application/json
  const res = await makeRequest("/api/submit", "POST", "{ invalid json string ---");
  assert.strictEqual(res.statusCode, 400);
  assert.strictEqual(res.json.error, "INVALID_JSON");
});

test("POST /api/submit rejects payloads exceeding 1MB limit with HTTP 413", async () => {
  // Generate a payload > 1MB (1048576 bytes)
  const largePayload = { data: "x".repeat(1 * 1024 * 1024 + 100) };
  const res = await makeRequest("/api/submit", "POST", largePayload);
  assert.strictEqual(res.statusCode, 413);
  assert.strictEqual(res.json.error, "PAYLOAD_TOO_LARGE");
});

test("GET /nonexistent returns HTTP 404", async () => {
  const res = await makeRequest("/nonexistent-endpoint-xyz");
  assert.strictEqual(res.statusCode, 404);
  assert.strictEqual(res.json.error, "NOT_FOUND");
});