//
//  TerminalSplitViewController.swift
//  NewTerm (iOS)
//
//  Created by Adam Demasi on 10/4/21.
//

import UIKit
import NewTermCommon

protocol TerminalSplitViewControllerDelegate: AnyObject {
	func terminal(viewController: BaseTerminalSplitViewControllerChild, titleDidChange title: String, isDirty: Bool, hasBell: Bool)
	func terminal(viewController: BaseTerminalSplitViewControllerChild, screenSizeDidChange screenSize: ScreenSize)
	func terminalDidBecomeActive(viewController: BaseTerminalSplitViewControllerChild)
}

class BaseTerminalSplitViewControllerChild: UIViewController {
	weak var delegate: TerminalSplitViewControllerDelegate?

	var screenSize: ScreenSize?
	var isSplitViewResizing = false
	var showsTitleView = false
}

class TerminalSplitViewController: BaseTerminalSplitViewControllerChild {

	private static let splitSnapPoints: [Double] = [
		1 / 2, // 50%
		1 / 4, // 25%
		1 / 3, // 33%
		2 / 3, // 66%
		3 / 4  // 75%
	]

	var viewControllers: [BaseTerminalSplitViewControllerChild]! {
		didSet { updateViewControllers() }
	}
	var axis: NSLayoutConstraint.Axis = .horizontal {
		didSet { stackView.axis = axis }
	}

	override var isSplitViewResizing: Bool {
		didSet { updateIsSplitViewResizing() }
	}
	override var showsTitleView: Bool {
		didSet { updateShowsTitleView() }
	}

	private let stackView = UIStackView()
	private var splitPercentages = [Double]()
	private var oldSplitPercentages = [Double]()
	private var constraints = [NSLayoutConstraint]()
    
    public var terminalIndex = 0
	private var selectedIndex = 0

	private var keyboardVisible = false
	private var keyboardHeight: CGFloat = 0

