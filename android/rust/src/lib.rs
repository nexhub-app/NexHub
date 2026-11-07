use std::io::{self, BufRead, BufReader, Read, Write};
use std::net::{Ipv4Addr, SocketAddrV4, TcpListener, TcpStream, ToSocketAddrs, UdpSocket};
use std::path::PathBuf;
use std::sync::Arc;
use std::thread;
use std::time::Instant;

// ======================= 跨平台: 裸句柄获取/关闭 =======================
// relay 循环里 backend 被 ManuallyDrop 包裹（异常路径跳过 OpenSSL drop 防 SIGSEGV），
// 异常结束时要手动关闭底层 TCP。裸句柄与关闭 API 两平台不同：
// unix = i32 fd + close(2)；windows = SOCKET(usize) + closesocket(ws2_32)。
// 统一转成 i64 传递（fd/sign 扩展、socket/零扩展均无损），关闭函数按平台各给一份。
#[cfg(unix)]
use std::os::unix::io::AsRawFd as RawHandle;
#[cfg(windows)]
use std::os::windows::io::AsRawSocket as RawHandle;

#[inline]
fn tcp_raw_handle(stream: &TcpStream) -> i64 {
    #[cfg(unix)]
    let h = stream.as_raw_fd() as i64;
    #[cfg(windows)]
    let h = stream.as_raw_socket() as i64;
    h
}

#[cfg(unix)]
#[inline]
unsafe fn close_raw_handle(handle: i64) {
    unsafe { libc::close(handle as i32) };
}

#[cfg(windows)]
#[inline]
unsafe fn close_raw_handle(handle: i64) {
    // std 已为 TcpStream 链接 ws2_32，无需额外的构建脚本声明。
    #[link(name = "ws2_32")]
    extern "system" {
        fn closesocket(s: usize) -> i32;
    }
    unsafe { closesocket(handle as usize) };
}

use foreign_types_shared::ForeignType;
#[cfg(has_ech)]
use foreign_types_shared::ForeignTypeRef;
use parking_lot::{Condvar, Mutex};

// Android logging
#[cfg(target_os = "android")]
extern "C" {
    fn __android_log_print(prio: i32, tag: *const u8, fmt: *const u8, ...) -> i32;
}

const ANDROID_LOG_DEBUG: i32 = 3;
const ANDROID_LOG_ERROR: i32 = 6;

macro_rules! log_d {
    ($($arg:tt)*) => {
        // 参考项目这里写的是 #[cfg(debug_assertions)]（「只在 debug 构建里打日志」），
        // 但本项目的 Rust 库**恒定**以 `cargo ndk ... --release` 编译
        // （见 android/rust/build-android.sh），该条件永远为假 —— 所有 log_d 全部变成
        // 死代码，真机上排查「某个域为什么没走 ECH」时一个字都看不到。
        //
        // 改为**运行期开关**：由上层 `setScope(..., verboseLog)` 下发，默认关
        // （与参考项目「release 不打 debug 日志」的性能意图一致）；Flutter 侧
        // 只在 debug 构建（kDebugMode）下打开，便于真机验收对照。
        if crate::VERBOSE_LOG.load(std::sync::atomic::Ordering::Relaxed) {
            #[cfg(target_os = "android")]
            {
                let msg = std::ffi::CString::new(format!($($arg)*)).unwrap_or_default();
                let tag = b"NexHubEch\0";
                unsafe {
                    __android_log_print(ANDROID_LOG_DEBUG, tag.as_ptr(), b"%s\0".as_ptr(), msg.as_ptr());
                }
            }
            #[cfg(not(target_os = "android"))]
            eprintln!($($arg)*);
        }
    };
}

macro_rules! log_e {
    ($($arg:tt)*) => {
        #[cfg(target_os = "android")]
        {
            let msg = std::ffi::CString::new(format!($($arg)*)).unwrap();
            let tag = b"EchProxy\0";
            unsafe {
                __android_log_print(ANDROID_LOG_ERROR, tag.as_ptr(), b"%s\0".as_ptr(), msg.as_ptr());
            }
            // msg is dropped here, after __android_log_print has finished
        }
        #[cfg(not(target_os = "android"))]
        eprintln!($($arg)*);
    };
}

#[cfg(has_ech)]
unsafe extern "C" {
    fn ech_get_retry_config(host: *const std::os::raw::c_char, port: std::os::raw::c_int, outer_sni: *const std::os::raw::c_char, out_cfg: *mut *mut u8, out_len: *mut usize) -> std::os::raw::c_int;
    fn ech_free(p: *mut std::os::raw::c_void);
}

#[cfg(has_ech)]
mod ffi {
    use std::os::raw::{c_char, c_int, c_void};
    unsafe extern "C" {
        pub fn SSL_set1_ech_config_list(s: *mut openssl_sys::SSL, ecl: *const u8, len: usize) -> c_int;
        pub fn SSL_ech_set1_server_names(s: *mut openssl_sys::SSL, inner: *const c_char, outer: *const c_char, no_outer: c_int) -> c_int;
        pub fn SSL_ech_get1_status(s: *mut openssl_sys::SSL, inner: *mut *mut c_char, outer: *mut *mut c_char) -> c_int;
        pub fn SSL_ech_get1_retry_config(s: *mut openssl_sys::SSL, ec: *mut *mut u8, eclen: *mut usize) -> c_int;
        pub fn SSL_set_fd(s: *mut openssl_sys::SSL, fd: c_int) -> c_int;
        pub fn SSL_connect(s: *mut openssl_sys::SSL) -> c_int;
        pub fn SSL_read(s: *mut openssl_sys::SSL, buf: *mut c_void, num: c_int) -> c_int;
        pub fn SSL_write(s: *mut openssl_sys::SSL, buf: *const c_void, num: c_int) -> c_int;
        pub fn SSL_get_error(s: *mut openssl_sys::SSL, ret_code: c_int) -> c_int;
        pub fn ech_free(p: *mut c_void);
    }
}

#[cfg(has_ech)]
const OUTER_SNI: &str = "cloudflare-ech.com";

/// 最近一次「该 host 握手被拒后服务器下发的 retry config」——实测可用的当前
/// 有效 config，优先于直供/缓存的过期值。按 host 隔离（不同边缘/服务的 config
/// 可能不同，跨域混用会引入新失败面）。
#[cfg(has_ech)]
static LAST_RETRY: std::sync::Mutex<Option<(String, Vec<u8>)>> = std::sync::Mutex::new(None);
/// Target domains for ECH proxy.
///
/// 必须与 Dart 侧 `lib/core/services/bangumi/bangumi_ech_proxy.dart` 的
/// `echTargetDomains` 保持同一口径: ECH 只作用于 Bangumi 有关的内容。
///
/// 与参考项目 (Bangumi-master) 的差异: 参考版还列了 `lain.bgm.tv` / `next.bgm.tv` /
/// `api.bgm.tv` (均已被 `is_target` 的子域匹配覆盖, 属冗余) 以及
/// `cloudflare-dns.com`。后者在参考工程里是为了让 App 自身的 DoH 查询也过本地代理;
/// 本工程的 DoH 走裸 HttpClient (不经 `HttpOverrides`), 该域名永远不会被路由到本地
/// 代理, 列入等于空转, 故一并去掉以严守「仅 Bangumi」口径。
///
/// 注意: 代理内部获取 ECH 配置所用的 DoH (`CF_DOH_HOST`) 是直接调用
/// `connect_ech`, **不经** `is_target` 判定, 因此去掉 `cloudflare-dns.com`
/// 不影响 ECH 配置的获取。
const TARGETS: &[&str] = &["bgm.tv", "chii.in"];

const CF_DOH_IPS: &[Ipv4Addr] = &[
    Ipv4Addr::new(104, 16, 248, 249),
    Ipv4Addr::new(104, 16, 249, 249),
    Ipv4Addr::new(1, 1, 1, 1),
    Ipv4Addr::new(1, 0, 0, 1),
];
const CF_DOH_HOST: &str = "cloudflare-dns.com";

/// 国内公共 DoH 引导端点：(IP, TLS/SNI 与 Host 头所用域名)。
/// ECH DoH（对 `cloudflare-dns.com` 的 ECH 握手）在部分网络下会被服务端拒绝
/// （`ech required` retry / 证书链校验失败），导致目标域解析不出、整条 ECH 链路
/// 瘫痪。国内加密 DNS 直连稳定，仅用于「解析目标域 A 记录」这一步；拿到 IP 后
/// 仍按原流程对目标域做 ECH 连接（config 来自直供或 GREASE），不改变作用域语义。
const PURE_DOH_ENDPOINTS: &[(Ipv4Addr, &str)] = &[
    (Ipv4Addr::new(223, 5, 5, 5), "dns.alidns.com"),
    (Ipv4Addr::new(223, 6, 6, 6), "dns.alidns.com"),
    (Ipv4Addr::new(120, 53, 53, 53), "doh.pub"),
    (Ipv4Addr::new(1, 12, 12, 12), "doh.pub"),
];

/// Cloudflare IPv4 CIDR ranges: (network_u32, prefix_len)
const CLOUDFLARE_CIDRS: &[(u32, u8)] = &[
    (ipv4_to_u32(104, 16, 0, 0), 13),
    (ipv4_to_u32(104, 24, 0, 0), 14),
    (ipv4_to_u32(172, 64, 0, 0), 13),
    (ipv4_to_u32(131, 0, 72, 0), 22),
    (ipv4_to_u32(162, 158, 0, 0), 15),
    (ipv4_to_u32(190, 93, 240, 0), 20),
    (ipv4_to_u32(188, 114, 96, 0), 20),
    (ipv4_to_u32(197, 234, 240, 0), 22),
    (ipv4_to_u32(198, 41, 128, 0), 17),
    (ipv4_to_u32(173, 245, 48, 0), 20),
    (ipv4_to_u32(103, 21, 244, 0), 22),
    (ipv4_to_u32(103, 22, 200, 0), 22),
    (ipv4_to_u32(103, 31, 4, 0), 22),
    (ipv4_to_u32(141, 101, 64, 0), 18),
    (ipv4_to_u32(108, 162, 192, 0), 18),
];

const fn ipv4_to_u32(a: u8, b: u8, c: u8, d: u8) -> u32 {
    ((a as u32) << 24) | ((b as u32) << 16) | ((c as u32) << 8) | d as u32
}

// ===================== 运行期 ECH 作用域 (NexHub 扩展) =======================

/// 运行期 ECH 作用域
///
/// 参考项目把被接管域名写死成编译期常量 `TARGETS`, 因此只能服务 Bangumi 一个场景。
/// NexHub 有**三套** ECH 作用域 —— ① bangumi 专用 ② 源级(单个源) ③ 应用级 —— 而 ECH
/// 代理是本地 MITM (CA 与监听端口全局唯一, `SERVER`/`HOST_GATES` 均为 static),
/// **不可能为三套各起一个实例**, 只能共用一个引擎实例、由上层决定「哪些请求被路由进来」。
/// 所以「哪些域名被接管」必须能在运行期下发, 这就是本结构存在的理由。
#[derive(Clone, Default)]
struct EchScope {
    /// 额外接管的域名 (含其子域); 与编译期 `TARGETS` 取并集
    targets: Vec<String>,
    /// true = 接管任意域名。
    /// 非 Cloudflare 前置的域即便被接管也拿不到 ECH 收益, 由 `open_backend` 回落到直连,
    /// 因此这里放开不会让「不支持 ECH 的站点」断链。
    allow_any: bool,
    /// 用户自备 ECHConfigList (应用级/源级 `EchConfig.echConfigList` 的「直供」语义)。
    /// Some 时直接使用, 跳过 GREASE 探测 —— 用户显式给了配置就以用户为准。
    ecl: Option<Vec<u8>>,
}

static SCOPE: std::sync::OnceLock<Mutex<EchScope>> = std::sync::OnceLock::new();

/// 运行期 debug 日志开关（语义与存在理由见 `log_d!` 上方的说明）。
///
/// 独立于 `SCOPE` 用原子量，是为了让每条日志只做一次 relaxed load、不进互斥锁 ——
/// 否则「开日志」本身就会把代理的每请求开销放大一个数量级。
static VERBOSE_LOG: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

fn set_verbose(on: bool) {
    VERBOSE_LOG.store(on, std::sync::atomic::Ordering::Relaxed);
}

fn scope() -> &'static Mutex<EchScope> {
    SCOPE.get_or_init(|| Mutex::new(EchScope::default()))
}

/// 下发运行期作用域 (幂等)
///
/// 可以在引擎启动**之前**调用 (先定作用域再起服务), 也可以在运行期调用以热更新
/// (例如用户在设置页里打开/关闭某一套 ECH)。整个结构在同一个锁里替换, 不存在
/// 「targets 已换、allow_any 还没换」的中间态。
///
/// `verbose` 控制 Rust 侧 debug 日志开关 (见 `log_d!` 说明), 与作用域一起下发以省掉
/// 一个 JNI 方法。
fn set_scope(targets: Vec<String>, allow_any: bool, ecl: Option<Vec<u8>>, verbose: bool) {
    set_verbose(verbose);
    let mut s = scope().lock();
    s.targets = targets;
    s.allow_any = allow_any;
    s.ecl = ecl;
    log_d!(
        "set_scope: allow_any={} targets={:?} direct_ecl={} bytes",
        s.allow_any,
        s.targets,
        s.ecl.as_ref().map(|v| v.len()).unwrap_or(0)
    );
}

