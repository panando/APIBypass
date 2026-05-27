import SwiftUI
import AppKit

struct ThreeColumnSplitView<Left: View, Center: View, Right: View>: NSViewRepresentable {
    let leftView: Left
    let centerView: Center
    let rightView: Right
    let leftDefaultWidth: CGFloat
    let rightDefaultWidth: CGFloat
    let leftMinWidth: CGFloat
    let rightMinWidth: CGFloat

    init(
        leftDefaultWidth: CGFloat = 220,
        rightDefaultWidth: CGFloat = 220,
        leftMinWidth: CGFloat = 160,
        rightMinWidth: CGFloat = 160,
        @ViewBuilder left: () -> Left,
        @ViewBuilder center: () -> Center,
        @ViewBuilder right: () -> Right
    ) {
        self.leftDefaultWidth = leftDefaultWidth
        self.rightDefaultWidth = rightDefaultWidth
        self.leftMinWidth = leftMinWidth
        self.rightMinWidth = rightMinWidth
        self.leftView = left()
        self.centerView = center()
        self.rightView = right()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(leftDefaultWidth: leftDefaultWidth, rightDefaultWidth: rightDefaultWidth,
                    leftMinWidth: leftMinWidth, rightMinWidth: rightMinWidth)
    }

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = context.coordinator

        let leftHosting = NSHostingView(rootView: leftView)
        let centerHosting = NSHostingView(rootView: centerView)
        let rightHosting = NSHostingView(rootView: rightView)

        splitView.addArrangedSubview(leftHosting)
        splitView.addArrangedSubview(centerHosting)
        splitView.addArrangedSubview(rightHosting)

        leftHosting.widthAnchor.constraint(greaterThanOrEqualToConstant: leftMinWidth).isActive = true
        rightHosting.widthAnchor.constraint(greaterThanOrEqualToConstant: rightMinWidth).isActive = true
        centerHosting.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true

        context.coordinator.splitView = splitView
        context.coordinator.leftHosting = leftHosting
        context.coordinator.centerHosting = centerHosting
        context.coordinator.rightHosting = rightHosting

        return splitView
    }

    func updateNSView(_ nsView: NSSplitView, context: Context) {
        if let hosting = context.coordinator.leftHosting {
            hosting.rootView = leftView
        }
        if let hosting = context.coordinator.centerHosting {
            hosting.rootView = centerView
        }
        if let hosting = context.coordinator.rightHosting {
            hosting.rootView = rightView
        }
    }

    class Coordinator: NSObject, NSSplitViewDelegate {
        weak var splitView: NSSplitView?
        weak var leftHosting: NSHostingView<Left>?
        weak var centerHosting: NSHostingView<Center>?
        weak var rightHosting: NSHostingView<Right>?

        let leftDefaultWidth: CGFloat
        let rightDefaultWidth: CGFloat
        let leftMinWidth: CGFloat
        let rightMinWidth: CGFloat
        var didSetInitialWidths = false

        init(leftDefaultWidth: CGFloat, rightDefaultWidth: CGFloat, leftMinWidth: CGFloat, rightMinWidth: CGFloat) {
            self.leftDefaultWidth = leftDefaultWidth
            self.rightDefaultWidth = rightDefaultWidth
            self.leftMinWidth = leftMinWidth
            self.rightMinWidth = rightMinWidth
        }

        func splitViewDidResizeSubviews(_ notification: Notification) {
            guard let splitView = splitView, !didSetInitialWidths else { return }
            didSetInitialWidths = true

            let totalWidth = splitView.bounds.width
            guard totalWidth > 0 else { return }

            let leftWidth = min(leftDefaultWidth, totalWidth * 0.25)
            let rightWidth = min(rightDefaultWidth, totalWidth * 0.25)

            // Set left divider position
            splitView.setPosition(leftWidth, ofDividerAt: 0)
            // Set right divider position (from the right edge)
            if splitView.arrangedSubviews.count >= 3 {
                splitView.setPosition(totalWidth - rightWidth, ofDividerAt: 1)
            }
        }

        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            if dividerIndex == 0 {
                return leftMinWidth
            }
            return proposedMinimumPosition
        }

        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            let totalWidth = splitView.bounds.width
            if dividerIndex == 0 {
                return totalWidth * 0.45
            }
            if dividerIndex == 1 {
                return totalWidth - rightMinWidth
            }
            return proposedMaximumPosition
        }
    }
}
