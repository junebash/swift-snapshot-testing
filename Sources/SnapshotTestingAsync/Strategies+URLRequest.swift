#if !os(WASI)
  import Foundation

  #if canImport(FoundationNetworking)
    import FoundationNetworking
  #endif

  // `URLRequest` is a concrete value type, so unlike the generic value strategies in
  // `Strategies+Any.swift`, these are exposed as static *vars*/funcs (no generic parameter needed).

  extension SnapshotStrategy where Self == _Pullback<URLRequest, LinesStrategy> {
    /// A snapshot strategy for comparing requests based on raw equality.
    ///
    /// ```swift
    /// assertSnapshot(of: request, as: .raw)
    /// ```
    ///
    /// Records:
    ///
    /// ```
    /// POST http://localhost:8080/account
    /// Cookie: pf_session={"userId":"1"}
    ///
    /// email=blob%40pointfree.co&name=Blob
    /// ```
    public static var raw: _Pullback<URLRequest, LinesStrategy> {
      .raw(pretty: false)
    }

    /// A snapshot strategy for comparing requests based on raw equality.
    ///
    /// - Parameter pretty: Attempts to pretty print the body of the request (supports JSON).
    public static func raw(pretty: Bool) -> _Pullback<URLRequest, LinesStrategy> {
      LinesStrategy().pullback { (request: URLRequest) in
        let method =
          "\(request.httpMethod ?? "GET") \(request.url?.sortingQueryItems()?.absoluteString ?? "(null)")"

        let headers = (request.allHTTPHeaderFields ?? [:])
          .map { key, value in "\(key): \(value)" }
          .sorted()

        let body: [String]
        do {
          if pretty {
            body =
              try request.httpBody
              .map { try JSONSerialization.jsonObject(with: $0, options: []) }
              .map {
                try JSONSerialization.data(
                  withJSONObject: $0, options: [.prettyPrinted, .sortedKeys])
              }
              .map { ["\n\(String(decoding: $0, as: UTF8.self))"] }
              ?? []
          } else {
            throw NSError(domain: "co.pointfree.Never", code: 1, userInfo: nil)
          }
        } catch {
          body =
            request.httpBody
            .map { ["\n\(String(decoding: $0, as: UTF8.self))"] }
            ?? []
        }

        return ([method] + headers + body).joined(separator: "\n")
      }
    }

    /// A snapshot strategy for comparing requests based on a cURL representation.
    ///
    /// ```swift
    /// assertSnapshot(of: request, as: .curl)
    /// ```
    ///
    /// Records:
    ///
    /// ```
    /// curl \
    ///   --request POST \
    ///   --header "Accept: text/html" \
    ///   --data 'pricing[billing]=monthly&pricing[lane]=individual' \
    ///   "https://www.pointfree.co/subscribe"
    /// ```
    public static var curl: _Pullback<URLRequest, LinesStrategy> {
      LinesStrategy().pullback { (request: URLRequest) in
        var components = ["curl"]

        // HTTP Method
        let httpMethod = request.httpMethod ?? "GET"
        switch httpMethod {
        case "GET": break
        case "HEAD": components.append("--head")
        default: components.append("--request \(httpMethod)")
        }

        // Headers
        if let headers = request.allHTTPHeaderFields {
          for field in headers.keys.sorted() where field != "Cookie" {
            guard let value = headers[field] else { continue }
            let escapedValue = value.replacingOccurrences(of: "\"", with: "\\\"")
            components.append("--header \"\(field): \(escapedValue)\"")
          }
        }

        // Body
        if let httpBodyData = request.httpBody,
          let httpBody = String(data: httpBodyData, encoding: .utf8)
        {
          var escapedBody = httpBody.replacingOccurrences(of: "\\\"", with: "\\\\\"")
          escapedBody = escapedBody.replacingOccurrences(of: "\"", with: "\\\"")

          components.append("--data \"\(escapedBody)\"")
        }

        // Cookies
        if let cookie = request.allHTTPHeaderFields?["Cookie"] {
          let escapedValue = cookie.replacingOccurrences(of: "\"", with: "\\\"")
          components.append("--cookie \"\(escapedValue)\"")
        }

        // URL
        let urlString = request.url?.sortingQueryItems()?.absoluteString ?? ""
        components.append("\"\(urlString)\"")

        return components.joined(separator: " \\\n\t")
      }
    }
  }

  extension URL {
    fileprivate func sortingQueryItems() -> URL? {
      var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
      let sortedQueryItems = components?.queryItems?.sorted { $0.name < $1.name }
      components?.queryItems = sortedQueryItems

      return components?.url
    }
  }
#endif
