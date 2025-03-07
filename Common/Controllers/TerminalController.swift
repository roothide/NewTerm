//
//  TerminalController.swift
//  NewTerm
//
//  Created by Adam Demasi on 10/1/18.
//  Copyright © 2018 HASHBANG Productions. All rights reserved.
//

import UIKit
import SwiftUI
import SwiftTerm
import os.log

public protocol TerminalControllerDelegate: AnyObject {
    func refresh(lines: inout [AnyView])
    func refresh(lines: inout [BufferLine], cursor: (Int,Int))
    func scroll(animated: Bool)
	func activateBell()
	func titleDidChange(_ title: String?, isDirty: Bool, hasBell: Bool)
	func currentFileDidChange(_ url: URL?, inWorkingDirectory workingDirectoryURL: URL?)

	func saveFile(url: URL)
	func fileUploadRequested()

	func close()
	func didReceiveError(error: Error)
}

public class TerminalController {

	public weak var delegate: TerminalControllerDelegate?

	public var colorMap: ColorMap {
		get { stringSupplier.colorMap! }
		set { stringSupplier.colorMap = newValue }
	}
	public var fontMetrics: FontMetrics {
		get { stringSupplier.fontMetrics! }
		set { stringSupplier.fontMetrics = newValue }
	}

    internal var terminal: Terminal?
	private var subProcess: SubProcess?
	private var subProcessFailureError: Error?
	public let stringSupplier = StringSupplier()
	private var lines = [AnyView]()

	private var processLaunchDate: Date?
	private var updateTimer: CADisplayLink?
	private var refreshRate: TimeInterval = 60
	private var isTabVisible = true
	private var isWindowVisible = true
	private var isVisible: Bool { isTabVisible && isWindowVisible }
	private var isDirty = false {
		didSet { updateTitle() }
	}
	private var hasBell = false {
		didSet { updateTitle() }
	}
	private var readBuffer = [UTF8Char]()
    private var bufferLock = NSLock()

    internal var terminalQueue = DispatchQueue(label: "ws.hbang.Terminal.terminal-queue")

	public var screenSize: ScreenSize? {
		didSet { updateScreenSize() }
	}
	public var scrollbackLines: Int { terminal?.getTopVisibleRow() ?? 0 }

	private var lastCursorLocation: (x: Int, y: Int) = (-1, -1)
	private var lastBellDate: Date?

	internal var title: String?
	internal var userAndHostname: String?
	internal var user: String?
	internal var hostname: String?
	internal var isLocalhost: Bool { hostname == nil || hostname == ProcessInfo.processInfo.hostName }
	internal var currentWorkingDirectory: URL?
	internal var currentFile: URL?

	internal var iTermIntegrationVersion: String?
	internal var shell: String?

	internal var logger = Logger(subsystem: "ws.hbang.Terminal", category: "TerminalController")

