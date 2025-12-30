import Foundation

/// Looks up vendor/manufacturer from MAC address OUI (first 3 bytes)
public final class MACVendorLookup: Sendable {
    public static let shared = MACVendorLookup()

    // Extended vendor database - covers most common IoT and network devices
    private let vendors: [String: String] = [
        // Apple (extensive list)
        "00:03:93": "Apple", "00:0A:27": "Apple", "00:0A:95": "Apple", "00:0D:93": "Apple",
        "00:10:FA": "Apple", "00:11:24": "Apple", "00:14:51": "Apple", "00:16:CB": "Apple",
        "00:17:F2": "Apple", "00:19:E3": "Apple", "00:1B:63": "Apple", "00:1C:B3": "Apple",
        "00:1D:4F": "Apple", "00:1E:52": "Apple", "00:1E:C2": "Apple", "00:1F:5B": "Apple",
        "00:1F:F3": "Apple", "00:21:E9": "Apple", "00:22:41": "Apple", "00:23:12": "Apple",
        "00:23:32": "Apple", "00:23:6C": "Apple", "00:23:DF": "Apple", "00:24:36": "Apple",
        "00:25:00": "Apple", "00:25:4B": "Apple", "00:25:BC": "Apple", "00:26:08": "Apple",
        "00:26:4A": "Apple", "00:26:B0": "Apple", "00:26:BB": "Apple", "00:30:65": "Apple",
        "00:3E:E1": "Apple", "00:50:E4": "Apple", "00:56:CD": "Apple", "00:61:71": "Apple",
        "00:6D:52": "Apple", "00:88:65": "Apple", "00:B3:62": "Apple", "00:C6:10": "Apple",
        "00:CD:FE": "Apple", "00:DB:70": "Apple", "00:F4:B9": "Apple", "00:F7:6F": "Apple",
        "04:0C:CE": "Apple", "04:15:52": "Apple", "04:26:65": "Apple", "04:48:9A": "Apple",
        "04:4B:ED": "Apple", "04:52:F3": "Apple", "04:54:53": "Apple", "04:D3:CF": "Apple",
        "04:DB:56": "Apple", "04:E5:36": "Apple", "04:F1:3E": "Apple", "04:F7:E4": "Apple",
        "08:66:98": "Apple", "08:6D:41": "Apple", "08:74:02": "Apple", "0C:4D:E9": "Apple",
        "0C:74:C2": "Apple", "0C:BC:9F": "Apple", "10:40:F3": "Apple", "10:41:7F": "Apple",
        "10:9A:DD": "Apple", "10:DD:B1": "Apple", "14:10:9F": "Apple", "14:5A:05": "Apple",
        "14:8F:C6": "Apple", "14:99:E2": "Apple", "18:20:32": "Apple", "18:34:51": "Apple",
        "18:65:90": "Apple", "18:9E:FC": "Apple", "18:AF:61": "Apple", "18:E7:F4": "Apple",
        "18:EE:69": "Apple", "18:F6:43": "Apple", "1C:1A:C0": "Apple", "1C:36:BB": "Apple",
        "1C:5C:F2": "Apple", "1C:91:48": "Apple", "1C:E6:2B": "Apple", "20:3C:AE": "Apple",
        "20:76:8F": "Apple", "20:78:F0": "Apple", "20:A2:E4": "Apple", "20:AB:37": "Apple",
        "20:C9:D0": "Apple", "24:1E:EB": "Apple", "24:24:0E": "Apple", "24:5B:A7": "Apple",
        "24:A0:74": "Apple", "24:AB:81": "Apple", "24:E3:14": "Apple", "24:F0:94": "Apple",
        "28:0B:5C": "Apple", "28:37:37": "Apple", "28:5A:EB": "Apple", "28:6A:B8": "Apple",
        "28:6A:BA": "Apple", "28:A0:2B": "Apple", "28:CF:DA": "Apple", "28:CF:E9": "Apple",
        "28:E0:2C": "Apple", "28:E1:4C": "Apple", "28:E7:CF": "Apple", "28:ED:E0": "Apple",
        "28:F0:76": "Apple", "2C:1F:23": "Apple", "2C:20:0B": "Apple", "2C:33:61": "Apple",
        "2C:54:CF": "Apple", "2C:61:F6": "Apple", "2C:BE:08": "Apple", "30:10:E4": "Apple",
        "30:35:AD": "Apple", "30:63:6B": "Apple", "30:90:AB": "Apple", "30:F7:C5": "Apple",
        "34:08:BC": "Apple", "34:12:98": "Apple", "34:15:9E": "Apple", "34:36:3B": "Apple",
        "34:51:C9": "Apple", "34:A3:95": "Apple", "34:AB:37": "Apple", "34:C0:59": "Apple",
        "34:E2:FD": "Apple", "38:0F:4A": "Apple", "38:48:4C": "Apple", "38:53:9C": "Apple",
        "38:66:F0": "Apple", "38:71:DE": "Apple", "38:B5:4D": "Apple", "38:C9:86": "Apple",
        "38:CA:DA": "Apple", "38:F9:D3": "Apple", "3C:06:30": "Apple", "3C:07:54": "Apple",
        "3C:15:C2": "Apple", "3C:2E:F9": "Apple", "3C:2E:FF": "Apple", "3C:AB:8E": "Apple",
        "3C:CD:36": "Apple", "3C:D0:F8": "Apple", "3C:E0:72": "Apple", "40:30:04": "Apple",
        "40:33:1A": "Apple", "40:3C:FC": "Apple", "40:4D:7F": "Apple", "40:6C:8F": "Apple",
        "40:83:1D": "Apple", "40:98:AD": "Apple", "40:9C:28": "Apple", "40:A6:D9": "Apple",
        "40:B3:95": "Apple", "40:BC:60": "Apple", "40:CB:C0": "Apple", "40:D3:2D": "Apple",
        "44:00:10": "Apple", "44:2A:60": "Apple", "44:4C:0C": "Apple", "44:D8:84": "Apple",
        "44:FB:42": "Apple", "48:3B:38": "Apple", "48:43:7C": "Apple", "48:4B:AA": "Apple",
        "48:60:BC": "Apple", "48:74:6E": "Apple", "48:A9:1C": "Apple", "48:BF:6B": "Apple",
        "48:D7:05": "Apple", "48:E1:5C": "Apple", "4C:32:75": "Apple", "4C:57:CA": "Apple",
        "4C:74:03": "Apple", "4C:7C:5F": "Apple", "4C:8D:79": "Apple", "4C:B1:99": "Apple",
        "50:1A:C5": "Apple", "50:32:37": "Apple", "50:7A:55": "Apple", "50:82:D5": "Apple",
        "50:BC:96": "Apple", "50:EA:D6": "Apple", "50:ED:3C": "Apple", "54:26:96": "Apple",
        "54:4E:90": "Apple", "54:72:4F": "Apple", "54:99:63": "Apple", "54:9F:13": "Apple",
        "54:AE:27": "Apple", "54:E4:3A": "Apple", "54:EA:A8": "Apple", "54:EE:75": "Apple",
        "58:1F:AA": "Apple", "58:40:4E": "Apple", "58:55:CA": "Apple", "58:B0:35": "Apple",
        "5C:59:48": "Apple", "5C:8D:4E": "Apple", "5C:95:AE": "Apple", "5C:96:9D": "Apple",
        "5C:97:F3": "Apple", "5C:F5:DA": "Apple", "5C:F7:E6": "Apple", "5C:F9:38": "Apple",
        "60:03:08": "Apple", "60:33:4B": "Apple", "60:69:44": "Apple", "60:8C:4A": "Apple",
        "60:92:17": "Apple", "60:A3:7D": "Apple", "60:C5:47": "Apple", "60:D9:C7": "Apple",
        "60:F4:45": "Apple", "60:F8:1D": "Apple", "60:FA:CD": "Apple", "60:FB:42": "Apple",
        "60:FE:C5": "Apple", "64:20:0C": "Apple", "64:4B:F0": "Apple", "64:70:33": "Apple",
        "64:76:BA": "Apple", "64:9A:BE": "Apple", "64:A3:CB": "Apple", "64:A5:C3": "Apple",
        "64:B0:A6": "Apple", "64:B9:E8": "Apple", "64:E6:82": "Apple", "68:09:27": "Apple",
        "68:5B:35": "Apple", "68:64:4B": "Apple", "68:96:7B": "Apple", "68:9C:70": "Apple",
        "68:A8:6D": "Apple", "68:AB:1E": "Apple", "68:AE:20": "Apple", "68:D9:3C": "Apple",
        "68:DB:CA": "Apple", "68:FB:7E": "Apple", "68:FE:F7": "Apple", "6C:19:C0": "Apple",
        "6C:3E:6D": "Apple", "6C:40:08": "Apple", "6C:70:9F": "Apple", "6C:72:E7": "Apple",
        "6C:94:F8": "Apple", "6C:96:CF": "Apple", "6C:AB:31": "Apple", "6C:C2:6B": "Apple",
        "70:11:24": "Apple", "70:14:A6": "Apple", "70:3E:AC": "Apple", "70:48:0F": "Apple",
        "70:56:81": "Apple", "70:5A:0F": "Apple", "70:73:CB": "Apple", "70:81:EB": "Apple",
        "70:A2:B3": "Apple", "70:CD:60": "Apple", "70:DE:E2": "Apple", "70:E7:2C": "Apple",
        "70:EC:E4": "Apple", "70:EF:00": "Apple", "70:F0:87": "Apple", "74:1B:B2": "Apple",
        "74:42:8B": "Apple", "74:8D:08": "Apple", "74:8F:3C": "Apple", "74:9E:AF": "Apple",
        "74:E1:B6": "Apple", "74:E2:F5": "Apple", "78:31:C1": "Apple", "78:32:1B": "Apple",
        "78:3A:84": "Apple", "78:4F:43": "Apple", "78:67:D7": "Apple", "78:6C:1C": "Apple",
        "78:7E:61": "Apple", "78:88:6D": "Apple", "78:9F:70": "Apple", "78:A3:E4": "Apple",
        "78:BD:BC": "Apple", "78:CA:39": "Apple", "78:D7:5F": "Apple", "78:FD:94": "Apple",
        "7C:01:91": "Apple", "7C:04:D0": "Apple", "7C:11:BE": "Apple", "7C:50:49": "Apple",
        "7C:6D:62": "Apple", "7C:6D:F8": "Apple", "7C:9A:1D": "Apple", "7C:C3:A1": "Apple",
        "7C:C5:37": "Apple", "7C:D1:C3": "Apple", "7C:F0:5F": "Apple", "7C:FA:DF": "Apple",
        "80:00:6E": "Apple", "80:19:34": "Apple", "80:49:71": "Apple", "80:82:23": "Apple",
        "80:92:9F": "Apple", "80:B0:3D": "Apple", "80:BE:05": "Apple", "80:E6:50": "Apple",
        "80:EA:96": "Apple", "80:ED:2C": "Apple", "84:29:99": "Apple", "84:38:35": "Apple",
        "84:78:8B": "Apple", "84:85:06": "Apple", "84:89:AD": "Apple", "84:8E:0C": "Apple",
        "84:8F:69": "Apple", "84:A1:34": "Apple", "84:B1:53": "Apple", "84:FC:AC": "Apple",
        "84:FC:FE": "Apple", "88:19:08": "Apple", "88:1F:A1": "Apple", "88:53:95": "Apple",
        "88:63:DF": "Apple", "88:64:40": "Apple", "88:66:A5": "Apple", "88:6B:6E": "Apple",
        "88:AE:07": "Apple", "88:C6:63": "Apple", "88:CB:87": "Apple", "88:E8:7F": "Apple",
        "88:E9:FE": "Apple", "8C:00:6D": "Apple", "8C:29:37": "Apple", "8C:2D:AA": "Apple",
        "8C:58:77": "Apple", "8C:7B:9D": "Apple", "8C:7C:92": "Apple", "8C:85:90": "Apple",
        "8C:8F:E9": "Apple", "8C:FA:BA": "Apple", "90:27:E4": "Apple", "90:3C:92": "Apple",
        "90:60:F1": "Apple", "90:72:40": "Apple", "90:84:0D": "Apple", "90:8D:6C": "Apple",
        "90:B0:ED": "Apple", "90:B2:1F": "Apple", "90:B9:31": "Apple", "90:C1:C6": "Apple",
        "90:DD:5D": "Apple", "90:FD:61": "Apple", "94:94:26": "Apple", "94:BF:94": "Apple",
        "94:E9:6A": "Apple", "94:F6:A3": "Apple", "98:01:A7": "Apple", "98:03:D8": "Apple",
        "98:10:E8": "Apple", "98:5A:EB": "Apple", "98:69:8A": "Apple", "98:B8:E3": "Apple",
        "98:CA:33": "Apple", "98:D6:BB": "Apple", "98:E0:D9": "Apple", "98:F0:AB": "Apple",
        "98:FE:94": "Apple", "9C:04:EB": "Apple", "9C:20:7B": "Apple", "9C:29:3F": "Apple",
        "9C:35:EB": "Apple", "9C:4F:DA": "Apple", "9C:84:BF": "Apple", "9C:8B:A0": "Apple",
        "9C:E3:3F": "Apple", "9C:E6:5E": "Apple", "9C:F3:87": "Apple", "9C:F4:8E": "Apple",
        "A0:18:28": "Apple", "A0:3B:E3": "Apple", "A0:4E:A7": "Apple", "A0:56:F3": "Apple",
        "A0:78:17": "Apple", "A0:99:9B": "Apple", "A0:D7:95": "Apple", "A0:ED:CD": "Apple",
        "A0:F4:79": "Apple", "A4:5E:60": "Apple", "A4:67:06": "Apple", "A4:83:E7": "Apple",
        "A4:B1:97": "Apple", "A4:B8:05": "Apple", "A4:C3:61": "Apple", "A4:D1:8C": "Apple",
        "A4:D1:D2": "Apple", "A4:D9:31": "Apple", "A4:F1:E8": "Apple", "A8:20:66": "Apple",
        "A8:26:D9": "Apple", "A8:5B:78": "Apple", "A8:5C:2C": "Apple", "A8:66:7F": "Apple",
        "A8:86:DD": "Apple", "A8:88:08": "Apple", "A8:8E:24": "Apple", "A8:96:75": "Apple",
        "A8:BE:27": "Apple", "A8:FA:D8": "Apple", "A8:FE:9F": "Apple", "AC:1F:74": "Apple",
        "AC:29:3A": "Apple", "AC:3C:0B": "Apple", "AC:61:EA": "Apple", "AC:7F:3E": "Apple",
        "AC:87:A3": "Apple", "AC:BC:32": "Apple", "AC:CF:5C": "Apple", "AC:E4:B5": "Apple",
        "AC:E9:3A": "Apple", "AC:FD:CE": "Apple", "B0:19:C6": "Apple", "B0:34:95": "Apple",
        "B0:48:1A": "Apple", "B0:65:BD": "Apple", "B0:70:2D": "Apple", "B0:9F:BA": "Apple",
        "B4:18:D1": "Apple", "B4:4B:D2": "Apple", "B4:8B:19": "Apple", "B4:9C:DF": "Apple",
        "B4:F0:AB": "Apple", "B4:F6:1C": "Apple", "B8:09:8A": "Apple", "B8:17:C2": "Apple",
        "B8:41:A4": "Apple", "B8:44:D9": "Apple", "B8:53:AC": "Apple", "B8:5A:F7": "Apple",
        "B8:63:4D": "Apple", "B8:78:2E": "Apple", "B8:7B:C5": "Apple", "B8:8D:12": "Apple",
        "B8:C1:11": "Apple", "B8:C7:5D": "Apple", "B8:E8:56": "Apple", "B8:F6:B1": "Apple",
        "B8:FF:61": "Apple", "BC:3B:AF": "Apple", "BC:4C:C4": "Apple", "BC:52:B7": "Apple",
        "BC:54:36": "Apple", "BC:67:78": "Apple", "BC:6C:21": "Apple", "BC:92:6B": "Apple",
        "BC:9F:EF": "Apple", "BC:A9:20": "Apple", "BC:D1:1F": "Apple", "BC:EC:5D": "Apple",
        "BC:FE:D9": "Apple", "C0:1A:DA": "Apple", "C0:25:5C": "Apple", "C0:36:72": "Apple",
        "C0:63:94": "Apple", "C0:84:7A": "Apple", "C0:9A:D0": "Apple", "C0:A5:3E": "Apple",
        "C0:CC:F8": "Apple", "C0:CE:CD": "Apple", "C0:D0:12": "Apple", "C0:D3:C0": "Apple",
        "C0:D7:AA": "Apple", "C0:F2:FB": "Apple", "C4:2C:03": "Apple", "C4:61:8B": "Apple",
        "C4:B3:01": "Apple", "C8:1E:E7": "Apple", "C8:2A:14": "Apple", "C8:33:4B": "Apple",
        "C8:3C:85": "Apple", "C8:69:CD": "Apple", "C8:6F:1D": "Apple", "C8:85:50": "Apple",
        "C8:B5:B7": "Apple", "C8:BC:C8": "Apple", "C8:D0:83": "Apple", "C8:E0:EB": "Apple",
        "C8:F6:50": "Apple", "CC:08:8D": "Apple", "CC:20:E8": "Apple", "CC:25:EF": "Apple",
        "CC:29:F5": "Apple", "CC:44:63": "Apple", "CC:78:5F": "Apple", "CC:C7:60": "Apple",
        "D0:03:4B": "Apple", "D0:0D:46": "Apple", "D0:23:DB": "Apple", "D0:25:98": "Apple",
        "D0:33:11": "Apple", "D0:4F:7E": "Apple", "D0:81:7A": "Apple", "D0:A6:37": "Apple",
        "D0:C5:F3": "Apple", "D0:E1:40": "Apple", "D4:61:9D": "Apple", "D4:9A:20": "Apple",
        "D4:A3:3D": "Apple", "D4:DC:CD": "Apple", "D4:F4:6F": "Apple", "D8:00:4D": "Apple",
        "D8:1C:79": "Apple", "D8:30:62": "Apple", "D8:8F:76": "Apple", "D8:96:95": "Apple",
        "D8:9E:3F": "Apple", "D8:A2:5E": "Apple", "D8:BB:2C": "Apple", "D8:CF:9C": "Apple",
        "D8:D1:CB": "Apple", "DC:0C:5C": "Apple", "DC:2B:2A": "Apple", "DC:2B:61": "Apple",
        "DC:37:14": "Apple", "DC:41:5F": "Apple", "DC:56:E7": "Apple", "DC:86:D8": "Apple",
        "DC:9B:9C": "Apple", "DC:A4:CA": "Apple", "DC:A9:04": "Apple", "DC:D3:A2": "Apple",
        "E0:5F:45": "Apple", "E0:66:78": "Apple", "E0:6F:13": "Apple", "E0:AC:CB": "Apple",
        "E0:B5:5F": "Apple", "E0:B9:BA": "Apple", "E0:C7:67": "Apple", "E0:C9:7A": "Apple",
        "E0:F5:C6": "Apple", "E0:F8:47": "Apple", "E4:25:E7": "Apple", "E4:2B:34": "Apple",
        "E4:8B:7F": "Apple", "E4:98:D6": "Apple", "E4:9A:79": "Apple", "E4:9A:DC": "Apple",
        "E4:C6:3D": "Apple", "E4:CE:8F": "Apple", "E4:E4:AB": "Apple", "E8:06:88": "Apple",
        "E8:36:17": "Apple", "E8:80:2E": "Apple", "E8:8D:28": "Apple", "E8:B2:AC": "Apple",
        "EC:35:86": "Apple", "EC:85:2F": "Apple", "EC:AD:B8": "Apple", "F0:18:98": "Apple",
        "F0:24:75": "Apple", "F0:79:60": "Apple", "F0:99:B6": "Apple", "F0:B0:E7": "Apple",
        "F0:B4:79": "Apple", "F0:C1:F1": "Apple", "F0:CB:A1": "Apple", "F0:D1:A9": "Apple",
        "F0:DB:E2": "Apple", "F0:DC:E2": "Apple", "F0:F6:1C": "Apple", "F4:0F:24": "Apple",
        "F4:1B:A1": "Apple", "F4:31:C3": "Apple", "F4:37:B7": "Apple", "F4:5C:89": "Apple",
        "F4:5F:D4": "Apple", "F4:F1:5A": "Apple", "F4:F9:51": "Apple", "F8:03:32": "Apple",
        "F8:1E:DF": "Apple", "F8:27:93": "Apple", "F8:38:80": "Apple", "F8:4D:89": "Apple",
        "F8:62:14": "Apple", "F8:95:C7": "Apple", "FC:25:3F": "Apple", "FC:A1:3E": "Apple",
        "FC:D8:48": "Apple", "FC:E9:98": "Apple", "FC:FC:48": "Apple",

        // Ubiquiti (extensive)
        "00:15:6D": "Ubiquiti", "00:27:22": "Ubiquiti", "04:18:D6": "Ubiquiti",
        "18:E8:29": "Ubiquiti", "24:5A:4C": "Ubiquiti", "24:A4:3C": "Ubiquiti",
        "44:D9:E7": "Ubiquiti", "68:72:51": "Ubiquiti", "74:83:C2": "Ubiquiti",
        "74:AC:B9": "Ubiquiti", "78:45:58": "Ubiquiti", "80:2A:A8": "Ubiquiti",
        "B4:FB:E4": "Ubiquiti", "DC:9F:DB": "Ubiquiti", "E0:63:DA": "Ubiquiti",
        "F0:9F:C2": "Ubiquiti", "FC:EC:DA": "Ubiquiti", "E4:38:83": "Ubiquiti",
        "AC:8B:A9": "Ubiquiti", "78:8A:20": "Ubiquiti", "28:70:4E": "Ubiquiti",

        // Sonos
        "00:0E:58": "Sonos", "34:7E:5C": "Sonos", "48:A6:B8": "Sonos",
        "5C:AA:FD": "Sonos", "78:28:CA": "Sonos", "94:9F:3E": "Sonos",
        "B8:E9:37": "Sonos", "54:2A:1B": "Sonos", "F0:F6:C1": "Sonos",

        // Google/Nest
        "00:1A:11": "Google", "1C:F2:9A": "Google", "3C:5A:B4": "Google",
        "54:60:09": "Google", "94:EB:2C": "Google", "A4:77:33": "Google",
        "F4:F5:D8": "Google", "F4:F5:E8": "Google", "D8:6C:63": "Google",
        "CC:F4:11": "Google", "20:DF:B9": "Google", "18:D6:C7": "Google",
        "18:B4:30": "Google Nest", "64:16:66": "Google Nest", "F8:0F:F9": "Google Nest",

        // Amazon/Ring
        "00:FC:8B": "Amazon", "0C:47:C9": "Amazon", "10:CE:A9": "Amazon",
        "18:74:2E": "Amazon", "34:D2:70": "Amazon", "40:B4:CD": "Amazon",
        "44:65:0D": "Amazon", "50:DC:E7": "Amazon", "68:37:E9": "Amazon",
        "68:54:FD": "Amazon", "74:C2:46": "Amazon", "78:E1:03": "Amazon",
        "84:D6:D0": "Amazon", "A0:02:DC": "Amazon", "AC:63:BE": "Amazon",
        "B4:7C:9C": "Amazon", "F0:27:2D": "Amazon", "F0:F0:A4": "Amazon",
        "FC:65:DE": "Amazon", "4C:EF:C0": "Amazon", "CC:F7:35": "Amazon",
        "34:3E:A4": "Ring", "40:38:C9": "Ring", "6C:8B:D3": "Ring",
        "90:A2:DA": "Ring",

        // Samsung
        "00:00:F0": "Samsung", "00:02:78": "Samsung", "00:07:AB": "Samsung",
        "00:09:18": "Samsung", "00:0D:AE": "Samsung", "00:12:47": "Samsung",
        "00:12:FB": "Samsung", "00:13:77": "Samsung", "00:15:99": "Samsung",
        "00:15:B9": "Samsung", "00:16:32": "Samsung", "00:16:6B": "Samsung",
        "00:16:6C": "Samsung", "00:16:DB": "Samsung", "00:17:C9": "Samsung",
        "00:17:D5": "Samsung", "00:18:AF": "Samsung", "00:1A:8A": "Samsung",
        "00:1B:98": "Samsung", "00:1C:43": "Samsung", "00:1D:25": "Samsung",
        "00:1D:F6": "Samsung", "00:1E:7D": "Samsung", "00:1F:CC": "Samsung",
        "00:1F:CD": "Samsung", "00:21:19": "Samsung", "00:21:4C": "Samsung",
        "00:21:D1": "Samsung", "00:21:D2": "Samsung", "00:23:39": "Samsung",
        "00:23:3A": "Samsung", "00:23:99": "Samsung", "00:23:D6": "Samsung",
        "00:23:D7": "Samsung", "00:24:54": "Samsung", "00:24:90": "Samsung",
        "00:24:91": "Samsung", "00:24:E9": "Samsung", "00:25:66": "Samsung",
        "00:25:67": "Samsung", "00:26:37": "Samsung", "00:26:5D": "Samsung",
        "00:26:5F": "Samsung", "08:08:C2": "Samsung", "08:37:3D": "Samsung",
        "0C:DF:A4": "Samsung", "10:D5:42": "Samsung", "14:49:E0": "Samsung",
        "14:89:FD": "Samsung", "18:3A:2D": "Samsung", "18:67:B0": "Samsung",
        "1C:5A:3E": "Samsung", "20:13:E0": "Samsung", "20:55:31": "Samsung",
        "20:64:32": "Samsung", "24:4B:81": "Samsung", "28:27:BF": "Samsung",
        "28:98:7B": "Samsung", "28:BA:B5": "Samsung", "2C:44:01": "Samsung",
        "30:07:4D": "Samsung", "30:19:66": "Samsung", "30:96:FB": "Samsung",
        "30:CD:A7": "Samsung", "34:23:BA": "Samsung", "34:BE:00": "Samsung",
        "34:C3:AC": "Samsung", "38:01:97": "Samsung", "38:16:D1": "Samsung",
        "38:2D:D1": "Samsung", "3C:5A:37": "Samsung", "3C:62:00": "Samsung",
        "3C:8B:FE": "Samsung", "40:0E:85": "Samsung", "44:4E:1A": "Samsung",
        "44:6D:6C": "Samsung", "44:78:3E": "Samsung", "44:F4:59": "Samsung",
        "48:13:7E": "Samsung", "4C:3C:16": "Samsung", "50:01:BB": "Samsung",
        "50:32:75": "Samsung", "50:85:69": "Samsung", "50:A4:C8": "Samsung",
        "50:B7:C3": "Samsung", "50:CC:F8": "Samsung", "50:F0:D3": "Samsung",
        "54:40:AD": "Samsung", "54:92:BE": "Samsung", "54:FA:3E": "Samsung",
        "58:C3:8B": "Samsung", "5C:2E:59": "Samsung", "5C:3C:27": "Samsung",
        "5C:A3:9D": "Samsung", "60:6B:BD": "Samsung", "60:A1:0A": "Samsung",
        "60:D0:A9": "Samsung", "64:77:91": "Samsung", "68:48:98": "Samsung",
        "68:EB:AE": "Samsung", "6C:2F:2C": "Samsung", "70:F9:27": "Samsung",
        "74:45:8A": "Samsung", "78:1F:DB": "Samsung", "78:25:AD": "Samsung",
        "78:40:E4": "Samsung", "78:AB:BB": "Samsung",
        "78:D6:F0": "Samsung", "7C:0B:C6": "Samsung",
        "7C:B1:5D": "Samsung", "80:18:A7": "Samsung", "80:65:6D": "Samsung",
        "84:25:DB": "Samsung", "84:38:38": "Samsung", "84:55:A5": "Samsung",
        "88:32:9B": "Samsung", "88:83:22": "Samsung", "8C:71:F8": "Samsung",
        "8C:77:12": "Samsung", "8C:F5:A3": "Samsung", "90:00:4E": "Samsung",
        "90:18:7C": "Samsung", "90:F1:AA": "Samsung", "94:01:C2": "Samsung",
        "94:35:0A": "Samsung", "94:51:03": "Samsung", "94:63:D1": "Samsung",
        "94:B1:0A": "Samsung", "98:0C:82": "Samsung", "98:52:B1": "Samsung",
        "9C:02:98": "Samsung", "9C:3A:AF": "Samsung", "9C:65:B0": "Samsung",
        "A0:07:98": "Samsung", "A0:21:95": "Samsung", "A0:82:1F": "Samsung",
        "A0:B4:A5": "Samsung", "A4:84:31": "Samsung", "A8:06:00": "Samsung",
        "A8:7C:01": "Samsung", "AC:36:13": "Samsung", "AC:5A:14": "Samsung",
        "AC:5F:3E": "Samsung", "B0:47:BF": "Samsung", "B0:72:BF": "Samsung",
        "B0:C4:E7": "Samsung", "B0:DF:3A": "Samsung", "B0:EC:71": "Samsung",
        "B4:3A:28": "Samsung", "B4:79:A7": "Samsung", "B4:EF:39": "Samsung",
        "B8:5A:73": "Samsung", "BC:14:01": "Samsung", "BC:20:A4": "Samsung",
        "BC:44:86": "Samsung", "BC:72:B1": "Samsung", "BC:8C:CD": "Samsung",
        "C0:19:7C": "Samsung", "C0:BD:D1": "Samsung",
        "C4:42:02": "Samsung", "C4:73:1E": "Samsung", "C4:AE:12": "Samsung",
        "C8:19:F7": "Samsung", "C8:BA:94": "Samsung", "CC:07:AB": "Samsung",
        "D0:22:BE": "Samsung", "D0:59:E4": "Samsung", "D0:66:7B": "Samsung",
        "D0:87:E2": "Samsung", "D4:88:90": "Samsung", "D4:E8:B2": "Samsung",
        "D8:57:EF": "Samsung", "D8:90:E8": "Samsung", "DC:66:72": "Samsung",
        "E0:99:71": "Samsung", "E4:12:1D": "Samsung", "E4:32:CB": "Samsung",
        "E4:7C:F9": "Samsung", "E4:92:FB": "Samsung", "E4:E0:C5": "Samsung",
        "E8:03:9A": "Samsung", "E8:50:8B": "Samsung", "EC:1F:72": "Samsung",
        "EC:9B:F3": "Samsung", "F0:25:B7": "Samsung", "F0:5A:09": "Samsung",
        "F0:6B:CA": "Samsung", "F0:72:8C": "Samsung", "F4:09:D8": "Samsung",
        "F4:7B:5E": "Samsung", "F4:D9:FB": "Samsung", "F8:04:2E": "Samsung",
        "F8:3F:51": "Samsung", "F8:77:B8": "Samsung",
        "FC:F1:36": "Samsung",

        // LG
        "00:1C:62": "LG", "00:1E:75": "LG", "00:1F:6B": "LG", "00:1F:E2": "LG",
        "00:22:A9": "LG", "00:24:83": "LG", "00:25:E5": "LG", "00:26:E2": "LG",
        "00:34:DA": "LG", "00:AA:70": "LG", "00:E0:91": "LG", "10:68:3F": "LG",
        "20:21:A5": "LG", "28:A0:24": "LG", "34:4D:F7": "LG",
        "38:8C:50": "LG", "40:B0:FA": "LG", "58:3F:54": "LG", "64:99:5D": "LG",
        "74:44:01": "LG", "74:A7:22": "LG", "78:5D:C8": "LG", "84:C0:EF": "LG",
        "88:07:4B": "LG", "88:C9:D0": "LG", "94:C9:B2": "LG", "A8:23:FE": "LG",
        "AC:0D:1B": "LG", "B4:E6:2A": "LG", "BC:F5:AC": "LG", "C4:36:6C": "LG",
        "C4:9A:02": "LG", "CC:FA:00": "LG", "D0:13:FD": "LG", "E8:5B:5B": "LG",
        "F8:0C:F3": "LG", "F8:23:B2": "LG",

        // Sony
        "00:01:4A": "Sony", "00:04:1F": "Sony", "00:0A:D9": "Sony", "00:0B:0D": "Sony",
        "00:0E:07": "Sony", "00:0F:DE": "Sony", "00:12:EE": "Sony", "00:13:A9": "Sony",
        "00:15:C1": "Sony", "00:16:20": "Sony", "00:18:13": "Sony", "00:19:63": "Sony",
        "00:1A:80": "Sony", "00:1D:28": "Sony", "00:1E:A4": "Sony", "00:1F:E4": "Sony",
        "00:21:9E": "Sony", "00:23:45": "Sony", "00:24:BE": "Sony", "28:0D:FC": "Sony",
        "30:39:26": "Sony", "40:B8:37": "Sony", "4C:C6:81": "Sony", "54:42:49": "Sony",
        "58:48:22": "Sony", "5C:B5:24": "Sony", "70:9E:29": "Sony", "78:84:3C": "Sony",
        "84:00:D2": "Sony", "AC:9B:0A": "Sony", "D4:6A:6A": "Sony",
        "D8:D4:3C": "Sony", "E0:B9:A5": "Sony", "F8:D0:AC": "Sony", "FC:0F:E6": "Sony",

        // Roku
        "00:0D:4B": "Roku", "08:05:81": "Roku", "20:EF:BD": "Roku", "AC:3A:7A": "Roku",
        "B0:A7:37": "Roku", "B8:3E:59": "Roku", "C8:3A:6B": "Roku", "D0:4D:C6": "Roku",
        "D8:31:34": "Roku", "DC:3A:5E": "Roku", "84:EA:ED": "Roku",

        // Philips/Hue
        "00:17:88": "Philips Hue", "EC:B5:FA": "Philips Hue", "00:24:88": "Philips",
        "AC:89:95": "Philips",

        // Espressif (ESP8266/ESP32 - IoT)
        "18:FE:34": "Espressif", "24:0A:C4": "Espressif", "24:6F:28": "Espressif",
        "24:B2:DE": "Espressif", "2C:3A:E8": "Espressif", "30:AE:A4": "Espressif",
        "3C:61:05": "Espressif", "3C:71:BF": "Espressif", "40:F5:20": "Espressif",
        "4C:11:AE": "Espressif", "5C:CF:7F": "Espressif", "60:01:94": "Espressif",
        "68:C6:3A": "Espressif", "80:7D:3A": "Espressif", "84:0D:8E": "Espressif",
        "84:CC:A8": "Espressif", "84:F3:EB": "Espressif", "8C:AA:B5": "Espressif",
        "90:97:D5": "Espressif", "98:F4:AB": "Espressif", "A0:20:A6": "Espressif",
        "A4:7B:9D": "Espressif", "A4:CF:12": "Espressif", "AC:67:B2": "Espressif",
        "B4:E6:2D": "Espressif", "BC:DD:C2": "Espressif", "C4:4F:33": "Espressif",
        "C8:2B:96": "Espressif", "CC:50:E3": "Espressif", "D8:A0:1D": "Espressif",
        "D8:BF:C0": "Espressif", "DC:4F:22": "Espressif", "E8:DB:84": "Espressif",
        "EC:FA:BC": "Espressif", "F4:CF:A2": "Espressif", "E0:98:06": "Espressif",
        "A8:03:2A": "Espressif", "FC:F5:C4": "Espressif", "B0:B2:1C": "Espressif",

        // Tuya/Smart Life
        "D8:1F:12": "Tuya", "10:D5:61": "Tuya", "68:57:2D": "Tuya",

        // TP-Link/Kasa
        "00:27:0E": "TP-Link", "00:31:92": "TP-Link", "10:FE:ED": "TP-Link",
        "14:CC:20": "TP-Link", "14:CF:92": "TP-Link", "18:A6:F7": "TP-Link",
        "1C:3B:F3": "TP-Link", "30:B5:C2": "TP-Link", "50:C7:BF": "TP-Link",
        "54:C8:0F": "TP-Link", "60:E3:27": "TP-Link", "64:70:02": "TP-Link",
        "6C:5A:B0": "TP-Link", "78:44:76": "TP-Link", "90:F6:52": "TP-Link",
        "98:DA:C4": "TP-Link", "A0:F3:C1": "TP-Link", "AC:84:C6": "TP-Link",
        "B0:4E:26": "TP-Link", "B0:BE:76": "TP-Link", "C0:06:C3": "TP-Link",
        "C0:25:E9": "TP-Link", "C4:6E:1F": "TP-Link", "C8:3A:35": "TP-Link",
        "D4:6E:0E": "TP-Link", "E8:DE:27": "TP-Link", "EC:08:6B": "TP-Link",
        "F4:F2:6D": "TP-Link", "50:D4:F7": "TP-Link", "60:32:B1": "TP-Link",
        "B0:A7:B9": "TP-Link", "5C:A6:E6": "TP-Link", "FC:9C:A7": "TP-Link Kasa",

        // Intel
        "00:02:B3": "Intel", "00:03:47": "Intel", "00:04:23": "Intel",
        "00:07:E9": "Intel", "00:0C:F1": "Intel", "00:0E:0C": "Intel",
        "00:0E:35": "Intel", "00:11:11": "Intel", "00:12:F0": "Intel",
        "00:13:02": "Intel", "00:13:20": "Intel", "00:13:CE": "Intel",
        "00:13:E8": "Intel", "00:15:00": "Intel", "00:15:17": "Intel",
        "00:16:6F": "Intel", "00:16:76": "Intel", "00:16:EA": "Intel",
        "00:16:EB": "Intel", "00:17:35": "Intel", "00:18:DE": "Intel",
        "00:19:D1": "Intel", "00:19:D2": "Intel", "00:1B:21": "Intel",
        "00:1B:77": "Intel", "00:1C:BF": "Intel", "00:1C:C0": "Intel",
        "00:1D:E0": "Intel", "00:1D:E1": "Intel", "00:1E:64": "Intel",
        "00:1E:65": "Intel", "00:1E:67": "Intel", "00:1F:3B": "Intel",
        "00:1F:3C": "Intel", "00:20:E0": "Intel", "00:21:5C": "Intel",
        "00:21:5D": "Intel", "00:21:6A": "Intel", "00:21:6B": "Intel",
        "00:22:FA": "Intel", "00:22:FB": "Intel", "00:23:14": "Intel",
        "00:23:15": "Intel", "00:24:D6": "Intel", "00:24:D7": "Intel",
        "00:26:C6": "Intel", "00:26:C7": "Intel", "00:27:10": "Intel",

        // HP
        "00:00:63": "HP", "00:01:E6": "HP", "00:01:E7": "HP", "00:02:A5": "HP",
        "00:04:EA": "HP", "00:08:02": "HP", "00:08:83": "HP", "00:09:B3": "HP",
        "00:0A:57": "HP", "00:0B:CD": "HP", "00:0D:9D": "HP", "00:0E:7F": "HP",
        "00:0F:20": "HP", "00:0F:61": "HP", "00:10:83": "HP", "00:10:E3": "HP",
        "00:11:0A": "HP", "00:11:85": "HP", "00:12:79": "HP", "00:13:21": "HP",
        "00:14:38": "HP", "00:14:C2": "HP", "00:15:60": "HP", "00:16:35": "HP",
        "00:17:08": "HP", "00:17:A4": "HP", "00:18:FE": "HP", "00:19:BB": "HP",
        "00:1A:4B": "HP", "00:1B:78": "HP", "00:1C:2E": "HP", "00:1C:C4": "HP",
        "00:1D:31": "HP", "00:1D:B3": "HP", "00:1E:0B": "HP", "00:1F:29": "HP",
        "00:21:5A": "HP", "00:22:64": "HP", "00:23:7D": "HP", "00:24:81": "HP",
        "00:25:B3": "HP", "00:26:55": "HP", "00:27:0D": "HP", "18:A9:05": "HP",
        "28:80:23": "HP", "30:E1:71": "HP", "3C:D9:2B": "HP", "40:A8:F0": "HP",
        "48:0F:CF": "HP", "58:20:B1": "HP", "64:51:06": "HP", "70:10:6F": "HP",
        "78:48:59": "HP", "80:C1:6E": "HP", "84:34:97": "HP", "98:4B:E1": "HP",
        "9C:B6:54": "HP", "A0:1D:48": "HP", "A0:2B:B8": "HP", "A0:D3:C1": "HP",
        "AC:16:2D": "HP", "B4:99:BA": "HP", "B4:B5:2F": "HP", "C0:91:34": "HP",
        "C8:CB:B8": "HP", "D4:85:64": "HP", "D8:D3:85": "HP", "E4:11:5B": "HP",
        "EC:8E:B5": "HP", "F0:62:81": "HP", "F4:03:43": "HP", "F4:CE:46": "HP",
        "FC:3F:DB": "HP",

        // Dell
        "00:06:5B": "Dell", "00:08:74": "Dell", "00:0B:DB": "Dell", "00:0D:56": "Dell",
        "00:0F:1F": "Dell", "00:11:43": "Dell", "00:12:3F": "Dell", "00:13:72": "Dell",
        "00:14:22": "Dell", "00:15:C5": "Dell", "00:16:F0": "Dell", "00:18:8B": "Dell",
        "00:19:B9": "Dell", "00:1A:A0": "Dell", "00:1C:23": "Dell", "00:1D:09": "Dell",
        "00:1E:4F": "Dell", "00:1E:C9": "Dell", "00:21:70": "Dell", "00:21:9B": "Dell",
        "00:22:19": "Dell", "00:23:AE": "Dell", "00:24:E8": "Dell", "00:25:64": "Dell",
        "00:26:B9": "Dell", "14:18:77": "Dell", "14:9E:CF": "Dell", "14:B3:1F": "Dell",
        "14:FE:B5": "Dell", "18:03:73": "Dell", "18:66:DA": "Dell", "18:A9:9B": "Dell",
        "18:DB:F2": "Dell", "1C:40:24": "Dell", "20:47:47": "Dell", "24:6E:96": "Dell",
        "24:B6:FD": "Dell", "28:C8:25": "Dell", "28:F1:0E": "Dell", "34:17:EB": "Dell",
        "34:E6:D7": "Dell", "44:A8:42": "Dell", "4C:76:25": "Dell", "50:9A:4C": "Dell",
        "54:9F:35": "Dell", "5C:26:0A": "Dell", "5C:F9:DD": "Dell", "64:00:6A": "Dell",
        "74:86:7A": "Dell", "74:E6:E2": "Dell", "78:2B:CB": "Dell", "84:2B:2B": "Dell",
        "84:7B:EB": "Dell", "90:B1:1C": "Dell", "98:90:96": "Dell",
        "A4:1F:72": "Dell", "A4:BA:DB": "Dell", "B0:83:FE": "Dell",
        "B4:E1:0F": "Dell", "BC:30:5B": "Dell", "C8:1F:66": "Dell", "D0:94:66": "Dell",
        "D4:81:D7": "Dell", "D4:AE:52": "Dell", "D4:BE:D9": "Dell", "E0:DB:55": "Dell",
        "E4:F0:04": "Dell", "EC:F4:BB": "Dell", "F0:1F:AF": "Dell", "F4:8E:38": "Dell",
        "F8:B1:56": "Dell", "F8:BC:12": "Dell", "F8:CA:B8": "Dell", "FC:15:B4": "Dell",

        // Synology
        "00:11:32": "Synology", "00:11:55": "Synology",

        // QNAP
        "00:08:9B": "QNAP", "24:5E:BE": "QNAP",

        // Ecobee
        "44:61:32": "Ecobee", "30:B4:B8": "Ecobee",

        // Raspberry Pi
        "B8:27:EB": "Raspberry Pi", "DC:A6:32": "Raspberry Pi", "E4:5F:01": "Raspberry Pi",
        "D8:3A:DD": "Raspberry Pi",

        // Xiaomi/Mi
        "00:9E:C8": "Xiaomi", "04:CF:8C": "Xiaomi", "0C:1D:AF": "Xiaomi",
        "10:2A:B3": "Xiaomi", "14:F6:5A": "Xiaomi", "18:59:36": "Xiaomi",
        "20:34:FB": "Xiaomi", "28:6C:07": "Xiaomi", "34:80:B3": "Xiaomi",
        "38:A4:ED": "Xiaomi", "3C:BD:3E": "Xiaomi", "44:23:7C": "Xiaomi",
        "48:FC:74": "Xiaomi", "4C:49:E3": "Xiaomi", "50:64:2B": "Xiaomi",
        "54:48:E6": "Xiaomi", "58:44:98": "Xiaomi", "5C:E2:8C": "Xiaomi",
        "64:09:80": "Xiaomi", "64:B4:73": "Xiaomi", "68:28:BA": "Xiaomi",
        "6C:5C:14": "Xiaomi", "70:9F:A9": "Xiaomi", "74:23:44": "Xiaomi",
        "74:51:BA": "Xiaomi", "78:02:F8": "Xiaomi", "78:11:DC": "Xiaomi",
        "7C:1C:4E": "Xiaomi", "80:AD:16": "Xiaomi",
        "84:9E:B5": "Xiaomi", "8C:DE:F9": "Xiaomi", "90:78:B2": "Xiaomi",
        "94:E9:79": "Xiaomi", "98:FA:E3": "Xiaomi", "9C:99:A0": "Xiaomi",
        "A0:86:C6": "Xiaomi", "A4:50:46": "Xiaomi", "AC:C1:EE": "Xiaomi",
        "B0:E2:35": "Xiaomi", "C4:0B:CB": "Xiaomi", "C8:FD:19": "Xiaomi",
        "D4:97:0B": "Xiaomi", "E4:46:DA": "Xiaomi", "F0:B4:29": "Xiaomi",
        "F4:F5:24": "Xiaomi", "F8:A4:5F": "Xiaomi", "FC:64:BA": "Xiaomi",

        // Wyze
        "2C:AA:8E": "Wyze", "D0:3F:27": "Wyze", "78:8C:B5": "Wyze",

        // Arlo
        "D0:52:A8": "Arlo", "3C:37:86": "Arlo", "A0:B4:39": "Arlo",

        // Logitech
        "00:04:20": "Logitech", "54:81:AD": "Logitech", "74:DA:38": "Logitech",
        "A4:5D:36": "Logitech", "C4:72:95": "Logitech",

        // Netgear
        "00:09:5B": "Netgear", "00:0F:B5": "Netgear", "00:14:6C": "Netgear",
        "00:18:4D": "Netgear", "00:1B:2F": "Netgear", "00:1E:2A": "Netgear",
        "00:1F:33": "Netgear", "00:22:3F": "Netgear", "00:24:B2": "Netgear",
        "00:26:F2": "Netgear", "08:02:8E": "Netgear", "08:36:C9": "Netgear",
        "0C:80:63": "Netgear", "10:0D:7F": "Netgear", "10:DA:43": "Netgear",
        "14:59:C0": "Netgear", "20:0C:C8": "Netgear", "20:4E:7F": "Netgear",
        "28:80:88": "Netgear", "28:C6:8E": "Netgear", "2C:B0:5D": "Netgear",
        "30:46:9A": "Netgear", "30:9B:AD": "Netgear",
        "44:94:FC": "Netgear", "48:EE:0C": "Netgear", "4C:60:DE": "Netgear",
        "6C:B0:CE": "Netgear",
        "80:37:73": "Netgear", "84:1B:5E": "Netgear", "88:F7:C7": "Netgear",
        "8C:3B:AD": "Netgear", "9C:D3:6D": "Netgear", "A0:04:60": "Netgear",
        "A0:21:B7": "Netgear", "A0:40:A0": "Netgear", "A4:2B:8C": "Netgear",
        "B0:7F:B9": "Netgear", "C0:3F:0E": "Netgear", "C0:FF:D4": "Netgear",
        "C4:04:15": "Netgear", "C4:3D:C7": "Netgear", "CC:40:D0": "Netgear",
        "D8:EB:97": "Netgear", "DC:EF:09": "Netgear", "E0:46:9A": "Netgear",
        "E0:91:F5": "Netgear", "E4:F4:C6": "Netgear", "E8:FC:AF": "Netgear",
        "F8:4F:57": "Netgear",

        // Wemo/Belkin
        "08:86:3B": "Belkin", "14:91:82": "Belkin", "24:F5:A2": "Belkin",
        "58:EF:68": "Belkin", "94:10:3E": "Belkin", "B4:75:0E": "Belkin",
        "C0:56:27": "Belkin", "C4:41:1E": "Belkin", "EC:1A:59": "Belkin Wemo",

        // Honeywell
        "00:D0:2D": "Honeywell", "28:93:FE": "Honeywell",
        "5C:31:3E": "Honeywell", "CC:F9:57": "Honeywell",

        // Lutron
        "00:10:F0": "Lutron", "78:FF:57": "Lutron",

        // August
        "BC:5C:4C": "August",

        // Schlage
        "48:F3:17": "Schlage",

        // SimpliSafe
        "B8:1F:5D": "SimpliSafe",

        // LIFX
        "D0:73:D5": "LIFX",

        // Yeelight
        "7C:49:EB": "Yeelight",

        // Nanoleaf
        "00:55:DA": "Nanoleaf", "B8:01:1F": "Nanoleaf",

        // Asus
        "00:0C:6E": "Asus", "00:0E:A6": "Asus", "00:11:2F": "Asus",
        "00:11:D8": "Asus", "00:13:D4": "Asus", "00:15:F2": "Asus",
        "00:17:31": "Asus", "00:18:F3": "Asus", "00:1A:92": "Asus",
        "00:1B:FC": "Asus", "00:1D:60": "Asus", "00:1E:8C": "Asus",
        "00:1F:C6": "Asus", "00:22:15": "Asus", "00:23:54": "Asus",
        "00:24:8C": "Asus", "00:25:22": "Asus", "00:26:18": "Asus",
        "08:60:6E": "Asus", "10:7B:44": "Asus", "10:BF:48": "Asus",
        "10:C3:7B": "Asus", "14:DA:E9": "Asus", "14:DD:A9": "Asus",
        "18:31:BF": "Asus", "1C:87:2C": "Asus", "1C:B7:2C": "Asus",
        "20:CF:30": "Asus", "24:4B:FE": "Asus", "2C:4D:54": "Asus",
        "2C:56:DC": "Asus", "30:5A:3A": "Asus", "30:85:A9": "Asus",
        "34:97:F6": "Asus", "38:2C:4A": "Asus", "38:D5:47": "Asus",
        "3C:97:0E": "Asus", "40:16:7E": "Asus", "40:B0:76": "Asus",
        "48:5B:39": "Asus", "4C:ED:FB": "Asus", "50:46:5D": "Asus",
        "50:67:F0": "Asus", "54:04:A6": "Asus", "54:A0:50": "Asus",
        "5C:E2:86": "Asus", "60:45:CB": "Asus", "60:A4:4C": "Asus",
        "6C:72:20": "Asus", "6C:F3:73": "Asus", "70:4D:7B": "Asus",
        "70:8B:CD": "Asus", "74:D0:2B": "Asus", "78:24:AF": "Asus",
        "78:47:1D": "Asus", "7C:10:C9": "Asus", "88:D7:F6": "Asus",
        "90:E6:BA": "Asus", "AC:22:0B": "Asus", "AC:9E:17": "Asus",
        "B0:6E:BF": "Asus", "BC:AE:C5": "Asus", "BC:EE:7B": "Asus",
        "C8:60:00": "Asus", "D4:5D:64": "Asus", "D8:50:E6": "Asus",
        "E0:3F:49": "Asus", "E4:A7:A0": "Asus", "F0:79:59": "Asus",
        "F4:6D:04": "Asus", "F8:32:E4": "Asus", "FC:C2:33": "Asus",

        // Multicast addresses
        "01:00:5E": "IPv4 Multicast",
        "33:33:00": "IPv6 Multicast",
    ]

