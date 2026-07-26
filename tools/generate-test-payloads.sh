#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# MOI01.VIP — Generate Test Payloads
#
# Creates JSON files of specific sizes for the live testing protocol:
#   - test-500kb.json  (~500 KB — should pass the 1MB limit)
#   - test-10mb.json   (~10 MB — should be rejected by Nginx/Node.js)
#
# USAGE:
#   chmod +x scripts/generate-test-payloads.sh
#   bash scripts/generate-test-payloads.sh
#
# OUTPUT:
#   Files are created in the current working directory.
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

echo "═══════════════════════════════════════════════════════════════"
echo "  MOI01.VIP — Test Payload Generator"
echo "═══════════════════════════════════════════════════════════════"

# ── Generate 500 KB payload (should PASS) ──
echo "▸ Generating test-500kb.json (~500 KB)..."
python3 -c "
import json, string, random
random.seed(42)
data = {
    'type': 'compliance_test',
    'version': '1.0',
    'description': 'This is a ~500KB test payload for MOI01.VIP vault compliance testing.',
    'records': []
}
# Each record is ~500 bytes, so ~1000 records ≈ 500KB
for i in range(1000):
    data['records'].append({
        'id': f'REC-{i:06d}',
        'timestamp': '2026-01-01T00:00:00Z',
        'payload': ''.join(random.choices(string.ascii_letters + string.digits, k=400)),
        'checksum': ''.join(random.choices('0123456789abcdef', k=64))
    })
with open('test-500kb.json', 'w') as f:
    json.dump(data, f)
print(f'   Size: {len(json.dumps(data)):,} bytes')
"
echo "   ✅ test-500kb.json created"

# ── Generate 10 MB payload (should FAIL — 413 error) ──
echo "▸ Generating test-10mb.json (~10 MB)..."
python3 -c "
import json, string, random
random.seed(42)
data = {
    'type': 'oversize_attack_test',
    'version': '1.0',
    'description': 'This is a ~10MB test payload that MUST be rejected by the vault.',
    'records': []
}
# Each record is ~500 bytes, so ~20000 records ≈ 10MB
for i in range(20000):
    data['records'].append({
        'id': f'REC-{i:06d}',
        'timestamp': '2026-01-01T00:00:00Z',
        'payload': ''.join(random.choices(string.ascii_letters + string.digits, k=400)),
        'checksum': ''.join(random.choices('0123456789abcdef', k=64))
    })
with open('test-10mb.json', 'w') as f:
    json.dump(data, f)
print(f'   Size: {len(json.dumps(data)):,} bytes')
"
echo "   ✅ test-10mb.json created"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  ✅ Test payloads ready!"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "  Files created:"
ls -lh test-500kb.json test-10mb.json 2>/dev/null | awk '{print "    " $5 "  " $9}'
echo ""
echo "  Usage:"
echo "    1. Open https://moi01.vip in your browser"
echo "    2. Upload test-500kb.json → Should succeed"
echo "    3. Upload test-10mb.json  → Should show Error 413"
echo ""

