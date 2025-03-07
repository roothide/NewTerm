//
//  TerminalSessionViewController.swift
//  NewTerm
//
//  Created by Adam Demasi on 10/1/18.
//  Copyright © 2018 HASHBANG Productions. All rights reserved.
//

import UIKit
import os.log
import CoreServices
import SwiftUIX
import SwiftTerm
import NewTermCommon

class TerminalSessionViewController: BaseTerminalSplitViewControllerChild {

    var keyboardToolbarHeightChanged: ((Double) -> Void)?

	var initialCommand: String?

	override var isSplitViewResizing: Bool {
		didSet { updateIsSplitViewResizing() }
	}
	override var showsTitleView: Bool {
		didSet { updateShowsTitleView() }
	}
	override var screenSize: ScreenSize? {
		get { terminalController.screenSize }
		set { terminalController.screenSize = newValue }
	}

	private var terminalController = TerminalController()
	private var keyInput = TerminalKeyInput(frame: .zero)
    private var textView: UIView!
    private var tableView: UITableView!
	private var textViewTapGestureRecognizer: UITapGestureRecognizer!
    
	private var state = TerminalState()
    private var lines = [BufferLine]()
    private var cursor = (x:Int(-1), y:Int(-1))

	private var hudState = HUDViewState()
	private var hudView: UIHostingView<AnyView>!

	private var hasAppeared = false
	private var hasStarted = false
	private var failureError: Error?

	private var lastAutomaticScrollOffset = CGPoint.zero
	private var invertScrollToTop = false

	private var isPickingFileForUpload = false

	override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
		super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)

		terminalController.delegate = self

		do {
			try terminalController.startSubProcess()
			hasStarted = true
		} catch {
			failureError = error
		}
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func loadView() {
		super.loadView()

		title = .localize("TERMINAL", comment: "Generic title displayed before the terminal sets a proper title.")

		preferencesUpdated()
        
        tableView = UITableView()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.separatorInset = .zero
        tableView.backgroundColor = .clear
        
//        textView = TerminalHostingView(state: state)
        textView = tableView

		textViewTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.handleTextViewTap(_:)))
		textViewTapGestureRecognizer.delegate = self
		textView.addGestureRecognizer(textViewTapGestureRecognizer)

		keyInput.frame = view.bounds
		keyInput.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		keyInput.textView = textView
        keyInput.keyboardToolbarHeightChanged = { height in
            self.keyboardToolbarHeightChanged?(height)
        }
		keyInput.terminalInputDelegate = terminalController
		view.addSubview(keyInput)
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		hudView = UIHostingView(rootView: AnyView(
			HUDView()
				.environmentObject(self.hudState)
		))
		hudView.translatesAutoresizingMaskIntoConstraints = false
		hudView.shouldResizeToFitContent = true
		hudView.setContentHuggingPriority(.fittingSizeLevel, for: .horizontal)
		hudView.setContentHuggingPriority(.fittingSizeLevel, for: .vertical)
		view.addSubview(hudView)

		NSLayoutConstraint.activate([
			hudView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
			hudView.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor)
		])

		addKeyCommand(UIKeyCommand(title: .localize("CLEAR_TERMINAL", comment: "VoiceOver label for a button that clears the terminal."),
															 image: UIImage(systemName: "text.badge.xmark"),
															 action: #selector(self.clearTerminal),
															 input: "k",
															 modifierFlags: .command))

		#if !targetEnvironment(macCatalyst)
		addKeyCommand(UIKeyCommand(title: .localize("PASSWORD_MANAGER", comment: "VoiceOver label for the password manager button."),
															 image: UIImage(systemName: "key.fill"),
															 action: #selector(self.activatePasswordManager),
															 input: "f",
															 modifierFlags: [ .command ]))
		#endif

		if UIApplication.shared.supportsMultipleScenes {
			NotificationCenter.default.addObserver(self, selector: #selector(self.sceneDidEnterBackground), name: UIWindowScene.didEnterBackgroundNotification, object: nil)
			NotificationCenter.default.addObserver(self, selector: #selector(self.sceneWillEnterForeground), name: UIWindowScene.willEnterForegroundNotification, object: nil)
		}

		NotificationCenter.default.addObserver(self, selector: #selector(self.preferencesUpdated), name: Preferences.didChangeNotification, object: nil)
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		keyInput.becomeFirstResponder()
		terminalController.terminalWillAppear()
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)

		hasAppeared = true

		if let error = failureError {
			didReceiveError(error: error)
		} else {
			if let initialCommand = initialCommand?.data(using: .utf8) {
				terminalController.write(initialCommand + EscapeSequences.return)
			}
		}

		initialCommand = nil
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)

		keyInput.resignFirstResponder()
		terminalController.terminalWillDisappear()
	}

	override func viewDidDisappear(_ animated: Bool) {
		super.viewDidDisappear(animated)

		hasAppeared = false
	}
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        NSLog("NewTermLog: viewWillTransition to \(size)")
        super.viewWillTransition(to: size, with: coordinator)
        if UIDevice.current.userInterfaceIdiom == .pad {
            if keyInput.isFirstResponder {
                //reload keyboardToolbar
                keyInput.resignFirstResponder()
            }
        }
    }
    
	override func viewWillLayoutSubviews() {
        NSLog("NewTermLog: TerminalSessionViewController.viewWillLayoutSubviews \(self.view.frame) \(self.view.safeAreaInsets)")
		super.viewWillLayoutSubviews()
		updateScreenSize()
	}
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        NSLog("NewTermLog: TerminalSessionViewController.viewDidLayoutSubviews \(self.view.frame) \(self.view.safeAreaInsets)")
        NSLog("NewTermLog: textView frame=\(self.textView.frame) safeArea=\(self.textView.safeAreaInsets)")
