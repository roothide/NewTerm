//
//  KeyboardToolbarInputView.swift
//  NewTerm
//
//  Created by Adam Demasi on 10/1/18.
//  Copyright © 2018 HASHBANG Productions. All rights reserved.
//

import UIKit
import SwiftUIX

class KeyboardToolbarInputView: UIInputView {

	private var hostingView: UIHostingView<AnyView>!
    private var delegate: KeyboardToolbarViewDelegate!

	init(delegate: KeyboardToolbarViewDelegate?, toolbars: [Toolbar], state: KeyboardToolbarViewState) {
		super.init(frame: .zero, inputViewStyle: .keyboard)
        self.delegate = delegate
        
        setContentHuggingPriority(.fittingSizeLevel, for: .vertical)
        setContentCompressionResistancePriority(.fittingSizeLevel, for: .vertical)
		translatesAutoresizingMaskIntoConstraints = false
		allowsSelfSizing = true

		hostingView = UIHostingView(rootView: AnyView(
			KeyboardToolbarView(delegate: delegate, toolbars: toolbars)
				.environmentObject(state)
		))
//        hostingView = UIHostingView(rootView: AnyView(
//            KeyboardToolbarViewTest()
//        ))
		hostingView.translatesAutoresizingMaskIntoConstraints = false
		hostingView.shouldResizeToFitContent = true
        hostingView.setContentHuggingPriority(.fittingSizeLevel, for: .vertical)
        hostingView.setContentCompressionResistancePriority(.fittingSizeLevel, for: .vertical)
		addSubview(hostingView)

		NSLayoutConstraint.activate([
			hostingView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
			hostingView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
			hostingView.topAnchor.constraint(equalTo: self.topAnchor),
			hostingView.bottomAnchor.constraint(equalTo: self.bottomAnchor)
		])
	}
    
    override func layoutSubviews() {
        super.layoutSubviews()
        delegate?.keyboardToolbarDidChangeHeight(height: self.frame.size.height)
        NSLog("NewTermLog: KeyboardToolbarInputView.layoutSubviews frame=\(self.frame) safeArea=\(self.safeAreaInsets)\n\nhostview=\(hostingView.frame) hvcview=\(hostingView.get_rootViewHostingController?.view.frame) safeArea=\(hostingView.get_rootViewHostingController?.view.safeAreaInsets)")
    }

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

}

extension KeyboardToolbarInputView: UIInputViewAudioFeedback {
	var enableInputClicksWhenVisible: Bool {
		// Conforming to <UIInputViewAudioFeedback> allows the buttons to make the click sound
		// when tapped
		true
	}
}
