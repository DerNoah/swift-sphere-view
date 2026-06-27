import simd
import UIKit

/// A `UIView` that arranges its `contentView` subviews on the surface of a virtual sphere,
/// supporting pan-to-rotate and pinch-to-zoom gestures.
///
/// Add any `UIView` instances as subviews of `contentView`. They will be positioned using a
/// Fibonacci sphere algorithm that distributes points evenly over the surface. Pan the view to
/// spin the sphere; the frontmost item snaps into focus automatically.
///
/// ## Usage
/// ```swift
/// let sphere = SphereElementView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
///
/// for label in myLabels {
///     sphere.contentView.addSubview(label)
/// }
///
/// sphere.onFrontItemChanged = {
///     // React to the frontmost item changing
/// }
/// ```
///
/// ## Exclusion
/// Tag a subview with `SphereElementView.excludedFromFocusTag` to exclude it from
/// focus/snap and interaction tracking.
open class SphereElementView: UIView {
    /// Tag value that marks a subview as excluded from focus/snap and interaction
    public static let excludedFromFocusTag = 1

    /// the radius of sphere
    open var sphereRadius: CGFloat { didSet { positionSubviews() }}
    
    /// subviews of contentView will be layouted as sphere
    open var contentView = UIView()
    
    /// the minimum amount of pan velocity that is required to decelerate the scroll
    open var decelerationTolerance: CGFloat = 80
    
    /// When `false`, the pan gesture recognizer is removed and the sphere cannot be rotated by the user.
    open var isScrollEnabled: Bool = true {
        didSet {
            if isScrollEnabled {
                addGestureRecognizer(panGestureRecognizer)
            } else {
                removeGestureRecognizer(panGestureRecognizer)
            }
        }
    }

    /// When `false`, the pinch gesture recognizer is removed and the sphere radius cannot be changed by the user.
    open var isPinchEnabled: Bool = true {
        didSet {
            if isPinchEnabled {
                addGestureRecognizer(pinchGestureRecognizer)
            } else {
                removeGestureRecognizer(pinchGestureRecognizer)
            }
        }
    }
    
    /// Called whenever the frontmost non-excluded item changes.
    public var onFrontItemChanged: (() -> Void)?