//        updateScreenSize()
    }

	override func viewSafeAreaInsetsDidChange() {
        NSLog("NewTermLog: TerminalSessionViewController.viewSafeAreaInsetsDidChange \(self.view.frame) \(view.safeAreaInsets)")
		super.viewSafeAreaInsetsDidChange()
//		updateScreenSize()
	}

	override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        NSLog("NewTermLog: TerminalSessionViewController.traitCollectionDidChange \(self.view.frame) \(view.safeAreaInsets)")
		super.traitCollectionDidChange(previousTraitCollection)
//		updateScreenSize()
	}

	override func removeFromParent() {
		if hasStarted {
			do {
				try terminalController.stopSubProcess()
			} catch {
				Logger().error("Failed to stop subprocess: \(String(describing: error))")
			}
		}

		super.removeFromParent()
	}

	// MARK: - Screen

	func updateScreenSize() {
		if isSplitViewResizing {
			return
		}

		// Determine the screen size based on the font size
        var layoutSize = self.view.safeAreaLayoutGuide.layoutFrame.size
		layoutSize.width -= TerminalView.horizontalSpacing * 2
		layoutSize.height -= TerminalView.verticalSpacing * 2

		if layoutSize.width <= 0 || layoutSize.height <= 0 {
			// Not laid out yet. We’ll be called again when we are.
			return
		}
        
        let layoutFrame1 = self.view.safeAreaLayoutGuide.layoutFrame
        if layoutFrame1.origin.x < 0 || layoutFrame1.origin.y < 0 {
            //in layouting
            return
        }
        let layoutFrame2 = self.textView.safeAreaLayoutGuide.layoutFrame
        if layoutFrame2.origin.x < 0 || layoutFrame2.origin.y < 0 {
            //in layouting
            return
        }

		let glyphSize = terminalController.fontMetrics.boundingBox
		if glyphSize.width == 0 || glyphSize.height == 0 {
			fatalError("Failed to get glyph size")
		}
        
        NSLog("NewTermLog: TerminalSessionViewController.updateScreenSize self=\(self.view.safeAreaLayoutGuide.layoutFrame) textView=\(textView.safeAreaLayoutGuide.layoutFrame)")
		let newSize = ScreenSize(cols: UInt16(layoutSize.width / glyphSize.width),
														 rows: UInt16(layoutSize.height / glyphSize.height.rounded(.up)),
														 cellSize: glyphSize)
		if screenSize != newSize {
			screenSize = newSize
			delegate?.terminal(viewController: self, screenSizeDidChange: newSize)
		}
        else {
            //when layout size changes, always scroll even if rows/columns don't change
            self.scroll(animated: true)
        }
	}

	@objc func clearTerminal() {
		terminalController.clearTerminal()
	}

	private func updateIsSplitViewResizing() {
        NSLog("NewTermLog: TerminalSessionViewController.updateIsSplitViewResizing")
		state.isSplitViewResizing = isSplitViewResizing

		if !isSplitViewResizing {
			updateScreenSize()
		}
	}

	private func updateShowsTitleView() {
        NSLog("NewTermLog: TerminalSessionViewController.updateShowsTitleView")
		updateScreenSize()
	}

	// MARK: - Gestures

	@objc private func handleTextViewTap(_ gestureRecognizer: UITapGestureRecognizer) {
		if gestureRecognizer.state == .ended && !keyInput.isFirstResponder {
			keyInput.becomeFirstResponder()
			delegate?.terminalDidBecomeActive(viewController: self)
		}
	}

	// MARK: - Lifecycle

	@objc private func sceneDidEnterBackground(_ notification: Notification) {
		if notification.object as? UIWindowScene == view.window?.windowScene {
			terminalController.windowDidEnterBackground()
		}
	}

	@objc private func sceneWillEnterForeground(_ notification: Notification) {
		if notification.object as? UIWindowScene == view.window?.windowScene {
			terminalController.windowWillEnterForeground()
		}
	}

	@objc private func preferencesUpdated() {
		state.fontMetrics = terminalController.fontMetrics
		state.colorMap = terminalController.colorMap
	}
}

