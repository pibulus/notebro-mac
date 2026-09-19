// NoteBroVaultSync.swift
// Zero-Knowledge Encrypted Pi Vault Sync for NoteBro macOS & iOS
// 100% private, client-side AES-GCM encryption with PBKDF2 key derivation.
// Interoperable with Web/PWA SubtleCrypto at apps/notebro/src/lib/vaultSync.js

import Foundation
import CryptoKit
import CommonCrypto

struct NoteBroVaultSync {
    static let defaultVaultURL = URL(string: "https://vault.talktype.app")!
    private static let appName = "notebro"
    private static let keyIterations: UInt32 = 100_000
    private static let saltBytes = 16
    private static let ivBytes = 12

    // MARK: - Passport Code Helper
    static func normalizeCode(_ code: String) -> String {
        return code.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "[^A-Z0-9-]", with: "", options: .regularExpression)
    }

    static func generatePassportCode() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var part1 = ""
        var part2 = ""
        for _ in 0..<3 {
            part1.append(chars.randomElement()!)
            part2.append(chars.randomElement()!)
        }
        return "BRO-\(part1)\(part2)"
    }

    // MARK: - Vault SHA-256 Hash
    static func vaultHash(for code: String) -> String {
        let norm = normalizeCode(code)
        let data = Data("notebro-vault-id:\(norm)".utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    // MARK: - PBKDF2 Key Derivation
    private static func deriveKey(code: String, salt: Data) throws -> SymmetricKey {
        let norm = normalizeCode(code)
        guard let passwordData = norm.data(using: .utf8) else {
            throw NSError(domain: "NoteBroSync", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid code encoding"])
        }

        var derivedKeyData = Data(count: 32) // 256-bit key
        let derivationStatus = derivedKeyData.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        keyIterations,
                        derivedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        32
                    )
                }
            }
        }

        guard derivationStatus == kCCSuccess else {
            throw NSError(domain: "NoteBroSync", code: 2, userInfo: [NSLocalizedDescriptionKey: "PBKDF2 derivation failed"])
        }

        return SymmetricKey(data: derivedKeyData)
    }

    // MARK: - Payload Envelope
    private struct VaultEnvelope: Codable {
        let version: Int
        let app: String
        let updatedAt: String
        let cards: [NoteCard]
    }

    // MARK: - Encrypt / Decrypt
    static func encrypt(cards: [NoteCard], code: String) throws -> String {
        let envelope = VaultEnvelope(
            version: 1,
            app: appName,
            updatedAt: NoteJSON.isoString(from: Date()),
            cards: cards
        )
        let plaintext = try NoteJSON.encoder.encode(envelope)

        // Generate 16-byte salt and 12-byte nonce
        var salt = Data(count: saltBytes)
        let saltResult = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, saltBytes, $0.baseAddress!) }
        guard saltResult == errSecSuccess else { throw NSError(domain: "NoteBroSync", code: 3) }

        var iv = Data(count: ivBytes)
        let ivResult = iv.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, ivBytes, $0.baseAddress!) }
        guard ivResult == errSecSuccess else { throw NSError(domain: "NoteBroSync", code: 4) }

        let key = try deriveKey(code: code, salt: salt)
        let nonce = try AES.GCM.Nonce(data: iv)
        let sealedBox = try AES.GCM.seal(plaintext, using: key, nonce: nonce)

        var packed = Data()
        packed.append(salt)
        packed.append(iv)
        packed.append(sealedBox.ciphertext)
        packed.append(sealedBox.tag)

        return packed.base64EncodedString()
    }

    static func decrypt(base64Data: String, code: String) throws -> [NoteCard] {
        guard let packed = Data(base64Encoded: base64Data), packed.count >= saltBytes + ivBytes + 16 else {
            throw NSError(domain: "NoteBroSync", code: 5, userInfo: [NSLocalizedDescriptionKey: "Corrupted vault payload"])
        }

        let salt = packed.subdata(in: 0..<saltBytes)
        let iv = packed.subdata(in: saltBytes..<(saltBytes + ivBytes))
        let ciphertextAndTag = packed.subdata(in: (saltBytes + ivBytes)..<packed.count)

        let tagLength = 16
        guard ciphertextAndTag.count >= tagLength else {
            throw NSError(domain: "NoteBroSync", code: 6, userInfo: [NSLocalizedDescriptionKey: "Ciphertext too short"])
        }

        let ciphertext = ciphertextAndTag.subdata(in: 0..<(ciphertextAndTag.count - tagLength))
        let tag = ciphertextAndTag.subdata(in: (ciphertextAndTag.count - tagLength)..<ciphertextAndTag.count)

        let key = try deriveKey(code: code, salt: salt)
        let nonce = try AES.GCM.Nonce(data: iv)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)

        let envelope = try NoteJSON.decoder.decode(VaultEnvelope.self, from: decryptedData)
        return envelope.cards
    }

    // MARK: - Last-Write-Wins (LWW) Merge
    static func merge(local: [NoteCard], remote: [NoteCard]) -> [NoteCard] {
        var cardMap = [String: NoteCard]()

        for card in local {
            cardMap[card.id] = card
        }

        for remoteCard in remote {
            if let existing = cardMap[remoteCard.id] {
                if remoteCard.updatedAt > existing.updatedAt {
                    cardMap[remoteCard.id] = remoteCard
                }
            } else {
                cardMap[remoteCard.id] = remoteCard
            }
        }

        var merged = Array(cardMap.values)
        merged.sort {
            if $0.pinned != $1.pinned {
                return $0.pinned && !$1.pinned
            }
            return $0.updatedAt > $1.updatedAt
        }
        return merged
    }

    // MARK: - HTTP Network Operations
    static func pull(from vaultURL: URL = defaultVaultURL, code: String) async throws -> [NoteCard]? {
        let hash = vaultHash(for: code)
        let endpoint = vaultURL.appendingPathComponent("vault/\(appName)/\(hash)")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpRes = response as? HTTPURLResponse else {
            throw NSError(domain: "NoteBroSync", code: 7)
        }

        if httpRes.statusCode == 404 { return nil }
        guard (200...299).contains(httpRes.statusCode) else {
            throw NSError(domain: "NoteBroSync", code: httpRes.statusCode, userInfo: [NSLocalizedDescriptionKey: "Vault pull HTTP \(httpRes.statusCode)"])
        }

        struct VaultGetResponse: Codable {
            let data: String?
        }
        let parsed = try JSONDecoder().decode(VaultGetResponse.self, from: data)
        guard let b64 = parsed.data else { return nil }
        return try decrypt(base64Data: b64, code: code)
    }

    static func push(to vaultURL: URL = defaultVaultURL, cards: [NoteCard], code: String) async throws {
        let hash = vaultHash(for: code)
        let endpoint = vaultURL.appendingPathComponent("vault/\(appName)/\(hash)")

        let encryptedB64 = try encrypt(cards: cards, code: code)
        let bodyPayload = try JSONSerialization.data(withJSONObject: ["data": encryptedB64])

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyPayload

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode) else {
            throw NSError(domain: "NoteBroSync", code: 8, userInfo: [NSLocalizedDescriptionKey: "Vault push failed"])
        }
    }

    // MARK: - Full 2-Way Sync
    static func sync(vaultURL: URL = defaultVaultURL, cards: [NoteCard], code: String) async throws -> [NoteCard] {
        let remote = try await pull(from: vaultURL, code: code)
        if let remoteCards = remote, !remoteCards.isEmpty {
            let merged = merge(local: cards, remote: remoteCards)
            try await push(to: vaultURL, cards: merged, code: code)
            return merged
        } else {
            try await push(to: vaultURL, cards: cards, code: code)
            return cards
        }
    }
}
