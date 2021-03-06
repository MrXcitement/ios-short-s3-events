import MySQL
import LoggerAPI

// MARK: - EventMySQLDataAccessorProtocol

public protocol EventMySQLDataAccessorProtocol {
    func getEvents(pageSize: Int, pageNumber: Int, type: EventScheduleType) throws -> [Event]?
    func getEvents(withIDs ids: [String], pageSize: Int, pageNumber: Int) throws -> [Event]?
    func getEventIDsNearLocation(latitude: Double, longitude: Double, miles: Int, pageSize: Int, pageNumber: Int) throws -> [String]?
    func getRSVPs(forEventID: String, pageSize: Int, pageNumber: Int) throws -> [RSVP]?
    func getRSVPsForUser(pageSize: Int, pageNumber: Int) throws -> [RSVP]?
    func createEvent(_ event: Event) throws -> Bool
    func createEventRSVPs(withEvent event: Event) throws -> Bool
    func updateEvent(_ event: Event) throws -> Bool
    func updateEventRSVP(_ event: Event, rsvp: RSVP) throws -> Bool
    func deleteEvent(withID id: String) throws -> Bool
}

// MARK: - EventMySQLDataAccessor: EventMySQLDataAccessorProtocol

public class EventMySQLDataAccessor: EventMySQLDataAccessorProtocol {

    // MARK: Properties

    let pool: MySQLConnectionPoolProtocol

    // MARK: Initializer

    public init(pool: MySQLConnectionPoolProtocol) {
        self.pool = pool
    }

    // MARK: READ

    public func getEvents(pageSize: Int = 10, pageNumber: Int = 1, type: EventScheduleType = .all) throws -> [Event]? {

        // Use schedule type to create proper query
        var selectEventIDs = MySQLQueryBuilder()
            .select(fields: ["id"], table: "events")
        switch type {
        case .upcoming:
            selectEventIDs = selectEventIDs.wheres(statement: "start_time >= CURDATE()", parameters: [])
        case .past:
            selectEventIDs = selectEventIDs.wheres(statement: "start_time < CURDATE()", parameters: [])
        default:
            break
        }

        // Select ids and apply pagination before joins
        let simpleResults = try execute(builder: selectEventIDs)
        simpleResults.seek(offset: cacluateOffset(pageSize: pageSize, pageNumber: pageNumber))
        let simpleEvents = simpleResults.toEvents(pageSize: pageSize)
        let ids = simpleEvents.map({String($0.id!)})

        var events = [Event]()

        // Once the ids are determind, perform the joins
        if ids.count > 0 {
            let selectEvents = MySQLQueryBuilder()
                .select(fields: ["id", "name", "emoji", "description", "host", "start_time",
                    "location", "latitude", "longitude", "is_public"], table: "events")
            let selectEventGames = MySQLQueryBuilder()
                .select(fields: ["activity_id", "event_id"], table: "event_games")
            let selectRSVPs = MySQLQueryBuilder()
                .select(fields: ["rsvp_id", "user_id", "event_id", "accepted", "comment"], table: "rsvps")
            let selectQuery = selectEvents.wheres(statement: "id IN (?)", parameters: ids)
                .join(builder: selectEventGames, from: "id", to: "event_id", type: .LeftJoin)
                .join(builder: selectRSVPs, from: "id", to: "event_id", type: .LeftJoin)
                .order(byExpression: "id", order: .Ascending)

            let result = try execute(builder: selectQuery)
            events = result.toEvents()
        }

        return (events.count == 0) ? nil : events
    }

