import CryptoKit
import Foundation
import Security

/// The nonce for Sign in with Apple. The UI puts `hashed` in the Apple request
/// (`request.nonce = nonce.hashed` on `SignInWithAppleButton`) and passes `raw` to
/// `AppModel.signInWithApple(idToken:rawNonce:fullName:)`; Supabase checks that the token's nonce is its hash.
enum AppleSignInNonce {
    static func make(length: Int = 32) -> (raw: String, hashed: String) {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        if SecRandomCopyBytes(kSecRandomDefault, length, &bytes) != errSecSuccess {
            for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        }
        let raw = String(bytes.map { charset[Int($0) % charset.count] })
        return (raw, sha256(raw))
    }

    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
