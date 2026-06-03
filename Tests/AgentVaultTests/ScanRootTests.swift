import Foundation
import Testing
@testable import AgentVault

@Suite("Scan roots")
struct ScanRootTests {
    @Test("defaults include Hermes canonical and opt-in roots")
    func defaultsIncludeHermesRoots() {
        let roots = ScanRoot.defaults()
        let names = Set(roots.map(\.displayName))

        #expect(names.contains("~/.hermes"))
        #expect(names.contains("~/Documents/Hermes"))
        #expect(names.contains("Hermes bundled skills"))
        #expect(names.contains("Hermes optional skills"))
        #expect(names.contains("Hermes plugins"))
        #expect(names.contains("Hermes optional MCPs"))

        #expect(roots.first { $0.displayName == "~/.hermes" }?.isCanonical == true)
        #expect(roots.first { $0.displayName == "Hermes bundled skills" }?.isCanonical == false)
    }
}
