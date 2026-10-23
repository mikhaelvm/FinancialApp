import Foundation
import CryptoKit

/// Each installation writes its own document. No device overwrites another
/// device's file; logical revisions and tombstones converge when files merge.
struct DriveSyncDocument: Codable, Equatable {
    struct Record: Codable, Equatable {
        let revision: Int64
        let writer: UUID
        let payload: Data?

        func supersedes(_ other: Record) -> Bool {
            if revision != other.revision { return revision > other.revision }
            if (payload == nil) != (other.payload == nil) { return payload == nil }
            if writer != other.writer { return writer.uuidString > other.writer.uuidString }
            // Deterministic even for a corrupt duplicate revision from the same writer.
            return (payload ?? Data()).lexicographicallyPrecedes(other.payload ?? Data())
        }
    }
    var formatVersion = 1
    var owner = UUID()
    var clock: Int64 = 0
    var records: [String: Record] = [:]

    mutating func merge(_ remote: Self) throws {
        guard remote.formatVersion == 1, remote.records.count <= 200_000,
              remote.clock >= 0, remote.clock < Int64.max - 1,
              remote.records.allSatisfy({ $0.key.count <= 300 && $0.value.revision > 0 && $0.value.revision <= remote.clock }) else {
            throw FinanceError.invalid("Dados de sincronização incompatíveis. Atualize o Trackr.")
        }
        clock = max(clock, remote.clock)
        for (key, record) in remote.records {
            if let existing = records[key] {
                var winner = record.supersedes(existing) ? record : existing
                if key.hasPrefix("subscriptions|"), let a = existing.payload, let b = record.payload,
                   var row = try JSONSerialization.jsonObject(with: winner.payload ?? Data()) as? [String: Any],
                   let first = try JSONSerialization.jsonObject(with: a) as? [String: Any],
                   let second = try JSONSerialization.jsonObject(with: b) as? [String: Any],
                   first["scheduleID"] as? String == second["scheduleID"] as? String {
                    // Automatic generation on two devices cannot rewind the same schedule.
                    let progress = (first["nextOccurrenceIndex"] as? Int ?? 0) > (second["nextOccurrenceIndex"] as? Int ?? 0) ? first : second
                    row["nextOccurrenceIndex"] = progress["nextOccurrenceIndex"]
                    row["nextRenewalDate"] = progress["nextRenewalDate"]
                    winner = Record(revision: winner.revision, writer: winner.writer,
                                    payload: try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]))
                }
                records[key] = winner
            } else { records[key] = record }
        }
        guard records.count <= 200_000 else { throw FinanceError.invalid("Limite de registros de sincronização atingido.") }
    }

    mutating func write(_ changes: [String: Data?]) {
        guard !changes.isEmpty else { return }
        clock += 1
        for (key, payload) in changes { records[key] = Record(revision: clock, writer: owner, payload: payload) }
    }

    mutating func capture(_ current: [String: Data], baseline: [String: Data]?, preferLocal: Bool = false) throws {
        var changes: [String: Data?] = [:]
        for (key, payload) in current {
            let changed = baseline.map { $0[key] != payload } ?? (preferLocal || records[key] == nil)
            if changed {
                // Editing or automatically renewing an old record cannot undo
                // a deletion already received from another device.
                if baseline?[key] != nil, let known = records[key], known.payload == nil { continue }
                var value = payload
                if key.hasPrefix("subscriptions|"), let old = baseline?[key], let incoming = records[key]?.payload,
                   let local = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
                   let base = try JSONSerialization.jsonObject(with: old) as? [String: Any],
                   var remote = try JSONSerialization.jsonObject(with: incoming) as? [String: Any] {
                    // A local renewal must not undo a pause performed on another device.
                    let remoteProgress = remote
                    for field in Set(local.keys).union(base.keys) {
                        if !NSDictionary(dictionary: ["v": local[field] ?? NSNull()]).isEqual(to: ["v": base[field] ?? NSNull()]) {
                            remote[field] = local[field]
                        }
                    }
                    if remote["scheduleID"] as? String == remoteProgress["scheduleID"] as? String,
                       (remoteProgress["nextOccurrenceIndex"] as? Int ?? 0) > (remote["nextOccurrenceIndex"] as? Int ?? 0) {
                        remote["nextOccurrenceIndex"] = remoteProgress["nextOccurrenceIndex"]
                        remote["nextRenewalDate"] = remoteProgress["nextRenewalDate"]
                    }
                    value = try JSONSerialization.data(withJSONObject: remote, options: [.sortedKeys])
                }
                changes[key] = .some(value)
            }
        }
        if let baseline {
            for key in baseline.keys where current[key] == nil { changes[key] = .some(nil) }
        }
        write(changes)
    }
}

