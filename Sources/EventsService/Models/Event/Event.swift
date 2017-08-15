import Foundation
import SwiftyJSON
import LoggerAPI

// MARK: - Event

public struct Event {
    public var id: Int?
    public var name: String?
    public var emoji: String?
    public var description: String?
    public var host: Int?
    public var startTime: Date?
    public var location: String?
    public var isPublic: Int?
    public var games: [Int]?
    public var rsvps: [RSVP]?
    public var createdAt: Date?
    public var updatedAt: Date?
}

// MARK: - Event: JSONAble

extension Event: JSONAble {
    public func toJSON() -> JSON {
        var dict = [String: Any]()
        let nilValue: Any? = nil

        dict["id"] = id != nil ? id : nilValue
        dict["public"] = isPublic != nil ? isPublic : nilValue
        dict["host"] = host != nil ? host : nilValue
        dict["name"] = name != nil ? name : nilValue
        dict["emoji"] = emoji != nil ? emoji : nilValue
        dict["description"] = description != nil ? description : nilValue
        dict["location"] = location != nil ? location : nilValue
        dict["activities"] = games != nil ? games : nilValue
        dict["attendees"] = rsvps != nil ? rsvps!.toJSON().object : nilValue

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        dict["start_time"] = startTime != nil ? dateFormatter.string(from: startTime!) : nilValue
        dict["created_at"] = createdAt != nil ? dateFormatter.string(from: createdAt!) : nilValue
        dict["updated_at"] = updatedAt != nil ? dateFormatter.string(from: updatedAt!) : nilValue

        return JSON(dict)
    }
}

// MARK: - Event (MySQLRow)

extension Event {
    func toMySQLRow() -> ([String: Any]) {
        var data = [String: Any]()

        data["name"] = name
        data["emoji"] = emoji
        data["description"] = description
        data["host"] = host
        data["start_time"] = startTime
        data["location"] = location
        data["is_public"] = isPublic

        return data
    }
}

// MARK: - Event (Validate)

extension Event {
    public func validate() -> [String] {
        var missingParameters = [String]()
        let validateParameters = ["name", "emoji", "description", "host", "start_time", "location", "is_public"]
        let eventMirror = Mirror(reflecting: self)

        for (name, value) in eventMirror.children {
            guard let name = name, validateParameters.contains(name) else { continue }
            if "\(value)" == "nil" {
                missingParameters.append("\(name)")
            }
        }

        return missingParameters
    }
}
