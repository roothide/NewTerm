//
//  Preferences.swift
//  NewTerm
//
//  Created by Adam Demasi on 10/1/18.
//  Copyright © 2018 HASHBANG Productions. All rights reserved.
//

import UIKit
import SwiftUI
import Combine
import os.log

public enum KeyboardButtonStyle: Int {
	case text, icons
}

public enum KeyboardTrackpadSensitivity: Int, CaseIterable {
	case off, low, medium, high
}

public enum KeyboardArrowsStyle: Int, CaseIterable {
	case butterfly, scissor, classic, vim, vimInverted
}

public enum PreferencesSyncService: Int, Identifiable {
	case none, icloud, folder

	public var id: Self { self }
}

public class Preferences: NSObject, ObservableObject {

	public static let didChangeNotification = Notification.Name(rawValue: "NewTermPreferencesDidChangeNotification")
    
    private func onChanged() {
        NotificationCenter.default.post(name: Preferences.didChangeNotification, object: nil)
    }

	public static let shared = Preferences()

	@Published public private(set) var fontMetrics = FontMetrics(font: AppFont(), fontSize: 12) {
		willSet { objectWillChange.send() }
	}
	@Published public private(set) var colorMap = ColorMap(theme: AppTheme()) {
		willSet { objectWillChange.send() }
	}

	override init() {
		super.init()

		if let version = Bundle.main.infoDictionary!["CFBundleVersion"] as? String {
			lastVersion = Int(version) ?? 0
		}

		fontMetricsChanged()
		colorMapChanged()
	}

	@AppStorage("fontName") private var _fontName: String = "SF Mono"
	public var fontName: String {
        get { return _fontName }
        set { objectWillChange.send(); _fontName=newValue; fontMetricsChanged(); onChanged() }
	}

	// TODO: Public just for testing, make it private later
	@AppStorage("fontSizePhone")
	private var fontSizePhone: Double = 12

	@AppStorage("fontSizePad")
	private var fontSizePad: Double = 13

	@AppStorage("fontSizeMac")
    private var fontSizeMac: Double = 13

	// TODO: Make this act like a DynamicProperty
    public var fontSize: Double {
		get {
			#if targetEnvironment(macCatalyst)
			return fontSizeMac
			#else
			return isBigDevice ? fontSizePad : fontSizePhone
			#endif
		}
		set {
            objectWillChange.send();
			#if targetEnvironment(macCatalyst)
			fontSizeMac = newValue
			#else
			if isBigDevice {
				fontSizePad = newValue
			} else {
				fontSizePhone = newValue
			}
			#endif
            fontMetricsChanged()
            onChanged()
		}
	}

	@AppStorage("themeName") private var _themeName: String = "Basic (Dark)"
	public var themeName: String {
		get { return _themeName }
        set { objectWillChange.send(); _themeName=newValue; colorMapChanged(); onChanged() }
	}

	@AppStorage("keyboardAccessoryStyle") private var _keyboardAccessoryStyle: KeyboardButtonStyle = .text
	public var keyboardAccessoryStyle: KeyboardButtonStyle {
        get { return _keyboardAccessoryStyle }
        set { objectWillChange.send(); _keyboardAccessoryStyle=newValue; onChanged() }
	}

	@AppStorage("keyboardTrackpadSensitivity") private var _keyboardTrackpadSensitivity: KeyboardTrackpadSensitivity = .medium
	public var keyboardTrackpadSensitivity: KeyboardTrackpadSensitivity {
        get { return _keyboardTrackpadSensitivity }
        set { objectWillChange.send(); _keyboardTrackpadSensitivity=newValue; onChanged() }
    }

    @AppStorage("keyboardArrowsStyle") private var _keyboardArrowsStyle: KeyboardArrowsStyle = isBigDevice ? .classic : (isSmallDevice ? .scissor : .butterfly)
	public var keyboardArrowsStyle: KeyboardArrowsStyle {
        get { return _keyboardArrowsStyle }
        set { objectWillChange.send(); _keyboardArrowsStyle=newValue; onChanged() }
	}

	@AppStorage("bellHUD") private var _bellHUD: Bool = true
	public var bellHUD: Bool {
        get { return _bellHUD }
        set { objectWillChange.send(); _bellHUD=newValue; onChanged() }
    }

	@AppStorage("bellVibrate") private var _bellVibrate: Bool = true
	public var bellVibrate: Bool {
        get { return _bellVibrate }
        set { objectWillChange.send(); _bellVibrate=newValue; onChanged() }
    }

	@AppStorage("bellSound") private var _bellSound: Bool = true
	public var bellSound: Bool {
        get { return _bellSound }
        set { objectWillChange.send(); _bellSound=newValue; onChanged() }
	}

	@AppStorage("refreshRateOnAC") private var _refreshRateOnAC: Int = 60
	public var refreshRateOnAC: Int {
        get { return _refreshRateOnAC }
        set { objectWillChange.send(); _refreshRateOnAC=newValue; onChanged() }
	}

	@AppStorage("refreshRateOnBattery") var _refreshRateOnBattery: Int = 60
	public var refreshRateOnBattery: Int {
        get { return _refreshRateOnBattery }
        set { objectWillChange.send(); _refreshRateOnBattery=newValue; onChanged() }
	}

	@AppStorage("reduceRefreshRateInLPM") private var _reduceRefreshRateInLPM: Bool = true
	public var reduceRefreshRateInLPM: Bool {
        get { return _reduceRefreshRateInLPM }
        set { objectWillChange.send(); _reduceRefreshRateInLPM=newValue; onChanged() }
	}

	@AppStorage("preferencesSyncService") private var _preferencesSyncService: PreferencesSyncService = .icloud
	public var preferencesSyncService: PreferencesSyncService {
        get { return _preferencesSyncService }
        set { objectWillChange.send(); _preferencesSyncService=newValue; onChanged() }
	}

	@AppStorage("preferencesSyncPath") private var _preferencesSyncPath: String = ""
	public var preferencesSyncPath: String {
        get { return _preferencesSyncPath }
        set { objectWillChange.send(); _preferencesSyncPath=newValue; onChanged() }
	}

	@AppStorage("preferredLocale") private var _preferredLocale: String = ""
	public var preferredLocale: String {
        get { return _preferredLocale }
        set { objectWillChange.send(); _preferredLocale=newValue; onChanged() }
	}

	@AppStorage("lastVersion") private var _lastVersion: Int = 0
	public var lastVersion: Int {
        get { return _lastVersion }
        set { objectWillChange.send(); _lastVersion=newValue; onChanged() }
	}

	public var userInterfaceStyle: UIUserInterfaceStyle { colorMap.userInterfaceStyle }

	// MARK: - Handlers

	private func fontMetricsChanged() {
		let font = AppFont.predefined[fontName] ?? AppFont()
		fontMetrics = FontMetrics(font: font, fontSize: CGFloat(fontSize))
        NSLog("NewTermLog: fontMetricsChanged -> size=\(fontSize) name=\(fontName) : \(AppFont.predefined[fontName])")
	}

	private func colorMapChanged() {
		let theme = AppTheme.predefined[themeName] ?? AppTheme()
		colorMap = ColorMap(theme: theme)
        NSLog("NewTermLog: colorMapChanged -> \(colorMap)")
	}

}