    public func getEvents(withIDs ids: [String], pageSize: Int = 10, pageNumber: Int = 1) throws -> [Event]? {
        let selectEventIDs = MySQLQueryBuilder()
            .select(fields: ["id"], table: "events")
            .wheres(statement:"id IN (?)", parameters: ids)

        // Select ids and apply pagination before joins
        let simpleResults = try execute(builder: selectEventIDs)
        simpleResults.seek(offset: cacluateOffset(pageSize: pageSize, pageNumber: pageNumber))
        let simpleEvents = simpleResults.toEvents(pageSize: pageSize)
        let newIDs = simpleEvents.map({String($0.id!)})

        // Select events and perform joins
        let selectEvents = MySQLQueryBuilder()
            .select(fields: ["id", "name", "emoji", "description", "host", "start_time",
                "location", "latitude", "longitude", "is_public"], table: "events")
        let selectEventGames = MySQLQueryBuilder()
            .select(fields: ["activity_id", "event_id"], table: "event_games")
        let selectRSVPs = MySQLQueryBuilder()
            .select(fields: ["rsvp_id", "user_id", "event_id", "accepted", "comment"], table: "rsvps")
        let selectQuery = selectEvents.wheres(statement: "id IN (?)", parameters: newIDs)
            .join(builder: selectEventGames, from: "id", to: "event_id", type: .LeftJoin)
            .join(builder: selectRSVPs, from: "id", to: "event_id", type: .LeftJoin)
            .order(byExpression: "id", order: .Ascending)

        let result = try execute(builder: selectQuery)
        let events = result.toEvents(pageSize: pageSize)

        return (events.count == 0) ? nil : events
    }

    public func getEventIDsNearLocation(latitude: Double, longitude: Double, miles: Int, pageSize: Int = 10, pageNumber: Int = 1) throws -> [String]? {
        let connection = try pool.getConnection()
        defer { pool.releaseConnection(connection!) }

        // Use stored MySQL procedure to get ids for events near location, apply pagination
        let procedureCall = "CALL events_within_miles_from_location(\(latitude), \(longitude), \(miles))"

        let result = try connection!.execute(query: procedureCall)
        result.seek(offset: cacluateOffset(pageSize: pageSize, pageNumber: pageNumber))

        let events = result.toEvents(pageSize: pageSize)
        let ids = events.map({String($0.id!)})

        return (ids.count == 0) ? nil : ids
    }

    public func getRSVPs(forEventID: String, pageSize: Int = 10, pageNumber: Int = 1) throws -> [RSVP]? {
        let selectRSVPs = MySQLQueryBuilder()
            .select(fields: ["rsvp_id", "user_id", "accepted", "comment"], table: "rsvps")
            .wheres(statement: "event_id=?", parameters: forEventID)

        let result = try execute(builder: selectRSVPs)
        result.seek(offset: cacluateOffset(pageSize: pageSize, pageNumber: pageNumber))

        let rsvps = result.toRSVPs(pageSize: pageSize)
        return (rsvps.count == 0) ? nil : rsvps
    }

    public func getRSVPsForUser(pageSize: Int = 10, pageNumber: Int = 1) throws -> [RSVP]? {
        // FIXME: Use wheres to select RSVPs for user specified in JWT
        let selectRSVPs = MySQLQueryBuilder()
            .select(fields: ["rsvp_id", "user_id", "accepted", "comment"], table: "rsvps")

        let result = try execute(builder: selectRSVPs)
        result.seek(offset: cacluateOffset(pageSize: pageSize, pageNumber: pageNumber))

        let rsvps = result.toRSVPs(pageSize: pageSize)
        return (rsvps.count == 0) ? nil : rsvps
    }

    // MARK: CREATE

