// JSONKit — the pure-Swift domain layer for JSON Studio.
//
// Zero UI, zero AppKit (ADR-05). All public types are Sendable value types and long work
// runs off the main actor with cooperative cancellation (ADR-09). JSONSerialization is a
// test oracle only — never the parser (ADR-01).
//
// The type surface below is the Phase 2 skeleton: signatures and models are in place so the
// package compiles and the shape is reviewable; implementations land in Phase 2.

public enum JSONKit {
    public static let version = "0.0.1"
}