struct DriveSyncState: Codable {
    var document = DriveSyncDocument()
    var baseline: [String: Data]?

    static func stableID(_ text: String) -> UUID {
        let bytes = Array(SHA256.hash(data: Data(text.utf8)).prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    private static let tables = ["categories", "cards", "subscriptions", "transactions", "payments", "scheduled"]

    /// Default categories and automatic receipts are independently created on
    /// both devices. Normalize their identities before comparing revisions.
    static func index(_ backup: TrackrBackup) throws -> [String: Data] {
        let data = try JSONEncoder().encode(backup)
        var root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var categoryMap: [String: String] = [:]
        var categories = root["categories"] as! [[String: Any]]
        for i in categories.indices {
            let name = (categories[i]["name"] as! String).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR"))
            let id = stableID("category:" + name).uuidString
            categoryMap[categories[i]["id"] as! String] = id
            categories[i]["id"] = id
        }
        root["categories"] = categories
        let scheduled = root["scheduled"] as! [[String: Any]]
        var transactionMap: [String: String] = [:]
        var transactions = root["transactions"] as! [[String: Any]]
        for i in transactions.indices {
            let old = transactions[i]["id"] as! String
            var identity = (transactions[i]["recurrenceKey"] as? String).map { "transaction:" + $0 }
            if identity == nil, let bill = scheduled.first(where: { ($0["paidTransactionID"] as? String) == old }) {
                identity = "scheduledReceipt:" + (bill["id"] as! String)
            }
            if let identity {
                let id = stableID(identity).uuidString
                transactionMap[old] = id; transactions[i]["id"] = id
                transactions[i]["purchaseID"] = stableID("purchase:" + identity).uuidString
            }
        }
        root["transactions"] = transactions
        var result: [String: Data] = [:]
        for table in tables {
            for var row in root[table] as! [[String: Any]] {
                if let old = row["categoryID"] as? String { row["categoryID"] = categoryMap[old] }
                if let old = row["paidTransactionID"] as? String, let id = transactionMap[old] { row["paidTransactionID"] = id }
                let key = table + "|" + (row["id"] as! String)
                result[key] = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
            }
        }
        for id in backup.dismissedPayments ?? [] { result["dismissals|" + id] = Data(id.utf8) }
        return result
    }

    mutating func materialize() throws -> TrackrBackup {
        var root: [String: Any] = ["formatVersion": 1, "createdAt": Date.now.timeIntervalSinceReferenceDate]
        for table in Self.tables {
            root[table] = try document.records.sorted(by: { $0.key < $1.key }).compactMap { key, record -> [String: Any]? in
                guard key.hasPrefix(table + "|"), let data = record.payload else { return nil }
                let decoder = JSONDecoder()
                switch table {
                case "categories": _ = try decoder.decode(TrackrBackup.CategoryRecord.self, from: data)
                case "cards": _ = try decoder.decode(TrackrBackup.CardRecord.self, from: data)
                case "subscriptions": _ = try decoder.decode(TrackrBackup.SubscriptionRecord.self, from: data)
                case "transactions": _ = try decoder.decode(TrackrBackup.TransactionRecord.self, from: data)
                case "payments": _ = try decoder.decode(TrackrBackup.PaymentRecord.self, from: data)
                default: _ = try decoder.decode(TrackrBackup.ScheduledRecord.self, from: data)
                }
                guard let row = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let id = row["id"] as? String, UUID(uuidString: id) != nil, key == table + "|" + id else {
                    throw FinanceError.invalid("Registro de sincronização inválido.")
                }
                return row
            }
        }
        let cards = Set((root["cards"] as! [[String: Any]]).map { $0["id"] as! String })
        let categories = Set((root["categories"] as! [[String: Any]]).map { $0["id"] as! String })
        let subscriptions = Set((root["subscriptions"] as! [[String: Any]]).map { $0["id"] as! String })
        var repairs: [String: Data?] = [:]
        var transactions = (root["transactions"] as! [[String: Any]]).filter { row in
            guard let card = row["cardID"] as? String, !cards.contains(card) else { return true }
            repairs["transactions|" + (row["id"] as! String)] = .some(nil)
            return false
        }
        // A card removed while another device registers a payment must not erase
        // the cash outflow. Use the same identity as the card deletion service.
        root["payments"] = try (root["payments"] as! [[String: Any]]).filter { row in
            if let card = row["cardID"] as? String, cards.contains(card) { return true }
            let key = "preserved-card-payment:" + (row["id"] as! String)
            let identity = "transaction:" + key
            let id = Self.stableID(identity).uuidString
            let recordKey = "transactions|" + id
            if document.records[recordKey] == nil {
                let receipt: [String: Any] = ["id": id, "purchaseID": Self.stableID("purchase:" + identity).uuidString,
                    "title": "Pagamento de fatura", "kindRaw": "expense", "amountCents": row["amountCents"]!,
                    "date": row["date"]!, "installmentNumber": 1, "totalInstallments": 1, "recurrenceKey": key]
                transactions.append(receipt)
                repairs[recordKey] = .some(try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys]))
            }
            repairs["payments|" + (row["id"] as! String)] = .some(nil)
            return false
        }
        root["transactions"] = transactions
        let transactionIDs = Set(transactions.map { $0["id"] as! String })
        for table in ["transactions", "subscriptions", "scheduled"] {
            root[table] = (root[table] as! [[String: Any]]).map { original -> [String: Any] in
                var row = original
                if let id = row["categoryID"] as? String, !categories.contains(id) { row.removeValue(forKey: "categoryID") }
                if let id = row["subscriptionID"] as? String, !subscriptions.contains(id) { row.removeValue(forKey: "subscriptionID") }
                if table == "subscriptions", let id = row["cardID"] as? String, !cards.contains(id) {
                    row.removeValue(forKey: "cardID"); row["isActive"] = false
                }
                if table == "scheduled", let id = row["paidTransactionID"] as? String, !transactionIDs.contains(id) {
                    row.removeValue(forKey: "paidTransactionID"); row["isPaid"] = false
                }
                return row
            }
        }
        root["dismissedPayments"] = try document.records.compactMap { key, record -> String? in
            guard key.hasPrefix("dismissals|"), let data = record.payload else { return nil }
            guard let id = String(data: data, encoding: .utf8), key == "dismissals|" + id else {
                throw FinanceError.invalid("Dispensa de pagamento inválida na sincronização.")
            }
            return id
        }.sorted()
        let backup = try JSONDecoder().decode(TrackrBackup.self, from: JSONSerialization.data(withJSONObject: root))
        try backup.validate()
        document.write(repairs)
        return backup
    }
}

@MainActor enum DriveSyncCache {
    private static func url(account: String) throws -> URL {
        var folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true).appendingPathComponent("DriveSync", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // A restored iPad must get a new writer identity, rather than sharing
        // the iPhone's identity through an operating-system device backup.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        return folder.appendingPathComponent(DriveSyncState.stableID(account).uuidString + ".json")
    }
    static func load(account: String) throws -> DriveSyncState {
        let file = try url(account: account)
        guard FileManager.default.fileExists(atPath: file.path) else { return DriveSyncState() }
        return try JSONDecoder().decode(DriveSyncState.self, from: Data(contentsOf: file))
    }
    static func save(_ state: DriveSyncState, account: String) throws {
        try JSONEncoder().encode(state).write(to: url(account: account), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func clearAll() throws {
        let folder = try url(account: "").deletingLastPathComponent()
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            where file.pathExtension == "json" {
            try FileManager.default.removeItem(at: file)
        }
    }
}
