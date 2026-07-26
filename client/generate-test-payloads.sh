#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# MOI01.VIP — Local MacBook Test Traffic Generator
#
# Creates JSON files of specific sizes for live testing:
#   - test-500kb.json  (~500 KB — compliant payload, should pass)
#   - test-10mb.json   (~10 MB — overflow payload, should be dropped at edge)
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

echo "═══════════════════════════════════════════════════════════════"
echo "  MOI01.VIP — Local Test Traffic Generator"
echo "═══════════════════════════════════════════════════════════════"

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
echo "  1. Open https://moi01.vip in your browser"
echo "  2. Upload test-500kb.json → Should succeed & flash on Destination Sink"
echo "  3. Upload test-10mb.json  → Should show Error 413"
echo ""

