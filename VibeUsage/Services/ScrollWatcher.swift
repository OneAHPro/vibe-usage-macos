import AppKit
import Observation

/// Suspends pointer-driven chart updates while a scroll gesture or its momentum
/// is active. SwiftUI otherwise emits hover changes as content moves beneath a
/// stationary pointer, forcing view updates into the same main-thread frames as
/// the scroll animation.
@MainActor
@Observable
final class ScrollWatcher {
    private(set) var isScrolling = false
    private var monitor: Any?
    private var resetTask: Task<Void, Never>?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            Task { @MainActor in self?.bump() }
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        resetTask?.cancel()
        resetTask = nil
        isScrolling = false
    }

    private func bump() {
        if !isScrolling { isScrolling = true }
        resetTask?.cancel()
        resetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            if Task.isCancelled { return }
            self?.isScrolling = false
        }
    }
}