/// 读取当前作用域快照 (targets, allow_any)
fn scope_snapshot() -> (Vec<String>, bool) {
    let s = scope().lock();
    (s.targets.clone(), s.allow_any)
}

/// 解析上层下发的原始作用域参数并调用 [set_scope]（JNI 与 C API 共用）。
///
/// - `raw_targets`: 英文逗号分隔的域名，允许 `*.` 前缀（会被剥掉），统一小写；
/// - `raw_ecl`: 标准 base64 的 ECHConfigList；空串 = 走 GREASE 探测，非法 base64 忽略本次；
/// - `allow_any` / `verbose`: 语义同 [set_scope]。
fn set_scope_from_raw(raw_targets: &str, raw_ecl: &str, allow_any: bool, verbose: bool) {
    let targets: Vec<String> = raw_targets
        .split(',')
        .map(|s| s.trim().trim_start_matches("*.").to_ascii_lowercase())
        .filter(|s| !s.is_empty())
        .collect();

    let ecl = {
        use base64::Engine as _;
        let t = raw_ecl.trim();
        if t.is_empty() {
            None
        } else {
            match base64::engine::general_purpose::STANDARD.decode(t) {
                Ok(v) if !v.is_empty() => Some(v),
                Ok(_) => None,
                Err(e) => {
                    log_e!("set_scope: ECHConfigList 不是合法 base64, 本次忽略: {e}");
                    None
                }
            }
        }
    };

    set_scope(targets, allow_any, ecl, verbose);
}

/// 某个 host 是否在本次接管范围内
///
/// 语义: `allow_any` 时全部接管; 否则命中「运行期 targets ∪ 编译期 TARGETS」即接管。
/// 子域匹配沿用参考项目的 `host == t || host.ends_with(".{t}")`。
fn is_target(host: &str) -> bool {
    let s = scope().lock();
    if s.allow_any {
        return true;
    }
    let hit = |t: &str| host == t || host.ends_with(&format!(".{t}"));
    s.targets.iter().any(|t| hit(t)) || TARGETS.iter().any(|&t| hit(t))
}

/// 某个 host 是否**被显式点名**接管 (忽略 `allow_any` 的兜底覆盖)
///
/// 存在的理由: 应用级 ECH 打开时 `allow_any=true`, 此时「显式点名的域」(bangumi 专用 /
/// 源级) 与「只是被 allow_any 顺带覆盖的域」必须区分对待 —— 前者总是走 MITM + ECH,
/// 后者在确认「不是 Cloudflare 前置、拿不到 ECH 收益」之后改走原始 TCP 隧道,
/// 既省掉一次本地 TLS 终结, 也不把 MITM 面扩大到全网。
fn is_explicit_target(host: &str) -> bool {
    let s = scope().lock();
    let hit = |t: &str| host == t || host.ends_with(&format!(".{t}"));
    s.targets.iter().any(|t| hit(t)) || TARGETS.iter().any(|&t| hit(t))
}

fn is_cloudflare_ip(ip: Ipv4Addr) -> bool {
    let ip_u = ipv4_to_u32(ip.octets()[0], ip.octets()[1], ip.octets()[2], ip.octets()[3]);
    CLOUDFLARE_CIDRS.iter().any(|&(net, prefix)| {
        let mask = u32::MAX << (32 - prefix);
        (ip_u & mask) == (net & mask)
    })
}

// ============================= CA ===========================================

struct MitmCa {
    ca_key: rcgen::KeyPair,
    ca_cert: rcgen::Certificate,
    cert_cache: Mutex<std::collections::HashMap<String, Arc<rustls::ServerConfig>>>,
}

impl MitmCa {
    fn load_or_generate(ca_dir: &str) -> io::Result<Self> {
        let dir = std::path::PathBuf::from(ca_dir);
        let cp = dir.join("ca.pem");
        let kp = dir.join("ca-key.pem");

        if cp.exists() && kp.exists() {
            let key_pem = std::fs::read_to_string(&kp)
                .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("read ca-key: {e}")))?;
            let key = rcgen::KeyPair::from_pem(&key_pem)
                .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("parse ca-key: {e}")))?;
            let mut p = rcgen::CertificateParams::new(vec!["bangumi-proxy CA".into()])
                .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("ca params: {e}")))?;
            p.is_ca = rcgen::IsCa::Ca(rcgen::BasicConstraints::Unconstrained);
            let cert = p.self_signed(&key)
                .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("self sign: {e}")))?;
            return Ok(Self { ca_cert: cert, ca_key: key, cert_cache: Mutex::new(std::collections::HashMap::new()) });
        }

        let key = rcgen::KeyPair::generate()
            .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("gen key: {e}")))?;
        let mut p = rcgen::CertificateParams::new(vec!["bangumi-proxy CA".into()])
            .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("ca params: {e}")))?;
        p.is_ca = rcgen::IsCa::Ca(rcgen::BasicConstraints::Unconstrained);
        let cert = p.self_signed(&key)
            .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("self sign: {e}")))?;
        std::fs::write(&cp, cert.pem())
            .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("write ca.pem: {e}")))?;
        std::fs::write(&kp, key.serialize_pem())
            .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("write ca-key: {e}")))?;
        Ok(Self { ca_cert: cert, ca_key: key, cert_cache: Mutex::new(std::collections::HashMap::new()) })
    }

    fn server_config(&self, host: &str) -> io::Result<Arc<rustls::ServerConfig>> {
        // 先查缓存, 命中则直接返回
        {
            let cache = self.cert_cache.lock();
            if let Some(cfg) = cache.get(host) {
                return Ok(Arc::clone(cfg));
            }
        }

        // 未命中, 生成新的证书和 config (加锁防止并发生成)
        let mut cache = self.cert_cache.lock();
        // double-check: 另一个线程可能已经生成了
        if let Some(cfg) = cache.get(host) {
            return Ok(Arc::clone(cfg));
        }

        let hk = rcgen::KeyPair::generate()
            .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("gen host key: {e}")))?;
        let mut p = rcgen::CertificateParams::new(vec![host.into()])
            .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("host params: {e}")))?;
        p.distinguished_name = rcgen::DistinguishedName::new();
        let hc = p.signed_by(&hk, &self.ca_cert, &self.ca_key)
            .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("sign host cert: {e}")))?;
        let certs = vec![
            rustls::pki_types::CertificateDer::from(hc.der().to_vec()),
            rustls::pki_types::CertificateDer::from(self.ca_cert.der().to_vec()),
        ];
        let key = rustls::pki_types::PrivatePkcs8KeyDer::from(hk.serialize_der());
        let cfg = rustls::ServerConfig::builder()
            .with_no_client_auth()
            .with_single_cert(certs, rustls::pki_types::PrivateKeyDer::from(key))
            .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("server config: {e}")))?;
        let cfg = Arc::new(cfg);
        cache.insert(host.to_string(), Arc::clone(&cfg));
        Ok(cfg)
    }
}

// ============================= ECH cache ====================================

/// Cache entry with TTL
struct CacheEntry<T: Clone> {
    value: T,
    created: Instant,
}

const IP_CACHE_TTL_SECS: u64 = 300; // 5 minutes
const ECH_CONFIG_TTL_SECS: u64 = 3600; // 1 hour
const CF_IPS_TTL_SECS: u64 = 3600; // 1 hour

/// IP 缓存过期后仍可继续使用的上限 (stale-while-revalidate), 超过则必须同步解析
const IP_STALE_MAX_SECS: u64 = 1800; // 30 minutes

/// ECH config 获取失败后的退避窗口, 避免周期性对全部 CF IP 重复尝试
const ECH_FAIL_BACKOFF_SECS: u64 = 60;

/// 负缓存有效期: 判定某域「非 CF 前置 / 未启用 ECH」后, 该窗口内直接走直连
const DIRECT_NEG_TTL_SECS: u64 = 600;

/// 刷新占用标记: Drop 时把 host 从 refreshing 集合中移除
///
/// 用 RAII 而不是「任务结尾手动 remove」: 后台任务 panic 展开时也会执行 Drop,
/// 否则该 host 会被永久标记为「刷新中」, 之后再也拿不到后台刷新。
struct RefreshingGuard {
    cache: Arc<EchCache>,
    host: String,
}

impl Drop for RefreshingGuard {
    fn drop(&mut self) {
        self.cache.refreshing.lock().remove(&self.host);
    }
}

struct EchCache {
    config: Mutex<Option<CacheEntry<Vec<u8>>>>,
    cf_ips: Mutex<Option<CacheEntry<Vec<Ipv4Addr>>>>,
    ips: Mutex<std::collections::HashMap<String, CacheEntry<Vec<Ipv4Addr>>>>,
    /// 正在后台刷新的 host (单飞, 避免刷新任务堆积)
    refreshing: Mutex<std::collections::HashSet<String>>,
    /// ECH config 上次获取失败时间 (退避用)
    ech_fail_at: Mutex<Option<Instant>>,
    /// 负缓存: 已知「拿不到 Cloudflare 前置 IP / 该域未启用 ECH」的 host → 判定时刻
    ///
    /// 应用级/源级接管会经手大量与 ECH 无关的域。没有负缓存时, 每个请求都要先走一次
    /// 「ECH-DoH 解析 → 发现没有 CF 前置 IP」才知道该走直连, 单次代价是秒级,
    /// 对非 ECH 站点是不可接受的退化。
    direct_until: Mutex<std::collections::HashMap<String, Instant>>,
    /// 「直连目标 IP」：非 Cloudflare 前置的域（签名图片 CDN 等）经 pure DoH
    /// 解析出的 A 记录。直连时按列表逐个带超时尝试——系统 DNS 单 IP + 无超时
    /// 在 IP 不可达时会卡满 OS 的 SYN 超时（~21s），把并发池拖死。
    direct_ips: Mutex<std::collections::HashMap<String, Vec<Ipv4Addr>>>,
    dns_servers: Vec<String>,
    cache_dir: PathBuf,
}

impl EchCache {
    fn new(dns: String, cache_dir: String) -> Self {
        // Parse dns into server list (split on comma for multi-server support)
        let dns_servers: Vec<String> = dns
            .split(',')
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect();
        let cache_path = PathBuf::from(&cache_dir);
        // Ensure cache directory exists
        let _ = std::fs::create_dir_all(&cache_path);

        let mut cache = Self {
            config: Mutex::new(None),
            cf_ips: Mutex::new(None),
            ips: Mutex::new(std::collections::HashMap::new()),
            refreshing: Mutex::new(std::collections::HashSet::new()),
            ech_fail_at: Mutex::new(None),
            direct_until: Mutex::new(std::collections::HashMap::new()),
            direct_ips: Mutex::new(std::collections::HashMap::new()),
            dns_servers,
            cache_dir: cache_path,
        };
        cache.load_persistent_cache();
        cache
    }

    /// Load cached data from disk on startup
    fn load_persistent_cache(&mut self) {
        // Load ECH config
        let ech_path = self.cache_dir.join("ech_config.bin");
        if let Ok(data) = std::fs::read(&ech_path) {
            if !data.is_empty() {
                log_d!("Loaded cached ECH config: {} bytes", data.len());
                *self.config.lock() = Some(CacheEntry { value: data, created: Instant::now() });
            }
        }

        // Load CF DoH IPs
        let cf_path = self.cache_dir.join("cf_ips.txt");
        if let Ok(text) = std::fs::read_to_string(&cf_path) {
            let ips: Vec<Ipv4Addr> = text.lines()
                .filter_map(|l| l.trim().parse().ok())
                .collect();
            if !ips.is_empty() {
                log_d!("Loaded cached CF IPs: {:?}", ips);
                *self.cf_ips.lock() = Some(CacheEntry { value: ips, created: Instant::now() });
            }
        }

        // Load target IPs
        let targets_path = self.cache_dir.join("target_ips.txt");
        if let Ok(text) = std::fs::read_to_string(&targets_path) {
            for line in text.lines() {
                let parts: Vec<&str> = line.splitn(2, '|').collect();
                if parts.len() == 2 {
                    let host = parts[0].to_string();
                    let ips: Vec<Ipv4Addr> = parts[1].split(',')
                        .filter_map(|s| s.trim().parse().ok())
                        .collect();
                    if !ips.is_empty() {
                        log_d!("Loaded cached IPs for {}: {:?}", host, ips);
                        self.ips.lock().insert(host, CacheEntry {
                            value: ips,
                            created: Instant::now(),
                        });
                    }
                }
            }
        }
    }

    /// Save ECH config to disk
    fn save_ech_config(&self, data: &[u8]) {
        let path = self.cache_dir.join("ech_config.bin");
        if let Err(e) = std::fs::write(&path, data) {
            log_e!("Failed to save ECH config: {}", e);
        } else {
            log_d!("Saved ECH config: {} bytes", data.len());
        }
    }

    /// Save CF DoH IPs to disk
    fn save_cf_ips(&self, ips: &[Ipv4Addr]) {
        let path = self.cache_dir.join("cf_ips.txt");
        let text: String = ips.iter()
            .map(|ip| ip.to_string())
            .collect::<Vec<_>>()
            .join("\n");
        if let Err(e) = std::fs::write(&path, text) {
            log_e!("Failed to save CF IPs: {}", e);
        } else {
            log_d!("Saved CF IPs: {:?}", ips);
        }
    }

