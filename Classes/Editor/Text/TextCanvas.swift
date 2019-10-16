//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import UIKit

/// Protocol for text canvas methods
protocol TextCanvasDelegate: class {
    /// Called when a text is tapped
    ///
    /// - Parameter option: text style options
    /// - Parameter transformations: transformations for the view
    func didTapText(options: TextOptions, transformations: ViewTransformations)
    
    /// Called when a touch event on a movable view begins
    func didBeginTouchesOnText()
    
    /// Called when the touch events on a movable view end
    func didEndTouchesOnText()
}

/// Constants for the text canvas
private struct Constants {
    static let animationDuration: TimeInterval = 0.25
    static let trashViewSize: CGFloat = 98
    static let trashViewBottomMargin: CGFloat = 93
    static let overlayColor = UIColor.black.withAlphaComponent(0.7)
}

/// View that contains the collection of text views
final class TextCanvas: IgnoreTouchesView, UIGestureRecognizerDelegate {
    
    weak var delegate: TextCanvasDelegate?
    
    // View that is being edited
    private var tappedView: MovableTextView?
    
    // View being touched at the moment
    private var currentMovableView: MovableTextView?
    
    // Touch locations during a long press
    private var touchPosition: [CGPoint] = []
    
    // Layout
    private let overlay: UIView
    private let trashView: TrashView
    
    // Values from which the different gestures start
    private var originTransformations: ViewTransformations
    
    
    init() {
        overlay = UIView()
        trashView = TrashView()
        originTransformations = ViewTransformations()
        super.init(frame: .zero)
        setUpViews()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Layout
    
    private func setUpViews() {
        setUpOverlay()
        setUpTrashView()
    }
    
    /// Sets up the trash bin used during text deletion
    private func setUpTrashView() {
        trashView.accessibilityIdentifier = "Editor Text Trash View"
        trashView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(trashView)
        
        NSLayoutConstraint.activate([
            trashView.heightAnchor.constraint(equalToConstant: Constants.trashViewSize),
            trashView.widthAnchor.constraint(equalToConstant: Constants.trashViewSize),
            trashView.centerXAnchor.constraint(equalTo: safeLayoutGuide.centerXAnchor),
            trashView.bottomAnchor.constraint(equalTo: safeLayoutGuide.bottomAnchor, constant: -Constants.trashViewBottomMargin),
        ])
    }
    
    /// Sets up the translucent black view used during text deletion
    private func setUpOverlay() {
        overlay.accessibilityIdentifier = "Editor Text Canvas Overlay"
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.backgroundColor = Constants.overlayColor
        addSubview(overlay)
        
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: topAnchor),
            overlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        
        overlay.alpha = 0
    }
    
    // MARK: - Public interface
    
    /// Adds a new text view
    ///
    /// - Parameter option: text style options
    /// - Parameter transformations: transformations for the view
    /// - Parameter location: location of the text view before transformations
    /// - Parameter size: size of the text view
    func addText(options: TextOptions, transformations: ViewTransformations, location: CGPoint, size: CGSize) {
        let textView = MovableTextView(options: options, transformations: transformations)
        textView.isUserInteractionEnabled = true
        textView.isExclusiveTouch = true
        textView.isMultipleTouchEnabled = true
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)
        