	public init() {
		let options = TerminalOptions(termName: "xterm-256color",
																	scrollback: 10000)
		terminal = Terminal(delegate: self, options: options)

		stringSupplier.terminal = terminal

		NotificationCenter.default.addObserver(self, selector: #selector(self.preferencesUpdated), name: Preferences.didChangeNotification, object: nil)
		preferencesUpdated()

		startUpdateTimer(fps: refreshRate)

		NotificationCenter.default.addObserver(self, selector: #selector(self.appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(self.appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)

		UIDevice.current.isBatteryMonitoringEnabled = true
		NotificationCenter.default.addObserver(self, selector: #selector(self.powerStateChanged), name: UIDevice.batteryStateDidChangeNotification, object: nil)

		if #available(macOS 12, *) {
			NotificationCenter.default.addObserver(self, selector: #selector(self.powerStateChanged), name: .NSProcessInfoPowerStateDidChange, object: nil)
		}
	}

	@objc private func preferencesUpdated() {
		let preferences = Preferences.shared
		stringSupplier.colorMap = preferences.colorMap
		stringSupplier.fontMetrics = preferences.fontMetrics

		powerStateChanged()
        terminalQueue.async {
            self.terminal?.refresh(startRow: 0, endRow: self.terminal?.rows ?? 0)
        }
	}

	@objc private func powerStateChanged() {
		let preferences = Preferences.shared
		if #available(macOS 12, *),
			 ProcessInfo.processInfo.isLowPowerModeEnabled && preferences.reduceRefreshRateInLPM {
			refreshRate = 15
		} else {
			let currentRate = UIDevice.current.batteryState == .unplugged ? preferences.refreshRateOnBattery : preferences.refreshRateOnAC
			refreshRate = TimeInterval(min(currentRate, UIScreen.main.maximumFramesPerSecond))
		}
		if isVisible {
			startUpdateTimer(fps: refreshRate)
		}
	}

	public func windowDidEnterBackground() {
		// Throttle the update timer to save battery. On iPhone, we shouldn’t be visible at all in this
		// case, so throttle right down to once per second so we can maintain the dirty bit.
		startUpdateTimer(fps: UIApplication.shared.supportsMultipleScenes ? 10 : 1)
		isWindowVisible = false
	}

	public func windowWillEnterForeground() {
		// Go back to full speed.
		isWindowVisible = true
		if isVisible {
			startUpdateTimer(fps: refreshRate)
		}
	}

	@objc private func appWillResignActive() {
		stopUpdatingTimer()
		isWindowVisible = false
	}

	@objc private func appDidBecomeActive() {
		startUpdateTimer(fps: refreshRate)
		isWindowVisible = true
	}

	public func terminalWillAppear() {
		// Start updating again.
		startUpdateTimer(fps: refreshRate)
		isTabVisible = true
	}

	public func terminalWillDisappear() {
		// Not visible, so throttle right down to once per second so we can maintain the dirty bit.
		startUpdateTimer(fps: 1)
		isTabVisible = false
	}

	private func startUpdateTimer(fps: TimeInterval) {
		updateTimer?.invalidate()
		updateTimer = CADisplayLink(target: self, selector: #selector(self.updateTimerFired))
		updateTimer?.preferredFramesPerSecond = Int(fps)
		updateTimer?.add(to: .main, forMode: .default)
	}

	private func stopUpdatingTimer() {
		updateTimer?.invalidate()
		updateTimer = nil
	}

	// MARK: - Sub Process

	public func startSubProcess() throws {
		subProcess = SubProcess()
		subProcess!.delegate = self
		processLaunchDate = Date()
		do {
			try subProcess!.start()
		} catch {
			subProcessFailureError = error
			throw error
		}
	}

	public func stopSubProcess() throws {
		try subProcess!.stop()
		stopUpdatingTimer()
	}

	// MARK: - Terminal

	public func readInputStream(_ data: [UTF8Char]) {
        var buflen = 0
        bufferLock.lock()
        self.readBuffer += data
        buflen = self.readBuffer.count
        bufferLock.unlock()
        
        if buflen > 100 {
            terminalQueue.sync {
                //waiting for terminal to process buffer
            }
        }
	}

	private func readInputStream(_ data: Data) {
		readInputStream([UTF8Char](data))
	}

	public func write(_ data: [UTF8Char]) {
		subProcess?.write(data: data)
	}

	public func write(_ data: Data) {
		write([UTF8Char](data))
	}

	@objc private func updateTimerFired() {
		terminalQueue.async {
            var buffer = [UTF8Char]()
            
            self.bufferLock.lock()
			if !self.readBuffer.isEmpty {
                buffer = self.readBuffer
                self.readBuffer.removeAll()
			}
            self.bufferLock.unlock()
            
            if !buffer.isEmpty {
                self.terminal?.feed(byteArray: buffer)
            }

			guard let terminal = self.terminal else {
				return
			}

			let scrollbackRows = terminal.getTopVisibleRow()
			var cursorLocation = terminal.getCursorLocation()
			cursorLocation.y += scrollbackRows

			let updateRange = terminal.getScrollInvariantUpdateRange() ?? (0, 0)
			if updateRange == (0, 0) && cursorLocation == self.lastCursorLocation {
				// Nothing changed, nothing to do.
				return
			}
			terminal.clearUpdateRange()

			let scrollInvariantRows = scrollbackRows + terminal.rows
			self.lastCursorLocation = cursorLocation
            
            var count = scrollInvariantRows
            if scrollbackRows==0 && !terminal.buffers.isAlternateBuffer {
                count = terminal.buffer.y+1
            }

//            self.lines = [AnyView]()
//            for i in 0..<count {
//                self.lines.append(self.stringSupplier.attributedString(forScrollInvariantRow: i))
//            }

            var alllines = [BufferLine]()
            for i in 0..<count {
                let line = terminal.buffer.lines[i]
//                NSLog("NewTermLog: buffer line[\(i)](len=\(line.count)): \(line)")
                alllines.append(line)
            }
            
            NSLog("NewTermLog: scrollbackRows=\(scrollbackRows) terminal.rows=\(terminal.rows) cursorLocation=\(cursorLocation)")
            NSLog("NewTermLog: buffer yBase=\(terminal.buffer.yBase) yDisp=\(terminal.buffer.yDisp) y=\(terminal.buffer.y) linesTop=\(terminal.buffer.linesTop)  scrollTop=\(terminal.buffer.scrollTop) scrollBottom=\(terminal.buffer.scrollBottom)")
            NSLog("NewTermLog: lines count=\(terminal.buffer.lines.count) startIndex=\(terminal.buffer.lines.startIndex) maxLength=\(terminal.buffer.lines.maxLength)")

			DispatchQueue.main.async {
//                self.delegate?.refresh(lines: &self.lines)
                self.delegate?.refresh(lines: &alllines, cursor: cursorLocation)

				if !self.isVisible && !self.isDirty {
					self.isDirty = true
				}
			}
		}
	}

	public func clearTerminal() {
        terminalQueue.async {
            self.terminal?.resetToInitialState()
        }

		// To trigger a redraw, update the screen size, then update it back.
		if let screenSize = screenSize {
			var newScreenSize = screenSize
			newScreenSize.cols -= 1
			self.subProcess?.screenSize = newScreenSize

			DispatchQueue.main.async {
				self.subProcess?.screenSize = screenSize
			}
		}
	}

	private func updateScreenSize() {
        NSLog("NewTermLog: TerminalController.updateScreenSize rows=\(screenSize?.rows) cols=\(screenSize?.cols) self=\(Unmanaged.passUnretained(self).toOpaque())")
//        Thread.callStackSymbols.forEach{NSLog("NewTermLog: callstack=\($0)")}
        
        terminalQueue.async {
            if let screenSize = self.screenSize, let terminal = self.terminal,
               screenSize.cols != terminal.cols || screenSize.rows != terminal.rows {
                
                self.subProcess?.screenSize = screenSize
                
                terminal.resize(cols: Int(screenSize.cols), rows: Int(screenSize.rows))
                
                self.subProcess?.activeProcess()
                
                DispatchQueue.main.async {
                    //                    self.delegate?.scroll()
                }
                NSLog("NewTermLog: TerminalController.updateScreenSize resized rows=\(screenSize.rows) cols=\(screenSize.cols)")
            
                if let error = self.subProcessFailureError {
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.readInputStream(ColorBars.render(screenSize: screenSize, message: message))
                }
            }
		}
	}

	private func updateTitle() {
		var newTitle: String? = nil
		if let title = title,
			 !title.isEmpty {
			newTitle = title
		}
		if let hostname = hostname {
			let user = self.user == NSUserName() ? nil : self.user
			let cleanedHostname = hostname.replacingOccurrences(of: #"\.local$"#, with: "", options: .regularExpression, range: hostname.startIndex..<hostname.endIndex)
			let hostString: String
			if isLocalhost {
				hostString = user ?? ""
			} else {
				hostString = "\(user ?? "")\(user == nil ? "" : "@")\(cleanedHostname)"
			}
			if !hostString.isEmpty {
				newTitle = "[\(hostString)] \(newTitle ?? "")"
			}
		}
		self.delegate?.titleDidChange(newTitle,
																	isDirty: isDirty,
																	hasBell: hasBell)
	}

	// MARK: - Object lifecycle

	deinit {
		updateTimer?.invalidate()
	}

}

extension TerminalController: TerminalDelegate {

	public func isProcessTrusted(source: Terminal) -> Bool { isLocalhost }

	public func send(source: Terminal, data: ArraySlice<UInt8>) {
		terminalQueue.async {
			self.write([UTF8Char](data))
		}
	}

	public func bell(source: Terminal) {
		DispatchQueue.main.async {
			// Throttle bell so it only rings a maximum of once a second.
			if self.lastBellDate == nil || self.lastBellDate! < Date(timeIntervalSinceNow: -1) {
				self.lastBellDate = Date()
				self.delegate?.activateBell()
			}

			if !self.isVisible && !self.hasBell {
				self.hasBell = true
			}
		}
	}

	public func showCursor(source: Terminal) {
		stringSupplier.cursorVisible = true
	}

	public func hideCursor(source: Terminal) {
		stringSupplier.cursorVisible = false
	}

	public func setTerminalTitle(source: Terminal, title: String) {
		self.title = title
		DispatchQueue.main.async {
			self.updateTitle()
		}
	}

	public func hostCurrentDirectoryUpdated(source: Terminal) {
		hostCurrentDocumentUpdated(source: source)
	}

	public func hostCurrentDocumentUpdated(source: Terminal) {
		let workingDirectory = source.hostCurrentDirectory
		let filePath = source.hostCurrentDocument ?? workingDirectory
		currentWorkingDirectory = nil
		currentFile = nil

		if let workingDirectory = workingDirectory,
			 let url = URL(string: workingDirectory),
			 url.isFileURL {
			hostname = url.host
			if isLocalhost {
				currentWorkingDirectory = url
			}
		}

		if let filePath = filePath,
			 let url = URL(string: filePath),
			 url.isFileURL {
			hostname = url.host
			if isLocalhost {
				currentFile = url
			}
		}

		DispatchQueue.main.async {
			self.delegate?.currentFileDidChange(self.currentFile ?? self.currentWorkingDirectory,
																					inWorkingDirectory: self.currentWorkingDirectory)
		}
	}

}

extension TerminalController: TerminalInputProtocol {

	public var applicationCursor: Bool { terminal?.applicationCursor ?? false }

	public func receiveKeyboardInput(data: [UTF8Char]) {
		// Forward the data from the keyboard directly to the subprocess
		subProcess!.write(data: data)
	}
    
    public func getAllText() -> String? {
        guard let terminal = self.terminal else { return nil }
        let start = Position(col: 0, row: 0)
        let end = Position(col: terminal.cols, row: terminal.buffer.lines.count)
        return terminal.getText(start: start, end: end)
    }
}

extension TerminalController: SubProcessDelegate {

	func subProcessDidConnect() {
		// Yay
	}

	func subProcess(didReceiveData data: [UTF8Char]) {
		// Simply forward the input stream down the VT100 processor. When it notices changes to the
		// screen, it should invoke our refresh delegate below.
		readInputStream(data)
	}

	func subProcess(didDisconnectWithError error: Error?) {
		if let error = error {
			delegate?.didReceiveError(error: error)
		} else {
			// This can be the user just typing an EOF (^D) to end the terminal session. However, it
			// can also happen because the process crashed for some reason. If it seems like the shell
			// exited gracefully, just close the tab.
			if (processLaunchDate ?? Date()) < Date(timeIntervalSinceNow: -3) {
				delegate?.close()
			}
		}

		// Write the termination message to the terminal.
		let processCompleted = String.localize("PROCESS_COMPLETED_TITLE", comment: "Title displayed when the terminal’s process has ended.")
		let cols = Int(subProcess?.screenSize.cols ?? 0)
		let messageLength = processCompleted.count + 2
		let divider = String(repeating: "═", count: max((cols - messageLength) / 2, 0))
		let message = "\r\n\u{1b}[0;31m\(divider) \u{1b}[1;31m\(processCompleted)\u{1b}[0;31m \(divider)\u{1b}[m\r\n"
		readInputStream(message.data(using: .utf8)!)

		updateTimer?.invalidate()
		updateTimer = nil
		updateTimerFired()
	}

	func subProcess(didReceiveError error: Error) {
		delegate?.didReceiveError(error: error)
	}

}
