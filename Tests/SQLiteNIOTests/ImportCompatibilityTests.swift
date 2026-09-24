import Foundation
import SQLiteNIO
import Synchronization
import Testing

@Test
func explicitFoundationImportSupportsSQLiteValues() {
    #expect(String(format: "%@", "value") == "value")
    let date = Date(timeIntervalSince1970: 42)
    #expect(date.sqliteData == .float(42))
}

#if os(Linux)
@Test
func explicitFoundationImportProvidesDatePlaygroundConformance() {
    let date = Date(timeIntervalSince1970: 42)
    let display: any CustomPlaygroundDisplayConvertible = date
    #expect(String(describing: display.playgroundDescription).isEmpty == false)
}
#endif

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
private func requireAtomicRepresentation<T: AtomicRepresentable>(_: T.Type) {}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
@Test
func explicitSynchronizationImportProvidesConformances() {
    requireAtomicRepresentation(Int.self)
    requireAtomicRepresentation(Int8.self)
    requireAtomicRepresentation(Int16.self)
    requireAtomicRepresentation(Int32.self)
    requireAtomicRepresentation(Int64.self)
    requireAtomicRepresentation(UInt.self)
    requireAtomicRepresentation(UInt8.self)
    requireAtomicRepresentation(UInt16.self)
    requireAtomicRepresentation(UInt32.self)
    requireAtomicRepresentation(UInt64.self)
    requireAtomicRepresentation(Double.self)
    requireAtomicRepresentation(Float.self)
    requireAtomicRepresentation(Bool.self)
}
