import {
  AbilityAware,
  AbilityPluginBinding,
  Any,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult
} from '@ohos/flutter_ohos';
import common from '@ohos.app.ability.common';
import hilog from '@ohos.hilog';
import { formBindingData, formProvider } from '@kit.FormKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { HomeWidgetStore, SNAPSHOT_KEYS } from '../widget/HomeWidgetStore';

const TAG: string = 'NexHubWidget';
const CHANNEL: string = 'nexhub/home_widget';

/**
 * 桌面卡片通道（`nexhub/home_widget`，与 Android 侧同名同协议）。
 *
 * - `update`：Dart 传 `{ data: <快照键值> }`，写入 preferences 后对每个已记录
 *   的 formId 调 `formProvider.updateForm` 主动推送（卡片进程无需再唤醒）；
 * - `takeLaunchRoute`：取走 EntryAbility 从 want.parameters 暂存的跳转目标。
 *
 * 卡片渲染在 FormExtensionAbility 进程，本插件跑在 EntryAbility 进程，
 * 两者只通过 preferences 与 updateForm 交互，不共享内存。
 */
export default class HomeWidgetPlugin implements FlutterPlugin, AbilityAware, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private context: common.UIAbilityContext | null = null;

  /// 待消费的跳转目标。onCreate / onNewWant 可能早于引擎就绪，先落静态位。
  private static pendingRoute: string | null = null;

  static setPendingRoute(route: string | null): void {
    HomeWidgetPlugin.pendingRoute = route;
  }

  getUniqueClassName(): string {
    return 'HomeWidgetPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.context = binding.getAbility().context as common.UIAbilityContext;
  }

  onDetachedFromAbility(): void {
    this.context = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'update':
        this.update(call, result);
        return;
      case 'takeLaunchRoute': {
        const route: string | null = HomeWidgetPlugin.pendingRoute;
        HomeWidgetPlugin.pendingRoute = null;
        result.success(route);
        return;
      }
      default:
        result.notImplemented();
    }
  }

  private update(call: MethodCall, result: MethodResult): void {
    const context: common.UIAbilityContext | null = this.context;
    if (context == null) {
      hilog.error(0x0000, TAG, 'update no ui context');
      result.error('no_context', 'UIAbility context is null', '');
      return;
    }
    const raw: Any = call.argument('data');
    if (raw == null) {
      result.error('bad_args', 'data is null', '');
      return;
    }
    const data = new Map<string, string>();
    try {
      // Dart 侧固定传 Map（{data: {...}}）。若通道把它解成对象，退化到按已知键取值。
      (raw as Map<Object, Object>).forEach((value: Object, key: Object) => {
        data.set(`${key}`, value == null ? '' : `${value}`);
      });
    } catch (e) {
      SNAPSHOT_KEYS.forEach((key: string) => {
        const value: Any = call.argument(key);
        data.set(key, value == null ? '' : `${value}`);
      });
    }
    const written: boolean = HomeWidgetStore.writeSnapshot(context, data);
    const ids: string[] = HomeWidgetStore.listFormIds(context);
    hilog.info(0x0000, TAG, 'update written=%{public}s forms=%{public}d',
      written ? '1' : '0', ids.length);
    if (ids.length > 0) {
      const binding = formBindingData.createFormBindingData(
        HomeWidgetStore.readSnapshot(context));
      ids.forEach((formId: string) => {
        formProvider.updateForm(formId, binding).then(() => {
          hilog.info(0x0000, TAG, 'updateForm ok %{public}s', formId);
        }).catch((e: BusinessError) => {
          // 系统对单卡刷新有频率限制，超限只记日志：下次进前台还会推。
          hilog.warn(0x0000, TAG, 'updateForm %{public}s failed: %{public}s',
            formId, e.message);
        });
      });
    }
    result.success(written);
  }
}
