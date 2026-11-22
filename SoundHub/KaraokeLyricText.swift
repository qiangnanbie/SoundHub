import SwiftUI

/// 逐字歌词渲染：按词级时间轴推进每个词的高亮进度。
/// 没有词级时间轴的普通 LRC 仍走原来的整行渲染。
struct KaraokeLyricText: View {
    let words: [LyricWord]
    let time: Double
    let font: Font
    let color: Color

    var body: some View {
        Text(attributed)
            .font(font)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        for word in words {
            var segment = AttributedString(word.text)
            segment.foregroundColor = color.opacity(LyricKaraokeTiming.opacity(for: word, at: time))
            result += segment
        }
        return result
    }
}
