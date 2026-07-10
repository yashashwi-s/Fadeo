import Foundation
import FadeoCore

/// A partial update to the Context. Sensors own one signal each and emit only the field
/// they're responsible for; the AppController merges patches into the global Context.
struct ContextPatch: Sendable {
    let apply: @Sendable (inout Context) -> Void
    /// For the Energy dashboard: a short human label of what fired.
    let label: String
}

/// One OS signal, normalized. Sensors are *lazily* activated — only those whose fields
/// some enabled workspace references are ever started, so a disabled sensor holds zero
/// observers and costs nothing.
@MainActor
protocol Sensor: AnyObject {
    /// Which Context fields this sensor provides (drives lazy activation).
    static var providedFields: Set<ContextField> { get }
    func start(emit: @escaping (ContextPatch) -> Void)
    func stop()
}
