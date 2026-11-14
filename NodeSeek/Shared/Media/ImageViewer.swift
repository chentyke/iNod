import SwiftUI

struct ImageViewer: View {
    let image: CGImage
    let url: URL
    let alt: String
    @Environment(\.dismiss) private var dismiss
    @State private var scale = 1.0
    @State private var offset = CGSize.zero
    @GestureState private var magnification = 1.0
    @GestureState private var translation = CGSize.zero
    var body: some View {
        NavigationStack {
            Image(image,scale:1,label:Text(alt.isEmpty ? "帖子图片" : alt)).resizable().scaledToFit()
                .scaleEffect(min(6,max(1,scale * magnification)))
                .offset(x:scale > 1 ? offset.width + translation.width : 0,y:scale > 1 ? offset.height + translation.height : 0)
                .frame(maxWidth:.infinity,maxHeight:.infinity).background(.black)
                .gesture(MagnifyGesture().updating($magnification) { value,state,_ in state = value.magnification }.onEnded { value in scale = min(6,max(1,scale * value.magnification)); if scale == 1 { offset = .zero } })
                .simultaneousGesture(DragGesture().updating($translation) { value,state,_ in if scale > 1 { state = value.translation } }.onEnded { value in if scale > 1 { offset.width += value.translation.width; offset.height += value.translation.height } })
                .onTapGesture(count:2) { scale = scale == 1 ? 2 : 1; offset = .zero }
                .accessibilityAction(named:"放大图片") { scale = min(6,scale + 1) }
                .accessibilityAction(named:"还原大小") { scale = 1; offset = .zero }
                .toolbar {
                    ToolbarItem(placement:.topBarLeading) { Button("完成") { dismiss() } }
                    ToolbarItem(placement:.topBarTrailing) { ShareLink(item:url) }
                }.toolbarColorScheme(.dark,for:.navigationBar).preferredColorScheme(.dark)
        }
    }
}
