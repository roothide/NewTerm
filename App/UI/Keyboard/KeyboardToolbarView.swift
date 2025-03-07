//
//  KeyboardToolbarView.swift
//  NewTerm (iOS)
//
//  Created by Chris Harper on 11/21/21.
//

import SwiftUI
import NewTermCommon
import SwiftUIX

fileprivate struct Key {
	var label: String
	var glyph: String?
	var imageName: SFSymbolName?
	var preferredStyle: KeyboardButtonStyle?
	var isToggle = false
	var halfHeight = false
    var widthRatio: CGFloat?
    var heightRatio: CGFloat?
    var minWidth: CGFloat?
	var keyRepeat: Bool?
}

enum Toolbar: CaseIterable {
	case primary, padPrimaryLeading, padPrimaryTrailing
	case secondary, fnKeys

	var keys: [ToolbarKey] {
		switch self {
		case .primary:
			return [
                .control, .escape, .tab, .Delete, //.more,
				.variableSpace(id: 0),
				.arrows
			]

		case .padPrimaryLeading:
			return [.control, .escape, .tab, .more]

		case .padPrimaryTrailing:
			return [.arrows]

		case .secondary:
			return [
				.home, .end,
				.variableSpace(id: 0),
				.pageUp, .pageDown,
				.variableSpace(id: 1),
				.delete,
				.variableSpace(id: 2),
				.fnKeys
			]

		case .fnKeys:
			return Array(1...12).map { .fnKey(index: $0) }
		}
	}
}

enum ToolbarKey: Hashable {
	// Special
	case fixedSpace(id: Int)
	case variableSpace(id: Int)
	case arrows
	// Primary - leading
	case control, escape, tab, more, Delete
	// Primary - trailing
	case up, down, left, right
	// Secondary - navigation
	case home, end, pageUp, pageDown
	// Secondary - extras
	case delete, fnKeys
	// Fn keys
	case fnKey(index: Int)

	fileprivate var key: Key {
		switch self {
		// Special
		case .fixedSpace, .variableSpace, .arrows:
			return Key(label: "")

		// Primary - leading
		case .control:  return Key(label: .localize("Control"),
															 glyph: .localize("Ctrl"),
															 imageName: .control,
															 isToggle: true)
		case .escape:   return Key(label: .localize("Escape"),
															 glyph: .localize("Esc"),
															 imageName: .escape)
		case .tab:      return Key(label: .localize("Tab"),
															 imageName: .arrowRightToLine)
		case .more:     return Key(label: .localize("More"),
															 imageName: .ellipsis,
															 preferredStyle: .icons,
															 isToggle: true)
            
        case .Delete:   return Key(label: .localize("Delete Forward"),
                                                                 glyph: .localize("Del"),
                                                                 imageName: .deleteRight,
                                                                 preferredStyle: .icons)
		// Primary - trailing
		case .up:       return Key(label: .localize("Up"),
															 imageName: .arrowUp,
															 preferredStyle: .icons,
															 widthRatio: 1, minWidth: 25)
		case .down:     return Key(label: .localize("Down"),
															 imageName: .arrowDown,
															 preferredStyle: .icons,
															 widthRatio: 1, minWidth: 25)
		case .left:     return Key(label: .localize("Left"),
															 imageName: .arrowLeft,
															 preferredStyle: .icons,
															 widthRatio: 1, minWidth: 25)
		case .right:    return Key(label: .localize("Right"),
															 imageName: .arrowRight,
															 preferredStyle: .icons,
															 widthRatio: 1, minWidth: 25)
		// Secondary - navigation
        case .home:     return Key(label: .localize("Home"),
                                   widthRatio: 1.25, heightRatio: isSmallDevice ? 0.8 : 1)
		case .end:      return Key(label: .localize("End"),
                                   widthRatio: 1.25, heightRatio: isSmallDevice ? 0.8 : 1)
		case .pageUp:   return Key(label: .localize("Page Up"),
															 glyph: .localize("PgUp"),
                                   widthRatio: 1.25, heightRatio: isSmallDevice ? 0.8 : 1)
		case .pageDown: return Key(label: .localize("Page Down"),
															 glyph: .localize("PgDn"),
                                   widthRatio: 1.25, heightRatio: isSmallDevice ? 0.8 : 1)

		// Secondary - extras
		case .delete:   return Key(label: .localize("Delete Forward"),
															 glyph: .localize("Del"),
//															 imageName: .deleteRight,
															 preferredStyle: .icons,
                                    widthRatio: 1, heightRatio: isSmallDevice ? 0.8 : 1)
		case .fnKeys:   return Key(label: .localize("Function Keys"),
															 glyph: .localize("Fn"),
															 isToggle: true,
                                   widthRatio: 1, heightRatio: isSmallDevice ? 0.8 : 1)

		// Fn keys
		case .fnKey(let index):
			return Key(label: "F\(index)",
								 preferredStyle: .text,
                       widthRatio: 1, heightRatio: isSmallDevice ? 0.7 : 1, minWidth: 35)
		}
	}
}

