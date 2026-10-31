import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { Configuration, ConfigurationConstant, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { HomeWidgetStore, SNAPSHOT_KEYS } from '../widget/HomeWidgetStore';

const TAG: string = 'NexHubForm';

/**
 * 桌面卡片生命周期。
 *
 * 数据链路：
 * 1. Flutter（EntryAbility 进程）算好快照 + 预渲染背景图 → `nexhub/home_widget`
 *    通道 → HomeWidgetPlugin 写 preferences → 对已记录的 formId 逐个
 *    `updateForm` 推送；
 * 2. 卡片进程（本 Ability）在 onAddForm / onUpdateForm 时读同一份 preferences
 *    组装 formBindingData，并把背景 PNG 转成 PixelMap 一起传给卡片；
 * 3. 卡片被移除时**保留** formId（见 onRemoveForm 注释）。
 *
 * 两个进程靠同名 preferences 共享数据（官方支持跨进程读取）。
 */
export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    let formId: string = '';
    let formName: string = '';
    if (want.parameters !== undefined) {
      formId = want.parameters[formInfo.FormParam.IDENTITY_KEY] as string;
      formName = want.parameters[formInfo.FormParam.NAME_KEY] as string;
    }
    hilog.info(0x0000, TAG, 'onAddForm formId=%{public}s name=%{public}s', formId, formName);
    HomeWidgetStore.addFormId(this.context, formId);
    return this.composeBindingData();
  }

  onUpdateForm(formId: string): void {
    const data = this.composeBindingData();
    formProvider.updateForm(formId, data).catch((e: BusinessError) => {
      hilog.error(0x0000, TAG, 'onUpdateForm failed: %{public}s', e.message);
    });
  }

  /**
   * 系统配置变化（深浅色切换、字体、语言）。
   *
   * 这是卡片能「自动跟随夜间模式」的关键：系统换配色时 Flutter 可能没运行，
   * 只能由 FormAbility 用新的 config 重算并重推一遍。
   */
  onConfigurationUpdate(newConfig: Configuration): void {
    const mode: ConfigurationConstant.ColorMode | undefined =
      newConfig.colorMode;
    hilog.info(0x0000, TAG, 'onConfigurationUpdate colorMode=%{public}s',
      mode === undefined ? 'unknown' : mode.toString());
    const ids: string[] = HomeWidgetStore.listFormIds(this.context);
    const data = this.composeBindingData();
    ids.forEach((formId: string) => {
      formProvider.updateForm(formId, data).catch((e: BusinessError) => {
        // 失效 id 报错很正常（重装会留下历史 id），只记日志。
        hilog.warn(0x0000, TAG, 'updateForm %{public}s failed: %{public}s',
          formId, e.message);
      });
    });
  }

  onRemoveForm(formId: string): void {
    // 故意**不删除** formId：系统在应用升级 / 桌面重排时会先 onRemoveForm 再
    // onAddForm，若这里删掉，用户重新添加卡片后应用侧就推不动（推了个已失效 id）。
    // 保留旧 id 的代价只是 updateForm 报一次错（调用处已 catch），而数量极少。
    hilog.info(0x0000, TAG, 'onRemoveForm formId=%{public}s (id kept)', formId);
  }

  /** 组装卡片数据：文本快照 + 背景/热力图 PixelMap。 */
  private composeBindingData(): formBindingData.FormBindingData {
    const snapshot = HomeWidgetStore.readSnapshot(this.context);
    const bgPath: string = snapshot['bg_path'] ?? '';
    const heatPath: string = snapshot['heatmap_path'] ?? '';
    const pixelMap = EntryFormAbility.loadBackground(bgPath);
    const heatmap = EntryFormAbility.loadBackground(heatPath);
    // API 26 的 FormBindingData 只有 data/proxies（旧版的 formImages 已移除），
    // 于是把 PixelMap 直接放进 data 的字段里：系统用 Parcel 传对象，
    // PixelMap 在同应用进程间可直接传递，卡片 LocalStorage 里就能拿到像素图。
    const payload: ESObject = {};
    SNAPSHOT_KEYS.forEach((key: string) => {
      payload[key] = snapshot[key];
    });
    // 主题色层：按系统当前深浅色选一套 —— 系统切换时 Flutter 不一定在跑，
    // 这里用 FormAbility 自己的 config 判断，保证卡片跟着系统变。
    let colorMode: ConfigurationConstant.ColorMode =
      ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    try {
      const current: ConfigurationConstant.ColorMode | undefined =
        this.context.config.colorMode;
      if (current !== undefined) {
        colorMode = current;
      }
    } catch (e) {
      // 取不到就按浅色处理
    }
    const isDark: boolean =
      colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    payload['bg_color'] = isDark
      ? (snapshot['bg_color_dark'] ?? snapshot['bg_color'] ?? '#00000000')
      : (snapshot['bg_color_light'] ?? snapshot['bg_color'] ?? '#00000000');
    // 主题层（底色 / 正文 / 次要 / 强调）：App 下发浅深两套，这里按系统
    // colorMode 选用 —— 系统换深浅色时 App 可能没在跑，靠这层兜底。
    // 缺失时回退当前套，再回退空串（卡片用资源色兜底）。
    payload['card_bg'] = isDark
      ? (snapshot['card_bg_dark'] ?? snapshot['card_bg'] ?? '')
      : (snapshot['card_bg_light'] ?? snapshot['card_bg'] ?? '');
    payload['text_primary'] = isDark
      ? (snapshot['text_primary_dark'] ?? snapshot['text_primary'] ?? '')
      : (snapshot['text_primary_light'] ?? snapshot['text_primary'] ?? '');
    payload['text_secondary'] = isDark
      ? (snapshot['text_secondary_dark'] ?? snapshot['text_secondary'] ?? '')
      : (snapshot['text_secondary_light'] ?? snapshot['text_secondary'] ?? '');
    payload['color_primary'] = isDark
      ? (snapshot['color_primary_dark'] ?? snapshot['color_primary'] ?? '#0EA5E9')
      : (snapshot['color_primary_light'] ?? snapshot['color_primary'] ?? '#0EA5E9');
    hilog.info(0x0000, TAG, 'compose dark=%{public}s', isDark ? '1' : '0');
    if (pixelMap != null) {
      payload['bg'] = pixelMap;
    }
    if (heatmap != null) {
      payload['heatmap'] = heatmap;
    }
    hilog.info(0x0000, TAG, 'compose bg=%{public}s heat=%{public}s',
      pixelMap == null ? '0' : '1', heatmap == null ? '0' : '1');
    return formBindingData.createFormBindingData(payload as Object);
  }

  /**
   * 把应用沙箱里的 PNG 读成 PixelMap。
   *
   * 卡片不能直读文件路径，只能收 PixelMap；用同步 API 是因为 onAddForm 必须
   * 立刻返回数据（签名同步），异步等待会导致首帧空白。
   */
  private static loadBackground(path: string): image.PixelMap | null {
    if (path.length === 0) return null;
    let file: fs.File | null = null;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const source: image.ImageSource = image.createImageSource(file.fd);
      const pixelMap: image.PixelMap = source.createPixelMapSync();
      source.release();
      return pixelMap;
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(0x0000, TAG, 'load background failed: %{public}s', err.message);
      return null;
    } finally {
      if (file != null) {
        try {
          fs.closeSync(file);
        } catch (e) {
          // 关闭失败不影响卡片，忽略。
        }
      }
    }
  }
}