    public func createEvent(_ event: Event) throws -> Bool {
        let insertEventQuery = MySQLQueryBuilder()
            .insert(data: event.toMySQLRow(), table: "events")
        let selectLastEventID = MySQLQueryBuilder()
            .select(fields: [MySQLFunction.LastInsertID], table: "events")
        var result: MySQLResultProtocol

        guard let connection = try pool.getConnection() else {
            Log.error("Could not get a connection")
            return false
        }
        defer { pool.releaseConnection(connection) }

        func rollbackEventTransaction(withConnection: MySQLConnectionProtocol, message: String) -> Bool {
            Log.error("Could not create event: \(message)")
            try! connection.rollbackTransaction()
            return false
        }

        connection.startTransaction()

        do {
            // Insert event record
            result = try connection.execute(builder: insertEventQuery)
            if result.affectedRows < 1 {
                return rollbackEventTransaction(withConnection: connection, message: "Failed to insert event")
            }

            // Get id of last inserted record
            result = try connection.execute(builder: selectLastEventID)
            guard let row = result.nextResult(), let lastEventID = row["LAST_INSERT_ID()"] as? Int else {
                return rollbackEventTransaction(withConnection: connection, message: "Could not get last inserted event id")
            }

            // Insert records for an event's activities (event_games)
            if let activities = event.activities {
                for activityID in activities {
                    let insertEventGameQuery = MySQLQueryBuilder()
                        .insert(data: ["activity_id": activityID, "event_id": lastEventID], table: "event_games")
                    result = try connection.execute(builder: insertEventGameQuery)
                    if result.affectedRows < 1 {
                        return rollbackEventTransaction(withConnection: connection, message: "Failed to insert \(activityID) into event_games")
                    }
                }
            }

            // Insert event rsvps
            if let rsvps = event.rsvps {
                for rsvp in rsvps {
                    let insertRSVPQuery = MySQLQueryBuilder()
                        .insert(data: [
                            "user_id": rsvp.userID!,
                            "event_id": lastEventID,
                            "accepted": -1,
                            "comment": ""
                        ], table: "rsvps")
                    result = try connection.execute(builder: insertRSVPQuery)
                    if result.affectedRows < 1 {
                        return rollbackEventTransaction(withConnection: connection, message: "Failed to insert \(rsvp) into rsvps")
                    }
                }
            }

            try connection.commitTransaction()

        } catch {
            return rollbackEventTransaction(withConnection: connection, message: "createEvent failed")
        }

        return true
    }

    public func createEventRSVPs(withEvent event: Event) throws -> Bool {
        let selectEventID = MySQLQueryBuilder()
            .select(fields: ["id"], table: "events")
            .wheres(statement: "Id=?", parameters: "\(event.id!)")
        var result: MySQLResultProtocol

        guard let connection = try pool.getConnection() else {
            Log.error("Could not get a connection")
            return false
        }
        defer { pool.releaseConnection(connection) }

        func rollbackEventTransaction(withConnection: MySQLConnectionProtocol, message: String) -> Bool {
            Log.error("Could not create event rsvps: \(message)")
            try! connection.rollbackTransaction()
            return false
        }

        connection.startTransaction()

        do {
            // Ensure event exists
            result = try connection.execute(builder: selectEventID)
            guard let row = result.nextResult(), let _ = row["id"] as? Int else {
                return rollbackEventTransaction(withConnection: connection, message: "Event with id \(event.id!) does not exist")
            }

            // Insert rsvps for event
            if let rsvps = event.rsvps {
                for rsvp in rsvps {
                    let insertRSVPQuery = MySQLQueryBuilder()
                        .insert(data: rsvp.toMySQLRow(), table: "rsvps")
                    result = try connection.execute(builder: insertRSVPQuery)
                    if result.affectedRows < 1 {
                        return rollbackEventTransaction(withConnection: connection, message: "Failed to insert \(rsvp) into rsvps")
                    }
                }
            }
            try connection.commitTransaction()

        } catch {
            return rollbackEventTransaction(withConnection: connection, message: "createEventRSVPs failed")
        }

        return true
    }

    // MARK: UPDATE

