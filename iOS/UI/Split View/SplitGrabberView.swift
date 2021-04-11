//
//  SplitGrabberView.swift
//  NewTerm (iOS)
//
//  Created by Adam Demasi on 11/4/21.
//

import UIKit

class SplitGrabberView: UIView {

	private(set) var axis: NSLayoutConstraint.Axis

	private var pillView: UIView!

	init(axis: NSLayoutConstraint.Axis) {
		self.axis = axis
		super.init(frame: .zero)

		backgroundColor = .black

		let pillContainerView = UIView()
		pillContainerView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(pillContainerView)

		pillView = UIView()
		pillView.translatesAutoresizingMaskIntoConstraints = false
		pillView.backgroundColor = .white
		pillView.alpha = 0.55
		pillView.layer.cornerRadius = 2
		pillContainerView.addSubview(pillView)

		let selfWidth: CGFloat = 10
		let pillWidth: CGFloat = 4
		let pillHeight: CGFloat = 44
		let pillSpacingX: CGFloat = 3
		let pillSpacingY: CGFloat = 12
		NSLayoutConstraint.activate([
				.vertical: [
					self.heightAnchor.constraint(equalToConstant: selfWidth),
					pillView.widthAnchor.constraint(equalToConstant: pillHeight),
					pillView.heightAnchor.constraint(equalToConstant: pillWidth),
					pillView.leadingAnchor.constraint(equalTo: pillContainerView.leadingAnchor, constant: pillSpacingY),
					pillView.trailingAnchor.constraint(equalTo: pillContainerView.trailingAnchor, constant: -pillSpacingY),
					pillView.topAnchor.constraint(equalTo: pillContainerView.topAnchor, constant: pillSpacingX),
					pillView.bottomAnchor.constraint(equalTo: pillContainerView.bottomAnchor, constant: -pillSpacingX)
				],
				.horizontal: [
					self.widthAnchor.constraint(equalToConstant: selfWidth),
					pillView.heightAnchor.constraint(equalToConstant: pillHeight),
					pillView.widthAnchor.constraint(equalToConstant: pillWidth),
					pillView.leadingAnchor.constraint(equalTo: pillContainerView.leadingAnchor, constant: pillSpacingX),
					pillView.trailingAnchor.constraint(equalTo: pillContainerView.trailingAnchor, constant: -pillSpacingX),
					pillView.topAnchor.constraint(equalTo: pillContainerView.topAnchor, constant: pillSpacingY),
					pillView.bottomAnchor.constraint(equalTo: pillContainerView.bottomAnchor, constant: -pillSpacingY)
				]
		][axis]!)

		NSLayoutConstraint.activate([
			pillContainerView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
			pillContainerView.centerYAnchor.constraint(equalTo: self.centerYAnchor)
		])

		// Mac: Entire bar is a grabber.
		// iOS: Just the pill is a grabber.
		// Matches expected behaviour of split views on each platform.
		addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(self.panGestureRecognizerFired)))

		#if targetEnvironment(macCatalyst)
		addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(self.hoverGestureRecognizerFired)))
		#endif

		if #available(iOS 13.4, *) {
			pillContainerView.addInteraction(UIPointerInteraction(delegate: self))
		}
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	@objc private func panGestureRecognizerFired(_ gestureRecognizer: UIPanGestureRecognizer) {
		switch gestureRecognizer.state {
		case .changed:
			break

		case .ended:
			break

		case .failed, .cancelled:
			break

		case .began, .possible: break
		@unknown default: break
		}
	}

	#if targetEnvironment(macCatalyst)
	@objc private func hoverGestureRecognizerFired(_ gestureRecognizer: UIHoverGestureRecognizer) {
		switch gestureRecognizer.state {
		case .began, .changed:
			UIView.animate(withDuration: 0.2) {
				self.pillView.alpha = 1
			}

			switch axis {
			case .horizontal: NSCursor.resizeLeftRight.set()
			case .vertical:   NSCursor.resizeUpDown.set()
			@unknown default: fatalError()
			}

		case .ended, .failed, .cancelled:
			UIView.animate(withDuration: 0.2) {
				self.pillView.alpha = 0.55
			}

			NSCursor.arrow.set()

		case .possible:   break
		@unknown default: break
		}
	}
	#endif

}

@available(iOS 13.4, *)
extension SplitGrabberView: UIPointerInteractionDelegate {

	func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
		let rectFrame: CGRect
		switch axis {
		case .horizontal: rectFrame = pillView.frame.insetBy(dx: -2, dy: -5)
		case .vertical:   rectFrame = pillView.frame.insetBy(dx: -5, dy: -2)
		@unknown default: fatalError()
		}
		return UIPointerStyle(effect: .highlight(UITargetedPreview(view: pillView)),
													shape: .roundedRect(rectFrame, radius: 7))
	}

}
