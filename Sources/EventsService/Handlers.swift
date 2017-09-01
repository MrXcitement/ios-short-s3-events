import MySQL
import Kitura
import LoggerAPI
import Foundation
import SwiftyJSON

// MARK: - Handlers

public class Handlers {

    // MARK: Properties

    let dataAccessor: EventMySQLDataAccessorProtocol

    // MARK: Initializer

    public init(dataAccessor: EventMySQLDataAccessorProtocol) {
        self.dataAccessor = dataAccessor
    }

    // MARK: OPTIONS

    public func getOptions(request: RouterRequest, response: RouterResponse, next: () -> Void) throws {
        response.headers["Access-Control-Allow-Headers"] = "accept, content-type"
        response.headers["Access-Control-Allow-Methods"] = "GET,POST,DELETE,OPTIONS,PUT"
        try response.status(.OK).end()
    }

    // MARK: GET

    public func getSingleEvent(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {

        guard let id = request.parameters["id"] else {
            Log.error("id (path parameter) missing")
            try response.send(json: JSON(["message": "id (path parameter) missing"]))
                        .status(.badRequest).end()
            return
        }

        let events = try dataAccessor.getEvents(withIDs: [id], pageSize: 1, pageNumber: 1)

        if events == nil {
            try response.status(.notFound).end()
            return
        }

        try response.send(json: events!.toJSON()).status(.OK).end()
    }

    public func getEvents(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {

        guard let pageSize = Int(request.queryParameters["page_size"] ?? "10"), let pageNumber = Int(request.queryParameters["page_number"] ?? "1") else {
            Log.error("could not initialize page_size and page_number")
            try response.send(json: JSON(["message": "could not initialize page_size and page_number"]))
                        .status(.internalServerError).end()
            return
        }

        guard let body = request.body, case let .json(json) = body, let idFilter = json["id"].array else {
            Log.error("json body is invalid; ensure id filter is present")
            try response.send(json: JSON(["message": "json body is invalid; ensure id filter is present"]))
                        .status(.internalServerError).end()
            return
        }

        let ids = idFilter.map({$0.stringValue})
        let events = try dataAccessor.getEvents(withIDs: ids, pageSize: pageSize, pageNumber: pageNumber)

        if events == nil {
            try response.status(.notFound).end()
            return
        }

        try response.send(json: events!.toJSON()).status(.OK).end()
    }

    public func getEventsOnSchedule(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {

        guard let pageSize = Int(request.queryParameters["page_size"] ?? "10"), let pageNumber = Int(request.queryParameters["page_number"] ?? "1") else {
            Log.error("could not initialize page_size and page_number")
            try response.send(json: JSON(["message": "could not initialize page_size and page_number"]))
                        .status(.internalServerError).end()
            return
        }

        guard let filterType = request.queryParameters["type"], let type = EventScheduleType(rawValue: filterType) else {
            Log.error("could not initialize type")
            try response.send(json: JSON(["message": "could not initialize type"]))
                        .status(.internalServerError).end()
            return
        }

        let events = try dataAccessor.getEvents(pageSize: pageSize, pageNumber: pageNumber, type: type)

        if events == nil {
            try response.status(.notFound).end()
            return
        }

        try response.send(json: events!.toJSON()).status(.OK).end()
    }

    public func getEventsBySearch(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {

        guard let pageSize = Int(request.queryParameters["page_size"] ?? "10"), let pageNumber = Int(request.queryParameters["page_number"] ?? "1") else {
            Log.error("could not initialize page_size and page_number")
            try response.send(json: JSON(["message": "could not initialize page_size and page_number"]))
                        .status(.internalServerError).end()
            return
        }

        guard let distanceInMilesString = request.queryParameters["distance"], let latitudeString = request.queryParameters["latitude"],
            let longitudeString = request.queryParameters["longitude"], let distanceInMiles = Int(distanceInMilesString),
            let latitude = Double(latitudeString), let longitude = Double(longitudeString) else {
                Log.error("could not initialize distance, latitude, and longitude")
                try response.send(json: JSON(["message": "could not initialize distance, latitude, and longitude"]))
                            .status(.internalServerError).end()
                return
        }

        guard distanceInMiles > 0 else {
            Log.error("distance must be greater than 0")
            try response.send(json: JSON(["message": "distance must be greater than 0"]))
                        .status(.internalServerError).end()
            return
        }

        guard latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180 else {
            Log.error("latitude must be [-90,90], longitude must be [-180,180]")
            try response.send(json: JSON(["message": "latitude must be [-90,90], longitude must be [-180,180]"]))
                        .status(.internalServerError).end()
            return
        }

        let ids = try dataAccessor.getEventIDsNearLocation(latitude: latitude, longitude: longitude,
            miles: distanceInMiles, pageSize: pageSize, pageNumber: pageNumber)
        var events: [Event]?

        if let ids = ids {
            events = try dataAccessor.getEvents(withIDs: ids, pageSize: pageSize, pageNumber: 1)
        }

        if events == nil {
            try response.status(.notFound).end()
            return
        }

        try response.send(json: events!.toJSON()).status(.OK).end()
    }

    public func getRSVPsForEvent(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
        // TODO: Implement.
    }

    public func getRSVPsForUser(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
        // TODO: Implement.
    }

    // MARK: POST

    public func postEvent(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {

        guard let body = request.body, case let .json(json) = body else {
            Log.error("body contains invalid JSON")
            try response.send(json: JSON(["message": "body is missing JSON or JSON is invalid"]))
                        .status(.badRequest).end()
            return
        }

        let activities = json["activities"].arrayValue.map({$0.intValue})
        let rsvps = json["rsvps"].arrayValue.map({
            RSVP(userID: $0.stringValue, eventID: nil, accepted: nil, comment: nil)
        })

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let startTimeString = json["start_time"].stringValue
        let startTime: Date? = startTimeString != "" ? dateFormatter.date(from: startTimeString) : nil

        let newEvent = Event(
            id: nil,
            name: json["name"].string,
            emoji: json["emoji"].string,
            description: json["description"].string,
            host: json["host"].string,
            startTime: startTime,
            location: json["location"].string,
            latitude: json["latitude"].double, longitude: json["longitude"].double,
            isPublic: json["is_public"].int,
            activities: activities, rsvps: rsvps,
            createdAt: nil, updatedAt: nil)

        let missingParameters = newEvent.validateParameters(
            ["name", "emoji", "description", "host", "startTime", "location",
                "latitude", "longitude", "isPublic", "activities", "rsvps"])

        if missingParameters.count != 0 {
            Log.error("parameters missing \(missingParameters)")
            try response.send(json: JSON(["message": "parameters missing \(missingParameters)"]))
                        .status(.badRequest).end()
            return
        }

        let success = try dataAccessor.createEvent(newEvent)

        if success {
            try response.send(json: JSON(["message": "event created"])).status(.created).end()
            return
        }

        try response.status(.notModified).end()
    }

    public func postRSVPsForEvent(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {

        guard let body = request.body, case let .json(json) = body else {
            Log.error("body contains invalid JSON")
            try response.send(json: JSON(["message": "body is missing JSON or JSON is invalid"]))
                        .status(.badRequest).end()
            return
        }

        guard let id = request.parameters["id"] else {
            Log.error("id (path parameter) missing")
            try response.send(json: JSON(["message": "id (path parameter) missing"]))
                        .status(.badRequest).end()
            return
        }

        let rsvps = json["rsvps"].arrayValue.map({
            RSVP(userID: $0.stringValue, eventID: nil, accepted: nil, comment: nil)
        })

        let postEvent = Event(
            id: Int(id),
            name: nil,
            emoji: nil,
            description: nil,
            host: nil,
            startTime: nil,
            location: nil,
            latitude: nil, longitude: nil,
            isPublic: nil,
            activities: nil, rsvps: rsvps,
            createdAt: nil, updatedAt: nil)

        let missingParameters = postEvent.validateParameters(["id", "rsvps"])

        if missingParameters.count != 0 {
            Log.error("parameters missing \(missingParameters)")
            try response.send(json: JSON(["message": "parameters missing \(missingParameters)"]))
                        .status(.badRequest).end()
            return
        }

        let success = try dataAccessor.postEventRSVPs(withEvent: postEvent)

        if success {
            try response.send(json: JSON(["message": "rsvps sent"])).status(.OK).end()
        }

        try response.status(.notModified).end()
    }

    // MARK: PUT

    public func putEvent(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {

        guard let body = request.body, case let .json(json) = body else {
            Log.error("body contains invalid JSON")
            try response.send(json: JSON(["message": "body is missing JSON or JSON is invalid"]))
                        .status(.badRequest).end()
            return
        }

        guard let id = request.parameters["id"] else {
            Log.error("id (path parameter) missing")
            try response.send(json: JSON(["message": "id (path parameter) missing"]))
                        .status(.badRequest).end()
            return
        }

        let updateEvent = Event(
            id: Int(id),
            name: json["name"].string,
            emoji: json["emoji"].string,
            description: json["description"].string,
            host: json["host"].string,
            startTime: nil,
            location: json["location"].string,
            latitude: json["latitude"].double, longitude: json["longitude"].double,
            isPublic: json["is_public"].int,
            activities: nil, rsvps: nil,
            createdAt: nil, updatedAt: nil)

        let missingParameters = updateEvent.validateParameters(
            ["name", "emoji", "description", "host", "startTime", "location",
                "latitude", "longitude", "isPublic"])

        if missingParameters.count != 0 {
            Log.error("parameters missing \(missingParameters)")
            try response.send(json: JSON(["message": "parameters missing \(missingParameters)"]))
                        .status(.badRequest).end()
            return
        }

        Log.info("perform put")
    }

    public func putRSVPForEvent(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
        // TODO: Implement.
    }

    // MARK: DELETE

    public func deleteEvent(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {

        guard let id = request.parameters["id"] else {
            Log.error("id (path parameter) missing")
            try response.send(json: JSON(["message": "id (path parameter) missing"]))
                        .status(.badRequest).end()
            return
        }

        let success = try dataAccessor.deleteEvent(withID: id)

        if success {
            try response.send(json: JSON(["message": "resource deleted"])).status(.noContent).end()
        }

        try response.status(.notModified).end()
    }
}