    public func updateEvent(_ event: Event) throws -> Bool {
        let eventID = "\(event.id!)"
        let updateEventQuery = MySQLQueryBuilder()
            .update(data: event.toMySQLRow(), table: "events")
            .wheres(statement: "id=?", parameters: eventID)
        let deleteEventGamesQuery = MySQLQueryBuilder()
            .delete(fromTable: "event_games")
            .wheres(statement: "event_id=?", parameters: eventID)
        var result: MySQLResultProtocol

        guard let connection = try pool.getConnection() else {
            Log.error("Could not get a connection")
            return false
        }
        defer { pool.releaseConnection(connection) }

        func rollbackEventTransaction(withConnection: MySQLConnectionProtocol, message: String) -> Bool {
            Log.error("Could not update event: \(message)")
            try! connection.rollbackTransaction()
            return false
        }

        connection.startTransaction()

        do {
            // Update event
            result = try connection.execute(builder: updateEventQuery)
            if result.affectedRows < 1 {
                return rollbackEventTransaction(withConnection: connection, message: "Failed to update event")
            }

            // Delete existing activities for event, so they can be replaced
            result = try connection.execute(builder: deleteEventGamesQuery)
            if result.affectedRows < 1 {
                return rollbackEventTransaction(withConnection: connection, message: "Failed to delete existing event games during update")
            }

            // Insert activities for event (event_games)
            if let activities = event.activities {
                for activityID in activities {
                    let insertEventGameQuery = MySQLQueryBuilder()
                        .insert(data: ["activity_id": activityID, "event_id": eventID], table: "event_games")
                    result = try connection.execute(builder: insertEventGameQuery)
                    if result.affectedRows < 1 {
                        return rollbackEventTransaction(withConnection: connection, message: "Failed to insert \(activityID) into event_games")
                    }
                }
            }

            try connection.commitTransaction()

        } catch {
            return rollbackEventTransaction(withConnection: connection, message: "updateEvent failed")
        }

        return true
    }

    public func updateEventRSVP(_ event: Event, rsvp: RSVP) throws -> Bool {
        let updateRSVPQuery = MySQLQueryBuilder()
            .update(data: rsvp.toMySQLRow(), table: "rsvps")
            .wheres(statement: "event_id=? AND rsvp_id=?", parameters: "\(event.id!)", "\(rsvp.rsvpID!)")

        let result = try execute(builder: updateRSVPQuery)
        return result.affectedRows > 0
    }

    // MARK: DELETE

    public func deleteEvent(withID id: String) throws -> Bool {
        let deleteEventQuery = MySQLQueryBuilder()
                .delete(fromTable: "events")
                .wheres(statement: "Id=?", parameters: "\(id)")
        let deleteEventGameQuery = MySQLQueryBuilder()
                .delete(fromTable: "event_games")
                .wheres(statement: "event_id=?", parameters: "\(id)")
        let deleteRSVPQuery = MySQLQueryBuilder()
                .delete(fromTable: "rsvps")
                .wheres(statement: "event_id=?", parameters: "\(id)")
        var result: MySQLResultProtocol

        guard let connection = try pool.getConnection() else {
            Log.error("Could not get a connection")
            return false
        }
        defer { pool.releaseConnection(connection) }

        func rollbackEventTransaction(withConnection: MySQLConnectionProtocol, message: String) -> Bool {
            Log.error("Could not delete event: \(message)")
            try! connection.rollbackTransaction()
            return false
        }

        connection.startTransaction()

        do {
            // Delete event
            result = try connection.execute(builder: deleteEventQuery)
            if result.affectedRows < 1 {
                return rollbackEventTransaction(withConnection: connection, message: "Failed to delete event")
            }

            // Delete activities for event
            result = try connection.execute(builder: deleteEventGameQuery)
            if result.affectedRows < 1 {
                return rollbackEventTransaction(withConnection: connection, message: "Failed to delete event games")
            }

            // Delete rsvps for event
            result = try connection.execute(builder: deleteRSVPQuery)

            try connection.commitTransaction()

        } catch {
            return rollbackEventTransaction(withConnection: connection, message: "deleteEvent failed")
        }

        return true
    }

    // MARK: Utility

    func execute(builder: MySQLQueryBuilder) throws -> MySQLResultProtocol {
        let connection = try pool.getConnection()
        defer { pool.releaseConnection(connection!) }

        return try connection!.execute(builder: builder)
    }

    func cacluateOffset(pageSize: Int, pageNumber: Int) -> Int64 {
        return Int64(pageNumber > 1 ? pageSize * (pageNumber - 1) : 0)
    }

    public func isConnected() -> Bool {
        do {
            let connection = try pool.getConnection()
            defer { pool.releaseConnection(connection!) }
        } catch {
            return false
        }
        return true
    }
}
