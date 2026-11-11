import Foundation
import CryptoKit

public struct CryptoManager: Sendable {
    private let key: SymmetricKey

    public init(passphrase: String, saltString: String = "Sokovia-R2-Salt") {
        let inputKey = SymmetricKey(data: Data(passphrase.utf8))
        let salt = Data(saltString.utf8)
        // Derive 256-bit key using HKDF-SHA256
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: salt,
            info: Data("Sokovia-Storage-Encryption-Key-v1".utf8),
            outputByteCount: 32
        )
        self.key = derived
    }

    /// Encrypts plaintext data with AES-256-GCM.
    /// The output data combines 12-byte Nonce + Ciphertext + 16-byte Tag.
    public func encrypt(data: Data) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: self.key)
        guard let combined = sealedBox.combined else {
            throw NSError(domain: "SokoviaCrypto", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to combine sealed box"])
        }
        return combined
    }

    /// Decrypts AES-256-GCM combined data (Nonce + Ciphertext + Tag).
    public func decrypt(data: Data) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: self.key)
    }
}

