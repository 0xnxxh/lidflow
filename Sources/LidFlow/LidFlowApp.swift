import SwiftUI
import AppKit
import MetalKit

@main struct LidFlowApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var updater = AppUpdater()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Window("LidFlow", id:"main") {
            MainView(model:model,updater:updater)
                .onAppear { delegate.model=model; NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps:true) }
        }
        .defaultSize(width:900,height:770)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing:.newItem) {}
            CommandGroup(after:.appInfo) {
                Button("检查更新…", action:updater.checkForUpdates).disabled(!updater.canCheckForUpdates)
            }
        }
        MenuBarExtra {
            MenuContent(model:model,updater:updater)
        } label: {
            Image(nsImage:BrandIcon.menuBar).accessibilityLabel("LidFlow")
        }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification:Notification) { MainActor.assumeIsolated { model?.shutdown() } }
}
struct MenuContent: View {
    @ObservedObject var model:AppModel
    @ObservedObject var updater:AppUpdater
    @Environment(\.openWindow) var openWindow
    var body:some View {
        Text(model.angle.map { "盖子角度 \(Int($0))°" } ?? "传感器不可用")
        Text(model.status)
        Divider()
        Button("打开 LidFlow") { openWindow(id:"main"); NSApp.activate(ignoringOtherApps:true) }
        Button("检查更新…", action:updater.checkForUpdates).disabled(!updater.canCheckForUpdates)
        Divider()
        Button("退出 LidFlow") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
struct MetalPreview:NSViewRepresentable {
    let model:AppModel
    func makeCoordinator()->Coordinator { Coordinator() }
    func makeNSView(context:Context)->MTKView {
        let view=MTKView()
        do {
            let renderer=try FoldRenderer()
            renderer.parameters={ [weak model] in model?.previewParameters() ?? EffectParameters() }
            renderer.isEnabled={ [weak model] in model?.windowVisible == true }
            renderer.attach(view); context.coordinator.renderer=renderer
        } catch { DispatchQueue.main.async { model.rendererError=error.localizedDescription } }
        return view
    }
    func updateNSView(_ view:MTKView,context:Context) {}
    static func dismantleNSView(_ view:MTKView,coordinator:Coordinator) { view.isPaused=true;view.delegate=nil;coordinator.renderer=nil }
    final class Coordinator { var renderer:FoldRenderer? }
}
struct MainView:View {
    @ObservedObject var model:AppModel
    @ObservedObject var updater:AppUpdater
    @State private var tab=0
    private let accent=Color(red:0.39,green:0.76,blue:0.69)
    var body:some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:8) {
                HStack(spacing:10) {
                    Image(nsImage:BrandIcon.menuBar).resizable().aspectRatio(contentMode:.fit)
                        .frame(width:28,height:25).foregroundStyle(accent)
                    Text("LidFlow").font(.title2.weight(.semibold))
                }.padding(.bottom,28)
                nav("外观",symbol:"circle.lefthalf.filled",index:0)
                nav("连接与行为",symbol:"slider.horizontal.3",index:1)
                Spacer()
                Circle().fill(model.angle == nil ? .orange : accent).frame(width:7,height:7)
                Text(model.angle.map { "\(Int($0))°" } ?? "—").font(.system(size:36,weight:.light,design:.rounded)).monospacedDigit()
                Text(model.sensorStatus).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                Text("macOS · 本机处理").font(.caption2).foregroundStyle(.tertiary).padding(.top,10)
            }.padding(24).frame(width:185).background(.black.opacity(0.16))
            VStack(alignment:.leading,spacing:20) {
                HStack {
                    VStack(alignment:.leading,spacing:6) {
                        Text(tab==0 ? "随开合，自然展开。" : "你的盖子，你的节奏。").font(.system(size:25,weight:.medium))
                        Text(tab==0 ? "柔光、深影、冰雾或飞灰，随角度变幻。" : "连接铰链，设置何时恢复清晰桌面。").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(AppUpdater.versionLabel).font(.caption).padding(.horizontal,10).padding(.vertical,6).background(.white.opacity(0.06),in:Capsule())
                }
                if tab==0 { appearance } else { behavior }
                Spacer(minLength:0)
                Divider()
                HStack(alignment:.center) {
                    VStack(alignment:.leading,spacing:5) {
                        Text(model.status).font(.callout).lineLimit(2)
                        Text("自动跟随 · 关闭设置窗口后继续运行 · Esc 恢复本次画面").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()

                }
            }.padding(28).frame(width:645)
        }
        .frame(width:878,height:750)
        .background(Color(red:0.10,green:0.12,blue:0.14))
        .preferredColorScheme(.dark)
        .alert("渲染不可用",isPresented:Binding(get:{model.rendererError != nil},set:{if !$0 {model.rendererError=nil}})) {
            Button("好") { model.rendererError=nil }
        } message: { Text(model.rendererError ?? "") }
    }
    func nav(_ title:String,symbol:String,index:Int)->some View {
        Button { tab=index } label: {
            Label(title,systemImage:symbol).frame(maxWidth:.infinity,alignment:.leading).padding(11)
                .background(tab==index ? .white.opacity(0.09) : .clear,in:RoundedRectangle(cornerRadius:9))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    var appearance:some View {
        VStack(spacing:14) {
            ZStack(alignment:.top) {
                MetalPreview(model:model).frame(height:294).clipShape(RoundedRectangle(cornerRadius:15))
                    .padding(9).background(.black,in:RoundedRectangle(cornerRadius:23))
                RoundedRectangle(cornerRadius:6).fill(.black).frame(width:90,height:16).offset(y:5)
            }
            HStack(spacing:12) {
                Button { model.toggleDemo() } label: { Image(systemName:model.demoPlaying ? "pause.fill" : "play.fill").frame(width:20) }
                    .help("播放或暂停开合预览")
                Text("\(Int(model.followPreview ? model.angle ?? model.clearAngle : model.previewAngle))°").monospacedDigit().frame(width:38)
                Slider(value:$model.previewAngle,in:10...140).disabled(model.followPreview || model.demoPlaying).accessibilityLabel("预览角度")
                Toggle("跟随盖子",isOn:$model.followPreview).toggleStyle(.switch).controlSize(.small)
                    .onChange(of:model.followPreview) { _, value in if value {model.demoPlaying=false} }
            }
            VStack(alignment:.leading,spacing:9) {
                HStack(spacing:8) {
                    styleButton("柔光",subtitle:"Silk",index:0,icon:"water.waves")
                    styleButton("深影",subtitle:"Shade",index:1,icon:"moon.fill")
                    styleButton("冰雾",subtitle:"Frost",index:2,icon:"snowflake")
                    styleButton("飞灰",subtitle:"Ash",index:3,icon:"square.dashed")
                }
                HStack {
                    Text(styleDescription).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength:4)
                    Button("恢复默认") {model.resetCurrentEffect()}
                        .font(.caption).buttonStyle(.plain).foregroundStyle(accent)
                        .help("只恢复当前效果的三个参数，其他效果保持不变。")
                }
            }
            VStack(spacing:14) {
                parameter("透视",value:$model.perspective,help:"控制画面后仰与收拢；0% 保持平面，100% 透视最强。")
                parameter(model.style==3 ? "飘散距离" : "柔焦强度",value:$model.blur,help:model.style==3 ? "控制碎片飞离原位置的距离。" : "同时调整画面细节与边缘柔化；0% 关闭柔焦。")
                parameter(model.style==3 ? "碎片大小" : "阴影",value:$model.shadow,help:model.style==3 ? "向右调节得到更大的碎片。" : "控制阴影浓度；0% 关闭额外阴影，100% 最深。")
            }.padding(16).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:12))
        }
    }
    func styleButton(_ name:String,subtitle:String,index:Int,icon:String)->some View {
        Button { model.selectStyle(index) } label: {
            HStack(spacing:7) {
                Image(systemName:icon).foregroundStyle(accent).frame(width:18)
                VStack(alignment:.leading,spacing:2) {Text(name);Text(subtitle).font(.caption2).foregroundStyle(.secondary)}
                Spacer(minLength:0)
            }.frame(maxWidth:.infinity)
                .padding(.horizontal,12).padding(.vertical,9).background(model.style==index ? accent.opacity(0.10) : .white.opacity(0.035),in:RoundedRectangle(cornerRadius:10))
                .overlay(RoundedRectangle(cornerRadius:10).stroke(model.style==index ? accent.opacity(0.65) : .clear,lineWidth:1))
        }.buttonStyle(.plain).accessibilityLabel("\(subtitle) · \(name)").accessibilityAddTraits(model.style==index ? .isSelected : [])
    }
    var styleDescription:String {
        switch model.style {
        case 1: return "Shade · 保留清晰细节，让深邃阴影沿折面展开。"
        case 2: return "Frost · 冰蓝雾面、细微颗粒与磨砂玻璃般的柔焦。"
        case 3: return "Ash · 桌面碎裂成飞灰；合盖飘散，开盖重新聚合。"
        default: return "Silk · 柔亮光带滑过桌面，像丝绸般渐渐舒展。"
        }
    }
    func parameter(_ name:String,value:Binding<Double>,help:String)->some View {
        HStack {Text(name).font(.callout).frame(width:80,alignment:.leading);Slider(value:value,in:0...1).accessibilityLabel(name).help(help);Text("\(Int(value.wrappedValue*100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width:37,alignment:.trailing)}
    }
    var behavior:some View {
        VStack(alignment:.leading,spacing:22) {
            GroupBox {
                VStack(alignment:.leading,spacing:12) {
                    Label(model.permissionLabel,systemImage:model.hasCapturePermission ? "checkmark.circle.fill" : "display").foregroundStyle(accent)
                    Text("读取桌面以绘制开合效果。画面只在内存中处理，不保存、不上传。").font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("验证屏幕访问") { model.requestPermission() }.disabled(model.checkingPermission)
                        Button("系统权限设置") { model.openPermissionSettings() }
                    }
                    if model.screenAccess == .denied {
                        Text("已开启仍不可用：从系统列表移除旧 LidFlow，再添加此版本并允许。")
                            .font(.caption).foregroundStyle(.orange)
                        Button("在 Finder 中显示当前 App") {
                            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                        }
                    }
                }.frame(maxWidth:.infinity,alignment:.leading).padding(12)
            }
            GroupBox("铰链传感器") {
                VStack(alignment:.leading,spacing:14) {
                    HStack {Text(model.sensorStatus);Spacer();Button("重新连接") { model.reconnectSensor() }}
                    Picker("读取方式",selection:$model.polling) {
                        Text("流畅读取 · 后台 120 Hz").tag(true)
                        Text("HID 事件 · 实验性").tag(false)
                    }.pickerStyle(.menu)
                    Picker("动画刷新",selection:$model.displayFPS) {
                        Text("120 fps · 高刷新").tag(120)
                        Text("60 fps · 稳定节奏").tag(60)
                    }.pickerStyle(.menu)
                    Text("流畅模式在后台读取角度，动画随显示器刷新。事件模式不轮询，需确认本机能持续回调。").font(.caption).foregroundStyle(.secondary)
                }.padding(12)
            }
            GroupBox("清除与反馈") {
                VStack(alignment:.leading,spacing:18) {
                    HStack {Text("清除角度");Slider(value:$model.clearAngle,in:70...135,step:1).accessibilityLabel("清除角度");Text("\(Int(model.clearAngle))°").monospacedDigit().frame(width:40)}
                    Text("盖子打开超过这个角度，桌面恢复清晰。关闭到阈值以下时开始生效。").font(.caption).foregroundStyle(.secondary)
                    Toggle("恢复清晰时播放轻响",isOn:$model.sound)
                }.padding(12)
            }
            Text("App 启动后自动跟随，关闭设置窗口仍会继续。睡眠或锁屏期间暂停，恢复后自动连接。Esc 可恢复本次画面，打开盖子后自动继续。").font(.caption).foregroundStyle(.secondary)
            HStack {
                Toggle("自动检查更新",isOn:$updater.automaticallyChecksForUpdates).toggleStyle(.switch).controlSize(.small)
                Spacer()
                Button("检查更新…",action:updater.checkForUpdates).disabled(!updater.canCheckForUpdates)
            }
        }
    }
}
