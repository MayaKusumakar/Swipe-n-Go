import SwiftUI
import UIKit

extension View {
    /// Runs `action` when someone swipes down on a sheet whose dismissal is blocked
    /// with `.interactiveDismissDisabled(true)`, so the sheet can ask "Save or discard?"
    /// (the same way Mail asks about a draft). Put it inside the sheet's content.
    func onDismissAttempt(_ action: @escaping () -> Void) -> some View {
        background(DismissAttemptCatcher(onAttempt: action).frame(width: 0, height: 0))
    }
}

/// SwiftUI has no callback for a blocked swipe-down, but UIKit does:
/// `presentationControllerDidAttemptToDismiss`. This installs a delegate that
/// reports it and forwards everything else to SwiftUI's own delegate.
private struct DismissAttemptCatcher: UIViewControllerRepresentable {
    let onAttempt: () -> Void

    func makeUIViewController(context: Context) -> Controller { Controller(onAttempt: onAttempt) }
    func updateUIViewController(_ controller: Controller, context: Context) { controller.proxy.onAttempt = onAttempt }

    final class Controller: UIViewController {
        let proxy = Proxy()

        init(onAttempt: @escaping () -> Void) {
            proxy.onAttempt = onAttempt
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // The sheet's own view controller is the top of this one's parent chain.
            var presented: UIViewController = self
            while let parent = presented.parent { presented = parent }
            guard let presentation = presented.presentationController,
                  presentation.delegate !== proxy else { return }
            proxy.original = presentation.delegate
            presentation.delegate = proxy
        }
    }

    final class Proxy: NSObject, UIAdaptivePresentationControllerDelegate {
        weak var original: UIAdaptivePresentationControllerDelegate?
        var onAttempt: () -> Void = {}

        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            onAttempt()
            original?.presentationControllerDidAttemptToDismiss?(presentationController)
        }

        // Everything else (should-dismiss, did-dismiss, ...) goes to SwiftUI's delegate unchanged.
        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || (original?.responds(to: selector) ?? false)
        }

        override func forwardingTarget(for selector: Selector!) -> Any? {
            original?.responds(to: selector) == true ? original : nil
        }
    }
}