	override func loadView() {
		super.loadView()

		stackView.translatesAutoresizingMaskIntoConstraints = false
		stackView.axis = axis
		stackView.spacing = 0
		view.addSubview(stackView)

		NSLayoutConstraint.activate([
			view.safeAreaLayoutGuide.topAnchor.constraint(equalTo: stackView.topAnchor),
			view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: stackView.bottomAnchor),
			view.safeAreaLayoutGuide.leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
			view.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: stackView.trailingAnchor)
		])
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

        self.keyboardVisible = false
		NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardVisibilityChanged(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardVisibilityChanged(_:)), name: UIResponder.keyboardDidShowNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardVisibilityChanged(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardVisibilityChanged(_:)), name: UIResponder.keyboardDidHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardVisibilityChanged(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardVisibilityChanged(_:)), name: UIResponder.keyboardDidChangeFrameNotification, object: nil)
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)

		// Removing keyboard notification observers should come first so we don’t trigger a bunch of
		// probably unnecessary screen size changes.
		NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
		NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardDidShowNotification, object: nil)
		NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
		NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardDidHideNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardDidChangeFrameNotification, object: nil)
	}

	override func updateViewConstraints() {
		super.updateViewConstraints()
		updateConstraints()
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		updateConstraints()
	}

	override func viewSafeAreaInsetsDidChange() {
        NSLog("NewTermLog: TerminalSplitViewController.viewSafeAreaInsetsDidChange view.safeAreaInsets=\(view.safeAreaInsets)")
		super.viewSafeAreaInsetsDidChange()
		updateConstraints()
	}

	override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
		super.traitCollectionDidChange(previousTraitCollection)
		updateConstraints()
	}
    
    override func removeFromParent() {
        super.removeFromParent()
        self.viewControllers.map { viewController in
            viewController.removeFromParent()
        }
    }

	// MARK: - Split View

	private func updateViewControllers() {
		loadViewIfNeeded()

		for view in stackView.arrangedSubviews {
			view.removeFromSuperview()
		}

		for (viewController, i) in zip(viewControllers, viewControllers.indices) {
			let containerView = UIView()
			containerView.translatesAutoresizingMaskIntoConstraints = false

			addChild(viewController)
			viewController.delegate = self
			viewController.view.frame = containerView.bounds
			viewController.view.autoresizingMask = [ .flexibleWidth, .flexibleHeight ]
			containerView.addSubview(viewController.view)
			stackView.addArrangedSubview(containerView)
			viewController.didMove(toParent: self)

			if i != viewControllers.count - 1 {
				let splitGrabberView = SplitGrabberView(axis: axis)
				splitGrabberView.translatesAutoresizingMaskIntoConstraints = false
				splitGrabberView.delegate = self
				stackView.addArrangedSubview(splitGrabberView)
			}
		}

		if splitPercentages.count != viewControllers.count {
			let split = Double(1) / Double(viewControllers.count)
			splitPercentages = Array(repeating: split, count: viewControllers.count)
		}

		let attribute: NSLayoutConstraint.Attribute
		let otherAttribute: NSLayoutConstraint.Attribute
		switch axis {
		case .horizontal:
			attribute = .width
			otherAttribute = .height
		case .vertical:
			attribute = .height
			otherAttribute = .width
		@unknown default: fatalError()
		}

		NSLayoutConstraint.deactivate(constraints)
		constraints = viewControllers.map { viewController in
			NSLayoutConstraint(item: viewController.view.superview!,
												 attribute: attribute,
												 relatedBy: .equal,
												 toItem: nil,
												 attribute: .notAnAttribute,
												 multiplier: 1,
												 constant: 0)
		}
		NSLayoutConstraint.activate(constraints)
		NSLayoutConstraint.activate(viewControllers.map { viewController in
			NSLayoutConstraint(item: viewController.view.superview!,
												 attribute: otherAttribute,
												 relatedBy: .equal,
												 toItem: stackView,
												 attribute: otherAttribute,
												 multiplier: 1,
												 constant: 0)
		})
	}

	func remove(viewController: UIViewController) {
		guard let viewController = viewController as? BaseTerminalSplitViewControllerChild,
					let index = viewControllers.firstIndex(where: { item in viewController == item }) else {
			return
		}

		viewControllers.remove(at: index)
        viewController.removeFromParent()

		if viewControllers.isEmpty {
			// All view controllers in the split have been removed, so remove ourselves.
			if let parentSplitView = parent as? TerminalSplitViewController {
				parentSplitView.remove(viewController: self)
			} else if let rootViewController = parent as? RootViewController {
				rootViewController.removeTerminal(viewController: self)
			}
		}
		updateViewControllers()
	}

	private func updateConstraints() {
		let totalSpace: CGFloat
		switch axis {
		case .horizontal: totalSpace = stackView.frame.size.width - 10
		case .vertical:   totalSpace = stackView.frame.size.height - 10
		@unknown default: fatalError()
		}

		for (i, constraint) in constraints.enumerated() {
			constraint.constant = totalSpace * CGFloat(splitPercentages[i])
		}
	}

	private func updateIsSplitViewResizing() {
		// A parent split view is resizing. Let our children know.
		for viewController in viewControllers {
			viewController.isSplitViewResizing = isSplitViewResizing
		}
	}

	private func updateShowsTitleView() {
		// A parent split view wants title views. Let our children know.
		for viewController in viewControllers {
			viewController.showsTitleView = showsTitleView
		}
	}

	// MARK: - Keyboard
    private var keyboardToolbarHeight: Double = 0
    public func keyboardToolbarHeightChanged(height: Double) {
        NSLog("NewTermLog: T\(terminalIndex) keyboardToolbarHeightChanged \(height)-\(self.parent?.view.safeAreaInsets.bottom) keyboardVisible=\(keyboardVisible)")
        if UIDevice.current.userInterfaceIdiom == .pad && !keyboardVisible {
            //Floating Keyboard
            let bottomInset = self.parent?.view.safeAreaInsets.bottom ?? 0
            self.additionalSafeAreaInsets.bottom = max(0, height - bottomInset)
            self.keyboardToolbarHeight = height
        }
    }

    @objc func keyboardVisibilityChanged(_ notification: Notification) {
        NSLog("NewTermLog: T\(terminalIndex) keyboardVisibilityChanged \(notification.name.rawValue) visible=\(keyboardVisible) local=\(notification.userInfo?[UIResponder.keyboardIsLocalUserInfoKey] ?? "")  \(notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] ?? "")")
        
        guard let userInfo = notification.userInfo,
              let isLocal = userInfo[UIResponder.keyboardIsLocalUserInfoKey] as? Bool,
              let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let animationDuration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval,
              let curve = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt else {
            return
        }
        //        NSLog("NewTermLog: keyboardVisibilityChanged notification=\(notification)")
        
        // We do this to avoid the scroll indicator from appearing as soon as the terminal appears.
        // We only want to see it after the keyboard has appeared.
        //		if !hasAppeared {
        //			hasAppeared = true
        //			textView.showsVerticalScrollIndicator = true
        //
        //			if let error = failureError {
        //				// Try to handle the error again now that the UI is ready.
        //				didReceiveError(error: error)
        //				failureError = nil
        //			}
        //		}
        
        // We update the safe areas in an animation block to force it to be animated with the exact
        // parameters given to us in the notification.
        func update(bottom: CGFloat) {
            NSLog("NewTermLog: T\(terminalIndex) keyboardVisibilityChanged update bottom=\(bottom) parent=\(self.parent?.view.safeAreaInsets.bottom)")
            if self.additionalSafeAreaInsets.bottom.isEqual(to: bottom) {
                NSLog("NewTermLog: T\(terminalIndex) keyboardVisibilityChanged update ignored")
                return
            }
            
            var options: UIView.AnimationOptions = .beginFromCurrentState
            options.insert(.init(rawValue: curve << 16))

            UIView.animate(withDuration: animationDuration, delay: 0, options: options) {
                self.additionalSafeAreaInsets.bottom = bottom
            }
        }
        
        switch notification.name {
        case UIResponder.keyboardWillShowNotification:
            if !keyboardFrame.size.height.isZero {
                keyboardVisible = true
            }
            if isLocal && keyboardVisible {
                let bottomInset = self.parent?.view.safeAreaInsets.bottom ?? 0
                let bottom = max(0, keyboardFrame.size.height - bottomInset)
                update(bottom: bottom)
            }
            
        case UIResponder.keyboardWillHideNotification:
            if keyboardVisible {
                keyboardVisible = false
                update(bottom: 0)
            }
            
        case UIResponder.keyboardDidHideNotification:
            if keyboardVisible {
                //Dock -> Floating
                keyboardVisible = false
            }
            
        default:
            break
        }
    }
}

