import Foundation

/// Non-destructive startup shared by the app and isolated regression tests.
public enum DatabaseStartup {
    public static func open(
        defaults: UserDefaults,
        makeDatabase: () throws -> DatabaseManager
    ) -> Result<DatabaseManager, Error> {
        do {
            let database = try makeDatabase()
            let repository = ClipItemRepository(dbPool: database.dbPool)
            let hasHistory = try !repository.fetchAll(limit: 1).isEmpty
            HistorySettings.prepare(defaults: defaults, hasExistingHistory: hasHistory)
            return .success(database)
        } catch {
            // Unknown existing history must not gain a destructive retention cap.
            HistorySettings.prepare(defaults: defaults, hasExistingHistory: true)
            return .failure(error)
        }
    }
}
