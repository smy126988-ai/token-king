import Foundation
import CryptoKit

enum VolcanoArkSigner {
    static func signedRequest(
        url: URL,
        accessKey: String,
        secretKey: String,
        service: String = "ark",
        region: String = "cn-beijing"
    ) -> URLRequest? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let resolvedURL = components.url else { return nil }

        var request = URLRequest(url: resolvedURL)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let now = Date()
        let xDate = formatXDate(now)
        request.setValue(xDate, forHTTPHeaderField: "X-Date")

        let payload = Data()
        let payloadHash = sha256Hex(payload)
        request.setValue(payloadHash, forHTTPHeaderField: "X-Content-Sha256")

        let host = components.host ?? ""
        let signedHeaders = "content-type;host;x-content-sha256;x-date"
        let canonicalHeaders = [
            "content-type:application/json; charset=utf-8",
            "host:\(host)",
            "x-content-sha256:\(payloadHash)",
            "x-date:\(xDate)"
        ].joined(separator: "\n") + "\n"

        let canonicalRequest = [
            "POST",
            components.path.isEmpty ? "/" : components.path,
            components.query ?? "",
            canonicalHeaders,
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")

        let shortDate = String(xDate.prefix(8))
        let credentialScope = "\(shortDate)/\(region)/\(service)/request"
        let stringToSign = [
            "HMAC-SHA256",
            xDate,
            credentialScope,
            sha256Hex(Data(canonicalRequest.utf8))
        ].joined(separator: "\n")

        let signingKey = deriveSigningKey(secretKey: secretKey, shortDate: shortDate, region: region, service: service)
        let signature = hmacHex(key: signingKey, data: Data(stringToSign.utf8))

        request.setValue(
            "HMAC-SHA256 Credential=\(accessKey)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)",
            forHTTPHeaderField: "Authorization"
        )
        return request
    }

    private static func formatXDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    private static func sha256Hex(_ data: Data) -> String {
        Data(SHA256.hash(data: data)).map { String(format: "%02x", $0) }.joined()
    }

    private static func hmacHex(key: Data, data: Data) -> String {
        let code = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))
        return Data(code).map { String(format: "%02x", $0) }.joined()
    }

    private static func deriveSigningKey(secretKey: String, shortDate: String, region: String, service: String) -> Data {
        let kDate = HMAC<SHA256>.authenticationCode(for: Data(shortDate.utf8), using: SymmetricKey(data: Data(secretKey.utf8)))
        let kRegion = HMAC<SHA256>.authenticationCode(for: Data(region.utf8), using: SymmetricKey(data: Data(kDate)))
        let kService = HMAC<SHA256>.authenticationCode(for: Data(service.utf8), using: SymmetricKey(data: Data(kRegion)))
        let kSigning = HMAC<SHA256>.authenticationCode(for: Data("request".utf8), using: SymmetricKey(data: Data(kService)))
        return Data(kSigning)
    }
}