    private var globalRotation = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1) // identity quaternion
    private weak var currentFrontView: UIView?

    private var currentDecelerationTask: Task<Void, Error>?
    
    private lazy var lastPinchScale: CGFloat = sphereRadius
    
    private lazy var panGestureRecognizer: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        recognizer.cancelsTouchesInView = false
        return recognizer
    }()

    private lazy var pinchGestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinchGesture(_:)))
    private lazy var contentTapGestureRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleContentTap(_:)))
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesEnded = false
        return recognizer
    }()
    
    public override init(frame: CGRect) {
        self.sphereRadius = frame.size.width / 2
        super.init(frame: frame)
        setup()
    }
    
    public required init?(coder: NSCoder) {
        self.sphereRadius = 1
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        addSubview(contentView)

        addGestureRecognizer(panGestureRecognizer)
        addGestureRecognizer(pinchGestureRecognizer)
        contentView.addGestureRecognizer(contentTapGestureRecognizer)
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        contentView.frame = bounds
        positionSubviews()
    }
    
    private func cancelCurrentPanDeceleration() {
        currentDecelerationTask?.cancel()
    }
    
    /// rotates around given axis
    /// animatable
    func setRotationOffset(xAxis: Double, yAxis: Double) {
        cancelCurrentPanDeceleration()
        globalRotation = rotateSphereWithGlobalAxes(globalRotation: globalRotation, deltaX: yAxis, deltaY: xAxis)
        positionSubviews()
    }
    
    /// resets current rotation
    /// animatable
    public func resetRotation() {
        cancelCurrentPanDeceleration()
        globalRotation = rotateSphereWithGlobalAxes(globalRotation: globalRotation, deltaX: 0, deltaY: 0)
        positionSubviews()
    }
    
    /// resets sphere scale
    /// animatable
    public func resetZoom() {
        sphereRadius = frame.size.width / 2
        lastPinchScale = sphereRadius
    }
    
    /// resets sphere rotation and zoom to origin
    /// animatable
    public func resetTransform() {
        cancelCurrentPanDeceleration()
        resetRotation()
        resetZoom()
        invalidateLayout()
    }
    
    /// calculates a layout that fits into space
    /// animatable
    public func invalidateLayout() {
        let averageViewSize = contentView.subviews.reduce(CGFloat.zero) { partialResult, element in
            partialResult + element.bounds.width
        } / CGFloat(contentView.subviews.count)
        
        let itemsFitInWidth = bounds.width / averageViewSize
        let newRadius = itemsFitInWidth * averageViewSize
        
        sphereRadius = newRadius
        lastPinchScale = newRadius
    }
    
    private func positionSubviews() {
        let subviews = contentView.subviews
        let spherePositions = fibonacciSphere(numberOfPoints: subviews.count)

        var newFrontView: UIView?
        var minZ = Double.infinity

        for (i, view) in subviews.reversed().enumerated() {
            let x = (spherePositions[i].x * sphereRadius) + contentView.bounds.width / 2
            let y = (spherePositions[i].y * sphereRadius) + contentView.bounds.height / 2
            let transformedZ = max((1 - CGFloat(spherePositions[i].z)) / 2, 0.3) // 0.3 to 1.0

            view.center = CGPoint(x: x, y: y)

            view.transform = CGAffineTransform(scaleX: transformedZ, y: transformedZ)
            view.alpha = transformedZ + 0.1

            view.layer.zPosition = transformedZ
            view.isUserInteractionEnabled = view.tag != Self.excludedFromFocusTag

            if view.tag != Self.excludedFromFocusTag && spherePositions[i].z < minZ {
                minZ = spherePositions[i].z
                newFrontView = view
            }
        }

        if let newFrontView, newFrontView !== currentFrontView {
            currentFrontView = newFrontView
            onFrontItemChanged?()
        }
    }

    /// repositions subviews on the sphere — call after changing excluded state
    public func refreshLayout() {
        positionSubviews()
    }

    /// snaps the frontmost non-excluded item to the center — call after changing excluded state
    public func snapToFrontItem() {
        cancelCurrentPanDeceleration()
        currentDecelerationTask = Task { @MainActor in
            let allSubviews = contentView.subviews
            let positions = fibonacciSphere(numberOfPoints: allSubviews.count)
            let candidates = zip(allSubviews.reversed(), positions)
                .filter { view, _ in view.tag != Self.excludedFromFocusTag }
            guard let (_, frontPoint) = candidates.min(by: { $0.1.z < $1.1.z }) else { return }
            try await snapToPoint(frontPoint)
        }
    }
    
    // MARK: Fibonacci Sphere
    
    private func fibonacciSphere(numberOfPoints: Int) -> [(x: Double, y: Double, z: Double)] {
        let phi = (1.0 + sqrt(5.0)) / 2.0 // golden ratio
        var points = [(x: Double, y: Double, z: Double)]()
        
        for i in 0..<numberOfPoints {
            let iDouble = Double(i)
            let theta = acos(1 - 2 * (iDouble + 0.5) / Double(numberOfPoints))
            let phi_i = 2 * Double.pi * (iDouble / phi).truncatingRemainder(dividingBy: 1)
            
            // Spherical coordinates to Cartesian
            let x = sin(theta) * cos(phi_i)
            let y = sin(theta) * sin(phi_i)
            let z = cos(theta)
            
            let rotated = globalRotation.act(simd_double3(x, y, z))
            points.append((x: rotated.x, y: rotated.y, z: rotated.z))
        }
        
        return points
    }
    
    // MARK: Tap Gesture

    @objc
    private func handleContentTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: contentView)

        let allSubviews = contentView.subviews
        let positions = fibonacciSphere(numberOfPoints: allSubviews.count)
        let reversedSubviews = Array(allSubviews.reversed())

        let sortedPairs = zip(reversedSubviews, positions)
            .sorted { $0.0.layer.zPosition > $1.0.layer.zPosition }

        guard let (tappedView, tappedPoint) = sortedPairs.first(where: { view, _ in
            guard view.tag != Self.excludedFromFocusTag else { return false }
            let localPoint = view.convert(location, from: contentView)
            return view.point(inside: localPoint, with: nil)
        }), tappedView.layer.zPosition > 0.5 else { return }

        if let tappedView = (tappedView as? UIControl) {
            tappedView.isSelected.toggle()
        }

        cancelCurrentPanDeceleration()
        currentDecelerationTask = Task { @MainActor in
            try await snapToPoint(tappedPoint)
        }
    }

    @MainActor
    private func snapToPoint(_ point: (x: Double, y: Double, z: Double)) async throws {
        let from = simd_normalize(simd_double3(point.x, point.y, point.z))
        let to = simd_double3(0, 0, -1)
        guard simd_length(from - to) > 0.01 else { return }

        let snapDelta = simd_quaternion(from, to)
        let targetRotation = simd_normalize(snapDelta * globalRotation)
        let startRotation = globalRotation

        for i in 1...20 {
            try await Task.sleep(nanoseconds: 16000000)
            let easedT = 1 - pow(1 - Double(i) / 20, 3)
            globalRotation = simd_slerp(startRotation, targetRotation, easedT)
            positionSubviews()
        }
    }

    // MARK: Pinch Gesture
    
    @objc
    private func handlePinchGesture(_ sender: UIPinchGestureRecognizer) {
        let pinchScale = (sender.scale * lastPinchScale)
        
        switch sender.state {
            case .changed:
                sphereRadius = pinchScale
            case .ended:
                lastPinchScale = pinchScale
            default:
                break
        }
    }
    
    // MARK: Pan Gesture
    
    @objc
    private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        let deltaX = -Double(translation.x)
        let deltaY = Double(translation.y)
        
        switch gesture.state {
            case .began:
                cancelCurrentPanDeceleration()
            case .changed:
                // Apply the rotation to the sphere's global rotation quaternion
                globalRotation = rotateSphereWithGlobalAxes(globalRotation: globalRotation, deltaX: deltaX, deltaY: deltaY)
                positionSubviews()
            case .ended:
                deceleratePanGesture(velocity: gesture.velocity(in: self))
            default:
                break
        }
        
        // Reset the gesture's translation to avoid compounding deltas
        gesture.setTranslation(.zero, in: self)
    }
    
    private func deceleratePanGesture(velocity: CGPoint) {
        let shouldDecelerate = abs(velocity.x) > decelerationTolerance || abs(velocity.y) > decelerationTolerance

        let decelerationRate = UIScrollView.DecelerationRate.fast.rawValue
        let decelerationMultiplier = decelerationRate / 1.03
        var currentVelocity = CGPoint(x: velocity.x / 100, y: velocity.y / 100)

        currentDecelerationTask = Task { @MainActor in
            if shouldDecelerate {
                while abs(currentVelocity.x) > 0.1 || abs(currentVelocity.y) > 0.1 {
                    try await Task.sleep(nanoseconds: 16000000) // 16ms frame delay

                    currentVelocity = CGPoint(
                        x: currentVelocity.x * decelerationMultiplier,
                        y: currentVelocity.y * decelerationMultiplier
                    )

                    let deltaX = -Double(currentVelocity.x)
                    let deltaY = Double(currentVelocity.y)

                    globalRotation = rotateSphereWithGlobalAxes(globalRotation: globalRotation, deltaX: deltaX, deltaY: deltaY)
                    positionSubviews()
                }
            }

            // Snap the closest non-excluded sphere item to the front center
            let allSubviews = contentView.subviews
            let positions = fibonacciSphere(numberOfPoints: allSubviews.count)
            // pair each (reversed) subview with its fibonacci position, skip excluded ones
            let candidates = zip(allSubviews.reversed(), positions)
                .filter { view, _ in view.tag != Self.excludedFromFocusTag }
            guard let (_, frontPoint) = candidates.min(by: { $0.1.z < $1.1.z }) else { return }

            try await snapToPoint(frontPoint)
        }
    }
}

// MARK: Rotation Helper

extension SphereElementView {
    private func rotateSphereWithGlobalAxes(
        globalRotation: simd_quatd,
        deltaX: Double,
        deltaY: Double,
        sensitivity: Double = 0.01
    ) -> simd_quatd {
        // Convert the pan deltas into rotation angles (radians)
        let rotationX = deltaY * sensitivity
        let rotationY = deltaX * sensitivity
        
        // Create quaternions for the rotations around the global axes
        let quaternionX = simd_quaternion(rotationX, simd_double3(1, 0, 0))
        let quaternionY = simd_quaternion(rotationY, simd_double3(0, 1, 0))
        
        // Combine the rotations: Y then X to ensure global axis orientation
        let newRotation = quaternionY * quaternionX
        
        // Apply the new rotation to the existing global rotation
        let updatedGlobalRotation = newRotation * globalRotation
        
        // Normalize the quaternion to maintain consistent behavior
        return simd_normalize(updatedGlobalRotation)
    }
}
