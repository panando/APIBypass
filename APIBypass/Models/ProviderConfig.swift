import Foundation

struct ProviderConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var apiProvider: APIProvider
    var baseURL: URL

    init(
        id: UUID = UUID(),
        name: String,
        apiProvider: APIProvider,
        baseURL: URL
    ) {
        self.id = id
        self.name = name
        self.apiProvider = apiProvider
        self.baseURL = baseURL
    }
}