    /// Save target IPs to disk
    fn save_target_ips(&self) {
        let path = self.cache_dir.join("target_ips.txt");
        let tmp = self.cache_dir.join("target_ips.txt.tmp");
        let cache = self.ips.lock();
        let text: String = cache.iter()
            .map(|(host, entry)| {
                let ips: String = entry.value.iter()
                    .map(|ip| ip.to_string())
                    .collect::<Vec<_>>()
                    .join(",");
                format!("{host}|{ips}")
            })
            .collect::<Vec<_>>()
            .join("\n");
        // 先写临时文件再原子改名: 后台刷新期间 Java 侧 (DoHDNS / getCachedIp) 会读该文件,
        // 直接覆盖写有概率被读到写了一半的内容
        if let Err(e) = std::fs::write(&tmp, text).and_then(|_| std::fs::rename(&tmp, &path)) {
            log_e!("Failed to save target IPs: {}", e);
        } else {
            log_d!("Saved {} target IP entries", cache.len());
        }
    }

    /// Get ECH config, trying all CF DoH IPs
    fn get_ech(&self, host: &str) -> io::Result<Vec<u8>> {
        // 上次该 host 握手被拒后服务器下发的 retry config: 实测可用, 优先于直供
        if let Ok(guard) = LAST_RETRY.lock() {
            if let Some((h, rc)) = guard.as_ref() {
                if h == host {
                    return Ok(rc.clone());
                }
            }
        }
        // 「直供」优先: 上层显式下发了 ECHConfigList 就直接用, 不碰 GREASE 探测,
        // 也不受下面 config 缓存/退避窗口影响 —— 直供是用户意图, 必须即时生效。
        if let Some(ecl) = scope().lock().ecl.clone() {
            if !ecl.is_empty() {
                return Ok(ecl);
            }
        }
        {
            let cache = self.config.lock();
            if let Some(entry) = &*cache {
                if entry.created.elapsed().as_secs() < ECH_CONFIG_TTL_SECS {
                    return Ok(entry.value.clone());
                }
            }
        }

        // 退避窗口内不再对全部 CF IP 重新尝试: 有旧 config 就继续用, 否则快速失败
        {
            let fail_at = *self.ech_fail_at.lock();
            if let Some(at) = fail_at {
                if at.elapsed().as_secs() < ECH_FAIL_BACKOFF_SECS {
                    let cache = self.config.lock();
                    if let Some(entry) = &*cache {
                        log_d!("ECH config refresh in backoff, keep stale config");
                        return Ok(entry.value.clone());
                    }
                    return Err(io::Error::new(io::ErrorKind::Other, "ECH config backoff"));
                }
            }
        }

        for ip in self.cloudflare_doh_ips()? {
            match grease_ech(ip) {
                Ok(c) => {
                    log_d!("ECH GREASE succeeded via {ip}, {} bytes", c.len());
                    self.save_ech_config(&c);
                    *self.config.lock() = Some(CacheEntry { value: c.clone(), created: Instant::now() });
                    *self.ech_fail_at.lock() = None;
                    return Ok(c);
                }
                Err(e) => {
                    log_e!("ECH GREASE via {ip}: {e}");
                }
            }
        }

        *self.ech_fail_at.lock() = Some(Instant::now());
        Err(io::Error::new(io::ErrorKind::Other, "all CF DoH IPs failed for GREASE"))
    }

    /// Get target IPs for a host (multiple, filtered to CF IPs only)
    ///
    /// 未过期直接返回; 过期但在 stale 窗口内先返回旧值并触发后台单飞刷新
    /// (stale-while-revalidate), 只有完全没有可用缓存时才同步解析, 避免刷新阻塞请求。
    fn get_target_ips(self: &Arc<Self>, host: &str) -> io::Result<Vec<Ipv4Addr>> {
        let mut stale: Option<Vec<Ipv4Addr>> = None;
        {
            let cache = self.ips.lock();
            if let Some(entry) = cache.get(host) {
                let age = entry.created.elapsed().as_secs();
                if age < IP_CACHE_TTL_SECS {
                    return Ok(entry.value.clone());
                }
                if age < IP_STALE_MAX_SECS {
                    stale = Some(entry.value.clone());
                }
            }
        }

        if let Some(ips) = stale {
            log_d!("{host} -> {:?} (stale, refresh in background)", ips);
            self.spawn_refresh(host);
            return Ok(ips);
        }

        self.refresh_target_ips(host)
    }

    /// 同步解析并写入缓存
    fn refresh_target_ips(&self, host: &str) -> io::Result<Vec<Ipv4Addr>> {
        let mut ips = match self.resolve_via_ech_multi(host) {
            Ok(ips) => ips,
            Err(e) => {
                // ECH DoH 引导失败（如对 cloudflare-dns.com 的 ECH 握手被服务端
                // 拒绝）不等于目标域不可 ECH：改用国内公共加密 DNS 解析目标域，
                // 拿到真实 CF IP 后仍按原流程 connect_ech（config 走直供/GREASE）。
                log_e!("{host}: ECH DNS failed ({e}); fallback to pure DoH");
                resolve_via_pure_doh(host)?
            }
        };
        let original_len = ips.len();
        let all_ips = ips.clone();
        ips.retain(|ip| is_cloudflare_ip(*ip));
        if ips.is_empty() {
            // 该域解析结果里没有 Cloudflare 前置 IP ⇒ 它不可能从 ECH 受益。
            // 记入负缓存, 让后续请求直接走直连; 同时把 pure DoH 的解析结果
            // 留给直连多 IP 尝试使用（系统 DNS 单 IP + 无超时容易卡满 SYN 超时）。
            self.save_direct_ips(host, all_ips);
            self.mark_direct(host);
            return Err(io::Error::new(io::ErrorKind::Other, "target resolved to no Cloudflare IPs"));
        }
        if ips.len() != original_len {
            log_e!("{host}: ignored non-Cloudflare A records");
        }
        log_d!("{host} -> {:?} (ECH)", ips);
        self.ips.lock().insert(host.to_string(), CacheEntry { value: ips.clone(), created: Instant::now() });
        self.direct_until.lock().remove(host);
        self.save_target_ips();
        Ok(ips)
    }

    /// 记入「该域走直连」负缓存
    fn mark_direct(&self, host: &str) {
        log_d!("{host}: no ECH-capable IP, marked direct for {DIRECT_NEG_TTL_SECS}s");
        self.direct_until
            .lock()
            .insert(host.to_string(), Instant::now());
    }

    /// 记录非 CF 域的直连候选 IP（pure DoH 解析结果），供直连多 IP 尝试。
    fn save_direct_ips(&self, host: &str, ips: Vec<Ipv4Addr>) {
        if ips.is_empty() {
            return;
        }
        log_d!("{host} -> {:?} (direct candidates)", ips);
        self.direct_ips.lock().insert(host.to_string(), ips);
    }

    /// 取非 CF 域的直连候选 IP（无则 None，回退系统 DNS）。
    fn get_direct_ips(&self, host: &str) -> Option<Vec<Ipv4Addr>> {
        self.direct_ips.lock().get(host).cloned()
    }

    /// 该域是否处于「直连」负缓存有效期内
    fn is_known_direct(&self, host: &str) -> bool {
        let mut map = self.direct_until.lock();
        match map.get(host) {
            Some(at) if at.elapsed().as_secs() < DIRECT_NEG_TTL_SECS => true,
            Some(_) => {
                map.remove(host);
                false
            }
            None => false,
        }
    }

    /// 后台单飞刷新: 同一 host 同时只允许一个刷新任务, 避免线程堆积
    fn spawn_refresh(self: &Arc<Self>, host: &str) {
        let cache = Arc::clone(self);
        let host = host.to_string();

        {
            let mut refreshing = cache.refreshing.lock();
            if !refreshing.insert(host.clone()) {
                return;
            }
        }

        // 守卫先建好再起线程: 正常结束或 panic 展开都会把 host 移出 refreshing
        let guard = RefreshingGuard {
            cache: Arc::clone(&cache),
            host: host.clone(),
        };
        thread::spawn(move || {
            let _guard = guard;
            match cache.refresh_target_ips(&host) {
                Ok(_) => {
                    log_d!("async refresh {} ok", host);
                }
                Err(e) => {
                    log_e!("async refresh {} failed: {}", host, e);
                }
            }
        });
    }

    /// Bootstrap CF DoH IPs (resolve via configured DNS, filter to CF range)
    fn cloudflare_doh_ips(&self) -> io::Result<Vec<Ipv4Addr>> {
        {
            let cache = self.cf_ips.lock();
            if let Some(entry) = &*cache {
                if entry.created.elapsed().as_secs() < CF_IPS_TTL_SECS {
                    return Ok(entry.value.clone());
                }
            }
        }

        let mut ips = match self.resolve_multi(CF_DOH_HOST) {
            Ok(ips) if !ips.is_empty() => ips,
            _ => {
                log_e!("{CF_DOH_HOST} bootstrap failed; using built-in IPs");
                CF_DOH_IPS.to_vec()
            }
        };
        let original_len = ips.len();
        ips.retain(|ip| is_cloudflare_ip(*ip));
        if ips.is_empty() {
            ips = CF_DOH_IPS.to_vec();
        }
        if ips.len() != original_len {
            log_e!("{CF_DOH_HOST}: ignored non-Cloudflare A records");
        }
        log_d!("{CF_DOH_HOST} -> {:?} (bootstrap)", ips);
        self.save_cf_ips(&ips);
        *self.cf_ips.lock() = Some(CacheEntry { value: ips.clone(), created: Instant::now() });
        Ok(ips)
    }

    /// Resolve host via all configured DNS servers, return all A records
    fn resolve_multi(&self, host: &str) -> io::Result<Vec<Ipv4Addr>> {
        let mut last_err = None;
        for server in &self.dns_servers {
            if server.starts_with("http") {
                match resolve_doh_multi(server, host) {
                    Ok(ips) if !ips.is_empty() => return Ok(ips),
                    Ok(_) => last_err = Some(io::Error::new(io::ErrorKind::NotFound, "no A")),
                    Err(e) => last_err = Some(e),
                }
            } else {
                match resolve_plain_dns(server, host) {
                    Ok(ip) => return Ok(vec![ip]),
                    Err(e) => last_err = Some(e),
                }
            }
        }
        Err(last_err.unwrap_or_else(|| io::Error::new(io::ErrorKind::NotFound, "no DNS servers")))
    }

    /// Resolve target host via Cloudflare DoH over ECH, return all A records
    fn resolve_via_ech_multi(&self, host: &str) -> io::Result<Vec<Ipv4Addr>> {
        let ecl = self.get_ech(host)?;
        let mut last_err = None;
        for cf_ip in self.cloudflare_doh_ips()? {
            match doh_query_via_ech(host, cf_ip, &ecl) {
                Ok(ips) if !ips.is_empty() => return Ok(ips),
                Ok(_) => {}
                Err(e) => {
                    log_e!("ECH DNS via {cf_ip}: {e}");
                    last_err = Some(e);
                }
            }
        }
        self.invalidate();
        Err(last_err.unwrap_or_else(|| io::Error::new(io::ErrorKind::Other, "all CF IPs failed")))
    }

    fn invalidate(&self) {
        self.config.lock().take();
    }

    fn invalidate_ips(&self, host: &str) {
        self.ips.lock().remove(host);
    }
}

// ============================= DNS =========================================

fn tls_skip() -> openssl::ssl::SslConnector {
    let mut b = openssl::ssl::SslConnector::builder(openssl::ssl::SslMethod::tls_client()).unwrap();
    b.set_verify(openssl::ssl::SslVerifyMode::NONE);
    b.build()
}

fn doh_json(host: &str, path: &str) -> io::Result<String> {
    let tcp = TcpStream::connect(format!("{host}:443"))?;
    tcp.set_read_timeout(Some(std::time::Duration::from_secs(5)))?;
    let mut s = tls_skip()
        .connect(host, tcp)
        .map_err(|e| io::Error::new(io::ErrorKind::Other, e.to_string()))?;
    s.write_all(
        format!("GET {path} HTTP/1.1\r\nHost: {host}\r\nAccept: application/dns-json\r\nConnection: close\r\n\r\n")
            .as_bytes(),
    )?;
    s.flush()?;
    let mut buf = vec![];
    s.read_to_end(&mut buf)?;
    let h = buf
        .windows(4)
        .position(|w| w == b"\r\n\r\n")
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "no hdr"))?;
    String::from_utf8(buf[h + 4..].to_vec()).map_err(|_| io::Error::new(io::ErrorKind::InvalidData, "utf8"))
}

/// Parse all A records from DoH JSON response
fn parse_a_records(json: &str) -> Vec<Ipv4Addr> {
    let Some(answer) = json.find("\"Answer\"") else {
        return Vec::new();
    };
    let mut ips = Vec::new();
    let mut rest = &json[answer..];
    while let Some(data) = rest.find("\"data\":\"") {
        let addr = &rest[data + 8..];
        let Some(end) = addr.find('"') else { break; };
        if let Ok(ip) = addr[..end].parse::<Ipv4Addr>() {
            if !ips.contains(&ip) {
                ips.push(ip);
            }
        }
        rest = &addr[end..];
    }
    ips
}

/// Resolve via DoH server, return all A records
fn resolve_doh_multi(server: &str, host: &str) -> io::Result<Vec<Ipv4Addr>> {
    let base = server.trim_start_matches("https://").trim_start_matches("http://");
    let (doh_host, path) = base
        .split_once('/')
        .map(|(h, p)| (h, format!("/{p}")))
        .unwrap_or((base, "/dns-query".into()));
    let json = doh_json(doh_host, &format!("{path}?name={host}&type=A"))?;
    let ips = parse_a_records(&json);
    if ips.is_empty() {
        Err(io::Error::new(io::ErrorKind::NotFound, "no A"))
    } else {
        Ok(ips)
    }
}

