import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import type Want from '@ohos.app.ability.Want';
import window from '@ohos.window';
import { BusinessError } from '@kit.BasicServicesKit';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import ClipboardPlugin from '../plugins/ClipboardPlugin';
import FileExportPlugin from '../plugins/FileExportPlugin';
import MediaStorePlugin from '../plugins/MediaStorePlugin';
import OhosStoragePlugin from '../plugins/OhosStoragePlugin';
import OhosTtsPlugin from '../plugins/OhosTtsPlugin';
import MdnsDiscoveryPlugin from '../plugins/MdnsDiscoveryPlugin';
import VolumeKeyPlugin from '../plugins/VolumeKeyPlugin';
import WallpaperColorPlugin from '../plugins/WallpaperColorPlugin';
import DeviceFormPlugin from '../plugins/DeviceFormPlugin';
import WindowControlPlugin from '../plugins/WindowControlPlugin';
import HarmonyContinuationPlugin from '../plugins/HarmonyContinuationPlugin';
import BackgroundTaskPlugin from '../plugins/BackgroundTaskPlugin';
import HomeWidgetPlugin from '../plugins/HomeWidgetPlugin';

/// 跨设备接续数据在 want.parameters 中的键（与 Dart 侧约定一致）。
const CONTINUATION_KEY: string = 'nexhub_continuation';

/// 桌面卡片点击时带过来的跳转目标（与 Android 侧同名）。
const CARD_ROUTE_KEY: string = 'nexhub_card_route';

