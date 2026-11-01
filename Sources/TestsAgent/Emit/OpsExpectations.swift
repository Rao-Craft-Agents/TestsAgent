//  WHAT: What a `set(.kind(…))` leaves in a service's state, read off its Ops: each plain assignment of the kind's
//        case whose value a test knows (a literal, or an argument the test can say in its own scope).

import Foundation

enum OpsExpectations {
    /// The expectations `call` leaves in `service`'s state, the test naming the service `root`. `value` says an
    /// argument of the call as the test can write it, or nil when it cannot.
    static func lines(_ call: SetCall, service: ServiceInfo, root: String, value: (String) -> String?) -> [String] {
        var lines: [String] = []
        var seen: Set<String> = []
        if let ops = service.ops.first(where: { $0.kinds.contains(call.kind) }) {
            for assignment in ops.assignments where !["loading", "lastError"].contains(assignment.field) && service.field(assignment.field) != nil {
                var expected: String?
                if Samples.isLiteral(assignment.value) {
                    expected = assignment.value
                } else if let position = ops.bindings.firstIndex(of: assignment.value), position < call.arguments.count {
                    let argument = call.arguments[position]
                    expected = Samples.isLiteral(argument) ? argument : value(argument)
                }
                guard let expected, seen.insert(assignment.field).inserted else { continue }
                lines.append("#expect(\(root).state.\(Naming.member(assignment.field)) == \(expected))")
            }
        } else if service.field(call.kind) != nil, call.arguments.count == 1 {
            let argument = call.arguments[0]
            if let expected = Samples.isLiteral(argument) ? argument : value(argument) {
                lines.append("#expect(\(root).state.\(Naming.member(call.kind)) == \(expected))")
            }
        }
        return lines
    }
}