/// 经国内公共 DoH（普通 TLS、IP 直连）解析 [host] 的 A 记录。
/// TLS 一律 `tls_skip`：端点证书与其 SNI/Host 名的匹配不做校验（解析结果不承载
/// 信任，后续 ECH 握手才真正验证 vhost）。不依赖 ECH 能力，no_ech 构建下同样可用。
fn resolve_via_pure_doh(host: &str) -> io::Result<Vec<Ipv4Addr>> {
    let mut last_err: Option<io::Error> = None;
    for (ip, sni) in PURE_DOH_ENDPOINTS {
        let path = format!("/dns-query?name={host}&type=A");
        match doh_query_plain(*ip, sni, &path) {
            Ok(body) => {
                let ips = parse_a_records(&body);
                if !ips.is_empty() {
                    log_d!("pure DoH {ip} ({sni}) -> {host} {:?}", ips);
                    return Ok(ips);
                }
                last_err = Some(io::Error::new(io::ErrorKind::NotFound, "no A"));
            }
            Err(e) => {
                log_e!("pure DoH {ip} ({sni}): {e}");
                last_err = Some(e);
            }
        }
    }
    Err(last_err.unwrap_or_else(|| io::Error::new(io::ErrorKind::Other, "pure DoH all failed")))
}

/// 以 [ip]:443 直连、[sni] 作 SNI 与 Host 头执行 DoH JSON 查询（TLS 跳过验证）。
fn doh_query_plain(ip: Ipv4Addr, sni: &str, path: &str) -> io::Result<String> {
    let tcp = TcpStream::connect_timeout(
        &SocketAddrV4::new(ip, 443).into(),
        std::time::Duration::from_secs(5),
    )?;
    tcp.set_read_timeout(Some(std::time::Duration::from_secs(5)))?;
    tcp.set_write_timeout(Some(std::time::Duration::from_secs(5)))?;
    let mut s = tls_skip()
        .connect(sni, tcp)
        .map_err(|e| io::Error::new(io::ErrorKind::Other, e.to_string()))?;
    s.write_all(
        format!(
            "GET {path} HTTP/1.1\r\nHost: {sni}\r\nAccept: application/dns-json\r\nConnection: close\r\n\r\n"
        )
        .as_bytes(),
    )?;
    s.flush()?;
    let mut buf = vec![];
    s.read_to_end(&mut buf)?;
    let h = buf
        .windows(4)
        .position(|w| w == b"\r\n\r\n")
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "no hdr"))?;
    String::from_utf8(buf[h + 4..].to_vec()).map_err(|_| io::Error::new(io::ErrorKind::InvalidData, "utf8"))
}

/// DoH query over ECH to a specific CF DoH IP, return all A records
#[cfg(has_ech)]
fn doh_query_via_ech(host: &str, cf_ip: Ipv4Addr, ecl: &[u8]) -> io::Result<Vec<Ipv4Addr>> {
    let mut backend = connect_ech(CF_DOH_HOST, cf_ip, ecl)?;
    backend.write_all(
        format!("GET /dns-query?name={host}&type=A HTTP/1.1\r\nHost: {CF_DOH_HOST}\r\nAccept: application/dns-json\r\nConnection: close\r\n\r\n")
            .as_bytes(),
    )?;
    backend.flush()?;
    let mut buf = vec![];
    backend.read_to_end(&mut buf)?;
    let h = buf
        .windows(4)
        .position(|w| w == b"\r\n\r\n")
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "no hdr"))?;
    let ips = parse_a_records(&String::from_utf8_lossy(&buf[h + 4..]));
    if ips.is_empty() {
        Err(io::Error::new(io::ErrorKind::NotFound, "no A"))
    } else {
        Ok(ips)
    }
}

#[cfg(no_ech)]
fn doh_query_via_ech(_host: &str, _cf_ip: Ipv4Addr, _ecl: &[u8]) -> io::Result<Vec<Ipv4Addr>> {
    Err(io::Error::new(io::ErrorKind::Unsupported, "ECH not available"))
}

fn skip_name(data: &[u8], mut p: usize) -> io::Result<usize> {
    loop {
        if p >= data.len() {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "overflow"));
        }
        let b = data[p];
        if b == 0 {
            return Ok(p + 1);
        }
        if b & 0xC0 == 0xC0 {
            return Ok(p + 2);
        }
        p += 1 + b as usize;
    }
}

fn resolve_plain_dns(server: &str, host: &str) -> io::Result<std::net::Ipv4Addr> {
    let txid: u16 = 0x1234;
    let mut pkt = Vec::with_capacity(512);
    pkt.extend_from_slice(&txid.to_be_bytes());
    pkt.extend_from_slice(&[1, 0, 0, 1, 0, 0, 0, 0, 0, 0]);
    for l in host.split('.') {
        pkt.push(l.len() as u8);
        pkt.extend_from_slice(l.as_bytes());
    }
    pkt.push(0);
    pkt.extend_from_slice(&[0, 1, 0, 1]);
    let sock = UdpSocket::bind("0.0.0.0:0")?;
    sock.set_read_timeout(Some(std::time::Duration::from_secs(5)))?;
    sock.send_to(&pkt, format!("{server}:53"))?;
    let mut buf = [0u8; 1024];
    let (n, _) = sock.recv_from(&mut buf)?;
    let r = &buf[..n];
    if r.len() < 12 || u16::from_be_bytes([r[0], r[1]]) != txid {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "bad DNS"));
    }
    let an = u16::from_be_bytes([r[6], r[7]]) as usize;
    let mut p = skip_name(r, 12)? + 4;
    for _ in 0..an {
        p = skip_name(r, p)?;
        if p + 10 > r.len() {
            break;
        }
        let t = u16::from_be_bytes([r[p], r[p + 1]]);
        let rl = u16::from_be_bytes([r[p + 8], r[p + 9]]) as usize;
        p += 10;
        if t == 1 && rl == 4 && p + 4 <= r.len() {
            return Ok(std::net::Ipv4Addr::new(r[p], r[p + 1], r[p + 2], r[p + 3]));
        }
        p += rl;
    }
    Err(io::Error::new(io::ErrorKind::NotFound, "no A"))
}

#[cfg(has_ech)]
fn grease_ech(ip: std::net::Ipv4Addr) -> io::Result<Vec<u8>> {
    let h = std::ffi::CString::new(ip.to_string()).unwrap();
    let s = std::ffi::CString::new(OUTER_SNI).unwrap();
    let (mut c, mut l): (*mut u8, usize) = (std::ptr::null_mut(), 0);
    let r = unsafe { ech_get_retry_config(h.as_ptr(), 443, s.as_ptr(), &mut c, &mut l) };
    if r == 1 && !c.is_null() && l > 0 {
        let d = unsafe { std::slice::from_raw_parts(c, l).to_vec() };
        unsafe { ech_free(c as *mut _) };
        Ok(d)
    } else {
        Err(io::Error::new(io::ErrorKind::Other, "GREASE failed"))
    }
}

#[cfg(no_ech)]
fn grease_ech(_ip: std::net::Ipv4Addr) -> io::Result<Vec<u8>> {
    Err(io::Error::new(
        io::ErrorKind::Unsupported,
        "ECH not available",
    ))
}

// ============================= ECH backend ==================================

static INIT: std::sync::Once = std::sync::Once::new();

/// 共享的 ECH 客户端上下文 (TLS1.3 + 跳过校验), 避免每条连接都新建 SSL_CTX
#[cfg(has_ech)]
static ECH_SSL_CTX: std::sync::OnceLock<openssl::ssl::SslContext> = std::sync::OnceLock::new();

/// 共享的直连客户端上下文
static DIRECT_SSL_CTX: std::sync::OnceLock<openssl::ssl::SslContext> = std::sync::OnceLock::new();

/// 构建客户端 SSL_CTX (ECH 需要 TLS1.3; 均跳过校验, 证书校验由 MITM 自签 CA 链路承担)
fn build_client_ctx(min_tls13: bool) -> io::Result<openssl::ssl::SslContext> {
    INIT.call_once(|| openssl::init());
    let mut ctx = openssl::ssl::SslContext::builder(openssl::ssl::SslMethod::tls_client())
        .map_err(|e| io::Error::new(io::ErrorKind::Other, e.to_string()))?;
    if min_tls13 {
        ctx.set_min_proto_version(Some(openssl::ssl::SslVersion::TLS1_3))
            .map_err(|e| io::Error::new(io::ErrorKind::Other, e.to_string()))?;
    }
    // ALPN：浏览器/curl 的 TLS ClientHello 必带 ALPN（h2,http/1.1）。不带 ALPN 的
    // 客户端会被部分 CDN 的 WAF 判为非浏览器直连而统一返回 403（签名图片 CDN
    // 实测如此）。引擎只转发 HTTP/1.1，故仅声明 http/1.1。
    // 字节格式：len + protocol（ALPN 线格式）。
    ctx.set_alpn_protos(b"\x08http/1.1").ok();
    ctx.set_verify(openssl::ssl::SslVerifyMode::NONE);
    Ok(ctx.build())
}

/// 取共享 SSL_CTX: 首次构建后全程复用, 省掉每条连接重建 SSL_CTX 的开销
/// 注意: 未开启客户端会话缓存 (SSL_SESS_CACHE_CLIENT), 所以不会带来 TLS1.3 会话复用
fn shared_client_ctx(
    cell: &'static std::sync::OnceLock<openssl::ssl::SslContext>,
    min_tls13: bool,
) -> io::Result<&'static openssl::ssl::SslContext> {
    if let Some(ctx) = cell.get() {
        return Ok(ctx);
    }

    let _ = cell.set(build_client_ctx(min_tls13)?);
    cell.get()
        .ok_or_else(|| io::Error::new(io::ErrorKind::Other, "ssl ctx init failed"))
}

/// 校验 ECH 握手所拿到的证书确实签发给目标 host
///
/// ECH 把真实 SNI 藏进内层 ClientHello, 外层 SNI 固定为 `OUTER_SNI`。若目标域所在的
/// Cloudflare zone **其实没启用 ECH**, Cloudflare 就会忽略 ECH 扩展、直接按外层 SNI 路由
/// —— 由于 `connect_ech` 关掉了证书校验, 这次握手依然会「成功」, 但对面是另一个虚拟主机。
/// 不核对证书就会出现「把别人的内容当成本域内容返回」的静默错误, 所以宽作用域下必须核对。
///
/// 只查 SAN: 公信 CA 签发的证书必须带 SAN, CN-only 已废弃。
/// 通配符 `*.example.com` 只覆盖一级子域, 不覆盖 `example.com` 本身 —— 与 RFC 6125 一致。
fn cert_covers_host(ssl: &openssl::ssl::SslRef, host: &str) -> bool {
    let Some(cert) = ssl.peer_certificate() else {
        return false;
    };
    let Some(names) = cert.subject_alt_names() else {
        return false;
    };
    let host = host.to_ascii_lowercase();
    for n in names.iter() {
        let Some(dns) = n.dnsname() else { continue };
        let dns = dns.to_ascii_lowercase();
        if dns == host {
            return true;
        }
        if let Some(suffix) = dns.strip_prefix("*.") {
            if let Some((_, rest)) = host.split_once('.') {
                if rest == suffix {
                    return true;
                }
            }
        }
    }
    false
}

/// 后端连接流：直连走 rust 模式 SslStream；ECH 走 fd BIO 模式（见 FdSslStream）。
enum BackendStream {
    Tls(openssl::ssl::SslStream<TcpStream>),
    Ech(FdSslStream),
}

impl BackendStream {
    fn get_ref(&self) -> &TcpStream {
        match self {
            BackendStream::Tls(s) => s.get_ref(),
            BackendStream::Ech(s) => s.get_ref(),
        }
    }
}

impl std::io::Read for BackendStream {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        match self {
            BackendStream::Tls(s) => std::io::Read::read(s, buf),
            BackendStream::Ech(s) => std::io::Read::read(s, buf),
        }
    }
}

impl std::io::Write for BackendStream {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        match self {
            BackendStream::Tls(s) => std::io::Write::write(s, buf),
            BackendStream::Ech(s) => std::io::Write::write(s, buf),
        }
    }
    fn flush(&mut self) -> io::Result<()> {
        match self {
            BackendStream::Tls(s) => std::io::Write::flush(s),
            BackendStream::Ech(s) => std::io::Write::flush(s),
        }
    }
}

/// fd BIO 模式的 ECH 连接流：socket fd 直接交给 OpenSSL（与 ech_helper.c 的
/// GREASE 探测完全同款）。OpenSSL 4.0.1 的 ECH 在 rust-openssl 的 BIO pair 模式
/// 下处理服务器 retry 会命中未定义函数槽位（ssl_undefined_function），fd 模式
/// 无此问题（GREASE 探测实测能完成与边缘的完整握手交互）。
#[allow(dead_code)]
struct FdSslStream {
    // ssl 永不 drop：对齐 handle_mitm 的 ManuallyDrop 策略，避免在损坏状态下
    // SSL_free 触发 SIGSEGV；进程存续期内的少量内存驻留可接受。
    ssl: std::mem::ManuallyDrop<openssl::ssl::Ssl>,
    tcp: TcpStream,
}

#[allow(dead_code)]
impl FdSslStream {
    fn get_ref(&self) -> &TcpStream {
        &self.tcp
    }
}

