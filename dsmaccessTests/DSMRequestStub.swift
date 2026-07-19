import Foundation

actor DSMRequestStub {
    enum Result: Sendable {
        case timeout
        case response(Data)
        case HTTPResponse(data: Data, statusCode: Int, contentType: String)
    }

    private var results: [Result]
    private(set) var requestCount = 0
    private(set) var requests: [URLRequest] = []
    private(set) var uploadedBodies: [Data] = []

    init(results: [Result]) {
        self.results = results
    }

    func data(for request: URLRequest) throws -> (Data, URLResponse) {
        requestCount += 1
        requests.append(request)
        guard !results.isEmpty else {
            throw URLError(.badServerResponse)
        }

        switch results.removeFirst() {
        case .timeout:
            throw URLError(.timedOut)
        case .response(let data):
            return try response(data: data, statusCode: 200, contentType: "application/json", for: request)
        case .HTTPResponse(let data, let statusCode, let contentType):
            return try response(
                data: data,
                statusCode: statusCode,
                contentType: contentType,
                for: request
            )
        }
    }

    func upload(for request: URLRequest, fromFile fileURL: URL) throws -> (Data, URLResponse) {
        uploadedBodies.append(try Data(contentsOf: fileURL))
        return try data(for: request)
    }

    func download(from url: URL) throws -> (URL, URLResponse) {
        let (data, response) = try data(for: URLRequest(url: url))
        let temporaryURL = FileManager.default.temporaryDirectory
            .appending(path: "dsmaccess-download-\(UUID().uuidString)")
        try data.write(to: temporaryURL, options: .atomic)
        return (temporaryURL, response)
    }

    private func response(
        data: Data,
        statusCode: Int,
        contentType: String,
        for request: URLRequest
    ) throws -> (Data, URLResponse) {
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: ["Content-Type": contentType]
                  ) else {
                throw URLError(.badURL)
            }
            return (data, response)
    }
}