export default class EntryAbility extends FlutterAbility {
  /// 常驻实例：onContinue / onCreate 可能在 configureFlutterEngine 之前回调，
  /// 未挂载引擎时通道为空，插件内部自行降级返回 null。
  private continuation: HarmonyContinuationPlugin = new HarmonyContinuationPlugin();
  private backgroundTask: BackgroundTaskPlugin = new BackgroundTaskPlugin();
  private homeWidget: HomeWidgetPlugin = new HomeWidgetPlugin();

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    // 应用级原生通道：保存图片到系统相册（见 MediaStorePlugin 注释）。
    flutterEngine.getPlugins()?.add(new MediaStorePlugin())
    // 应用级原生通道：离线朗读（CoreSpeechKit，见 OhosTtsPlugin 注释）。
    flutterEngine.getPlugins()?.add(new OhosTtsPlugin())
    // 应用级原生通道：图片写入系统剪贴板（见 ClipboardPlugin 注释）。
    flutterEngine.getPlugins()?.add(new ClipboardPlugin())
    // 应用级原生通道：导出文件到用户可见位置（见 FileExportPlugin 注释）。
    flutterEngine.getPlugins()?.add(new FileExportPlugin())
    // 应用级原生通道：系统下载目录授权与读写（见 OhosStoragePlugin 注释）。
    flutterEngine.getPlugins()?.add(new OhosStoragePlugin())
    // 应用级原生通道：投屏设备发现（@ohos.net.mdns，见 MdnsDiscoveryPlugin 注释）。
    flutterEngine.getPlugins()?.add(new MdnsDiscoveryPlugin())
    // 应用级原生通道：阅读器音量键翻页拦截（见 VolumeKeyPlugin 注释）。
    flutterEngine.getPlugins()?.add(new VolumeKeyPlugin())
    // 应用级原生通道：壁纸主色（莫奈 seed，见 WallpaperColorPlugin 注释）。
    flutterEngine.getPlugins()?.add(new WallpaperColorPlugin())
    // 应用级原生通道：设备形态判定（手机 / 2in1 PC，见 DeviceFormPlugin 注释）。
    flutterEngine.getPlugins()?.add(new DeviceFormPlugin())
    // 应用级原生通道：窗口全屏控制（2in1 PC，见 WindowControlPlugin 注释）。
    flutterEngine.getPlugins()?.add(new WindowControlPlugin())
    // 应用级原生通道：跨设备接续（流转，见 HarmonyContinuationPlugin 注释）。
    flutterEngine.getPlugins()?.add(this.continuation)
    // 应用级原生通道：后台下载长任务（dataTransfer，见 BackgroundTaskPlugin 注释）。
    flutterEngine.getPlugins()?.add(this.backgroundTask)
    // 应用级原生通道：桌面卡片快照与点击跳转（见 HomeWidgetPlugin 注释）。
    flutterEngine.getPlugins()?.add(this.homeWidget)
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam) {
    super.onCreate(want, launchParam)
    // 桌面卡片冷启动：先把目标存下来，Flutter 首帧后经通道取走。
    this.captureCardRoute(want);
    // 默认不可接续：仅当播放器 / 阅读器挂载后由 Dart 置为 ACTIVE，
    // 避免无内容时对端出现接续入口、点击后提示接续失败。
    this.context
      .setMissionContinueState(AbilityConstant.ContinueState.INACTIVE)
      .catch((err: BusinessError) => {
        console.error(`setMissionContinueState failed: ${err.code} ${err.message}`);
      });
    if (this.handleContinuation(want, launchParam, false)) {
      // 接续冷启动时系统触发 onWindowStageRestore 而非 onWindowStageCreate，
      // FlutterAbility 不使用 ArkUI 页面栈，需主动恢复窗口内容。
      this.context.restoreWindowStage(new LocalStorage());
    }
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam) {
    super.onNewWant(want, launchParam)
    // 桌面卡片热启动：应用已在后台时点卡片走这里。
    this.captureCardRoute(want);
    // 热启动：窗口与 Flutter 引擎均已就绪，可直接推送通知 Dart 跳转。
    this.handleContinuation(want, launchParam, true);
  }

  /**
   * 取出卡片点击带来的跳转目标。与接续不同，它不看 launchReason：
   * 卡片点击走的是普通 router 拉起，launchReason 为 NORMAL。
   */
  private captureCardRoute(want: Want): void {
    const route: Object | undefined = want.parameters?.[CARD_ROUTE_KEY];
    if (typeof route === 'string' && (route as string).length > 0) {
      HomeWidgetPlugin.setPendingRoute(route as string);
    }
  }

  /**
   * 接续冷启动的窗口恢复回调。FlutterAbility 未实现此回调（不使用
   * ArkUI 页面栈），按正常创建流程初始化 Flutter 视图并加载页面。
   */
  onWindowStageRestore(windowStage: window.WindowStage): void {
    this.onWindowStageCreate(windowStage);
  }

  /**
   * 源端（发起方）：系统发起接续时向 Dart 拉取当前播放/阅读快照。
   * 无持有者（Dart 返回 null）时拒绝本次接续。
   */
  async onContinue(
    wantParam: Record<string, Object>): Promise<AbilityConstant.OnContinueResult> {
    const state: string | null = await this.continuation.getContinuationState();
    if (state == null || state.length == 0) {
      return AbilityConstant.OnContinueResult.REJECT;
    }
    wantParam[CONTINUATION_KEY] = state;
    return AbilityConstant.OnContinueResult.AGREE;
  }

  /**
   * 对端（接收方）：从 want 中取出源端快照并暂存，由 Dart 首帧后拉取。
   * 返回是否为接续启动。
   */
  private handleContinuation(want: Want, launchParam: AbilityConstant.LaunchParam,
    notify: boolean): boolean {
    if (launchParam.launchReason !== AbilityConstant.LaunchReason.CONTINUATION) {
      return false;
    }
    const data: Object | undefined = want.parameters?.[CONTINUATION_KEY];
    if (typeof data === 'string') {
      const text: string = data as string;
      if (text.length > 0) {
        this.continuation.setPendingContinuation(text, notify);
      }
    }
    return true;
  }

  onWindowStageCreate(windowStage: window.WindowStage) {
    super.onWindowStageCreate(windowStage)
    // 窗口尺寸与位置记忆（2in1 / 平板自由窗口）：交系统托管，
    // 下次冷启动按上次关闭时的窗口矩形与状态恢复。
    windowStage.setWindowRectAutoSave(true).catch((err: BusinessError) => {
      console.error(`setWindowRectAutoSave failed: ${err.code} ${err.message}`);
    });
  }
}