#[allow(dead_code)]
impl std::io::Read for FdSslStream {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        let ret = unsafe {
            openssl_sys::SSL_read(
                self.ssl.as_ptr(),
                buf.as_mut_ptr() as *mut std::os::raw::c_void,
                buf.len() as i32,
            )
        };
        if ret > 0 {
            return Ok(ret as usize);
        }
        match unsafe { openssl_sys::SSL_get_error(self.ssl.as_ptr(), ret) } {
            openssl_sys::SSL_ERROR_ZERO_RETURN => Ok(0),
            openssl_sys::SSL_ERROR_WANT_READ | openssl_sys::SSL_ERROR_WANT_WRITE => {
                Err(io::Error::new(io::ErrorKind::WouldBlock, "ssl want read"))
            }
            _ => {
                // 非阻塞 fd 超时/被远端断开：统一视为 EOF，relay 循环自行收尾
                let e = io::Error::last_os_error();
                if e.kind() == io::ErrorKind::WouldBlock {
                    Err(e)
                } else {
                    Ok(0)
                }
            }
        }
    }
}

#[allow(dead_code)]
impl std::io::Write for FdSslStream {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        let ret = unsafe {
            openssl_sys::SSL_write(
                self.ssl.as_ptr(),
                buf.as_ptr() as *const std::os::raw::c_void,
                buf.len() as i32,
            )
        };
        if ret > 0 {
            return Ok(ret as usize);
        }
        match unsafe { openssl_sys::SSL_get_error(self.ssl.as_ptr(), ret) } {
            openssl_sys::SSL_ERROR_WANT_READ | openssl_sys::SSL_ERROR_WANT_WRITE => {
                Err(io::Error::new(io::ErrorKind::WouldBlock, "ssl want write"))
            }
            _ => Err(io::Error::new(io::ErrorKind::Other, "ssl write")),
        }
    }
    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

#[cfg(has_ech)]
fn connect_ech(host: &str, ip: Ipv4Addr, ecl: &[u8]) -> io::Result<FdSslStream> {
    match ech_handshake(host, ip, ecl) {
        Ok(s) => Ok(s),
        Err((e, retry)) => {
            // 服务端不认当前 config 时 (SSL_R_ECH_REQUIRED), 握手 flight 里会带回
            // retry config —— 按服务端下发的配置重连一次。拿不到就原样抛错。
            match retry {
                Some(rc) if rc != ecl => {
                    // 记住该 host 被拒后服务器下发的 retry config: 后续连接直接用,
                    // 省掉每条连接「失败握手 + 重连」的双轮开销。
                    if let Ok(mut g) = LAST_RETRY.lock() {
                        *g = Some((host.to_string(), rc.clone()));
                    }
                    log_d!("ECH retry config from server ({} bytes), retrying {host} -> {ip}", rc.len());
                    ech_handshake(host, ip, &rc).map_err(|(e2, _)| e2)
                }
                _ => Err(e),
            }
        }
    }
}

/// 单次 ECH 握手（fd BIO 模式）。Err 的第二项为服务端下发的 retry config（若有）。
#[cfg(has_ech)]
fn ech_handshake(
    host: &str,
    ip: Ipv4Addr,
    ecl: &[u8],
) -> Result<FdSslStream, (io::Error, Option<Vec<u8>>)> {
    // ECH config 与 server names 仍按连接 (SSL 对象) 设置, 只有 SSL_CTX 复用
    let ssl = openssl::ssl::Ssl::new(shared_client_ctx(&ECH_SSL_CTX, true).map_err(|e| (e, None))?)
        .map_err(|e| (io::Error::new(io::ErrorKind::Other, e.to_string()), None))?;
    if unsafe { ffi::SSL_set1_ech_config_list(ssl.as_ptr(), ecl.as_ptr(), ecl.len()) } != 1 {
        return Err((io::Error::new(io::ErrorKind::Other, "ech_config"), None));
    }
    let ci = std::ffi::CString::new(host).unwrap();
    let co = std::ffi::CString::new(OUTER_SNI).unwrap();
    unsafe { ffi::SSL_ech_set1_server_names(ssl.as_ptr(), ci.as_ptr(), co.as_ptr(), 0) };
    let tcp = TcpStream::connect_timeout(
        &SocketAddrV4::new(ip, 443).into(),
        std::time::Duration::from_secs(10),
    )
    .map_err(|e| (io::Error::new(io::ErrorKind::Other, e.to_string()), None))?;
    tcp.set_nodelay(true).ok();
    // 握手期保持阻塞 + 10s 超时（与 ech_helper.c 的 GREASE 探测一致）
    tcp.set_read_timeout(Some(std::time::Duration::from_secs(10)))
        .map_err(|e| (e, None))?;
    tcp.set_write_timeout(Some(std::time::Duration::from_secs(10)))
        .map_err(|e| (e, None))?;
    // fd BIO 模式: socket fd 直接交给 OpenSSL（勿用 SslStream/BIO pair —— 4.0.1 的
    // ECH 在该模式下处理 retry 会走未定义函数槽位）
    #[cfg(target_os = "windows")]
    let fd: i32 = tcp.as_raw_socket() as i32;
    #[cfg(not(target_os = "windows"))]
    let fd: i32 = {
        use std::os::unix::io::AsRawFd as _;
        tcp.as_raw_fd()
    };
    unsafe { ffi::SSL_set_fd(ssl.as_ptr(), fd) };
    if unsafe { ffi::SSL_connect(ssl.as_ptr()) } != 1 {
        // fd 所有权已移交 OpenSSL: 失败时由本函数返回后的 SSL_free 负责关闭,
        // 故 forget 掉 TcpStream 防止双重 close。
        std::mem::forget(tcp);
        // fd 模式下握手失败后调 get1_retry_config 是安全模式（ech_helper.c 同款）
        let retry = extract_retry_config(ssl.as_ref());
        return Err((io::Error::new(io::ErrorKind::Other, "ech handshake"), retry));
    }
    // 注意: 不要在此调 SSL_ech_get1_status —— OpenSSL 4.0.1 里它对「ECH 已被接受
    // 的连接」会 internal error (ech_ssl_apis.c:178)，把成功的握手误判为失败。
    // v16 真机日志: retry config 重连后 accept 成功, 却在此处被丢弃。

    // 宽作用域 (应用级 / 源级接管) 下必须核对 vhost, 否则「没启用 ECH 的 CF 前置域」
    // 会被静默接到错误的后端。bangumi 专用作用域保持与参考项目完全一致, 不引入新失败面。
    let strict = scope().lock().allow_any;
    if strict && !cert_covers_host(ssl.as_ref(), host) {
        return Err((
            io::Error::new(
                io::ErrorKind::Other,
                format!("ECH vhost mismatch for {host}: server did not honour the inner SNI"),
            ),
            None,
        ));
    }

    // 成功: fd 归 OpenSSL 持续使用; tcp 由 FdSslStream 持有（关闭时收尾）
    Ok(FdSslStream {
        ssl: std::mem::ManuallyDrop::new(ssl),
        tcp,
    })
}

/// 从已失败的握手 SSL 对象里提取服务端下发的 ECH retry config。
/// （v16 起不再使用：在握手中断的 SSL 上调 OpenSSL 4.0 的
/// `SSL_ech_get1_retry_config` 会命中 `ssl_undefined_function` 槽位，
/// 改由 `grease_ech` 用独立连接做 GREASE 探测。）
#[cfg(has_ech)]
#[allow(dead_code)]
fn extract_retry_config(ssl: &openssl::ssl::SslRef) -> Option<Vec<u8>> {
    unsafe {
        let mut ec: *mut u8 = std::ptr::null_mut();
        let mut len: usize = 0;
        if ffi::SSL_ech_get1_retry_config(ssl.as_ptr(), &mut ec, &mut len) == 1
            && !ec.is_null()
            && len > 0
        {
            let v = std::slice::from_raw_parts(ec, len).to_vec();
            ffi::ech_free(ec as *mut std::os::raw::c_void);
            Some(v)
        } else {
            None
        }
    }
}

#[cfg(no_ech)]
fn connect_ech(_host: &str, _ip: Ipv4Addr, _ecl: &[u8]) -> io::Result<openssl::ssl::SslStream<TcpStream>> {
    Err(io::Error::new(io::ErrorKind::Unsupported, "ECH not available"))
}

/// 直连后端：优先用 pure DoH 解析出的候选 IP 列表逐个带超时尝试（首连即失败
/// 的 IP 不会再拖满 OS SYN 超时）；无候选时回退系统 DNS 单次连接。
fn connect_direct_multi(host: &str, cache: &Arc<EchCache>) -> io::Result<BackendStream> {
    if let Some(ips) = cache.get_direct_ips(host) {
        let mut last_err: Option<io::Error> = None;
        for ip in ips {
            match connect_direct(host, Some(ip)) {
                Ok(s) => {
                    log_d!("direct connected: {host} -> {ip}");
                    return Ok(BackendStream::Ech(s));
                }
                Err(e) => {
                    log_e!("direct {host} -> {ip}: {e}");
                    last_err = Some(e);
                }
            }
        }
        if let Some(e) = last_err {
            return Err(e);
        }
    }
    connect_direct(host, None).map(BackendStream::Ech)
}

/// 直连后端（**fd BIO 模式**，与 `openssl s_client` 完全一致）。
///
/// 为什么不用 `SslStream::new`（rust-openssl 的 BIO pair 模式）：部分 CDN 的
/// WAF 会把「BIO pair 客户端」的 TLS/HTTP 行为判为异常直接 403/断连；同一
/// OpenSSL、同一 IP、同一 ALPN 下，`s_client`（fd 模式）实测 200。ECH 路径
/// 早已因此改用 fd 模式，直连同样统一。
fn connect_direct(host: &str, connect_ip: Option<Ipv4Addr>) -> io::Result<FdSslStream> {
    let ssl = openssl::ssl::Ssl::new(shared_client_ctx(&DIRECT_SSL_CTX, false)?)
        .map_err(|e| io::Error::new(io::ErrorKind::Other, e.to_string()))?;
    let host_c = std::ffi::CString::new(host).unwrap();
    unsafe { openssl_sys::SSL_set_tlsext_host_name(ssl.as_ptr(), host_c.as_ptr() as *mut _) };
    let tcp = match connect_ip {
        Some(ip) => TcpStream::connect_timeout(
            &SocketAddrV4::new(ip, 443).into(),
            std::time::Duration::from_secs(15),
        )?,
        None => TcpStream::connect(format!("{host}:443"))?,
    };
    tcp.set_nodelay(true).ok();
    tcp.set_read_timeout(Some(std::time::Duration::from_secs(15)))?;
    tcp.set_write_timeout(Some(std::time::Duration::from_secs(15)))?;
    #[cfg(target_os = "windows")]
    let fd: i32 = tcp.as_raw_socket() as i32;
    #[cfg(not(target_os = "windows"))]
    let fd: i32 = {
        use std::os::unix::io::AsRawFd as _;
        tcp.as_raw_fd()
    };
    unsafe { ffi::SSL_set_fd(ssl.as_ptr(), fd) };
    if unsafe { ffi::SSL_connect(ssl.as_ptr()) } != 1 {
        // fd 所有权已移交 OpenSSL：由 SSL_free 关闭，防止 TcpStream 双重 close。
        std::mem::forget(tcp);
        return Err(io::Error::new(io::ErrorKind::Other, "direct handshake"));
    }
    Ok(FdSslStream {
        ssl: std::mem::ManuallyDrop::new(ssl),
        tcp,
    })
}

/// Open backend connection.
///
/// 目标域: 优先 ECH (多 IP 重试); 一旦「拿不到 ECH 配置 / 解析不到 Cloudflare 前置 IP /
/// 全部 ECH 尝试失败」, **一律回落到直连 TLS**, 而不是把连接判死。非目标域: 直连 TLS。
///
/// 为什么要回落: 应用级 / 源级接管必然经手「Cloudflare 前置但该 zone 没启用 ECH」的域,
/// 这类域用 ECH 永远谈不成。参考项目因为没有回落, 只能靠编译期白名单把这类域挡在门外。
/// 对一组候选 IP 用同一 ECH config 尝试一轮 ECH 连接
fn try_ech_ips(
    host: &str,
    ips: &[Ipv4Addr],
    ecl: &[u8],
    cache: &Arc<EchCache>,
) -> io::Result<BackendStream> {
    let mut last_err: Option<io::Error> = None;
    for ip in ips {
        if !is_cloudflare_ip(*ip) {
            log_e!("{host} -> {ip}: non-CF IP, skipping ECH");
            continue;
        }
        match connect_ech(host, *ip, ecl) {
            Ok(s) => {
                log_d!("ECH connection successful: {host} -> {ip}");
                return Ok(BackendStream::Ech(s));
            }
            Err(e) if is_timeout(&e) => {
                log_e!("ECH {host} -> {ip}: timeout, trying next IP");
                last_err = Some(e);
            }
            Err(e) => {
                log_e!("ECH {host} -> {ip}: {e}");
                cache.invalidate_ips(host);
                last_err = Some(e);
            }
        }
    }
    Err(last_err.unwrap_or_else(|| io::Error::new(io::ErrorKind::Other, "no candidate IP")))
}