extension TerminalSessionViewController: TerminalControllerDelegate {

    func refresh(lines: inout [AnyView]) {
        state.lines = lines
        self.scroll()
    }
    
    func refresh(lines: inout [BufferLine], cursor: (Int,Int)) {
        NSLog("NewTermLog: refresh lines=\(lines.count)")
        self.lines = lines
        self.cursor = cursor
        self.tableView.reloadData()
        self.scroll()
	}
    
    func scroll(animated: Bool = false) {
        state.scroll += 1
        
        let lastRow = self.tableView.numberOfRows(inSection: 0) - 1
        if lastRow >= 0 {
            let indexPath = IndexPath(row: lastRow, section: 0)
            self.tableView.scrollToRow(at: indexPath, at: .bottom, animated: false)
            NSLog("NewTermLog: scrollToRow \(indexPath)")
        }
    }

	func activateBell() {
		if Preferences.shared.bellHUD {
			hudState.isVisible = true
		}

		HapticController.playBell()
	}

	func titleDidChange(_ title: String?, isDirty: Bool, hasBell: Bool) {
		let newTitle = title ?? .localize("TERMINAL", comment: "Generic title displayed before the terminal sets a proper title.")
		delegate?.terminal(viewController: self,
											 titleDidChange: newTitle,
											 isDirty: isDirty,
											 hasBell: hasBell)
	}

	func currentFileDidChange(_ url: URL?, inWorkingDirectory workingDirectoryURL: URL?) {
		#if targetEnvironment(macCatalyst)
		if let windowScene = view.window?.windowScene {
			windowScene.titlebar?.representedURL = url
		}
		#endif
	}

	func saveFile(url: URL) {
		let viewController = UIDocumentPickerViewController(forExporting: [url], asCopy: false)
		viewController.delegate = self
		present(viewController, animated: true, completion: nil)
	}

	func fileUploadRequested() {
		isPickingFileForUpload = true

		let viewController = UIDocumentPickerViewController(forOpeningContentTypes: [.data, .directory])
		viewController.delegate = self
		present(viewController, animated: true, completion: nil)
	}

	@objc func activatePasswordManager() {
		keyInput.activatePasswordManager()
	}

	@objc func close() {
		if let splitViewController = parent as? TerminalSplitViewController {
			splitViewController.remove(viewController: self)
		}
	}

	func didReceiveError(error: Error) {
		if !hasAppeared {
			failureError = error
			return
		}
		failureError = nil

		let alertController = UIAlertController(title: .localize("TERMINAL_LAUNCH_FAILED_TITLE", comment: "Alert title displayed when a terminal could not be launched."),
																						message: .localize("TERMINAL_LAUNCH_FAILED_BODY", comment: "Alert body displayed when a terminal could not be launched."),
																						preferredStyle: .alert)
		alertController.addAction(UIAlertAction(title: .ok, style: .cancel, handler: nil))
		present(alertController, animated: true, completion: nil)
	}

}

extension TerminalSessionViewController: UIGestureRecognizerDelegate {

	func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
		// This allows the tap-to-activate-keyboard gesture to work without conflicting with UIKit’s
		// internal text view/scroll view gestures… as much as we can avoid conflicting, at least.
		return gestureRecognizer == textViewTapGestureRecognizer
			&& (!(otherGestureRecognizer is UITapGestureRecognizer) || keyInput.isFirstResponder)
	}
}

extension TerminalSessionViewController: UIDocumentPickerDelegate {

	func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
		guard isPickingFileForUpload,
					let url = urls.first else {
			return
		}
		terminalController.uploadFile(url: url)
		isPickingFileForUpload = false
	}

	func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
		if isPickingFileForUpload {
			isPickingFileForUpload = false
			terminalController.cancelUploadRequest()
		} else {
			// The system will clean up the temp directory for us eventually anyway, but still delete the
			// downloads temp directory now so the file doesn’t linger around till then.
			terminalController.deleteDownloadCache()
		}
	}

}

class SwiftUITableViewCell: UITableViewCell {
    func configure(with view: AnyView) {
        let hostingView = UIHostingView(rootView: view)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
//            hostingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: contentView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        
        self.backgroundColor = .clear
        contentView.backgroundColor = .clear
        hostingView.backgroundColor = .clear
    }
}

extension TerminalSessionViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        return nil
    }
}

extension TerminalSessionViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        self.lines.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = SwiftUITableViewCell()
        let line = self.lines[indexPath.row]
        let view = terminalController.stringSupplier.attributedString(line: line, cursorX: indexPath.row==cursor.y ? cursor.x : -1)
        cell.configure(with: view)
        return cell
    }
    
}
