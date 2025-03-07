//
//  TerminalView.swift
//  NewTerm (iOS)
//
//  Created by Adam Demasi on 5/4/2022.
//

import SwiftUI
import SwiftUIX
import SwiftTerm
import NewTermCommon

class TerminalState: ObservableObject {
    @Published var scroll = 0
	@Published var lines = [AnyView]()
	@Published var fontMetrics = FontMetrics(font: AppFont(), fontSize: 12)
	@Published var colorMap = ColorMap(theme: AppTheme())
	@Published var isSplitViewResizing = false
}

struct TerminalView: View {
	static let horizontalSpacing: CGFloat = isBigDevice ? 3 : 0
	static let verticalSpacing: CGFloat = isBigDevice ? 2 : 0

	@EnvironmentObject private var state: TerminalState

	var body: some View {
		let view = ScrollViewReader { scrollView in
			ScrollView(.vertical, showsIndicators: true) {
				LazyVStack(alignment: .leading, spacing: 0) {
					ForEach(Array(zip(state.lines, state.lines.indices)), id: \.1) { line, i in
						line
							.drawingGroup(opaque: true)
							.id(i)
					}
				}
                .padding(.vertical, Self.verticalSpacing)
                .padding(.horizontal, Self.horizontalSpacing)
                .background(Color(state.colorMap.background))
			}
            .background(Color(state.colorMap.background))
            .onChange(of: state.scroll, perform: { _ in
                NSLog("NewTermLog: scrollTo \(state.lines.indices.last)")
                scrollView.scrollTo(state.lines.indices.last, anchor: .bottom)
            })
		}
        .opacity(state.isSplitViewResizing ? 0.6 : 1)
        .animation(.linear(duration: 0.1), value: state.isSplitViewResizing)

        if #available(iOS 16, *) {
            view.accessibilityTextContentType(.console).scrollDismissesKeyboard(.interactively)
        } else if #available(iOS 15, *) {
            view.accessibilityTextContentType(.console)
		} else {
            view
		}
	}
}

class TerminalHostingView: UIHostingView<AnyView> {
	init(state: TerminalState) {
		let view = TerminalView()
			.environmentObject(state)
		super.init(rootView: AnyView(view))
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	required init(rootView: AnyView) {
		fatalError("init(rootView:) has not been implemented")
	}
}

struct TerminalSampleView: View {
	private class TerminalSampleViewDelegate: NSObject, TerminalDelegate {
		func send(source: Terminal, data: ArraySlice<UInt8>) {}
	}

	@State var fontMetrics: FontMetrics
	@State var colorMap: ColorMap

	private var terminal: Terminal!
	private let stringSupplier = StringSupplier()
	private let delegate = TerminalSampleViewDelegate()
	private let state = TerminalState()

	init(fontMetrics: FontMetrics = FontMetrics(font: AppFont(), fontSize: 12),
			 colorMap: ColorMap = ColorMap(theme: AppTheme())) {
        NSLog("NewTermLog: TerminalSampleView.init \(fontMetrics) \(colorMap)")
		self.fontMetrics = fontMetrics
		self.colorMap = colorMap
        state.colorMap = colorMap
        state.fontMetrics = fontMetrics
        stringSupplier.colorMap = colorMap
        stringSupplier.fontMetrics = fontMetrics

		let options = TerminalOptions(cols: 80,
																	rows: 25,
																	termName: "xterm-256color",
																	scrollback: 100)
		terminal = Terminal(delegate: delegate, options: options)
		stringSupplier.terminal = terminal

		if let colorTest = try? Data(contentsOf: Bundle.main.url(forResource: "colortest", withExtension: "txt")!) {
			terminal?.feed(byteArray: [UTF8Char](colorTest))
		}

        state.lines = Array(0...(terminal.rows + terminal.getTopVisibleRow())).map { stringSupplier.attributedString(forScrollInvariantRow: $0) }
	}

	var body: some View {
		TerminalView()
			.environmentObject(state)
            .onChange(of: colorMap, perform: {
                NSLog("NewTermLog: new colorMap=\($0)")
                state.colorMap = colorMap
                stringSupplier.colorMap = $0 })
			.onChange(of: fontMetrics, perform: {
                NSLog("NewTermLog: new fontMetrics=\($0)")
                state.fontMetrics = fontMetrics
                stringSupplier.fontMetrics = $0 })
			.onChangeOfFrame(perform: { size in
				// Determine the screen size based on the font size
				// TODO: Calculate the exact number of lines we need from the buffer
				let glyphSize = stringSupplier.fontMetrics?.boundingBox ?? .zero
				terminal.resize(cols: Int(size.width / glyphSize.width),
												rows: 32)
			})
	}
}

struct TerminalView_Previews: PreviewProvider {
	static var previews: some View {
		TerminalSampleView()
			.preferredColorScheme(.dark)
	}
}