/// 经国内公共 DoH 查询 ECHConfigList（live）：先查目标域自己的 HTTPS(SVCB) 记录
/// （zone 专属配置），再查 `cloudflare-ech.com` 的（共享配置）。直供/缓存的 config
/// 被 Cloudflare 轮换后，服务器会以 `ech required` (retry) 拒绝握手 —— 对策就是
/// 每次取 live config 再试。返回 `(config, 来源)`。
fn fetch_live_ech_config(host: &str) -> io::Result<(Vec<u8>, String)> {
    let mut last_err: Option<io::Error> = None;
    for query_host in [host, "cloudflare-ech.com"] {
        let path = format!("/dns-query?name={query_host}&type=HTTPS");
        for (ip, sni) in PURE_DOH_ENDPOINTS {
            let body = match doh_query_plain(*ip, sni, &path) {
                Ok(b) => b,
                Err(e) => {
                    log_e!("live ECH via {ip} ({sni}) [{query_host}]: {e}");
                    last_err = Some(e);
                    continue;
                }
            };
            if let Some(ecl) = extract_ech_from_svcb(&body) {
                log_d!(
                    "live ECHConfigList ({query_host}) via {ip} ({sni}): {} bytes",
                    ecl.len()
                );
                return Ok((ecl, query_host.to_string()));
            }
            log_d!("live ECH [{query_host}] via {ip}: no ech param in HTTPS RR");
            last_err = Some(io::Error::new(io::ErrorKind::NotFound, "no ech param"));
        }
    }
    Err(last_err.unwrap_or_else(|| io::Error::new(io::ErrorKind::Other, "live ECH all failed")))
}

/// 从 DoH JSON（HTTPS/SVCB 记录）的 data 文本里提取 `ech=` 参数并 base64 解码。
/// 字符集兼容标准与 URL-safe 两种 base64（含 `-_` 与 padding `=`），解码宽容处理。
fn extract_ech_from_svcb(json: &str) -> Option<Vec<u8>> {
    use base64::Engine as _;
    const NEEDLE: &str = "ech=";
    let mut search_from = 0usize;
    while let Some(pos) = json[search_from..].find(NEEDLE) {
        let start = search_from + pos + NEEDLE.len();
        let rest = &json[start..];
        let end = rest
            .find(|c: char| {
                !(c.is_ascii_alphanumeric() || c == '+' || c == '/' || c == '-' || c == '_' || c == '=')
            })
            .unwrap_or(rest.len());
        let token = &rest[..end];
        if token.len() >= 8 {
            let clean: String = token.chars().filter(|c| *c != '=').collect();
            let engine = if clean.contains('-') || clean.contains('_') {
                &base64::engine::general_purpose::URL_SAFE_NO_PAD
            } else {
                &base64::engine::general_purpose::STANDARD_NO_PAD
            };
            if let Ok(wire) = engine.decode(clean.as_bytes()) {
                if !wire.is_empty() {
                    return Some(wire);
                }
            }
        }
        search_from = start;
    }
    None
}

fn open_backend(host: &str, cache: &Arc<EchCache>) -> io::Result<BackendStream> {
    if !is_target(host) {
        return connect_direct_multi(host, cache);
    }

    // 负缓存命中: 已知该域拿不到 ECH 收益, 直接直连, 省掉一次 DoH + ECH 探测
    if cache.is_known_direct(host) {
        log_d!("open_backend: {host} known direct, skip ECH");
        return connect_direct_multi(host, cache);
    }

    let ecl = match cache.get_ech(host) {
        Ok(ecl) => ecl,
        Err(e) => {
            // 故意不调 cache.invalidate(): get_ech 内部已按 ECH_FAIL_BACKOFF_SECS 退避,
            // 若在这里清空缓存, 每个请求都会重新打一遍全部 CF DoH IP
            log_d!("open_backend: {host} ECH config unavailable ({e}), fallback to direct");
            return connect_direct_multi(host, cache);
        }
    };

    let ips = match cache.get_target_ips(host) {
        Ok(ips) => ips,
        Err(e) => {
            log_d!("open_backend: {host} no ECH-capable IP ({e}), fallback to direct");
            return connect_direct_multi(host, cache);
        }
    };

    let mut last_err: Option<io::Error> = None;
    match try_ech_ips(host, &ips, &ecl, cache) {
        Ok(s) => return Ok(s),
        Err(e) => last_err = Some(e),
    }

    // 直供 config 被服务端拒绝（`ech required` retry）时，向同一边缘做 GREASE 探测
    // （ech_helper.c 的独立连接）拿该边缘下发的 retry config，再用它重试一轮。
    // 注意：国内 DoH 的 HTTPS 记录会剥离 ech 参数（实测），DNS 查询路线不可用。
    let mut retry_cfg: Option<Vec<u8>> = None;
    for ip in &ips {
        match grease_ech(*ip) {
            Ok(c) => {
                log_d!("GREASE retry config from {ip}: {} bytes", c.len());
                retry_cfg = Some(c);
                break;
            }
            Err(e) => {
                log_e!("GREASE probe {ip}: {e}");
            }
        }
    }
    match retry_cfg {
        Some(live) if live != ecl => {
            log_d!("retry ECH with server retry config ({} bytes)", live.len());
            match try_ech_ips(host, &ips, &live, cache) {
                Ok(s) => return Ok(s),
                Err(e) => last_err = Some(e),
            }
        }
        _ => {}
    }

    // 全部 ECH 尝试失败 → 直连兜底。SNI 会暴露, 但这类域本来就无法通过 ECH 隐藏,
    // 「能连上」优先于「连不上但保持沉默」。
    log_e!(
        "open_backend: all ECH attempts failed for {host}, fallback to direct ({})",
        last_err
            .as_ref()
            .map(|e| e.to_string())
            .unwrap_or_else(|| "no candidate IP".to_string())
    );
    connect_direct_multi(host, cache)
}

fn is_timeout(err: &io::Error) -> bool {
    err.kind() == io::ErrorKind::TimedOut
}

/// POLLIN/POLLHUP/POLLERR 任一事件都视为「该 fd 需处理」
// ============================= Proxy Handler ================================

fn handle_connect(client: &mut TcpStream, host: &str, cache: &Arc<EchCache>, ca: &MitmCa) {
    if !is_target(host) {
        // Non-target domains should never reach here if proxySelector is correct
        // But as safety measure, just close connection silently
        log_d!("handle_connect: rejecting non-target host: {}", host);
        return;
    }

    // 只被 allow_any 顺带覆盖、且已确认「不是 Cloudflare 前置」的域: 走原始 TCP 隧道。
    // 这类域不可能有 ECH 收益, 再 MITM 一遍只是白白多一次本地 TLS 终结 (还多一份自签证书)。
    if !is_explicit_target(host) && cache.is_known_direct(host) {
        log_d!("handle_connect: {host} known non-ECH, using raw tunnel");
        handle_tunnel(client, host, cache);
        return;
    }

    handle_mitm(client, host, cache, ca);
}

fn handle_tunnel(client: &mut TcpStream, host: &str, _cache: &EchCache) {
    let connect_addr = format!("{host}:443");
    let mut remote = match TcpStream::connect(&connect_addr) {
        Ok(s) => s,
        Err(_) => return,
    };
    remote.set_nodelay(true).ok();
    remote.set_read_timeout(Some(std::time::Duration::from_secs(60))).ok();
    remote.set_write_timeout(Some(std::time::Duration::from_secs(60))).ok();
    let _ = client.write_all(b"HTTP/1.1 200 Connection Established\r\n\r\n");
    let _ = client.flush();

    client.set_nonblocking(true).ok();
    remote.set_nonblocking(true).ok();
    let relay_start = Instant::now();
    let relay_timeout = std::time::Duration::from_secs(300);
    let mut last_activity = Instant::now();
    let idle_timeout = std::time::Duration::from_secs(60);
    let mut buf = vec![0u8; 32768]; // 32KB buffer

    loop {
        if relay_start.elapsed() > relay_timeout {
            log_e!("handle_tunnel: relay timeout for {}", host);
            break;
        }
        if last_activity.elapsed() > idle_timeout {
            log_d!("handle_tunnel: idle timeout for {}", host);
            break;
        }

        let mut activity = false;
        match client.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => {
                let _ = remote.write_all(&buf[..n]);
                let _ = remote.flush();
                last_activity = Instant::now();
                activity = true;
            }
            Err(ref e) if e.kind() == io::ErrorKind::WouldBlock => {}
            Err(_) => break,
        }
        match remote.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => {
                let _ = client.write_all(&buf[..n]);
                let _ = client.flush();
                last_activity = Instant::now();
                activity = true;
            }
            Err(ref e) if e.kind() == io::ErrorKind::WouldBlock => {}
            Err(_) => break,
        }
        if !activity {
            thread::sleep(std::time::Duration::from_millis(5));
        }
    }
    client.set_nonblocking(false).ok();
}

/// 在 [haystack] 中查找 [needle] 首次出现的位置。
fn find_subslice(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    if needle.is_empty() || haystack.len() < needle.len() {
        return None;
    }
    haystack.windows(needle.len()).position(|w| w == needle)
}

/// 规范化 HTTP/1.1 请求头（TLS 解密后的明文首块）：
/// - 头名 Title-Case（RFC 9110 规范形态；Dart HttpClient 默认发小写）；
/// - `Host` 提到首位（RFC 9112 规范形态）；
/// - 删除原 `Connection` 并强制 `Connection: close`——每连接一个请求，使每个
///   请求各自的「首请求头重写」都能生效（keep-alive 复用连接时后续请求头
///   无法再被重写）。
/// 请求行与头值保持原样；无法识别为请求头时原样返回。
fn rewrite_http_head(head: &[u8]) -> Vec<u8> {
    let Ok(text) = std::str::from_utf8(head) else {
        return head.to_vec();
    };
    let mut lines = text.split("\r\n");
    let request_line = match lines.next() {
        Some(l)
            if l.starts_with("GET ")
                || l.starts_with("POST ")
                || l.starts_with("HEAD ")
                || l.starts_with("PUT ")
                || l.starts_with("DELETE ")
                || l.starts_with("OPTIONS ") =>
        {
            l
        }
        _ => return head.to_vec(),
    };
    let mut host: Option<String> = None;
    let mut others: Vec<String> = Vec::new();
    for line in lines {
        if line.is_empty() {
            break;
        }
        let Some(colon) = line.find(':') else {
            others.push(line.to_string());
            continue;
        };
        let name = line[..colon].trim();
        let value = line[colon + 1..].trim_start();
        let lower = name.to_ascii_lowercase();
        if lower == "host" {
            host = Some(value.to_string());
        } else if lower == "connection" {
            // 丢弃：统一强制 close
        } else {
            let mut canonical = String::with_capacity(name.len());
            for (i, seg) in name.split('-').enumerate() {
                if i > 0 {
                    canonical.push('-');
                }
                let mut chars = seg.chars();
                if let Some(first) = chars.next() {
                    canonical.push(first.to_ascii_uppercase());
                    canonical.extend(chars);
                }
            }
            others.push(format!("{canonical}: {value}"));
        }
    }
    let mut out = String::with_capacity(text.len() + 24);
    out.push_str(request_line);
    out.push_str("\r\n");
    if let Some(h) = host {
        out.push_str("Host: ");
        out.push_str(&h);
        out.push_str("\r\n");
    }
    for l in others {
        out.push_str(&l);
        out.push_str("\r\n");
    }
    out.push_str("Connection: close\r\n\r\n");
    out.into_bytes()
}

