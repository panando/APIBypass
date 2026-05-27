import SwiftUI
import AppKit

struct SplitView<Leading: View, Center: View, Trailing: View>: NSViewRepresentable {
    let leading: Leading
    let center: Center
    let trailing: Trailing
    let leadingDefaultWidth: CGFloat
    let trailingDefaultWidth: CGFloat

    init(
        leadingDefaultWidth: CGFloat = 200,
        trailingDefaultWidth: CGFloat = 200,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder center: () -> Center,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.leadingDefaultWidth = leadingDefaultWidth
        self.trailingDefaultWidth = trailingDefaultWidth
        self.leading = leading()
        self.center = center()
        self.trailing = trailing()
    }

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        let leadingHost = NSHostingView(rootView: leading)
        let centerHost = NSHostingView(rootView: center)
        let trailingHost = NSHostingView(rootView: trailing)

        splitView.addSubview(leadingHost)
        splitView.addSubview(centerHost)
        splitView.addSubview(trailingHost)

        // Set initial constraints
        leadingHost.translatesAutoresizingMaskIntoConstraints = false
        centerHost.translatesAutoresizingMaskIntoConstraints = false
        trailingHost.translatesAutoresizingMaskIntoConstraints = false

        // Set default widths
        let totalWidth = splitView.frame.width > 0 ? splitView.frame.width : 1200
        leadingHost.setFrameSize(NSSize(width: leadingDefaultWidth, height: splitView.frame.height))
        centerHost.setFrameSize(NSSize(width: totalWidth - leadingDefaultWidth - trailingDefaultWidth, height: splitView.frame.height))
        trailingHost.setFrameSize(NSSize(width: trailingDefaultWidth, height: splitView.frame.height))

        // Center pane should expand
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 1)

        context.coordinator.splitView = splitView
        context.coordinator.leadingHost = leadingHost
        context.coordinator.centerHost = centerHost
        context.coordinator.trailingHost = trailingHost

        splitView.delegate = context.coordinator

        return splitView
    }

    func updateNSView(_ splitView: NSSplitView, context: Context) {
        context.coordinator.leadingHost?.rootView = leading
        context.coordinator.centerHost?.rootView = center
        context.coordinator.trailingHost?.rootView = trailing
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(leadingMinWidth: 180, trailingMinWidth: 180, centerMinWidth: 300)
    }

    class Coordinator: NSObject, NSSplitViewDelegate {
        var splitView: NSSplitView?
        var leadingHost: NSHostingView<Leading>?
        var centerHost: NSHostingView<Center>?
        var trailingHost: NSHostingView<Trailing>?

        let leadingMinWidth: CGFloat
        let trailingMinWidth: CGFloat
        let centerMinWidth: CGFloat

        init(leadingMinWidth: CGFloat, trailingMinWidth: CGFloat, centerMinWidth: CGFloat) {
            self.leadingMinWidth = leadingMinWidth
            self.trailingMinWidth = trailingMinWidth
            self.centerMinWidth = centerMinWidth
        }

        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            if dividerIndex == 0 {
                // Left divider: ensure leading pane has min width
                return leadingMinWidth
            } else if dividerIndex == 1 {
                // Right divider: ensure trailing pane has min width
                if let trailingFrame = trailingHost?.frame {
                    return splitView.frame.width - trailingMinWidth - splitView.dividerThickness
                }
            }
            return proposedMinimumPosition
        }

        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            if dividerIndex == 0 {
                // Left divider: don't let leading pane eat into center's min width
                if let trailingFrame = trailingHost?.frame {
                    let rightEdge = splitView.frame.width - trailingFrame.width - splitView.dividerThickness
                    return rightEdge - centerMinWidth - splitView.dividerThickness
                }
                return splitView.frame.width - centerMinWidth - trailingMinWidth
            } else if dividerIndex == 1 {
                // Right divider: ensure trailing pane doesn't eat into center's min width
                if let leadingFrame = leadingHost?.frame {
                    return leadingFrame.width + centerMinWidth + splitView.dividerThickness
                }
            }
            return proposedMaximumPosition
        }

        func splitViewDidResizeSubviews(_ notification: Notification) {
            guard let splitView = splitView,
                  let leading = leadingHost,
                  let trailing = trailingHost,
                  let center = centerHost else { return }

            let totalWidth = splitView.frame.width
            let dividerWidth = splitView.dividerThickness * 2

            // Enforce min widths after resize
            let leadingWidth = max(leadingMinWidth, leading.frame.width)
            let trailingWidth = max(trailingMinWidth, trailing.frame.width)
            let centerWidth = totalWidth - leadingWidth - trailingWidth - dividerWidth

            if centerWidth >= centerMinWidth {
                leading.setFrameSize(NSSize(width: leadingWidth, height: splitView.frame.height))
                center.setFrameSize(NSSize(width: centerWidth, height: splitView.frame.height))
                trailing.setFrameSize(NSSize(width: trailingWidth, height: splitView.frame.height))
            } else {
                // Center too small, proportionally shrink side panels
                let available = totalWidth - centerMinWidth - dividerWidth
                let ratio = leadingWidth / max(1, leadingWidth + trailingWidth)
                let newLeading = max(leadingMinWidth, available * ratio)
                let newTrailing = available - newLeading

                leading.setFrameSize(NSSize(width: newLeading, height: splitView.frame.height))
                center.setFrameSize(NSSize(width: centerMinWidth, height: splitView.frame.height))
                trailing.setFrameSize(NSSize(width: newTrailing, height: splitView.frame.height))
            }

            splitView.adjustSubviews()
        }
    }
}
