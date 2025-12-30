import Foundation

/// Fetches and parses UPnP device description XML from LOCATION URLs
public actor UPnPDescriptionFetcher {
    public static let shared = UPnPDescriptionFetcher()

    private let session: URLSession
    private let timeout: TimeInterval = 5.0

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        self.session = URLSession(configuration: config)
    }

    /// Fetch and parse UPnP device description from a LOCATION URL
    /// - Parameter locationURL: The URL from SSDP LOCATION header
    /// - Returns: Parsed DeviceFingerprint with UPnP data, or nil if fetch/parse failed
    public func fetchDescription(from locationURL: String) async -> DeviceFingerprint? {
        print("[UPnP] Fetching description from: \(locationURL)")

        guard let url = URL(string: locationURL) else {
            print("[UPnP] Invalid URL: \(locationURL)")
            return nil
        }

        do {
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("[UPnP] Non-HTTP response from \(locationURL)")
                return nil
            }

            print("[UPnP] HTTP \(httpResponse.statusCode) from \(locationURL)")

            guard (200...299).contains(httpResponse.statusCode) else {
                print("[UPnP] Bad status code: \(httpResponse.statusCode)")
                return nil
            }

            print("[UPnP] Received \(data.count) bytes, parsing XML...")
            let result = parseXML(data: data)
            if let fp = result {
                print("[UPnP] Parsed successfully: \(fp.friendlyName ?? "unknown") by \(fp.manufacturer ?? "unknown")")
            } else {
                print("[UPnP] XML parsing returned nil")
            }
            return result
        } catch {
            print("[UPnP] Network error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - XML Parsing

    private func parseXML(data: Data) -> DeviceFingerprint? {
        let parser = UPnPXMLParser(data: data)
        return parser.parse()
    }
}

// MARK: - UPnP XML Parser

/// Parses UPnP device description XML
private class UPnPXMLParser: NSObject, XMLParserDelegate {
    private let data: Data

    // Parsing state
    private var currentElement = ""
    private var currentValue = ""
    private var insideDevice = false
    private var insideService = false
    private var serviceDepth = 0

    // Parsed values
    private var friendlyName: String?
    private var manufacturer: String?
    private var manufacturerURL: String?
    private var modelDescription: String?
    private var modelName: String?
    private var modelNumber: String?
    private var serialNumber: String?
    private var deviceType: String?
    private var services: [UPnPService] = []

    // Current service being parsed
    private var currentServiceType: String?
    private var currentServiceId: String?
    private var currentControlURL: String?
    private var currentEventSubURL: String?
    private var currentSCPDURL: String?

    init(data: Data) {
        self.data = data
    }

    func parse() -> DeviceFingerprint? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false

        guard parser.parse() else {
            return nil
        }

        // Only return if we got at least some data
        guard friendlyName != nil || manufacturer != nil || modelName != nil || deviceType != nil else {
            return nil
        }

        return DeviceFingerprint(
            friendlyName: friendlyName,
            manufacturer: manufacturer,
            manufacturerURL: manufacturerURL,
            modelDescription: modelDescription,
            modelName: modelName,
            modelNumber: modelNumber,
            serialNumber: serialNumber,
            upnpDeviceType: deviceType,
            upnpServices: services.isEmpty ? nil : services,
            source: .upnp,
            timestamp: Date(),
            cacheHit: false
        )
    }

    // MARK: XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentValue = ""

        if elementName == "device" {
            insideDevice = true
        } else if elementName == "service" {
            insideService = true
            serviceDepth += 1
            currentServiceType = nil
            currentServiceId = nil
            currentControlURL = nil
            currentEventSubURL = nil
            currentSCPDURL = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentValue += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmedValue = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if insideService {
            switch elementName {
            case "serviceType":
                currentServiceType = trimmedValue
            case "serviceId":
                currentServiceId = trimmedValue
            case "controlURL":
                currentControlURL = trimmedValue
            case "eventSubURL":
                currentEventSubURL = trimmedValue
            case "SCPDURL":
                currentSCPDURL = trimmedValue
            case "service":
                // End of service - save it
                if let type = currentServiceType, let id = currentServiceId {
                    let service = UPnPService(
                        serviceType: type,
                        serviceId: id,
                        controlURL: currentControlURL,
                        eventSubURL: currentEventSubURL,
                        SCPDURL: currentSCPDURL
                    )
                    services.append(service)
                }
                insideService = false
                serviceDepth -= 1
            default:
                break
            }
        } else if insideDevice {
            switch elementName {
            case "friendlyName":
                friendlyName = trimmedValue
            case "manufacturer":
                manufacturer = trimmedValue
            case "manufacturerURL":
                manufacturerURL = trimmedValue
            case "modelDescription":
                modelDescription = trimmedValue
            case "modelName":
                modelName = trimmedValue
            case "modelNumber":
                modelNumber = trimmedValue
            case "serialNumber":
                serialNumber = trimmedValue
            case "deviceType":
                deviceType = trimmedValue
            case "device":
                insideDevice = false
            default:
                break
            }
        }

        currentElement = ""
        currentValue = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        // Silently handle parse errors
    }
}
