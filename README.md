# swift-sphere-view

A `UIView` subclass that arranges subviews on the surface of a virtual sphere using a Fibonacci distribution algorithm. Supports pan-to-rotate, pinch-to-zoom, deceleration, and automatic front-item focus snapping.

## Requirements

- iOS 16+
- Swift 6.0+

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/DerNoah/swift-sphere-view", from: "1.0.0")
]
```

---

## Usage

### 1. Create the view

```swift
import SphereView

let sphere = SphereElementView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
view.addSubview(sphere)
```

### 2. Add subviews to `contentView`

Any `UIView` added to `sphere.contentView` is automatically distributed across the sphere surface.

```swift
let labels = ["Swift", "iOS", "UIKit", "SpriteKit", "SwiftUI"]

for text in labels {
    let label = UILabel()
    label.text = text
    label.sizeToFit()
    sphere.contentView.addSubview(label)
}
```

### 3. Respond to focus changes

```swift
sphere.onFrontItemChanged = {
    // The frontmost (closest to the viewer) item changed.
    // Inspect sphere.contentView.subviews to find the one at the front.
}
```

---

## Configuration

```swift
// Sphere radius (default: half the view width)
sphere.sphereRadius = 180

// Minimum pan velocity required to trigger deceleration scroll
sphere.decelerationTolerance = 80

// Disable gestures individually
sphere.isScrollEnabled = false
sphere.isPinchEnabled = false
```

---

## Excluding subviews

Tag any subview with `SphereElementView.excludedFromFocusTag` to exclude it from the focus system and interaction tracking. Excluded views are still positioned on the sphere but never become the front item.

```swift
let backgroundDecoration = UIView()
backgroundDecoration.tag = SphereElementView.excludedFromFocusTag
sphere.contentView.addSubview(backgroundDecoration)
```

---

## Programmatic control

| Method | Effect |
|---|---|
| `resetRotation()` | Animatably resets the sphere's rotation to its origin orientation |
| `resetZoom()` | Resets the sphere radius to the default (half the view width) |
| `resetTransform()` | Resets both rotation and zoom, then recomputes the layout |
| `invalidateLayout()` | Recalculates a sphere radius that best fits the current subviews into the available space |
| `refreshLayout()` | Repositions subviews on the sphere — call after adding/removing subviews or changing a view's excluded state |
| `snapToFrontItem()` | Animates the frontmost non-excluded item to face the viewer |

```swift
sphere.refreshLayout()      // after mutating contentView.subviews
sphere.snapToFrontItem()    // bring the front item into focus
sphere.resetTransform()     // back to the initial orientation and zoom
```

---

## How it works

Subviews are placed using the [Fibonacci sphere](https://arxiv.org/abs/0912.4540) algorithm (golden-angle distribution), which produces near-uniform coverage with no clustering at the poles. Rotation is tracked as a unit quaternion (`simd_quatd`) to avoid gimbal lock. Deceleration uses cubic easing driven by an async `Task`.

---

## License

Released under the MIT License. See [LICENSE](LICENSE).
