#!/bin/bash
# Round-trips one card Web -> Mac -> Web through the encrypted vault format.
# Catches what silently breaks sync: AES-GCM packing, PBKDF2 params, the "pinned"
# field name, and JS millisecond dates vs Swift's ISO-8601 parser.
# Run from the notebro-mac dir: ./verify-interop.sh
set -e
cd "$(dirname "$0")"
WEB_DIR="$(cd ../../apps/notebro && pwd)"
CODE="BRO-TEST01"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# 1. Web encrypts a pinned card carrying a millisecond timestamp
node -e "
(async () => {
  const { encryptCards } = await import('$WEB_DIR/src/lib/vaultSync.js');
  process.stdout.write(await encryptCards([{
    id: 'interop-1', content: 'hello from the web #sync', color: 'mint', pinned: true,
    createdAt: '2026-09-19T05:00:00.123Z', updatedAt: '2026-09-19T05:00:00.456Z'
  }], '$CODE'));
})();
" > "$TMP/from_web.b64"

# 2. Mac decrypts it, asserts the card survived, re-encrypts
cat > "$TMP/check.swift" <<'SWIFT'
import Foundation
@main struct Check {
    static func main() throws {
        let b64 = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        let code = CommandLine.arguments[2]
        let cards = try NoteBroVaultSync.decrypt(base64Data: b64, code: code)
        guard let card = cards.first else { fatalError("no cards decrypted") }
        guard card.pinned else { fatalError("pinned flag lost decoding web payload") }
        guard card.id == "interop-1" else { fatalError("id lost") }
        guard abs(card.updatedAt.timeIntervalSince1970 - 1789794000.456) < 1.0 else {
            fatalError("millisecond timestamp mangled: \(card.updatedAt)")
        }
        FileHandle.standardOutput.write(Data(try NoteBroVaultSync.encrypt(cards: cards, code: code).utf8))
    }
}
SWIFT
swiftc -parse-as-library -target arm64-apple-macos13.0 \
    NoteBroModel.swift NoteBroVaultSync.swift "$TMP/check.swift" -o "$TMP/check"
"$TMP/check" "$TMP/from_web.b64" "$CODE" > "$TMP/from_mac.b64"

# 3. Web decrypts what the Mac wrote back
node -e "
(async () => {
  const fs = await import('node:fs');
  const { decryptCards } = await import('$WEB_DIR/src/lib/vaultSync.js');
  const c = (await decryptCards(fs.readFileSync('$TMP/from_mac.b64', 'utf8'), '$CODE'))[0];
  if (!c) throw new Error('no cards decrypted');
  if (c.pinned !== true) throw new Error('pinned flag lost on the way back: ' + JSON.stringify(c));
  if (c.id !== 'interop-1') throw new Error('id lost');
  if (Math.abs(new Date(c.updatedAt) - new Date('2026-09-19T05:00:00.456Z')) > 1000)
    throw new Error('timestamp drifted: ' + c.updatedAt);
})();
"

echo "✅ vault interop OK — web → mac → web round-trip intact"
