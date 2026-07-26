/**
 * MOI01.VIP — Zero-Knowledge Ephemeral Vault Server
 *
 * SECURITY INVARIANTS:
 *   1. No fs.writeFile, fs.appendFile, or any disk-write call exists in this file.
 *   2. No payload data is logged (console.log is used ONLY for startup/health).
 *   3. All payload data lives exclusively in V8 RAM and is garbage-collected.
 *   4. Credentials are injected via systemd EnvironmentFile — never read from disk at runtime.
 *
 * ENVIRONMENT VARIABLES (injected by systemd from /etc/myapp/config.env):
 *   PORT         — Listen port (default: 3000)
 *   WEBHOOK_URL  — Destination URL for payload relay
 *   API_KEY      — Bearer token for webhook authentication
 */

"use strict";

const express = require("express");
const path = require("path");
const http = require("http");
const https = require("https");

// ─── Configuration ──────────────────────────────────────────────────────────────

const PORT = parseInt(process.env.PORT, 10) || 3000;
const WEBHOOK_URL = process.env.WEBHOOK_URL || "";
const API_KEY = process.env.API_KEY || "";
const MAX_PAYLOAD_BYTES = 1 * 1024 * 1024; // 1 MB — matches Nginx client_max_body_size

// ─── App Initialization ─────────────────────────────────────────────────────────

const app = express();

// Parse JSON bodies with strict size limit
app.use(
  express.json({
    limit: MAX_PAYLOAD_BYTES,
    strict: false,
  })
);

// Serve static frontend UI (Automatically handles GET "/" by serving index.html)
app.use(express.static(path.join(__dirname, "public")));

// ─── Health Check ────────────────────────────────────────────────────────────────

app.get("/health", (_req, res) => {
  res.json({
    status: "ok",
    uptime: process.uptime(),
    memoryUsage: process.memoryUsage().rss,
    timestamp: Date.now(),
  });
});

// ─── Payload Submission Endpoint ─────────────────────────────────────────────────

app.post("/api/submit", async (req, res, next) => {
  try {
    // Validate that body exists and isn't an empty object/string
    // Handles cases where strict:false allows raw strings or null
    if (
      req.body == null ||
      req.body === "" ||
      (typeof req.body === "object" && Object.keys(req.body).length === 0)
    ) {
      return res.status(400).json({
        error: "EMPTY_PAYLOAD",
        message: "Request body is empty or missing.",
      });
    }

    const payloadString = JSON.stringify(req.body);
    const bytesProcessed = Buffer.byteLength(payloadString);

    // If no webhook configured, just acknowledge receipt
    if (!WEBHOOK_URL) {
      return res.status(200).json({
        status: "received",
        message: "Payload processed in RAM. No webhook configured — data discarded.",
        bytesProcessed,
      });
    }

    // Forward payload to destination audit sink
    const result = await forwardToWebhook(payloadString);

    return res.status(200).json({
      status: "relayed",
      message: "Payload processed in RAM and relayed to destination. Local copy discarded.",
      webhookStatus: result.statusCode,
      bytesProcessed,
    });
  } catch (error) {
    // Pass to global error handler
    next(error);
  }
});

// ─── Webhook Relay Function ──────────────────────────────────────────────────────

function forwardToWebhook(payloadString) {
  return new Promise((resolve, reject) => {
    const url = new URL(WEBHOOK_URL);
    const transport = url.protocol === "https:" ? https : http;

    const options = {
      hostname: url.hostname,
      port: url.port || (url.protocol === "https:" ? 443 : 80),
      path: url.pathname + url.search,
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Content-Length": Buffer.byteLength(payloadString),
        ...(API_KEY ? { Authorization: `Bearer ${API_KEY}` } : {}),
      },
      timeout: 10000,
    };

    const request = transport.request(options, (response) => {
      let body = "";
      response.on("data", (chunk) => {
        body += chunk;
      });
      response.on("end", () => {
        // Fail the promise if the destination server returns an error code
        if (response.statusCode >= 400) {
          reject(new Error(`Destination responded with status ${response.statusCode}`));
        } else {
          resolve({ statusCode: response.statusCode, body });
        }
      });
    });

    request.on("error", (err) => reject(err));

    request.on("timeout", () => {
      request.destroy();
      reject(new Error("Webhook request timed out after 10 seconds"));
    });

    request.write(payloadString);
    request.end();
  });
}

/* 
 * NOTE: If you are using Node 18+, you can replace the entire forwardToWebhook 
 * function above with native fetch:
 * 
 * async function forwardToWebhook(payloadString) {
 *   const controller = new AbortController();
 *   const timeout = setTimeout(() => controller.abort(), 10000);
 *   try {
 *     const response = await fetch(WEBHOOK_URL, {
 *       method: "POST",
 *       headers: { 
 *         "Content-Type": "application/json",
 *         ...(API_KEY && { Authorization: `Bearer ${API_KEY}` })
 *       },
 *       body: payloadString,
 *       signal: controller.signal
 *     });
 *     if (!response.ok) throw new Error(`Destination responded with ${response.status}`);
 *     return { statusCode: response.status, body: await response.text() };
 *   } finally {
 *     clearTimeout(timeout);
 *   }
 * }
 */

// ─── Catch-All for Unmatched Routes ──────────────────────────────────────────────

app.use((_req, res) => {
  res.status(404).json({ error: "NOT_FOUND", message: "Endpoint not found." });
});

// ─── Global Error Handler ────────────────────────────────────────────────────────
// MUST be the last middleware added to catch errors from all routes

app.use((err, _req, res, _next) => {
  // Handle body-parser / payload errors cleanly
  if (err.type === "entity.too.large") {
    return res.status(413).json({
      error: "PAYLOAD_TOO_LARGE",
      message: `Payload exceeds the ${MAX_PAYLOAD_BYTES} byte limit. Dropped at edge.`,
      maxBytes: MAX_PAYLOAD_BYTES,
    });
  }
  if (err.type === "entity.parse.failed") {
    return res.status(400).json({
      error: "INVALID_JSON",
      message: "Request body is not valid JSON.",
    });
  }

  // Handle webhook relay failures specifically
  if (err.message && err.message.startsWith("Destination responded")) {
    return res.status(502).json({
      error: "RELAY_FAILED",
      message: "Payload processed in RAM but destination rejected the relay.",
      detail: err.message,
    });
  }

  // Catch-all for unexpected errors
  console.error(`[VAULT ERROR] ${err.name}: ${err.message}`);
  res.status(500).json({
    error: "INTERNAL_ERROR",
    message: "An internal error occurred. No data was persisted.",
  });
});

// ─── Start Server ────────────────────────────────────────────────────────────────

let server;

if (require.main === module) {
  server = app.listen(PORT, "127.0.0.1", () => {
    console.log(`[VAULT] MOI01.VIP Vault listening on 127.0.0.1:${PORT}`);
    console.log(`[VAULT] Webhook relay: ${WEBHOOK_URL ? "CONFIGURED" : "DISABLED"}`);
    console.log(`[VAULT] Max payload: ${MAX_PAYLOAD_BYTES} bytes`);
  });
}

// Graceful shutdown
function shutdown(signal) {
  console.log(`[VAULT] ${signal} received — shutting down gracefully`);
  if (server) {
    server.close(() => process.exit(0));
  } else {
    process.exit(0);
  }
}

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));

module.exports = { app };