fn handle_mitm(client: &mut TcpStream, host: &str, cache: &Arc<EchCache>, ca: &MitmCa) {
    log_d!("handle_mitm: {}", host);

    // Per-host 有界并发: 限制同时进行的 open_backend + TLS 握手数量, relay 阶段不持名额
    let mut browser_tls;
    let mut backend;
    {
        let host_gate = get_host_gate(host);
        let _host_permit = host_gate.acquire();

        backend = match open_backend(host, cache) {
            Ok(s) => s,
            Err(e) => { log_e!("handle_mitm: open_backend failed: {}", e); return; },
        };
        if let Err(e) = client.write_all(b"HTTP/1.1 200 Connection Established\r\n\r\n") {
            log_e!("handle_mitm: write 200 failed: {}", e);
            return;
        }
        if let Err(e) = client.flush() {
            log_e!("handle_mitm: flush 200 failed: {}", e);
            return;
        }
        log_d!("handle_mitm: sent 200, waiting for client TLS");
        let config = match ca.server_config(host) {
            Ok(c) => c,
            Err(e) => { log_e!("handle_mitm: server_config failed: {}", e); return; },
        };
        let mut acceptor = rustls::server::Acceptor::default();
        let mut tcp = match client.try_clone() {
            Ok(c) => c,
            Err(e) => { log_e!("handle_mitm: try_clone failed: {}", e); return; },
        };
        let accept_start = Instant::now();
        let accept_timeout = std::time::Duration::from_secs(15);
        let accepted = loop {
            if accept_start.elapsed() > accept_timeout {
                log_e!("handle_mitm: TLS accept timed out for {}", host);
                return;
            }
            match acceptor.accept() {
                Ok(Some(a)) => {
                    log_d!("handle_mitm: TLS accept succeeded");
                    break a;
                },
                Ok(None) => {
                    let mut buf = [0u8; 4096];
                    match tcp.read(&mut buf) {
                        Ok(0) => {
                            log_e!("handle_mitm: client closed before TLS");
                            return;
                        },
                        Ok(n) => {
                            log_d!("handle_mitm: read {} bytes from client", n);
                            if acceptor.read_tls(&mut &buf[..n]).is_err() {
                                log_e!("handle_mitm: read_tls failed");
                                return;
                            }
                        }
                        Err(ref e) if e.kind() == io::ErrorKind::WouldBlock => {
                            thread::sleep(std::time::Duration::from_millis(10));
                            continue;
                        }
                        Err(e) => {
                            log_e!("handle_mitm: client read error: {}", e);
                            return;
                        }
                    }
                }
                Err((_, e)) => {
                    log_e!("handle_mitm: acceptor error: {:?}", e);
                    return;
                }
            }
        };
        browser_tls = match accepted.into_connection(config) {
            Ok(c) => { log_d!("handle_mitm: into_connection OK"); c },
            Err((_, e)) => { log_e!("handle_mitm: into_connection failed: {:?}", e); return; },
        };
    }
    // _host_permit 已释放, 不同连接可以并行 relay
    // 使用 ManuallyDrop 包装 backend: 当连接异常断开时 (如 App 挂后台后 OS 杀掉 TCP),
    // 直接跳过 OpenSSL 的 drop (SSL_free), 避免在已损坏的内部状态上触发 SIGSEGV。
    // 改为手动关闭底层 TCP socket 来释放资源。
    log_d!("handle_mitm: starting data relay for {}", host);
    client.set_nonblocking(true).ok();
    backend.get_ref().set_nonblocking(true).ok();
    let tcp_raw = tcp_raw_handle(backend.get_ref());
    let mut backend = std::mem::ManuallyDrop::new(backend);
    let mut bs = rustls::Stream::new(&mut browser_tls, &mut *client);
    let relay_start = Instant::now();
    let relay_timeout = std::time::Duration::from_secs(300); // 5 min max for large images
    let mut last_activity = Instant::now();
    let idle_timeout = std::time::Duration::from_secs(60); // 60s idle timeout
    let mut buf = vec![0u8; 32768]; // Larger buffer for images (32KB)
    let mut backend_error = false;
    // 首个 HTTP 请求头重写状态：Dart 的 HttpClient 发出的请求是「Host 非首位 +
    // 头名小写」形态，部分 CDN（签名图片 CDN 等）的 WAF 按该形态指纹直接 403；
    // 浏览器/curl 是 Host 首位 + Title-Case。这里在转发前把首请求头规范化，
    // 并强制 Connection: close（每连接一个请求 ⇒ 后续请求各自的首头都会被重写）。
    let mut head_done = false;
    let mut head_buf: Vec<u8> = Vec::new();

    loop {
        // Check timeouts
        if relay_start.elapsed() > relay_timeout {
            log_e!("handle_mitm: relay timeout for {}", host);
            break;
        }
        if last_activity.elapsed() > idle_timeout {
            log_d!("handle_mitm: idle timeout for {}", host);
            break;
        }

        let mut activity = false;
        match bs.read(&mut buf) {
            Ok(0) => {
                log_d!("handle_mitm: client EOF");
                break;
            }
            Ok(n) => {
                if !head_done {
                    head_buf.extend_from_slice(&buf[..n]);
                    if let Some(pos) = find_subslice(&head_buf, b"\r\n\r\n") {
                        let head = &head_buf[..pos + 4];
                        let rest: Vec<u8> = head_buf[pos + 4..].to_vec();
                        let rewritten = rewrite_http_head(head);
                        // 诊断：转发到上游的完整请求头（与 curl 200 头逐行对比用）
                        if let Ok(s) = std::str::from_utf8(&rewritten) {
                            log_d!("forward head >>>\n{}", s);
                        }
                        if let Err(e) = backend.write_all(&rewritten) {
                            log_e!("handle_mitm: backend write (head) failed: {}", e);
                            backend_error = true;
                            break;
                        }
                        if !rest.is_empty() {
                            if let Err(e) = backend.write_all(&rest) {
                                log_e!("handle_mitm: backend write (body) failed: {}", e);
                                backend_error = true;
                                break;
                            }
                        }
                        head_done = true;
                        head_buf.clear();
                    } else if head_buf.len() > 16384 {
                        // 头异常大：原样转发（不阻断业务）
                        if let Err(e) = backend.write_all(&head_buf) {
                            log_e!("handle_mitm: backend write (oversized head) failed: {}", e);
                            backend_error = true;
                            break;
                        }
                        head_done = true;
                        head_buf.clear();
                    }
                } else if let Err(e) = backend.write_all(&buf[..n]) {
                    log_e!("handle_mitm: backend write failed: {}", e);
                    backend_error = true;
                    break;
                }
                backend.flush().ok();
                last_activity = Instant::now();
                activity = true;
            }
            Err(ref e) if e.kind() == io::ErrorKind::WouldBlock => {}
            Err(ref e) if e.kind() == io::ErrorKind::TimedOut => {
                break;
            }
            Err(e) => {
                log_e!("handle_mitm: client read error: {}", e);
                break;
            }
        }
        match backend.read(&mut buf) {
            Ok(0) => {
                log_d!("handle_mitm: backend EOF");
                break;
            }
            Ok(n) => {
                if let Err(e) = bs.write_all(&buf[..n]) {
                    log_e!("handle_mitm: client write failed: {}", e);
                    break;
                }
                bs.flush().ok();
                last_activity = Instant::now();
                activity = true;
            }
            Err(ref e) if e.kind() == io::ErrorKind::WouldBlock => {}
            Err(ref e) if e.kind() == io::ErrorKind::TimedOut => {
                backend_error = true;
                break;
            }
            Err(e) => {
                log_e!("handle_mitm: backend read error: {}", e);
                backend_error = true;
                break;
            }
        }
        // Only sleep if no activity
        if !activity {
            thread::sleep(std::time::Duration::from_millis(5));
        }
    }
    // 后端连接出错时, 跳过 OpenSSL drop (SSL_free/SSL_shutdown 会访问已损坏的状态导致 SIGSEGV)
    // 直接关闭底层 TCP socket 释放 fd
    if backend_error {
        unsafe { close_raw_handle(tcp_raw); }
        // ManuallyDrop 不会调用 SSL_free, 避免 crash
    } else {
        // 正常结束: 必须真正释放 backend (SSL_free + 关闭 fd)
        // 否则每次成功请求都会泄漏一个 fd 和 SSL 缓冲 (ManuallyDrop 不会自动 drop)
        unsafe { std::mem::ManuallyDrop::drop(&mut backend); }
    }
    log_d!("handle_mitm: relay done for {}", host);
    client.set_nonblocking(false).ok();
}

fn handle_client(mut client: TcpStream, cache: Arc<EchCache>, ca: Arc<MitmCa>) {
    // 转发以请求头/小包为主, 关闭 Nagle 避免额外延迟
    client.set_nodelay(true).ok();
    let peer = client.peer_addr().map(|a| a.to_string()).unwrap_or_default();
    let client_clone = match client.try_clone() {
        Ok(c) => c,
        Err(e) => { log_e!("[{}] try_clone failed: {}", peer, e); return; },
    };
    let mut reader = BufReader::new(client_clone);
    let mut req_line = String::new();
    if reader.read_line(&mut req_line).is_err() || req_line.is_empty() {
        return;
    }
    let req_line = req_line.trim_end().to_string();
    let mut headers = Vec::new();
    loop {
        let mut l = String::new();
        if reader.read_line(&mut l).is_err() || l == "\r\n" || l.is_empty() {
            break;
        }
        headers.push(l.trim_end().to_string());
    }
    let method = req_line.split_whitespace().next().unwrap_or("");
    if method.eq_ignore_ascii_case("CONNECT") {
        let target = req_line.split_whitespace().nth(1).unwrap_or("");
        let (host, _) = target
            .rsplit_once(':')
            .map(|(h, p)| (h, p.parse().unwrap_or(443)))
            .unwrap_or((target, 443));
        log_d!("[{}] CONNECT {}", peer, host);
        handle_connect(&mut client, host, &cache, &ca);
    } else {
        let parts: Vec<&str> = req_line.split_whitespace().collect();
        let (method, uri) = (parts[0], parts[1]);
        let host = if uri.starts_with("http://") {
            uri[7..].split('/').next().unwrap_or("").split(':').next().unwrap_or("")
        } else {
            headers
                .iter()
                .find(|h| h.to_lowercase().starts_with("host:"))
                .and_then(|h| h.split(':').nth(1))
                .map(str::trim)
                .unwrap_or("")
        };
        let path = if uri.starts_with("http://") {
            match &uri[7..].find('/') {
                Some(i) => &uri[7 + i..],
                None => "/",
            }
        } else {
            uri
        };
        log_d!("[{}] {} {} (host={})", peer, method, path, host);

        // 跳过 localhost/127.0.0.1 请求 (Expo dev tools 等)
        if host == "localhost" || host == "127.0.0.1" {
            log_d!("[{}] skipping localhost request", peer);
            return;
        }

        // 跳过非 TARGETS 的域名
        if !is_target(host) {
            log_d!("[{}] skipping non-target host: {}", peer, host);
            return;
        }

        let cl: usize = headers
            .iter()
            .find(|h| h.to_lowercase().starts_with("content-length:"))
            .and_then(|h| h.split(':').nth(1))
            .and_then(|v| v.trim().parse().ok())
            .unwrap_or(0);
        let mut body = vec![0u8; cl];
        if cl > 0 {
            let _ = reader.read_exact(&mut body);
        }
        let mut backend = match open_backend(host, &cache) {
            Ok(s) => s,
            Err(e) => {
                log_e!("open_backend failed for {}: {}", host, e);
                return;
            }
        };
        let _ = backend.write_all(format!("{method} {path} HTTP/1.1\r\n").as_bytes());
        for h in &headers {
            let l = h.to_lowercase();
            if l.starts_with("proxy-connection:") || l.starts_with("proxy-authenticate:") {
                continue;
            }
            let _ = backend.write_all(format!("{h}\r\n").as_bytes());
        }
        let _ = backend.write_all(b"\r\n");
        if !body.is_empty() {
            let _ = backend.write_all(&body);
        }
        let _ = backend.flush();
        client.set_nonblocking(true).ok();
        backend.get_ref().set_nonblocking(true).ok();
        let tcp_raw = tcp_raw_handle(backend.get_ref());
        let mut backend = std::mem::ManuallyDrop::new(backend);
        let mut backend_error = false;
        loop {
            let mut buf = [0u8; 8192];
            match client.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => {
                    if backend.write_all(&buf[..n]).is_err() { backend_error = true; break; }
                    backend.flush().ok();
                }
                Err(ref e) if e.kind() == io::ErrorKind::WouldBlock => {}
                Err(_) => break,
            }
            match backend.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => {
                    let _ = client.write_all(&buf[..n]);
                    let _ = client.flush();
                }
                Err(ref e) if e.kind() == io::ErrorKind::WouldBlock => {}
                Err(_) => { backend_error = true; break; }
            }
            thread::sleep(std::time::Duration::from_millis(1));
        }
        if backend_error {
            // 异常路径: 跳过 SSL_free, 仅关闭底层 fd
            unsafe { close_raw_handle(tcp_raw); }
        } else {
            // 正常路径: 真正释放, 避免 fd 与 SSL 缓冲泄漏
            unsafe { std::mem::ManuallyDrop::drop(&mut backend); }
        }
        client.set_nonblocking(false).ok();
    }
}

// ============================= Proxy Server =================================

struct ProxyServer {
    port: u16,
    running: Arc<Mutex<bool>>,
    listener_handle: Option<std::thread::JoinHandle<()>>,
}

/// 最大并发连接数, 防止图片瀑布流打爆低端机
const MAX_CONCURRENT: u32 = 64;

/// 并发贴顶告警上次输出时间 (按 60s 节流)
static LAST_LIMIT_WARN: Mutex<Option<Instant>> = Mutex::new(None);

static SERVER: Mutex<Option<ProxyServer>> = Mutex::new(None);
static CA_PEM: std::sync::OnceLock<String> = std::sync::OnceLock::new();

/// 同一 host 允许同时进行「建连 + 握手」的最大连接数
///
/// 同一 host 的新连接被完全串行握手时, 一屏同域图片的队尾请求很容易超过客户端读超时;
/// 这里改为有界并发: 保留「避免集中握手风暴」的保护, 同时把排队时长收敛在上限内。
const HOST_HANDSHAKE_CONCURRENCY: usize = 3;

/// 每 host 建连闸门 (parking_lot 0.12 无 Semaphore, 用 Mutex + Condvar 自建)
struct HostGate {
    in_flight: Mutex<usize>,
    cond: Condvar,
}

impl HostGate {
    fn new() -> Self {
        Self {
            in_flight: Mutex::new(0),
            cond: Condvar::new(),
        }
    }

    /// 申请一个建连名额, 满则等待
    fn acquire(&self) -> HostPermit<'_> {
        let mut in_flight = self.in_flight.lock();
        while *in_flight >= HOST_HANDSHAKE_CONCURRENCY {
            self.cond.wait(&mut in_flight);
        }
        *in_flight += 1;
        HostPermit(self)
    }
}

/// 建连名额 RAII: 释放时归还名额并唤醒等待者 (保证提前 return 也会释放)
struct HostPermit<'a>(&'a HostGate);

impl Drop for HostPermit<'_> {
    fn drop(&mut self) {
        let mut in_flight = self.0.in_flight.lock();
        *in_flight = in_flight.saturating_sub(1);
        self.0.cond.notify_one();
    }
}

static HOST_GATES: Mutex<Option<std::collections::HashMap<String, Arc<HostGate>>>> = Mutex::new(None);