protocol KeyboardToolbarViewDelegate: AnyObject {
	func keyboardToolbarDidPressKey(_ key: ToolbarKey)
	func keyboardToolbarDidBeginPressingKey(_ key: ToolbarKey)
	func keyboardToolbarDidEndPressingKey(_ key: ToolbarKey)
    func keyboardToolbarDidChangeHeight(height: Double)
}

class KeyboardToolbarViewState: ObservableObject {
	@Published var toggledKeys = Set<ToolbarKey>()
}

struct KeyboardToolbarKeyStack: View {
	weak var delegate: KeyboardToolbarViewDelegate?

	let toolbar: Toolbar
	var arrowsStyle: KeyboardArrowsStyle?

	@EnvironmentObject var state: KeyboardToolbarViewState

	@ObservedObject private var preferences = Preferences.shared

	var body: some View {
		HStack(alignment: .center, spacing: 5) {
            let keys = toolbar.keys
			ForEach(keys, id: \.self) { key in
				switch key {
				case .fixedSpace:    EmptyView()
				case .variableSpace: Spacer(minLength: 0)
				case .arrows:        arrowsView
				default:             button(for: key)
				}
                if toolbar == .fnKeys && key != keys.last {
                    Spacer(minLength: 0)
                }
			}
		}
	}

	@ViewBuilder
	func button(for key: ToolbarKey, halfHeight: Bool? = nil) -> some View {
		let button = Button {
			UIDevice.current.playInputClick()

			if key.key.isToggle {
				if state.toggledKeys.contains(key) {
					state.toggledKeys.remove(key)
				} else {
					state.toggledKeys.insert(key)
				}
			}

			delegate?.keyboardToolbarDidPressKey(key)
		} label: {
			switch key {
			case .up, .down, .left, .right:
				Image(systemName: key.key.imageName!)
					.frame(width: 14, height: 14, alignment: .center)
					.accessibilityLabel(key.key.label)

			default:
				VStack(alignment: .trailing, spacing: 2) {
                    if let imageName = key.key.imageName,
                         key.key.preferredStyle != .text {
					HStack(spacing: 0) {
							Image(systemName: imageName)
								.imageScale(.small)
								.opacity(0.5)
								.frame(width: 14, height: 14, alignment: .center)
								.padding(.trailing, 1)
								.accessibilityLabel(key.key.label)
					}
					.frame(height: 14)
                    }

					Text((key.key.glyph ?? key.key.label).localizedLowercase)
				}
			}
		}
			.buttonStyle(.keyboardKey(selected: state.toggledKeys.contains(key),
																hasShadow: true,
                                      halfHeight: halfHeight ?? key.key.halfHeight,
                                      widthRatio: key.key.widthRatio, minWidth: key.key.minWidth, heightRatio: key.key.heightRatio))

		if KeyboardPreferences.isKeyRepeatEnabled {
			button
				.onLongPressGesture(minimumDuration: KeyboardPreferences.keyRepeatDelay,
														perform: {},
														onPressingChanged: { pressing in
					if pressing {
						delegate?.keyboardToolbarDidBeginPressingKey(key)
					} else {
						delegate?.keyboardToolbarDidEndPressingKey(key)
					}
				})
		} else {
			button
		}
	}
    
    struct ButtonHeightPreferenceKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }
    @State private var halfButtonsHeight: CGFloat = 0

	@ViewBuilder
	var arrowsView: some View {
		switch arrowsStyle ?? preferences.keyboardArrowsStyle {
		case .butterfly:
			HStack(spacing: isBigDevice ? 5 : 2) {
				button(for: .left)
				VStack(spacing: 2) {
					button(for: .up, halfHeight: true)
					button(for: .down, halfHeight: true)
				}
				button(for: .right)
			}

		case .scissor:
			HStack(spacing: isBigDevice ? 5 : 2) {
				VStack(alignment: .trailing, spacing: 2) {
                    Spacer(minLength: 45/2-1)
					button(for: .left, halfHeight: true)
				}
				VStack(alignment: .trailing, spacing: 2) {
					button(for: .up, halfHeight: true)
					button(for: .down, halfHeight: true)
				}
				VStack(alignment: .trailing, spacing: 2) {
                    Spacer(minLength: 45/2-1)
					button(for: .right, halfHeight: true)
				}
			}

		case .classic:
			HStack(spacing: 5) {
				button(for: .up)
				button(for: .down)
				button(for: .left)
				button(for: .right)
			}

		case .vim:
			HStack(spacing: 5) {
				button(for: .left)
				button(for: .down)
				button(for: .up)
				button(for: .right)
			}

		case .vimInverted:
			HStack(spacing: 5) {
				button(for: .left)
				button(for: .up)
				button(for: .down)
				button(for: .right)
			}
		}
	}
}
struct KeyboardToolbarViewTest: View {
    var body: some View {
        Rectangle()
            .fill(Color.red)
            .frame(height: 50)
            .opacity(0.5)
            .padding(5)
    }
}
struct KeyboardToolbarView: View {
	weak var delegate: KeyboardToolbarViewDelegate?

