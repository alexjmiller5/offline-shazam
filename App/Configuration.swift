import Foundation
import Security

struct DeliveryConfiguration: Codable {
    let endpoint: URL
    let token: String

    init(endpoint: String, token: String) throws {
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw ConfigurationError.invalidEndpoint
        }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 512,
              trimmed.unicodeScalars.allSatisfy({ $0.value >= 33 && $0.value <= 126 }) else {
            throw ConfigurationError.invalidToken
        }
        self.endpoint = url
        self.token = trimmed
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(endpoint: values.decode(URL.self, forKey: .endpoint).absoluteString,
                      token: values.decode(String.self, forKey: .token))
    }
}

enum ConfigurationError: LocalizedError {
    case invalidEndpoint, invalidToken, keychain(OSStatus)
    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "Enter the HTTPS capture URL from Music Sync, without login details or query parameters."
        case .invalidToken: return "Enter a valid capture access token from Music Sync."
        case .keychain: return "Could not access the saved connection. Unlock the phone and try again."
        }
    }
}

struct CapturePayload {
    let id: UUID
    let metadata: MatchMetadata
    func data() throws -> Data {
        var fields = [
            "capture_id": id.uuidString.lowercased(),
            "title": metadata.title,
            "artist": metadata.artist,
            "apple_music_id": metadata.appleMusicID ?? "",
            "shazam_url": metadata.shazamURL ?? ""
        ]
        if let isrc = metadata.isrc { fields["isrc"] = isrc }
        return try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
    }
}

struct ConnectionStore {
    var service = (Bundle.main.bundleIdentifier ?? "offline-shazam") + ".connection"
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: "capture"]
    }

    func load() throws -> DeliveryConfiguration? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else {
            throw ConfigurationError.keychain(status)
        }
        return try JSONDecoder().decode(DeliveryConfiguration.self, from: data)
    }

    func save(_ configuration: DeliveryConfiguration) throws {
        let values: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(configuration),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        var status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw ConfigurationError.keychain(status) }
    }
}