fn get_host_gate(host: &str) -> Arc<HostGate> {
    let mut map = HOST_GATES.lock();
    let map = map.get_or_insert_with(std::collections::HashMap::new);
    map.entry(host.to_string())
        .or_insert_with(|| Arc::new(HostGate::new()))
        .clone()
}

fn start_server(port: u16, dns: &str, ca_dir: &str, cache_dir: &str) -> u16 {
    log_d!("start_server: port={}, dns={}, ca_dir={}, cache_dir={}", port, dns, ca_dir, cache_dir);

    let addr = format!("127.0.0.1:{port}");
    let ca = match MitmCa::load_or_generate(ca_dir) {
        Ok(ca) => Arc::new(ca),
        Err(e) => {
            log_e!("Failed to load/generate CA: {}", e);
            return 0;
        }
    };
    let pem = ca.ca_cert.pem();
    log_d!("CA PEM length={}, first 80 chars: {}", pem.len(), &pem[..80.min(pem.len())]);
    let _ = CA_PEM.set(pem);
    let cache = Arc::new(EchCache::new(dns.to_string(), cache_dir.to_string()));
    let cache_clone = cache.clone();
    let running = Arc::new(Mutex::new(true));
    let running_clone = running.clone();

    let listener = match TcpListener::bind(&addr) {
        Ok(l) => {
            log_d!("Main listener bound to {}", addr);
            l
        }
        Err(e) => {
            log_e!("Failed to bind {}: {}", addr, e);
            return 0;
        }
    };
    let actual_port = listener.local_addr().unwrap().port();
    log_d!("Main proxy port: {}", actual_port);

    let active_count = Arc::new(Mutex::new(0u32));

    let handle = thread::spawn(move || {
        listener.set_nonblocking(true).ok();
        while *running_clone.lock() {
            // 检查并发数
            let current = *active_count.lock();
            if current >= MAX_CONCURRENT {
                // 贴顶日志按 60s 节流, 便于真机观测是否长期占满
                {
                    let mut last = LAST_LIMIT_WARN.lock();
                    let should_log = last.map(|t| t.elapsed().as_secs() >= 60).unwrap_or(true);
                    if should_log {
                        *last = Some(Instant::now());
                        log_e!("connection limit reached ({}), delaying accept", MAX_CONCURRENT);
                    }
                }
                thread::sleep(std::time::Duration::from_millis(20));
                continue;
            }

            match listener.accept() {
                Ok((client, _)) => {
                    *active_count.lock() += 1;
                    let (c, ca, ac) = (Arc::clone(&cache_clone), Arc::clone(&ca), Arc::clone(&active_count));
                    thread::spawn(move || {
                        let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                            handle_client(client, c, ca);
                        }));
                        *ac.lock() -= 1;
                    });
                }
                Err(ref e) if e.kind() == io::ErrorKind::WouldBlock => {
                    thread::sleep(std::time::Duration::from_millis(10));
                }
                Err(e) => {
                    log_e!("Main accept error: {}", e);
                    break;
                }
            }
        }
        log_d!("Main listener thread exiting");
    });

    *SERVER.lock() = Some(ProxyServer {
        port: actual_port,
        running,
        listener_handle: Some(handle),
    });

    // 预热: 只预热「编译期 TARGETS ∪ 运行期 targets」。
    // allow_any 下不预热 —— 对「任意域」预热等于先把全网探一遍, 既慢又无意义:
    // 到底哪个域会被访问只有上层知道, 等它真的来了再解析 (带负缓存) 更划算。
    let cache_for_resolve = cache.clone();
    let (extra_targets, allow_any) = scope_snapshot();
    thread::spawn(move || {
        if allow_any {
            log_d!("scope allow_any=true, skip target warmup");
            return;
        }
        let hosts: Vec<String> = TARGETS
            .iter()
            .map(|s| s.to_string())
            .chain(extra_targets.into_iter())
            .filter(|h| h != "cloudflare-dns.com")
            .collect();
        for host in hosts {
            match cache_for_resolve.get_target_ips(&host) {
                Ok(ips) => {
                    log_d!("Pre-resolved {host} -> {ips:?}");
                }
                Err(e) => {
                    log_e!("Pre-resolve failed for {host}: {e}");
                }
            }
        }
    });

    log_d!("Server started: proxy={}", actual_port);
    actual_port
}

fn stop_server() {
    if let Some(server) = SERVER.lock().take() {
        *server.running.lock() = false;
        // 等待 listener 线程退出
        if let Some(handle) = server.listener_handle {
            let _ = handle.join();
        }
        log_d!("Server stopped");
    }
}

fn get_status() -> (bool, u16) {
    match &*SERVER.lock() {
        Some(server) => (*server.running.lock(), server.port),
        None => (false, 0),
    }
}

/// 真实存活检测: 检查 SERVER 存在 + running 标志为 true + listener 线程未退出
fn is_proxy_alive() -> bool {
    match &*SERVER.lock() {
        Some(server) => {
            if !*server.running.lock() {
                return false;
            }
            // listener_handle.is_finished() == true 意味着线程已退出 (被 OS kill 或异常)
            if let Some(handle) = &server.listener_handle {
                !handle.is_finished()
            } else {
                false
            }
        }
        None => false,
    }
}

// ============================= JNI ==========================================
//
// 仅 Android 目标编译：jni crate 及其符号只在 target_os = "android" 下存在。
// 桌面端 (Windows/Linux/macOS) 走文件末尾的 C API (`ech_*`)，经 dart:ffi 调用。

#[cfg(target_os = "android")]
#[allow(non_snake_case)]
pub mod android {
    use super::*;
    use jni::JNIEnv;
    use jni::objects::{JClass, JString};
    use jni::sys::jint;

    #[no_mangle]
    pub extern "C" fn Java_com_nexhub_app_EchProxyNative_startProxy(
        mut env: JNIEnv,
        _class: JClass,
        port: jint,
        dns: JString,
        ca_dir: JString,
        cache_dir: JString,
    ) -> jint {
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let dns: String = env.get_string(&dns).unwrap().into();
            let ca_dir: String = env.get_string(&ca_dir).unwrap().into();
            let cache_dir: String = env.get_string(&cache_dir).unwrap().into();
            start_server(port as u16, &dns, &ca_dir, &cache_dir) as jint
        }));
        match result {
            Ok(port) => port,
            Err(e) => {
                log_e!("startProxy panicked: {:?}", e);
                0
            }
        }
    }

    #[no_mangle]
    pub extern "C" fn Java_com_nexhub_app_EchProxyNative_stopProxy(
        _env: JNIEnv,
        _class: JClass,
    ) {
        let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            stop_server();
        }));
    }

    #[no_mangle]
    pub extern "C" fn Java_com_nexhub_app_EchProxyNative_getCaPem<'local>(
        mut env: JNIEnv<'local>,
        _class: JClass<'local>,
    ) -> jni::objects::JString<'local> {
        let pem = CA_PEM.get().map(|s| s.as_str()).unwrap_or("");
        env.new_string(pem).unwrap()
    }

    #[no_mangle]
    pub extern "C" fn Java_com_nexhub_app_EchProxyNative_isAlive(
        _env: JNIEnv,
        _class: JClass,
    ) -> jni::sys::jboolean {
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            is_proxy_alive()
        }));
        match result {
            Ok(alive) => if alive { 1 } else { 0 },
            Err(_) => 0,
        }
    }

    /// 下发运行期 ECH 作用域 (NexHub 扩展; 参考项目没有这个入口)
    ///
    /// 参数:
    /// - `targets_csv`: 额外接管的域名, 英文逗号分隔; 空串 = 只接管编译期 `TARGETS`
    /// - `ech_config_list_b64`: 用户自备 ECHConfigList (标准 base64); 空串 = 走 GREASE 探测
    /// - `allow_any`: 非 0 = 接管任意域 (应用级 / 源级接管打开时为非 0)
    /// - `verbose_log`: 非 0 = 打开 Rust 侧 debug 日志 (见 `log_d!`)
    ///
    /// 之所以做成**独立符号**而不是给 `startProxy` 加形参: 不改动既有 JNI 签名,
    /// 上层既能「先 setScope 再 startProxy」, 也能在引擎运行中热更新作用域。
    #[no_mangle]
    pub extern "C" fn Java_com_nexhub_app_EchProxyNative_setScope(
        mut env: JNIEnv,
        _class: JClass,
        targets_csv: JString,
        ech_config_list_b64: JString,
        allow_any: jni::sys::jboolean,
        verbose_log: jni::sys::jboolean,
    ) {
        let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let raw_targets: String = env
                .get_string(&targets_csv)
                .map(|s| s.into())
                .unwrap_or_default();
            let raw_ecl: String = env
                .get_string(&ech_config_list_b64)
                .map(|s| s.into())
                .unwrap_or_default();
            set_scope_from_raw(&raw_targets, &raw_ecl, allow_any != 0, verbose_log != 0);
        }));
    }
}

// ============================= C API (桌面端 FFI) ============================
//
// 供 Flutter 桌面 (Windows/Linux/macOS) 经 dart:ffi 调用的纯 C ABI 导出，
// 语义与 android 模块的 JNI 入口一一对应 (startProxy/stopProxy/isAlive/setScope)。
// 两端都会编译本模块，互不影响；Android 侧 Dart 仍走 MethodChannel→JNI。

/// 启动本地 ECH 代理，返回实际监听端口（`port <= 0` 由 native 分配随机端口；失败返回 0）。
///
/// # Safety
/// `dns` / `ca_dir` / `cache_dir` 必须是合法的 NUL 结尾 UTF-8 C 字符串（可为 NULL，按空串处理）。
#[no_mangle]
pub unsafe extern "C" fn ech_start_proxy(
    port: i32,
    dns: *const std::os::raw::c_char,
    ca_dir: *const std::os::raw::c_char,
    cache_dir: *const std::os::raw::c_char,
) -> i32 {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| unsafe {
        let dns = cstr_or_empty(dns);
        let ca_dir = cstr_or_empty(ca_dir);
        let cache_dir = cstr_or_empty(cache_dir);
        start_server(port.max(0) as u16, &dns, &ca_dir, &cache_dir) as i32
    }));
    match result {
        Ok(p) => p,
        Err(e) => {
            log_e!("ech_start_proxy panicked: {e:?}");
            0
        }
    }
}

/// 停止本地 ECH 代理（幂等）。
///
/// # Safety
/// 无入参约束；可在任何线程调用。
#[no_mangle]
pub unsafe extern "C" fn ech_stop_proxy() {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(stop_server));
}

/// listener 线程是否真实存活（1 = 存活，0 = 不在运行或已死）。
#[no_mangle]
pub extern "C" fn ech_is_alive() -> i32 {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(is_proxy_alive));
    match result {
        Ok(alive) => i32::from(alive),
        Err(_) => 0,
    }
}

/// 下发运行期 ECH 作用域（可在 [ech_start_proxy] 之前或运行中调用，语义同 JNI `setScope`）。
///
/// # Safety
/// `targets_csv` / `ech_config_list_b64` 必须是合法的 NUL 结尾 UTF-8 C 字符串（可为 NULL）。
#[no_mangle]
pub unsafe extern "C" fn ech_set_scope(
    targets_csv: *const std::os::raw::c_char,
    ech_config_list_b64: *const std::os::raw::c_char,
    allow_any: i32,
    verbose_log: i32,
) {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| unsafe {
        let raw_targets = cstr_or_empty(targets_csv);
        let raw_ecl = cstr_or_empty(ech_config_list_b64);
        set_scope_from_raw(&raw_targets, &raw_ecl, allow_any != 0, verbose_log != 0);
    }));
}

/// 读取自签 MITM CA 的 PEM（未生成前为空串）。返回值可用 [ech_free_cstring] 释放，
/// 也可只读不释放（静态空串分支不可释放）。
///
/// # Safety
/// 返回的指针在进程生命周期内有效（静态空串）或到 [ech_free_cstring] 为止（动态拷贝）；
/// 调用方不得写入。
#[no_mangle]
pub extern "C" fn ech_get_ca_pem() -> *const std::os::raw::c_char {
    match CA_PEM.get() {
        Some(pem) => match std::ffi::CString::new(pem.as_str()) {
            // CA pem 内部不会含 NUL；一旦含（理论不可能）返回静态空串，绝不悬垂。
            Ok(c) => c.into_raw(),
            Err(_) => EMPTY_CSTR.as_ptr() as *const std::os::raw::c_char,
        },
        None => EMPTY_CSTR.as_ptr() as *const std::os::raw::c_char,
    }
}

/// 释放 [ech_get_ca_pem] 返回的字符串（配对使用；静态空串指针自动跳过）。
///
/// # Safety
/// `p` 必须来自 [ech_get_ca_pem] 且只释放一次。
#[no_mangle]
pub unsafe extern "C" fn ech_free_cstring(p: *mut std::os::raw::c_char) {
    if !p.is_null() && !std::ptr::eq(p, EMPTY_CSTR.as_ptr() as *const std::os::raw::c_char) {
        unsafe { drop(std::ffi::CString::from_raw(p)) };
    }
}

/// 合法空 C 字符串（NUL 结尾），进程级静态，替代 const 构造 CString 的不可行方案。
static EMPTY_CSTR: &[u8] = b"\0";

/// # Safety
/// `p` 必须为合法 NUL 结尾字符串指针（可为 NULL）。
unsafe fn cstr_or_empty(p: *const std::os::raw::c_char) -> String {
    if p.is_null() {
        String::new()
    } else {
        unsafe { std::ffi::CStr::from_ptr(p).to_string_lossy().into_owned() }
    }
}