	let toolbars: [Toolbar]

	@State private var outerSize = CGSize.zero

	@EnvironmentObject var state: KeyboardToolbarViewState

	@ObservedObject private var preferences = Preferences.shared

	private func isToolbarVisible(_ toolbar: Toolbar) -> Bool {
		switch toolbar {
		case .primary, .padPrimaryLeading, .padPrimaryTrailing:
			return true
		case .secondary:
			return state.toggledKeys.contains(.more)
		case .fnKeys:
			return state.toggledKeys.contains(.fnKeys)
		}
	}

	@ViewBuilder
	var body: some View {
//		ZStack(alignment: .bottom) {
//			Color.black
//				.frame(height: 0)
//				.captureSize(in: $outerSize)
//                .background(GeometryReader { geometry in
//                 Color.blue.opacity(0.5)
//                     .onAppear {
//                         NSLog("NewTermLog: ZStack onAppear \(geometry.size)")
//                     }
//                     .onChange(of: geometry.size) { newSize in
//                         NSLog("NewTermLog: ZStack onChange \(newSize)")
//                     }
//                })
            
			VStack(spacing: 0) {
				ForEach(toolbars, id: \.self) { toolbar in
					if isToolbarVisible(toolbar) {
                        let _ = NSLog("NewTermLog: outerSize=\(outerSize)")
						let view = KeyboardToolbarKeyStack(delegate: delegate,
																							 toolbar: toolbar)
                            .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .pad ? 4  : 1)
							.padding(.top, 5)

						switch toolbar {
						case .primary, .padPrimaryLeading, .padPrimaryTrailing, .secondary:
							view
//								.frame(width: outerSize.width)

						case .fnKeys:
							CocoaScrollView(.horizontal, showsIndicators: false) {
								view
                            }
//								.frame(width: outerSize.width)
						}
					}
				}
                .padding(.bottom, UIDevice.current.userInterfaceIdiom == .pad ? 5 : 2)
//                .background(GeometryReader { geometry in
//                    Color.green.opacity(0.5)
//                         .onAppear {
//                             NSLog("NewTermLog: VStack onAppear \(geometry.size)")
//                         }
//                         .onChange(of: geometry.size) { newSize in
//                             NSLog("NewTermLog: VStack onChange \(newSize)")
//                         }
//                 })
			}
            .onChangeOfFrame(perform: { size in
                NSLog("NewTermLog: KeyboardToolbarView.VStack.onChangeOfFrame \(size)")
            })
//		}
//        .onChangeOfFrame(perform: { size in
//            NSLog("NewTermLog: ZStack onChangeOfFrame \(size)")
//        })
	}
}

struct KeyboardToolbarView_Previews: PreviewProvider {
	@State private static var state = KeyboardToolbarViewState()

	static var previews: some View {
		ForEach(ColorScheme.allCases, id: \.self) { scheme in
			VStack {
				Spacer()
				KeyboardToolbarView(toolbars: [.fnKeys, .secondary, .primary])
					.environmentObject(state)
					.padding(.bottom, 4)
					.background(BlurEffectView(style: .systemChromeMaterial))
					.preferredColorScheme(scheme)
					.previewLayout(.sizeThatFits)
			}
				.previewDisplayName("\(scheme)")
				.previewLayout(.fixed(width: 414, height: 100))
		}

		VStack() {
			Spacer()
			HStack {
				KeyboardToolbarKeyStack(toolbar: .padPrimaryLeading)
					.environmentObject(state)
				Spacer()
				KeyboardToolbarKeyStack(toolbar: .padPrimaryTrailing)
					.environmentObject(state)
			}
				.previewLayout(.sizeThatFits)
		}
			.previewDisplayName("iPad Toolbar")
			.previewLayout(.fixed(width: 600, height: 100))
	}
}