    private init() {}

    /// Look up vendor from MAC address
    public func lookup(mac: String) -> String? {
        let normalized = normalizeMACPrefix(mac)
        return vendors[normalized]
    }

    /// Normalize MAC to OUI format (first 3 bytes, uppercase, colon-separated)
    /// Handles various formats: "0:E:58:...", "00:0E:58:...", "000E58..."
    private func normalizeMACPrefix(_ mac: String) -> String {
        // Remove common separators and convert to uppercase
        let cleaned = mac.uppercased()
            .replacingOccurrences(of: "-", with: ":")
            .replacingOccurrences(of: ".", with: "")

        // Split by colons if present
        var components: [String]
        if cleaned.contains(":") {
            components = cleaned.components(separatedBy: ":").prefix(3).map { component in
                // Pad single-digit hex values to two digits
                if component.count == 1 {
                    return "0" + component
                }
                return String(component.prefix(2))
            }
        } else {
            // No separators - assume pairs of hex digits
            var pairs: [String] = []
            var remaining = cleaned
            while !remaining.isEmpty && pairs.count < 3 {
                let end = remaining.index(remaining.startIndex, offsetBy: min(2, remaining.count))
                var pair = String(remaining[..<end])
                // Pad if needed
                if pair.count == 1 {
                    pair = "0" + pair
                }
                pairs.append(pair)
                remaining = String(remaining[end...])
            }
            components = pairs
        }

        // Ensure we have 3 components, each 2 chars
        while components.count < 3 {
            components.append("00")
        }

        return components.map { $0.padding(toLength: 2, withPad: "0", startingAt: 0) }.joined(separator: ":")
    }
}
