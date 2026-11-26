import SwiftUI

struct SettingsDropdown<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    var placeholder = ""
    let optionTitle: (Value) -> String
    var swatch: (Value) -> Color? = { _ in nil }

    @State private var isShowing = false
    @State private var hoveredOption: Value?
    @FocusState private var focusedOption: Value?

    private let width: CGFloat = 220
    private let rowHeight: CGFloat = 34

    private var selectedTitle: String {
        options.contains(selection) ? optionTitle(selection) : placeholder
    }

    var body: some View {
        HStack {
            Text(title)
                .frame(width: 120, alignment: .leading)
                .accessibilityHidden(true)
            Button {
                isShowing.toggle()
            } label: {
                HStack(spacing: 8) {
                    if options.contains(selection) { colorSwatch(selection) }
                    Text(selectedTitle).lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(width: width)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(.gray.opacity(0.3))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(selectedTitle)
            .disabled(options.isEmpty)
            .popover(isPresented: $isShowing, arrowEdge: .bottom) {
                optionList
            }
        }
    }

    private var optionList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(options, id: \.self) { option in
                        optionRow(option)
                            .id(option)
                    }
                }
                .padding(6)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(width: width, height: rowHeight * CGFloat(min(options.count, 8)) + 12)
            .onAppear {
                hoveredOption = nil
                focusedOption = options.contains(selection) ? selection : options.first
            }
            .onChange(of: focusedOption, initial: true) { _, option in
                if let option { proxy.scrollTo(option) }
            }
            .onMoveCommand { direction in
                guard direction == .up || direction == .down,
                      let option = focusedOption,
                      let index = options.firstIndex(of: option) else { return }
                let next = index + (direction == .up ? -1 : 1)
                if options.indices.contains(next) { focusedOption = options[next] }
            }
        }
    }

    private func optionRow(_ option: Value) -> some View {
        let accent = Color.themePrimaryAccent
        return Button {
            selection = option
            isShowing = false
        } label: {
            HStack(spacing: 10) {
                colorSwatch(option)
                Text(optionTitle(option)).lineLimit(1)
                Spacer(minLength: 4)
                if option == selection {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(accent)
                        .accessibilityHidden(true)
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(height: rowHeight)
            .background(
                hoveredOption == option || focusedOption == option ? Color.themeSelectionBackground : .clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focusedOption, equals: option)
        .accessibilityAddTraits(option == selection ? .isSelected : [])
        .onHover { hovering in
            if hovering { hoveredOption = option }
            else if hoveredOption == option { hoveredOption = nil }
        }
    }

    @ViewBuilder
    private func colorSwatch(_ option: Value) -> some View {
        if let color = swatch(option) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
        }
    }
}
