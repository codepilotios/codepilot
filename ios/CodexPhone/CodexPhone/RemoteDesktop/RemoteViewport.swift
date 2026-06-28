import CoreGraphics

struct RemoteViewport: Equatable {
    var zoom: CGFloat
    var cursor: CGPoint

    init(zoom: CGFloat = 1, cursor: CGPoint = CGPoint(x: 0.5, y: 0.5)) {
        self.zoom = min(4, max(1, zoom))
        self.cursor = CGPoint(
            x: min(1, max(0, cursor.x)),
            y: min(1, max(0, cursor.y))
        )
    }

    func offset(container: CGSize, image: CGSize) -> CGSize {
        let scaled = scaledImageSize(container: container, image: image)
        let desired = CGSize(
            width: scaled.width * (0.5 - cursor.x),
            height: scaled.height * (0.5 - cursor.y)
        )
        let horizontalLimit = max(0, (scaled.width - container.width) / 2)
        let verticalLimit = max(0, (scaled.height - container.height) / 2)
        return CGSize(
            width: min(horizontalLimit, max(-horizontalLimit, desired.width)),
            height: min(verticalLimit, max(-verticalLimit, desired.height))
        )
    }

    func cursorPosition(container: CGSize, image: CGSize) -> CGPoint {
        let scaled = scaledImageSize(container: container, image: image)
        let origin = CGPoint(
            x: (container.width - scaled.width) / 2,
            y: (container.height - scaled.height) / 2
        )
        let viewportOffset = offset(container: container, image: image)
        return CGPoint(
            x: origin.x + viewportOffset.width + cursor.x * scaled.width,
            y: origin.y + viewportOffset.height + cursor.y * scaled.height
        )
    }

    private func scaledImageSize(container: CGSize, image: CGSize) -> CGSize {
        guard container.width > 0, container.height > 0, image.width > 0, image.height > 0 else {
            return .zero
        }
        let fitScale = min(container.width / image.width, container.height / image.height)
        return CGSize(width: image.width * fitScale * zoom, height: image.height * fitScale * zoom)
    }
}