        NSLayoutConstraint.activate([
            textView.heightAnchor.constraint(equalToConstant: size.height),
            textView.widthAnchor.constraint(equalToConstant: size.width),
            textView.topAnchor.constraint(equalTo: topAnchor, constant: location.y - size.height / 2),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: location.x - size.width / 2)
        ])
        
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(textTapped(recognizer:)))
        let rotationRecognizer = UIRotationGestureRecognizer(target: self, action: #selector(textRotated(recognizer:)))
        let pinchRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(textPinched(recognizer:)))
        let panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(textPanned(recognizer:)))
        let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(textLongPressed(recognizer:)))
        
        tapRecognizer.delegate = self
        rotationRecognizer.delegate = self
        pinchRecognizer.delegate = self
        panRecognizer.delegate = self
        longPressRecognizer.delegate = self

        textView.addGestureRecognizer(tapRecognizer)
        textView.addGestureRecognizer(rotationRecognizer)
        textView.addGestureRecognizer(pinchRecognizer)
        textView.addGestureRecognizer(panRecognizer)
        textView.addGestureRecognizer(longPressRecognizer)
        
        UIView.animate(withDuration: Constants.animationDuration) {
            textView.moveToDefinedPosition()
        }
    }
    
    /// Saves the current view into its layer
    func updateLayer() {
        layer.contents = asImage().cgImage
    }
    
    /// Removes the tapped view from the canvas
    func removeTappedView() {
        tappedView?.removeFromSuperview()
        tappedView = nil
    }
    
    // MARK: - Gesture recognizers
    
    @objc func textTapped(recognizer: UITapGestureRecognizer) {
        guard let movableView = recognizer.view as? MovableTextView else { return }
        UIView.animate(withDuration: Constants.animationDuration, animations: {
            movableView.goBackToOrigin()
        }, completion: { [weak self] _ in
            self?.delegate?.didTapText(options: movableView.options, transformations: movableView.transformations)
            self?.tappedView = movableView
            self?.removeTappedView()
        })
    }
    
    @objc func textRotated(recognizer: UIRotationGestureRecognizer) {
        guard let movableView = recognizer.view as? MovableTextView else { return }

        switch recognizer.state {
        case .began:
            onRecognizerBegan(view: movableView)
            originTransformations.rotation = movableView.rotation
        case .changed:
            let newRotation = originTransformations.rotation + recognizer.rotation
            movableView.rotation = newRotation
        case .ended, .cancelled, .failed:
            onRecognizerEnded()
        case .possible:
            break
        @unknown default:
            break
        }
    }
    
    @objc func textPinched(recognizer: UIPinchGestureRecognizer) {
        guard let movableView = recognizer.view as? MovableTextView else { return }
        
        switch recognizer.state {
        case .began:
            onRecognizerBegan(view: movableView)
            originTransformations.scale = movableView.scale
        case .changed:
            let newScale = originTransformations.scale * recognizer.scale
            movableView.scale = newScale
        case .ended, .cancelled, .failed:
            onRecognizerEnded()
        case .possible:
            break
        @unknown default:
            break
        }
    }
    
    @objc func textPanned(recognizer: UIPanGestureRecognizer) {
        guard let movableView = recognizer.view as? MovableTextView else { return }
        
        switch recognizer.state {
        case .began:
            onRecognizerBegan(view: movableView)
            originTransformations.position = movableView.position
        case .changed:
            let newPosition = originTransformations.position + recognizer.translation(in: self)
            movableView.position = newPosition
        case .ended, .cancelled, .failed:
            onRecognizerEnded()
        case .possible:
            break
        @unknown default:
            break
        }
    }
    
    @objc func textLongPressed(recognizer: UILongPressGestureRecognizer) {
        guard let movableView = recognizer.view as? MovableTextView else { return }
        
        switch recognizer.state {
        case .began:
            onRecognizerBegan(view: movableView)
            showOverlay(true)
            movableView.fadeOut()
            touchPosition = recognizer.touchLocations
            trashView.changeStatus(touchPosition)
        case .changed:
            touchPosition = recognizer.touchLocations
            trashView.changeStatus(touchPosition)
        case .ended, .cancelled, .failed:
            if trashView.contains(touchPosition) {
                movableView.remove()
            }
            else {
                movableView.fadeIn()
            }
            showOverlay(false)
            trashView.hide()
            onRecognizerEnded()
        case .possible:
            break
        @unknown default:
            break
        }
    }
    
    // MARK: - UIGestureRecognizerDelegate
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        let oneIsTapGesture = gestureRecognizer is UITapGestureRecognizer || otherGestureRecognizer is UITapGestureRecognizer
        return !oneIsTapGesture
    }
    
    // MARK: - Private utilities
    
    /// shows or hides the overlay
    ///
    /// - Parameter show: true to show, false to hide
    func showOverlay(_ show: Bool) {
        UIView.animate(withDuration: Constants.animationDuration) {
            self.overlay.alpha = show ? 1 : 0
        }
    }
    
    // MARK: - Extended touch area
    
    private func onRecognizerBegan(view: MovableTextView) {
        if currentMovableView == nil {
            didBeginTouches(on: view)
        }
    }
    
    private func onRecognizerEnded() {
        guard let currentMovableView = currentMovableView,
            let recognizers = currentMovableView.gestureRecognizers else { return }
        
        let allRecognizersAreInactive = recognizers.allSatisfy { $0.isInactive }
        if allRecognizersAreInactive {
            didEndTouches()
        }
    }
    
    func didBeginTouches(on view: MovableTextView) {
        currentMovableView = view
        delegate?.didBeginTouchesOnText()
    }
    
    func didEndTouches() {
        currentMovableView = nil
        delegate?.didEndTouchesOnText()
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let currentMovableView = currentMovableView {
            return currentMovableView
        }
        else {
            return super.hitTest(point, with: event)
        }
    }
}

// Extension for obtaining touch locations easily
private extension UILongPressGestureRecognizer {
    
    var touchLocations: [CGPoint] {
        var locations: [CGPoint] = []
        for touch in 0..<numberOfTouches {
            locations.append(location(ofTouch: touch, in: view?.superview))
        }
        
        return locations
    }
}