extension TerminalSplitViewController: TerminalSplitViewControllerDelegate {

	func terminal(viewController: BaseTerminalSplitViewControllerChild, titleDidChange title: String, isDirty: Bool, hasBell: Bool) {
		guard let index = viewControllers.firstIndex(of: viewController),
					selectedIndex == index else {
			return
		}

		#if targetEnvironment(macCatalyst)
		let newTitle: String
		switch true {
		case hasBell: newTitle = "🔔 \(title)"
		case isDirty: newTitle = "• \(title)"
		default:      newTitle = title
		}
		self.title = newTitle
		#else
		self.title = title
		#endif

		if let parent = parent as? TerminalSplitViewControllerDelegate {
			parent.terminal(viewController: self, titleDidChange: title, isDirty: isDirty, hasBell: hasBell)
		} else if let parent = parent as? BaseTerminalSplitViewControllerChild {
			parent.delegate?.terminal(viewController: self, titleDidChange: title, isDirty: isDirty, hasBell: hasBell)
		}
	}

	func terminal(viewController: BaseTerminalSplitViewControllerChild, screenSizeDidChange screenSize: ScreenSize) {
		guard let index = viewControllers.firstIndex(of: viewController),
					selectedIndex == index else {
			return
		}

		self.screenSize = screenSize

		if let parent = parent as? TerminalSplitViewControllerDelegate {
			parent.terminal(viewController: self, screenSizeDidChange: screenSize)
		} else if let parent = parent as? BaseTerminalSplitViewControllerChild {
			parent.delegate?.terminal(viewController: self, screenSizeDidChange: screenSize)
		}
	}

	func terminalDidBecomeActive(viewController: BaseTerminalSplitViewControllerChild) {
		guard let index = viewControllers.firstIndex(of: viewController) else {
			return
		}

		selectedIndex = index

		if let parent = parent as? TerminalSplitViewControllerDelegate {
			parent.terminalDidBecomeActive(viewController: self)
		} else if let parent = parent as? BaseTerminalSplitViewControllerChild {
			parent.delegate?.terminalDidBecomeActive(viewController: self)
		}
	}

}

extension TerminalSplitViewController: SplitGrabberViewDelegate {

	func splitGrabberViewDidBeginDragging(_ splitGrabberView: SplitGrabberView) {
		oldSplitPercentages = splitPercentages

		for viewController in viewControllers {
			viewController.isSplitViewResizing = true
		}
	}

	func splitGrabberView(_ splitGrabberView: SplitGrabberView, splitDidChange delta: CGFloat) {
		let totalSpace: CGFloat
		switch axis {
		case .horizontal: totalSpace = stackView.frame.size.width
		case .vertical:   totalSpace = stackView.frame.size.height
		@unknown default: fatalError()
		}

		let percentage = Double(delta / totalSpace)
		let firstSplit = max(0.15, min(0.85, oldSplitPercentages[0] + percentage))
		let secondSplit = 1 - firstSplit

		var didSnap = false
		for point in Self.splitSnapPoints {
			if firstSplit > point - 0.02 && firstSplit < point + 0.02 {
				splitPercentages[0] = point
				splitPercentages[1] = 1 - point
				didSnap = true
				break
			}
		}

		if !didSnap {
			splitPercentages[0] = firstSplit
			splitPercentages[1] = secondSplit
		}

		UIView.animate(withDuration: 0.2) {
			self.updateConstraints()
		}
	}

	func splitGrabberViewDidCommit(_ splitGrabberView: SplitGrabberView) {
		oldSplitPercentages.removeAll()

		for viewController in viewControllers {
			viewController.isSplitViewResizing = false
		}
	}

	func splitGrabberViewDidCancel(_ splitGrabberView: SplitGrabberView) {
		splitPercentages = oldSplitPercentages
		updateConstraints()

		for viewController in viewControllers {
			viewController.isSplitViewResizing = false
		}
	}

}
