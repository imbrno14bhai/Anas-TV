import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;

class AnasTvApp extends StatefulWidget {
  const AnasTvApp({super.key});

  @override
  State<AnasTvApp> createState() => _AnasTvAppState();
}

class _AnasTvAppState extends State<AnasTvApp> {
  static const _deviceChannel = MethodChannel('anas_tv/device');
  bool _isTv = false;

  @override
  void initState() {
    super.initState();
    PaintingBinding.instance.imageCache.maximumSize = 400;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 64 << 20;
    _detectDeviceMode();
  }

  Future<void> _detectDeviceMode() async {
    try {
      final tv = await _deviceChannel.invokeMethod<bool>('isTv') ?? false;
      if (!mounted) return;
      setState(() => _isTv = tv);
      if (tv) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.portraitUp,
        ]);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'AnasTV',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFE65312),
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF050505),
        ),
        home: AnasTvHomePage(isTv: _isTv),
      );
}

class TvChannel {
  final int id, categoryId, languageId, order, channelNumber;
  final String name, logo, fallbackLogo, category, language;
  final bool hd;
  final int? epgChannelId;
  final String? epgChannelName;
  final Map<String, dynamic>? raw;

  const TvChannel({
    required this.id,
    required this.name,
    required this.logo,
    required this.fallbackLogo,
    required this.categoryId,
    required this.category,
    required this.languageId,
    required this.language,
    required this.hd,
    required this.order,
    this.channelNumber = 0,
    this.epgChannelId,
    this.epgChannelName,
    this.raw,
  });

  TvChannel copyWith({
    int? channelNumber,
    String? logo,
    String? fallbackLogo,
    int? epgChannelId,
    String? epgChannelName,
  }) {
    return TvChannel(
      id: id,
      name: name,
      logo: logo ?? this.logo,
      fallbackLogo: fallbackLogo ?? this.fallbackLogo,
      categoryId: categoryId,
      category: category,
      languageId: languageId,
      language: language,
      hd: hd,
      order: order,
      channelNumber: channelNumber ?? this.channelNumber,
      epgChannelId: epgChannelId ?? this.epgChannelId,
      epgChannelName: epgChannelName ?? this.epgChannelName,
      raw: raw,
    );
  }
}

class _ChannelMatcher {
  static final RegExp _nonAlnum = RegExp(r'[^a-z0-9\s]+');
  static final RegExp _multiSpace = RegExp(r'\s+');
  static final RegExp _bracketed = RegExp(r'[\(\[\{].*?[\)\]\}]');
  static final RegExp _sonySportsTen = RegExp(r'\bsony\s+sports?\s+ten\b');
  static final RegExp _sonySportsNum = RegExp(r'\bsony\s+sports?\s+(?=[1-5]\b)');
  static final RegExp _sonyEnt = RegExp(r'\bsony\s+entertainment\s+television\b');
  static final RegExp _joinedDigits = RegExp(r'\b(ten|max|sports|sab|wah|mix|pal|pix)(\d+)\b');

  static String exactKey(String name) {
    var s = name.toLowerCase().replaceAll('&', ' and ');
    s = s.replaceAll(_bracketed, ' ');
    s = s.replaceAll(_nonAlnum, ' ').replaceAll(_multiSpace, ' ').trim();
    s = s.replaceAllMapped(_joinedDigits, (m) => '${m[1]} ${m[2]}');
    s = s.replaceAll(_sonySportsTen, 'sony ten');
    s = s.replaceAll(_sonySportsNum, 'sony ten ');
    s = s.replaceAll(_sonyEnt, 'set');
    if (s == 'sab tv' || s == 'sab') {
      s = 'sony sab';
    } else if (s.startsWith('sab tv ')) {
      s = s.replaceFirst('sab tv ', 'sony sab ');
    } else if (s.startsWith('sab ')) {
      s = s.replaceFirst('sab ', 'sony sab ');
    }
    return s.replaceAll(_multiSpace, ' ').trim();
  }

  static String sdEquivKey(String name) {
    final exact = exactKey(name);
    if (exact.isEmpty) return '';
    final tokens = exact.split(' ').where((t) =>
        t.isNotEmpty &&
        t != 'sd' &&
        t != 'streamx' &&
        t != 'sonyliv' &&
        t != 'backup');
    final joined = tokens.join(' ').trim();
    return joined.isNotEmpty ? joined : exact;
  }

  static String langNeutralSdKey(String name) {
    final exact = exactKey(name);
    if (exact.isEmpty) return '';
    final tokens = exact.split(' ').where((t) =>
        t.isNotEmpty &&
        t != 'hindi' &&
        t != 'sd' &&
        t != 'streamx' &&
        t != 'sonyliv' &&
        t != 'backup');
    final joined = tokens.join(' ').trim();
    return joined.isNotEmpty ? joined : exact;
  }

  static String baseKey(String name) {
    final exact = exactKey(name);
    if (exact.isEmpty) return '';
    final tokens = exact.split(' ').where((t) =>
        t.isNotEmpty &&
        t != 'sd' &&
        t != 'hd' &&
        t != 'fhd' &&
        t != 'uhd' &&
        t != '4k' &&
        t != '1080p' &&
        t != '720p' &&
        t != 'hevc' &&
        t != 'streamx' &&
        t != 'sonyliv' &&
        t != 'backup');
    final joined = tokens.join(' ').trim();
    return joined.isNotEmpty ? joined : exact;
  }

  static String langNeutralBaseKey(String name) {
    final exact = exactKey(name);
    if (exact.isEmpty) return '';
    final tokens = exact.split(' ').where((t) =>
        t.isNotEmpty &&
        t != 'hindi' &&
        t != 'sd' &&
        t != 'hd' &&
        t != 'fhd' &&
        t != 'uhd' &&
        t != '4k' &&
        t != '1080p' &&
        t != '720p' &&
        t != 'hevc' &&
        t != 'streamx' &&
        t != 'sonyliv' &&
        t != 'backup');
    final joined = tokens.join(' ').trim();
    return joined.isNotEmpty ? joined : exact;
  }
}

Map<String, String> _imageHeadersFor(String url) {
  final uri = Uri.tryParse(url);
  final host = uri?.host.toLowerCase() ?? '';
  if (host.contains('jio.com')) {
    return const {'User-Agent': StreamResolver.defaultUa};
  }
  if (host.contains('wikia.nocookie.net')) {
    return const {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 13; TV) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
      'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
      'Referer': 'https://logos.fandom.com/',
    };
  }
  return const {
    'User-Agent': 'Dalvik/2.1.0 (Linux; U; Android 13; Android TV Build/TQ3A.230805.001)',
    'Accept': '*/*',
  };
}

String? _digitFromKeyEvent(KeyEvent event) {
  final l = event.logicalKey;
  final p = event.physicalKey;
  if (l == LogicalKeyboardKey.digit0 ||
      l == LogicalKeyboardKey.numpad0 ||
      p == PhysicalKeyboardKey.digit0 ||
      p == PhysicalKeyboardKey.numpad0) return '0';
  if (l == LogicalKeyboardKey.digit1 ||
      l == LogicalKeyboardKey.numpad1 ||
      p == PhysicalKeyboardKey.digit1 ||
      p == PhysicalKeyboardKey.numpad1) return '1';
  if (l == LogicalKeyboardKey.digit2 ||
      l == LogicalKeyboardKey.numpad2 ||
      p == PhysicalKeyboardKey.digit2 ||
      p == PhysicalKeyboardKey.numpad2) return '2';
  if (l == LogicalKeyboardKey.digit3 ||
      l == LogicalKeyboardKey.numpad3 ||
      p == PhysicalKeyboardKey.digit3 ||
      p == PhysicalKeyboardKey.numpad3) return '3';
  if (l == LogicalKeyboardKey.digit4 ||
      l == LogicalKeyboardKey.numpad4 ||
      p == PhysicalKeyboardKey.digit4 ||
      p == PhysicalKeyboardKey.numpad4) return '4';
  if (l == LogicalKeyboardKey.digit5 ||
      l == LogicalKeyboardKey.numpad5 ||
      p == PhysicalKeyboardKey.digit5 ||
      p == PhysicalKeyboardKey.numpad5) return '5';
  if (l == LogicalKeyboardKey.digit6 ||
      l == LogicalKeyboardKey.numpad6 ||
      p == PhysicalKeyboardKey.digit6 ||
      p == PhysicalKeyboardKey.numpad6) return '6';
  if (l == LogicalKeyboardKey.digit7 ||
      l == LogicalKeyboardKey.numpad7 ||
      p == PhysicalKeyboardKey.digit7 ||
      p == PhysicalKeyboardKey.numpad7) return '7';
  if (l == LogicalKeyboardKey.digit8 ||
      l == LogicalKeyboardKey.numpad8 ||
      p == PhysicalKeyboardKey.digit8 ||
      p == PhysicalKeyboardKey.numpad8) return '8';
  if (l == LogicalKeyboardKey.digit9 ||
      l == LogicalKeyboardKey.numpad9 ||
      p == PhysicalKeyboardKey.digit9 ||
      p == PhysicalKeyboardKey.numpad9) return '9';
  return null;
}

int? _resolveChannelIndexByNumber(List<TvChannel> channels, int number) {
  if (channels.isEmpty || number < 1) return null;
  final exactIdx = channels.indexWhere((c) => c.channelNumber == number);
  if (exactIdx >= 0) return exactIdx;
  if (number < 101) {
    final offsetIdx = channels.indexWhere((c) => c.channelNumber == 100 + number);
    if (offsetIdx >= 0) return offsetIdx;
  }
  if (channels.every((c) => c.channelNumber <= 0)) {
    if (number >= 101) {
      final idx = number - 101;
      return (idx >= 0 && idx < channels.length) ? idx : null;
    }
    final idx = number - 1;
    return (idx >= 0 && idx < channels.length) ? idx : null;
  }
  return null;
}

class _StbChannelNumberOsd extends StatelessWidget {
  final String digits;
  final String? previewChannelName;
  final String? errorMessage;

  const _StbChannelNumberOsd({
    required this.digits,
    this.previewChannelName,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    final text = errorMessage ?? (digits.isEmpty ? '' : digits);
    if (text.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              errorMessage != null ? errorMessage! : digits,
              style: const TextStyle(
                fontFamily: 'Anton',
                color: Colors.white,
                fontSize: 32,
                height: 1.05,
                letterSpacing: 1.8,
              ),
            ),
            if (errorMessage == null && (previewChannelName ?? '').isNotEmpty) ...[
              const SizedBox(height: 3),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  previewChannelName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Anton',
                    color: Color(0xFFD6DCE8),
                    fontSize: 13.5,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ResolvedPlayback {
  final String streamUrl;
  final Map<String, String> headers;
  final String drmLicenseUrl;
  final Map<String, String> clearKeys;

  const ResolvedPlayback({
    required this.streamUrl,
    required this.headers,
    required this.drmLicenseUrl,
    required this.clearKeys,
  });
}

class StreamResolver {
  static const defaultUa =
      'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Mobile Safari/537.36';

  static Future<ResolvedPlayback> resolve(TvChannel channel) async {
    final raw = channel.raw ?? <String, dynamic>{};
    final rawChannelId = (raw['channel_id'] ?? raw['channelId'] ?? channel.id).toString().trim();
    final requestHeaders = <String, String>{
      'User-Agent': (raw['user_agent'] ?? raw['userAgent'] ?? defaultUa).toString(),
      'Accept': '*/*',
    };
    final referer = (raw['referer'] ?? raw['referrer'] ?? '').toString().trim();
    final origin = (raw['origin'] ?? '').toString().trim();
    final cookie = (raw['cookie'] ?? '').toString().trim();
    if (referer.isNotEmpty) requestHeaders['Referer'] = referer;
    if (origin.isNotEmpty) requestHeaders['Origin'] = origin;
    if (cookie.isNotEmpty) requestHeaders['Cookie'] = cookie;

    String firstValue(List<String> keys) {
      for (final key in keys) {
        final value = (raw[key] ?? '').toString().trim();
        if (value.isNotEmpty && value != 'null') return value;
      }
      return '';
    }

    bool isHttp(String value) => value.startsWith('https://') || value.startsWith('http://');

    final direct = firstValue([
      'ready_to_use_link',
      'url',
      'stream_url',
      'm3u8_url',
      'mpd_url',
      'play_url',
      'playUrl',
      'channel_url',
    ]);

    String? streamUrl;
    String drmLicenseUrl = '';
    final clearKeys = <String, String>{};

    if (channel.id < 1000000 && rawChannelId.isNotEmpty) {
      try {
        final response = await http
            .get(
              Uri.https('eliteapiyash.streamxlive.workers.dev', '/', {'id': rawChannelId}),
              headers: const {'User-Agent': defaultUa},
            )
            .timeout(const Duration(seconds: 20));
        final body = response.body.replaceFirst('\uFEFF', '').trim();
        if (response.statusCode != 200) {
          throw Exception('Resolver HTTP ${response.statusCode}');
        }
        if (body.isEmpty) throw Exception('Resolver returned an empty response.');

        dynamic decoded;
        try {
          decoded = jsonDecode(_extractJsonValue(body));
        } on FormatException {
          if (isHttp(body.split('|').first.trim())) {
            decoded = {'ready_to_use_link': body, 'status': 'success'};
          } else {
            throw Exception('Resolver JSON invalid');
          }
        }

        final Map<String, dynamic> data =
            decoded is List && decoded.isNotEmpty && decoded.first is Map
                ? Map<String, dynamic>.from(decoded.first as Map)
                : decoded is Map
                    ? Map<String, dynamic>.from(decoded as Map)
                    : <String, dynamic>{};

        if ((data['status'] ?? 'success').toString().toLowerCase() == 'error') {
          throw Exception((data['message'] ?? 'Stream resolve failed').toString());
        }

        drmLicenseUrl =
            _firstFromMap(data, ['widevine_license_url', 'drm_license_url', 'license_url']) ?? '';

        final ready = (data['ready_to_use_link'] ?? '').toString().trim();
        if (ready.isNotEmpty) {
          final parts = ready.split('|');
          final candidate = parts.first.trim();
          if (isHttp(candidate)) streamUrl = candidate;
          for (final entry in parts.skip(1).join('&').split('&')) {
            final idx = entry.indexOf('=');
            if (idx <= 0) continue;
            final k = entry.substring(0, idx).trim().toLowerCase();
            final v = Uri.decodeComponent(entry.substring(idx + 1).trim());
            if (k == 'cookie' && v.isNotEmpty) requestHeaders['Cookie'] = v;
            if ((k == 'user-agent' || k == 'useragent') && v.isNotEmpty) {
              requestHeaders['User-Agent'] = v;
            }
            if (k == 'drmlicense' && v.isNotEmpty && !v.startsWith('http')) {
              clearKeys.addAll(_parseClearKeys(v));
            }
          }
        }

        streamUrl ??= _firstFromMap(data, ['mpd_url', 'm3u8_url', 'url', 'stream_url']);

        final responseCookie = (data['cookie'] ?? '').toString().trim();
        if (responseCookie.isNotEmpty) requestHeaders['Cookie'] = responseCookie;

        final responseUa = (data['user_agent'] ?? data['userAgent'] ?? '').toString().trim();
        if (responseUa.isNotEmpty) requestHeaders['User-Agent'] = responseUa;

        for (final field in [
          'all_keys',
          'allKeys',
          'drmLicense',
          'drm_license',
          'clearkey',
          'clearKey',
          'keys',
          'key',
        ]) {
          if (data[field] != null) clearKeys.addAll(_parseClearKeys(data[field]));
        }
      } catch (e) {
        if (!isHttp(direct.split('|').first.trim())) {
          rethrow;
        }
      }
    }

    if (streamUrl == null && direct.isNotEmpty) {
      final parts = direct.split('|');
      final candidate = parts.first.trim();
      if (isHttp(candidate)) streamUrl = candidate;
      for (final entry in parts.skip(1).join('&').split('&')) {
        final idx = entry.indexOf('=');
        if (idx <= 0) continue;
        final k = entry.substring(0, idx).trim().toLowerCase();
        final v = Uri.decodeComponent(entry.substring(idx + 1).trim());
        if (k == 'cookie' && v.isNotEmpty) requestHeaders['Cookie'] = v;
        if (k == 'drmlicense' && v.isNotEmpty && !v.startsWith('http')) {
          clearKeys.addAll(_parseClearKeys(v));
        }
      }
    }

    if (clearKeys.isEmpty) {
      for (final field in ['all_keys', 'drmLicense', 'drm_license', 'clearkey', 'clearKey', 'key']) {
        if (raw[field] != null) clearKeys.addAll(_parseClearKeys(raw[field]));
      }
    }

    if (streamUrl == null || !isHttp(streamUrl)) {
      throw Exception('Valid stream URL nahi mila');
    }

    return ResolvedPlayback(
      streamUrl: streamUrl,
      headers: requestHeaders,
      drmLicenseUrl: drmLicenseUrl,
      clearKeys: clearKeys,
    );
  }

  static Map<String, String> _parseClearKeys(dynamic raw) {
    final pairs = <String, String>{};
    if (raw is Map) {
      final kid = (raw['kid'] ?? raw['key_id'] ?? '').toString().trim();
      final key = (raw['key'] ?? raw['k'] ?? '').toString().trim();
      if (kid.isNotEmpty && key.isNotEmpty) {
        pairs[kid] = key;
      } else {
        raw.forEach((k, v) {
          final ks = k.toString().trim(), vs = v.toString().trim();
          if (ks.isNotEmpty && vs.isNotEmpty) pairs[ks] = vs;
        });
      }
    } else if (raw is List) {
      for (final item in raw) {
        pairs.addAll(_parseClearKeys(item));
      }
    } else if (raw != null) {
      final str = raw.toString().trim();
      if (str.isNotEmpty && !str.startsWith('http')) {
        for (final seg in str.split(RegExp(r'[,;\n]'))) {
          final parts = seg.trim().split(':');
          if (parts.length == 2 && parts[0].trim().isNotEmpty && parts[1].trim().isNotEmpty) {
            pairs[parts[0].trim()] = parts[1].trim();
          }
        }
      }
    }
    return pairs;
  }

  static String _extractJsonValue(String raw) {
    final text = raw.replaceFirst('\uFEFF', '').trimLeft();
    final arrayStart = text.indexOf('[');
    final objectStart = text.indexOf('{');
    int start;
    if (arrayStart < 0) {
      start = objectStart;
    } else if (objectStart < 0) {
      start = arrayStart;
    } else {
      start = arrayStart < objectStart ? arrayStart : objectStart;
    }
    if (start < 0) return text;

    final opening = text[start];
    final closing = opening == '[' ? ']' : '}';
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < text.length; i++) {
      final ch = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch == r'\') {
          escaped = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      if (ch == '"') {
        inString = true;
      } else if (ch == opening) {
        depth++;
      } else if (ch == closing) {
        depth--;
        if (depth == 0) return text.substring(start, i + 1);
      }
    }
    throw const FormatException('Resolver JSON value is incomplete.');
  }

  static String? _firstFromMap(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = (data[key] ?? '').toString().trim();
      if (value.startsWith('https://') || value.startsWith('http://')) return value;
    }
    return null;
  }
}

class _BrandCircularLoader extends StatelessWidget {
  final double size;

  const _BrandCircularLoader({this.size = 76});

  @override
  Widget build(BuildContext context) {
    final innerSize = size - 14;
    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            RepaintBoundary(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: innerSize * 0.86,
                    height: innerSize * 0.86,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SvgPicture.asset(
                    'assets/images/jio_logo.svg',
                    width: innerSize,
                    height: innerSize,
                    fit: BoxFit.contain,
                  ),
                ],
              ),
            ),
            RepaintBoundary(
              child: SizedBox(
                width: size,
                height: size,
                child: const CircularProgressIndicator(
                  strokeWidth: 3.2,
                  color: Color(0xFFE65312),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AnasTvHomePage extends StatefulWidget {
  final bool isTv;

  const AnasTvHomePage({super.key, required this.isTv});

  @override
  State<AnasTvHomePage> createState() => _AnasTvHomePageState();
}

class _AnasTvHomePageState extends State<AnasTvHomePage> {
  static const categories = <int, String>{
    0: 'All',
    5: 'Entertainment',
    6: 'Movies',
    8: 'Sports',
    12: 'News',
    7: 'Kids',
    13: 'Music',
    10: 'Infotainment',
    9: 'Lifestyle',
    15: 'Devotional',
    16: 'Business',
    17: 'Educational',
    18: 'Shopping',
  };

  static const headers = {
    'User-Agent': 'JioTV',
    'x-api-key': 'l7xx75e822925f184370b2e25170c5d5820a',
    'Origin': 'https://www.jiotv.com',
    'Referer': 'https://www.jiotv.com/tv-guide',
    'Accept': 'application/json',
    'appkey': 'NzNiMDhlYzQyNjJm',
    'os': 'android',
    'devicetype': 'phone',
  };

  static const extraUrl = 'https://api.npoint.io/9db02feba76eb297fc65';

  final List<String> _debugErrors = [];
  final ScrollController _tabScroll = ScrollController();
  final ScrollController _gridScroll = ScrollController();
  final Map<int, FocusNode> _tabNodes = {};
  final Map<int, FocusNode> _cardNodes = {};

  List<TvChannel> allChannels = [];
  List<String> filterTabs = ['ALL'];
  String selectedTab = 'ALL';
  bool loading = true;
  String? error;

  Timer? _zeroHoldTimer;
  bool _openedSearchOnHold = false;
  bool _searchOpen = false;
  double _dragDeltaX = 0;
  DateTime? _lastSubScreenReturnAt;
  String _typedDigits = '';
  String? _digitOsdError;
  Timer? _digitCommitTimer;

  int _int(dynamic value, [int fallback = 0]) =>
      int.tryParse(value?.toString() ?? '') ?? fallback;

  String _category(int id) => categories[id] ?? 'General';

  FocusNode _tabNode(int index) => _tabNodes.putIfAbsent(index, () => FocusNode());
  FocusNode _cardNode(int index) => _cardNodes.putIfAbsent(index, () => FocusNode());

  (String, String) _logoUrls(String raw) {
    final clean = raw.trim();
    if (clean.isEmpty || clean.toLowerCase() == 'null') return ('', '');
    if (clean.startsWith('//')) {
      final httpsUrl = 'https:${clean.replaceAll(' ', '%20')}';
      return (httpsUrl, httpsUrl);
    }
    if (clean.startsWith('http://') || clean.startsWith('https://')) {
      final safeUrl = clean.replaceAll(' ', '%20');
      return (safeUrl, safeUrl);
    }
    final stripped = clean.replaceFirst(RegExp(r'^/+'), '');
    final path = stripped.startsWith('dare_images/') ? stripped : 'dare_images/images/$stripped';
    return (
      'https://jiotvimages.cdn.jio.com/$path',
      'https://jiotv.catchup.cdn.jio.com/$path',
    );
  }

  @override
  void initState() {
    super.initState();
    _loadChannels();
  }

  @override
  void didUpdateWidget(covariant AnasTvHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isTv && widget.isTv && !loading && error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_filteredChannels.isNotEmpty) {
          _focusCard(0);
        } else {
          _focusSelectedTab();
        }
      });
    }
  }

  @override
  void dispose() {
    _zeroHoldTimer?.cancel();
    _digitCommitTimer?.cancel();
    _tabScroll.dispose();
    _gridScroll.dispose();
    for (final n in _tabNodes.values) {
      n.dispose();
    }
    for (final n in _cardNodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  Future<List<TvChannel>> _fetchJio() async {
    const urls = [
      'https://jiotv.data.cdn.jio.com/apis/v3.1/getMobileChannelList/get/?os=android&devicetype=phone&usertype=tvYR7NSNn7rymo3F',
      'https://jiotv.data.cdn.jio.com/apis/v3.0/getMobileChannelList/get/?os=android&devicetype=phone&usertype=tvYR7NSNn7rymo3F',
    ];
    for (final url in urls) {
      try {
        final response = await http
            .get(Uri.parse(url), headers: headers)
            .timeout(const Duration(seconds: 18));
        if (response.statusCode != 200 || response.body.trim().isEmpty) continue;
        final decoded = jsonDecode(response.body);
        final List rows =
            decoded is Map && decoded['result'] is List ? decoded['result'] as List : [];
        final parsed = rows
            .whereType<Map>()
            .map((e) {
              final j = Map<String, dynamic>.from(e);
              final id = _int(j['channel_id']);
              final logos = _logoUrls((j['logoUrl'] ?? '').toString());
              final c = _int(j['channelCategoryId']), l = _int(j['channelLanguageId']);
              return TvChannel(
                id: id,
                name: (j['channel_name'] ?? 'Channel $id').toString(),
                logo: logos.$1,
                fallbackLogo: logos.$2,
                categoryId: c,
                category: _category(c),
                languageId: l,
                language: '',
                hd: j['isHD'] == true,
                order: _int(j['channel_order'], 999999),
                raw: j,
              );
            })
            .where((c) => c.id > 0)
            .toList();
        if (parsed.isNotEmpty) return parsed;
      } catch (e) {
        _debugErrors.add('JioTV API error: $e');
      }
    }
    return [];
  }

  Future<(List<TvChannel>, List<String>)> _fetchExtra() async {
    try {
      final response = await http.get(
        Uri.parse(extraUrl),
        headers: const {'Accept': 'application/json', 'User-Agent': StreamResolver.defaultUa},
      ).timeout(const Duration(seconds: 18));
      if (response.statusCode != 200 || response.body.trim().isEmpty) {
        _debugErrors.add('npoint API HTTP ${response.statusCode}');
        return (<TvChannel>[], <String>[]);
      }
      final decoded = jsonDecode(response.body);
      List rows = [];
      if (decoded is List) rows = decoded;
      if (decoded is Map) {
        for (final key in ['channels', 'result', 'data', 'list', 'items', 'tv']) {
          if (decoded[key] is List) {
            rows = decoded[key] as List;
            break;
          }
        }
        if (rows.isEmpty) {
          rows = decoded.values.firstWhere((v) => v is List, orElse: () => []) as List;
        }
      }

      final result = <TvChannel>[];
      final seenGenres = <String>{};
      final apiGenres = <String>[];

      for (var i = 0; i < rows.length; i++) {
        if (rows[i] is! Map) continue;
        final j = Map<String, dynamic>.from(rows[i]);
        String pick(List<String> keys) {
          for (final key in keys) {
            final value = (j[key] ?? '').toString().trim();
            if (value.isNotEmpty && value != 'null') return value;
          }
          return '';
        }

        final name = pick(['channel_name', 'channelName', 'name', 'title', 'tvg_name']);
        final stream = pick([
          'ready_to_use_link',
          'channel_url',
          'stream_url',
          'mpd_url',
          'm3u8_url',
          'url',
        ]);
        if (name.isEmpty && stream.isEmpty) continue;

        final id = _int(pick(['channel_id', 'channelId', 'id', 'chid', 'channelNo']), 1000000 + i);
        var rawLogo = pick([
          'channel_logo',
          'channelLogo',
          'logo_url',
          'logoUrl',
          'logo',
          'tvg_logo',
          'tvgLogo',
          'image',
          'channel_image',
          'channel_img',
          'img',
          'icon',
          'poster',
          'thumbnail',
          'pic',
        ]);
        if (rawLogo.isEmpty) {
          for (final entry in j.entries) {
            final k = entry.key.toLowerCase();
            if (k.contains('logo') || k.contains('icon') || k.contains('img') || k.contains('image')) {
              final v = (entry.value ?? '').toString().trim();
              if (v.isNotEmpty && v != 'null') {
                rawLogo = v;
                break;
              }
            }
          }
        }
        final logos = _logoUrls(rawLogo);
        final rawCategory = pick(['channel_genre', 'cat', 'categoryName', 'category', 'genre', 'group_title']);
        final c = _int(pick(['channelCategoryId', 'category_id', 'categoryId']));
        final l = _int(pick(['channelLanguageId', 'language_id', 'languageId']));
        final rawLanguage = pick(['languageName', 'language', 'lang']);

        final cleanGenre = rawCategory.trim();
        if (cleanGenre.isNotEmpty && cleanGenre.toLowerCase() != 'unknown') {
          final key = cleanGenre.toLowerCase();
          if (seenGenres.add(key)) {
            apiGenres.add(cleanGenre);
          }
        }

        result.add(TvChannel(
          id: id,
          name: name.isEmpty ? 'Channel $id' : name,
          logo: logos.$1,
          fallbackLogo: logos.$2,
          categoryId: c,
          category: cleanGenre,
          languageId: l,
          language: rawLanguage,
          hd: j['isHD'] == true || j['isHd'] == true || name.toUpperCase().contains('HD'),
          order: _int(pick(['channel_order', 'order']), 10000 + i),
          raw: j,
        ));
      }
      return (result, apiGenres);
    } catch (e) {
      _debugErrors.add('npoint API error: $e');
      return (<TvChannel>[], <String>[]);
    }
  }

  Future<void> _loadChannels() async {
    setState(() {
      loading = true;
      error = null;
      _debugErrors.clear();
    });
    try {
      final jioFuture = _fetchJio();
      final extraFuture = _fetchExtra();
      final jioList = await jioFuture;
      final extraResult = await extraFuture;
      final extraList = extraResult.$1;
      final apiGenres = extraResult.$2;

      final merged = <int, TvChannel>{};
      for (final channel in jioList) {
        merged.putIfAbsent(channel.id, () => channel);
      }
      for (final extra in extraList) {
        final old = merged[extra.id];
        if (old == null) {
          merged[extra.id] = extra;
        } else {
          merged[extra.id] = TvChannel(
            id: old.id,
            name: old.name.isNotEmpty ? old.name : extra.name,
            logo: old.logo.isNotEmpty ? old.logo : extra.logo,
            fallbackLogo: old.fallbackLogo.isNotEmpty ? old.fallbackLogo : extra.fallbackLogo,
            categoryId: extra.categoryId != 0 ? extra.categoryId : old.categoryId,
            category: extra.category.isNotEmpty ? extra.category : old.category,
            languageId: old.languageId != 0 ? old.languageId : extra.languageId,
            language: extra.language.isNotEmpty ? extra.language : old.language,
            hd: old.hd || extra.hd,
            order: old.order,
            raw: extra.raw,
          );
        }
      }

      final sorted = merged.values.toList()
        ..sort((a, b) {
          final order = a.order.compareTo(b.order);
          return order != 0 ? order : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });

      if (sorted.isEmpty) {
        throw Exception(_debugErrors.isEmpty ? 'Both APIs returned zero channels.' : _debugErrors.join('\n'));
      }

      // Build title indexes so ID-less / logo-less / Hindi-aliased channels (e.g. Sony Live | StreamX)
      // share official logos & EPG program data from matching titles (incl. Sony Yay <-> Sony YAY! Hindi, Ten 3 <-> Sports Ten 3 Hindi).
      final exactEpgMap = <String, TvChannel>{};
      final sdEpgMap = <String, TvChannel>{};
      final langSdEpgMap = <String, TvChannel>{};
      final baseEpgMap = <String, TvChannel>{};
      final langBaseEpgMap = <String, TvChannel>{};
      final exactLogoMap = <String, TvChannel>{};
      final sdLogoMap = <String, TvChannel>{};
      final langSdLogoMap = <String, TvChannel>{};
      final baseLogoMap = <String, TvChannel>{};
      final langBaseLogoMap = <String, TvChannel>{};

      void putLogoCandidate(Map<String, TvChannel> map, String key, TvChannel ch) {
        if (key.isEmpty) return;
        final cur = map[key];
        if (cur == null || (cur.id >= 1000000 && ch.id < 1000000)) {
          map[key] = ch;
        }
      }

      for (final ch in sorted) {
        final ek = _ChannelMatcher.exactKey(ch.name);
        final sk = _ChannelMatcher.sdEquivKey(ch.name);
        final lk = _ChannelMatcher.langNeutralSdKey(ch.name);
        final bk = _ChannelMatcher.baseKey(ch.name);
        final lbk = _ChannelMatcher.langNeutralBaseKey(ch.name);
        if (ch.id < 1000000) {
          if (ek.isNotEmpty) exactEpgMap.putIfAbsent(ek, () => ch);
          if (sk.isNotEmpty) sdEpgMap.putIfAbsent(sk, () => ch);
          if (lk.isNotEmpty) langSdEpgMap.putIfAbsent(lk, () => ch);
          if (bk.isNotEmpty) baseEpgMap.putIfAbsent(bk, () => ch);
          if (lbk.isNotEmpty) langBaseEpgMap.putIfAbsent(lbk, () => ch);
        }
        if (ch.logo.trim().isNotEmpty) {
          putLogoCandidate(exactLogoMap, ek, ch);
          putLogoCandidate(sdLogoMap, sk, ch);
          putLogoCandidate(langSdLogoMap, lk, ch);
          putLogoCandidate(baseLogoMap, bk, ch);
          putLogoCandidate(langBaseLogoMap, lbk, ch);
        }
      }

      TvChannel? findMatch(
        TvChannel target,
        Map<String, TvChannel> exactMap,
        Map<String, TvChannel> sdMap,
        Map<String, TvChannel> langSdMap,
        Map<String, TvChannel> baseMap,
        Map<String, TvChannel> langBaseMap,
      ) {
        final ek = _ChannelMatcher.exactKey(target.name);
        final sk = _ChannelMatcher.sdEquivKey(target.name);
        final lk = _ChannelMatcher.langNeutralSdKey(target.name);
        final bk = _ChannelMatcher.baseKey(target.name);
        final lbk = _ChannelMatcher.langNeutralBaseKey(target.name);
        for (final m in [
          exactMap[ek],
          sdMap[sk],
          langSdMap[lk],
          baseMap[bk],
          langBaseMap[lbk],
        ]) {
          if (m != null && m.id != target.id) return m;
        }
        return null;
      }

      final enriched = List<TvChannel>.generate(sorted.length, (index) {
        final ch = sorted[index];
        final epgDonor = ch.id >= 1000000
            ? findMatch(ch, exactEpgMap, sdEpgMap, langSdEpgMap, baseEpgMap, langBaseEpgMap)
            : null;
        final logoDonor =
            findMatch(ch, exactLogoMap, sdLogoMap, langSdLogoMap, baseLogoMap, langBaseLogoMap);

        var nextLogo = ch.logo;
        var nextFallback = ch.fallbackLogo;
        if (nextLogo.trim().isEmpty && logoDonor != null) {
          nextLogo = logoDonor.logo;
          nextFallback = logoDonor.fallbackLogo.isNotEmpty ? logoDonor.fallbackLogo : logoDonor.logo;
        } else if (nextLogo.contains('://www.sonypicturesnetworks.com/')) {
          nextFallback = nextLogo.replaceFirst(
            '://www.sonypicturesnetworks.com/',
            '://sonypicturesnetworks.com/',
          );
        }

        return ch.copyWith(
          channelNumber: 101 + index,
          logo: nextLogo,
          fallbackLogo: nextFallback,
          epgChannelId: epgDonor?.id,
          epgChannelName: epgDonor?.name,
        );
      });

      _EpgService.registerChannels(enriched);

      final tabs = <String>['ALL', ...apiGenres];
      if (!mounted) return;
      setState(() {
        allChannels = enriched;
        filterTabs = tabs;
        if (!tabs.any((t) => t.toLowerCase() == selectedTab.toLowerCase())) {
          selectedTab = 'ALL';
        }
      });
      _precacheVisibleLogos(_filteredChannels.take(48).toList());
      if (widget.isTv) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _filteredChannels.isNotEmpty) _focusCard(0);
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _precacheVisibleLogos(List<TvChannel> channels) async {
    for (final ch in channels.take(20)) {
      if (!mounted) return;
      final url = ch.logo.trim();
      if (url.isEmpty) continue;
      await precacheImage(
        CachedNetworkImageProvider(
          url,
          headers: _imageHeadersFor(url),
          maxWidth: 140,
          maxHeight: 140,
        ),
        context,
      ).catchError((_) {});
    }
  }

  List<TvChannel> get _filteredChannels {
    if (selectedTab.toUpperCase() == 'ALL') return allChannels;
    final target = selectedTab.trim().toLowerCase();
    return allChannels
        .where((c) => c.category.trim().toLowerCase() == target)
        .toList();
  }

  int get _selectedTabIndex {
    final idx = filterTabs.indexWhere((t) => t.toLowerCase() == selectedTab.toLowerCase());
    return idx >= 0 ? idx : 0;
  }

  void _focusSelectedTab() {
    if (!widget.isTv || filterTabs.isEmpty) return;
    _tabNode(_selectedTabIndex).requestFocus();
  }

  void _selectTab(String label) {
    setState(() => selectedTab = label);
    _precacheVisibleLogos(_filteredChannels.take(32).toList());
    if (_gridScroll.hasClients) {
      _gridScroll.jumpTo(0);
    }
  }

  void _focusCard(int targetIndex) {
    final node = _cardNodes[targetIndex];
    if (node != null && node.canRequestFocus && node.context != null) {
      node.requestFocus();
      return;
    }
    if (targetIndex == 0 && _gridScroll.hasClients) {
      _gridScroll.jumpTo(0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final n = _cardNodes[0];
        if (n != null && n.canRequestFocus) n.requestFocus();
      });
    }
  }

  void _clearTypedDigits() {
    _digitCommitTimer?.cancel();
    if (_typedDigits.isNotEmpty || _digitOsdError != null) {
      setState(() {
        _typedDigits = '';
        _digitOsdError = null;
      });
    }
  }

  void _appendTypedDigit(String digit) {
    _digitCommitTimer?.cancel();
    setState(() {
      _digitOsdError = null;
      _typedDigits = _typedDigits.length >= 4 ? digit : '$_typedDigits$digit';
    });
    _digitCommitTimer = Timer(const Duration(milliseconds: 1400), _commitTypedChannel);
  }

  void _commitTypedChannel() {
    _digitCommitTimer?.cancel();
    final raw = _typedDigits;
    if (raw.isEmpty || allChannels.isEmpty) {
      _clearTypedDigits();
      return;
    }
    final num = int.tryParse(raw);
    final idx = num == null ? null : _resolveChannelIndexByNumber(allChannels, num);
    if (idx != null) {
      final restoreIdx = _focusedRestoreIndex();
      setState(() {
        _typedDigits = '';
        _digitOsdError = null;
      });
      _openChannel(allChannels, idx, restoreCardIndex: restoreIdx);
    } else {
      setState(() {
        _typedDigits = '';
        _digitOsdError = 'Ch $raw not found';
      });
      _digitCommitTimer = Timer(const Duration(milliseconds: 1100), () {
        if (mounted) setState(() => _digitOsdError = null);
      });
    }
  }

  String? get _typedPreviewChannelName {
    final num = int.tryParse(_typedDigits);
    if (num == null) return null;
    final idx = _resolveChannelIndexByNumber(allChannels, num);
    if (idx == null) return null;
    return allChannels[idx].name;
  }

  KeyEventResult _handleTabKey(int tabIndex, KeyEvent event) {
    if (!widget.isTv || event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_typedDigits.isNotEmpty) {
        _commitTypedChannel();
        return KeyEventResult.handled;
      }
      if (tabIndex >= 0 && tabIndex < filterTabs.length) {
        _selectTab(filterTabs[tabIndex]);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (tabIndex > 0) _tabNode(tabIndex - 1).requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (tabIndex + 1 < filterTabs.length) _tabNode(tabIndex + 1).requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (_filteredChannels.isNotEmpty) _focusCard(0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleCardKey(int index, int columns, int totalCount, KeyEvent event) {
    if (!widget.isTv || event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final row = index ~/ columns;
    final col = index % columns;
    final isFirstRowLastItem = row == 0 && (col == columns - 1 || index == totalCount - 1);

    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_typedDigits.isNotEmpty) {
        _commitTypedChannel();
        return KeyEventResult.handled;
      }
      final filtered = _filteredChannels;
      if (index >= 0 && index < filtered.length) {
        _openChannel(filtered, index, restoreCardIndex: index);
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (row == 0 && col == 0) {
        _focusSelectedTab();
        return KeyEventResult.handled;
      }
      if (index > 0) {
        _focusCard(index - 1);
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      if (isFirstRowLastItem) {
        _focusSelectedTab();
        return KeyEventResult.handled;
      }
      if (index + 1 < totalCount) {
        _focusCard(index + 1);
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      if (row == 0) {
        _focusSelectedTab();
        return KeyEventResult.handled;
      }
      _focusCard(index - columns);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      if (index + columns < totalCount) {
        _focusCard(index + columns);
      } else if ((row + 1) * columns < totalCount) {
        _focusCard(totalCount - 1);
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  KeyEventResult _handleGlobalTvKey(FocusNode node, KeyEvent event) {
    if (loading || error != null || allChannels.isEmpty) {
      return KeyEventResult.ignored;
    }

    final digit = _digitFromKeyEvent(event);
    if (digit == '0' && widget.isTv) {
      if (event is KeyDownEvent) {
        if (_typedDigits.isNotEmpty) {
          _zeroHoldTimer?.cancel();
          _appendTypedDigit('0');
          return KeyEventResult.handled;
        }
        if (!_openedSearchOnHold) {
          _zeroHoldTimer?.cancel();
          _zeroHoldTimer = Timer(const Duration(milliseconds: 500), () {
            _openedSearchOnHold = true;
            _clearTypedDigits();
            if (mounted) _openSearchScreen();
          });
        }
        return KeyEventResult.handled;
      }
      if (event is KeyRepeatEvent) {
        if (_typedDigits.isEmpty && !_openedSearchOnHold) {
          _zeroHoldTimer?.cancel();
          _openedSearchOnHold = true;
          _openSearchScreen();
        }
        return KeyEventResult.handled;
      }
      if (event is KeyUpEvent) {
        _zeroHoldTimer?.cancel();
        if (!_openedSearchOnHold && _typedDigits.isEmpty) {
          _appendTypedDigit('0');
        }
        _openedSearchOnHold = false;
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (digit != null) {
      if (event is KeyDownEvent) {
        _zeroHoldTimer?.cancel();
        _appendTypedDigit(digit);
      }
      return KeyEventResult.handled;
    }

    if (_typedDigits.isNotEmpty && event is KeyDownEvent) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter) {
        _commitTypedChannel();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.backspace) {
        _clearTypedDigits();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  int _focusedRestoreIndex() {
    for (final entry in _cardNodes.entries) {
      if (entry.value.hasFocus) return entry.key;
    }
    return 0;
  }

  void _openSearchScreen() {
    if (_searchOpen || allChannels.isEmpty) return;
    _searchOpen = true;
    final restoreIndex = _focusedRestoreIndex();
    Navigator.of(context)
        .push(PageRouteBuilder<void>(
          transitionDuration: widget.isTv ? Duration.zero : const Duration(milliseconds: 220),
          reverseTransitionDuration: widget.isTv ? Duration.zero : const Duration(milliseconds: 180),
          pageBuilder: (_, __, ___) => AnasTvSearchScreen(channels: allChannels, isTv: widget.isTv),
          transitionsBuilder: widget.isTv
              ? (_, __, ___, child) => child
              : (_, animation, __, child) => SlideTransition(
                    position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                        .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
                    child: child,
                  ),
        ))
        .then((_) {
          _zeroHoldTimer?.cancel();
          _openedSearchOnHold = false;
          _searchOpen = false;
          _lastSubScreenReturnAt = DateTime.now();
          if (widget.isTv && mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _focusCard(restoreIndex);
            });
          }
        });
  }

  void _openChannel(List<TvChannel> channels, int initialIndex, {int? restoreCardIndex}) {
    if (channels.isEmpty) return;
    final safeIdx = initialIndex.clamp(0, channels.length - 1);
    Navigator.of(context)
        .push(PageRouteBuilder<void>(
          transitionDuration: widget.isTv ? Duration.zero : const Duration(milliseconds: 180),
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, __, ___) => AnasTvPlayerScreen(
            channels: channels,
            allChannels: allChannels,
            initialIndex: safeIdx,
            isTv: widget.isTv,
          ),
        ))
        .then((_) {
          _lastSubScreenReturnAt = DateTime.now();
          if (widget.isTv && restoreCardIndex != null && mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _focusCard(restoreCardIndex);
            });
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredChannels;
    final gridWidget = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = widget.isTv ? 8 : (width >= 700 ? 6 : 4);
        final spacing = widget.isTv ? 7.0 : (width >= 700 ? 10.0 : 8.0);
        return GridView.builder(
          controller: _gridScroll,
          cacheExtent: 260,
          clipBehavior: Clip.none,
          padding: widget.isTv
              ? const EdgeInsets.fromLTRB(12, 10, 12, 14)
              : EdgeInsets.fromLTRB(spacing, spacing, spacing, spacing + 8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            childAspectRatio: widget.isTv ? 0.88 : 0.86,
          ),
          itemCount: filtered.length,
          itemBuilder: (context, index) => RepaintBoundary(
            child: _ChannelCard(
              channel: filtered[index],
              isTv: widget.isTv,
              focusNode: widget.isTv ? _cardNode(index) : null,
              autofocus: widget.isTv && index == 0,
              onKeyEvent: widget.isTv
                  ? (node, event) => _handleCardKey(index, columns, filtered.length, event)
                  : null,
              onTap: () => _openChannel(filtered, index, restoreCardIndex: index),
            ),
          ),
        );
      },
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_typedDigits.isNotEmpty) {
          _clearTypedDigits();
          return;
        }
        final lastReturn = _lastSubScreenReturnAt;
        if (lastReturn != null &&
            DateTime.now().difference(lastReturn) < const Duration(milliseconds: 700)) {
          return;
        }
        SystemNavigator.pop();
      },
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _handleGlobalTvKey,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: !widget.isTv ? (_) => _dragDeltaX = 0 : null,
          onHorizontalDragUpdate: !widget.isTv ? (details) => _dragDeltaX += details.delta.dx : null,
          onHorizontalDragEnd: !widget.isTv
              ? (details) {
                  if ((details.primaryVelocity ?? 0) < -240 || _dragDeltaX < -75) {
                    _openSearchScreen();
                  }
                }
              : null,
          child: Scaffold(
            backgroundColor: const Color(0xFF050505),
            body: SafeArea(
              child: Stack(
                children: [
                  Column(
                children: [
                  if (!loading && error == null && filterTabs.length > 1)
                    Padding(
                      padding: EdgeInsets.only(top: widget.isTv ? 10 : 0),
                      child: Container(
                        height: widget.isTv ? 46 : 44,
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          color: Color(0xFF050505),
                          border: Border(
                            bottom: BorderSide(color: Color(0xFF1F1F1F), width: 1),
                          ),
                        ),
                        child: ListView.builder(
                          controller: _tabScroll,
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          itemCount: filterTabs.length,
                          itemBuilder: (context, index) {
                            final label = filterTabs[index];
                            final selected = label.toLowerCase() == selectedTab.toLowerCase();
                            return _CategoryTab(
                              label: label.toUpperCase(),
                              selected: selected,
                              isTv: widget.isTv,
                              focusNode: widget.isTv ? _tabNode(index) : null,
                              onKeyEvent:
                                  widget.isTv ? (node, event) => _handleTabKey(index, event) : null,
                              onTap: () => _selectTab(label),
                            );
                          },
                        ),
                      ),
                    ),
                  Expanded(
                    child: ClipRect(
                      child: loading
                          ? const Center(child: _BrandCircularLoader(size: 80))
                          : error != null
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.wifi_off_rounded, color: Color(0xFFE65312), size: 48),
                                        const SizedBox(height: 12),
                                        Text(error!,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(color: Colors.white)),
                                        const SizedBox(height: 16),
                                        FilledButton(onPressed: _loadChannels, child: const Text('Retry')),
                                      ],
                                    ),
                                  ),
                                )
                              : filtered.isEmpty
                                  ? Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text('Koi channel nahi mila',
                                              style: TextStyle(color: Colors.white)),
                                          TextButton(
                                            onPressed: () => setState(() => selectedTab = 'ALL'),
                                            child: const Text('Show All'),
                                          ),
                                        ],
                                      ),
                                    )
                                  : widget.isTv
                                      ? gridWidget
                                      : RefreshIndicator(
                                          color: const Color(0xFFE65312),
                                          onRefresh: _loadChannels,
                                          child: gridWidget,
                                        ),
                    ),
                  ),
                ],
              ),
                  if (_typedDigits.isNotEmpty || _digitOsdError != null)
                    Positioned(
                      top: 14,
                      right: 20,
                      child: _StbChannelNumberOsd(
                        digits: _typedDigits,
                        previewChannelName: _typedPreviewChannelName,
                        errorMessage: _digitOsdError,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryTab extends StatefulWidget {
  final String label;
  final bool selected;
  final bool isTv;
  final FocusNode? focusNode;
  final FocusOnKeyEventCallback? onKeyEvent;
  final VoidCallback onTap;

  const _CategoryTab({
    required this.label,
    required this.selected,
    required this.isTv,
    required this.onTap,
    this.focusNode,
    this.onKeyEvent,
  });

  @override
  State<_CategoryTab> createState() => _CategoryTabState();
}

class _CategoryTabState extends State<_CategoryTab> {
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected;
    final showTvFocus = widget.isTv && focused;

    return Focus(
      focusNode: widget.focusNode,
      canRequestFocus: widget.isTv,
      onKeyEvent: widget.onKeyEvent,
      onFocusChange: (v) {
        if (widget.isTv) {
          setState(() => focused = v);
          if (v) {
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              duration: const Duration(milliseconds: 120),
            );
          }
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: EdgeInsets.fromLTRB(16, widget.isTv ? 4 : 0, 16, 0),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: showTvFocus ? const Color(0xFF23262F) : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: active ? const Color(0xFFE65312) : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Text(
            widget.label,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: 12.5,
              letterSpacing: 0.35,
              fontWeight: active || showTvFocus ? FontWeight.w700 : FontWeight.w600,
              color: active
                  ? const Color(0xFFE65312)
                  : (showTvFocus ? Colors.white : const Color(0xFFD0D4DC)),
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusSearchGridIntent extends Intent {
  const _FocusSearchGridIntent();
}

class AnasTvSearchScreen extends StatefulWidget {
  final List<TvChannel> channels;
  final bool isTv;

  const AnasTvSearchScreen({
    super.key,
    required this.channels,
    required this.isTv,
  });

  @override
  State<AnasTvSearchScreen> createState() => _AnasTvSearchScreenState();
}

class _AnasTvSearchScreenState extends State<AnasTvSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  late final FocusNode _searchFocus;
  final ScrollController _gridScroll = ScrollController();
  final Map<int, FocusNode> _cardNodes = {};

  String _query = '';
  bool _isExiting = false;
  bool _ignoreInitialZeroKeys = false;
  late final DateTime _openedAt = DateTime.now();
  Timer? _zeroGuardTimer;
  double _dragDeltaX = 0;

  FocusNode _cardNode(int index) => _cardNodes.putIfAbsent(index, () => FocusNode());

  bool _isZeroKey(KeyEvent event) {
    final l = event.logicalKey;
    final p = event.physicalKey;
    return l == LogicalKeyboardKey.digit0 ||
        l == LogicalKeyboardKey.numpad0 ||
        p == PhysicalKeyboardKey.digit0 ||
        p == PhysicalKeyboardKey.numpad0;
  }

  void _reopenSearchKeyboard() {
    _ignoreInitialZeroKeys = false;
    _zeroGuardTimer?.cancel();
    _searchFocus.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocus.requestFocus();
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    });
  }

  @override
  void initState() {
    super.initState();
    _ignoreInitialZeroKeys = widget.isTv;
    if (widget.isTv) {
      _zeroGuardTimer = Timer(const Duration(milliseconds: 1200), () {
        _ignoreInitialZeroKeys = false;
      });
    }
    _searchFocus = FocusNode(
      onKeyEvent: (node, event) {
        if (!widget.isTv) return KeyEventResult.ignored;
        if (_isZeroKey(event) && _ignoreInitialZeroKeys) {
          if (event is KeyUpEvent) {
            _ignoreInitialZeroKeys = false;
            _zeroGuardTimer?.cancel();
          }
          return KeyEventResult.handled;
        }
        if (_ignoreInitialZeroKeys && event is KeyDownEvent && !_isZeroKey(event)) {
          _ignoreInitialZeroKeys = false;
          _zeroGuardTimer?.cancel();
        }
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter) {
          if (event is KeyDownEvent) {
            _reopenSearchKeyboard();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );
  }

  @override
  void dispose() {
    _zeroGuardTimer?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _gridScroll.dispose();
    for (final n in _cardNodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  List<TvChannel> get _results {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.channels;
    final starts = <TvChannel>[];
    final contains = <TvChannel>[];
    for (final c in widget.channels) {
      final lower = c.name.toLowerCase();
      if (lower.startsWith(q)) {
        starts.add(c);
      } else if (lower.contains(q)) {
        contains.add(c);
      }
    }
    return [...starts, ...contains];
  }

  void _focusCard(int targetIndex) {
    final node = _cardNodes[targetIndex];
    if (node != null && node.canRequestFocus && node.context != null) {
      node.requestFocus();
      return;
    }
    if (targetIndex == 0 && _gridScroll.hasClients) {
      _gridScroll.jumpTo(0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final n = _cardNodes[0];
        if (n != null && n.canRequestFocus) n.requestFocus();
      });
    }
  }

  KeyEventResult _handleCardKey(int index, int columns, int totalCount, KeyEvent event) {
    if (!widget.isTv || event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final row = index ~/ columns;
    final col = index % columns;
    final isFirstRowLastItem = row == 0 && (col == columns - 1 || index == totalCount - 1);

    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final results = _results;
      if (index >= 0 && index < results.length) {
        _openChannel(results, index, restoreCardIndex: index);
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (row == 0 && col == 0) {
        _searchFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (index > 0) _focusCard(index - 1);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      if (isFirstRowLastItem) {
        _searchFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (index + 1 < totalCount) _focusCard(index + 1);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      if (row == 0) {
        _searchFocus.requestFocus();
        return KeyEventResult.handled;
      }
      _focusCard(index - columns);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      if (index + columns < totalCount) {
        _focusCard(index + columns);
      } else if ((row + 1) * columns < totalCount) {
        _focusCard(totalCount - 1);
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _openChannel(List<TvChannel> channels, int initialIndex, {int? restoreCardIndex}) {
    if (channels.isEmpty) return;
    final safeIdx = initialIndex.clamp(0, channels.length - 1);
    Navigator.of(context)
        .push(PageRouteBuilder<void>(
          transitionDuration: widget.isTv ? Duration.zero : const Duration(milliseconds: 180),
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, __, ___) => AnasTvPlayerScreen(
            channels: channels,
            allChannels: widget.channels,
            initialIndex: safeIdx,
            isTv: widget.isTv,
          ),
        ))
        .then((_) {
          if (widget.isTv && restoreCardIndex != null && mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _focusCard(restoreCardIndex);
            });
          }
        });
  }

  void _exitSearch() {
    if (_isExiting) return;
    _isExiting = true;
    FocusScope.of(context).unfocus();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitSearch();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: !widget.isTv ? (_) => _dragDeltaX = 0 : null,
        onHorizontalDragUpdate: !widget.isTv ? (details) => _dragDeltaX += details.delta.dx : null,
        onHorizontalDragEnd: !widget.isTv
            ? (details) {
                if ((details.primaryVelocity ?? 0) > 260 || _dragDeltaX > 80) {
                  _exitSearch();
                }
              }
            : null,
        child: Scaffold(
          backgroundColor: const Color(0xFF050505),
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.only(top: widget.isTv ? 10 : 0),
                  child: Container(
                    height: widget.isTv ? 46 : 44,
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Color(0xFF050505),
                      border: Border(
                        bottom: BorderSide(color: Color(0xFF1F1F1F), width: 1),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Shortcuts(
                      shortcuts: widget.isTv
                          ? const <ShortcutActivator, Intent>{
                              SingleActivator(LogicalKeyboardKey.arrowDown):
                                  _FocusSearchGridIntent(),
                            }
                          : const <ShortcutActivator, Intent>{},
                      child: Actions(
                        actions: <Type, Action<Intent>>{
                          _FocusSearchGridIntent: CallbackAction<_FocusSearchGridIntent>(
                            onInvoke: (_) {
                              if (_results.isNotEmpty) _focusCard(0);
                              return null;
                            },
                          ),
                        },
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(24, widget.isTv ? 4 : 0, 24, 0),
                          child: TextField(
                            controller: _searchController,
                            focusNode: _searchFocus,
                            autofocus: true,
                            textAlign: TextAlign.center,
                            textAlignVertical: TextAlignVertical.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                            cursorColor: const Color(0xFFE65312),
                            textInputAction: TextInputAction.search,
                            onTap: widget.isTv ? _reopenSearchKeyboard : null,
                            onSubmitted: (_) {
                              if (widget.isTv && _results.isNotEmpty) {
                                _focusCard(0);
                              }
                            },
                            inputFormatters: widget.isTv
                                ? [
                                    TextInputFormatter.withFunction((oldValue, newValue) {
                                      if (_ignoreInitialZeroKeys &&
                                          DateTime.now().difference(_openedAt) <
                                              const Duration(milliseconds: 1200) &&
                                          oldValue.text.isEmpty &&
                                          RegExp(r'^0+$').hasMatch(newValue.text)) {
                                        return oldValue;
                                      }
                                      if (newValue.text.isNotEmpty &&
                                          !RegExp(r'^0+$').hasMatch(newValue.text)) {
                                        _ignoreInitialZeroKeys = false;
                                      }
                                      return newValue;
                                    }),
                                  ]
                                : null,
                            decoration: const InputDecoration(
                              hintText: 'Search...',
                              hintStyle: TextStyle(
                                color: Color(0xFF8B909E),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                              border: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              filled: false,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onChanged: (value) {
                              setState(() => _query = value);
                              if (_gridScroll.hasClients) _gridScroll.jumpTo(0);
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRect(
                    child: results.isEmpty
                        ? const Center(
                            child: Text(
                              'Koi channel nahi mila',
                              style: TextStyle(color: Colors.white),
                            ),
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final width = constraints.maxWidth;
                              final columns = widget.isTv ? 8 : (width >= 700 ? 6 : 4);
                              final spacing = widget.isTv ? 7.0 : (width >= 700 ? 10.0 : 8.0);
                              return GridView.builder(
                                controller: _gridScroll,
                                cacheExtent: 260,
                                clipBehavior: Clip.none,
                                padding: widget.isTv
                                    ? const EdgeInsets.fromLTRB(12, 10, 12, 14)
                                    : EdgeInsets.fromLTRB(spacing, spacing, spacing, spacing + 8),
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  mainAxisSpacing: spacing,
                                  crossAxisSpacing: spacing,
                                  childAspectRatio: widget.isTv ? 0.88 : 0.86,
                                ),
                                itemCount: results.length,
                                itemBuilder: (context, index) => RepaintBoundary(
                                  child: _ChannelCard(
                                    channel: results[index],
                                    isTv: widget.isTv,
                                    focusNode: widget.isTv ? _cardNode(index) : null,
                                    onKeyEvent: widget.isTv
                                        ? (node, event) =>
                                            _handleCardKey(index, columns, results.length, event)
                                        : null,
                                    onTap: () =>
                                        _openChannel(results, index, restoreCardIndex: index),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StbProgram {
  final int startMs;
  final String title;
  final String timeLabel;
  final String description;
  final String posterUrl;
  final String fallbackPosterUrl;
  final double progress;
  final bool isLiveNow;

  const _StbProgram({
    required this.startMs,
    required this.title,
    required this.timeLabel,
    required this.description,
    required this.posterUrl,
    required this.fallbackPosterUrl,
    required this.progress,
    required this.isLiveNow,
  });
}

int _parseEpochMsStatic(dynamic val) {
  final n = int.tryParse(val?.toString() ?? '') ?? 0;
  if (n <= 0) return 0;
  return n < 100000000000 ? n * 1000 : n;
}

(String, String) _posterCandidatesStatic(String rawPoster) {
  final clean = rawPoster.trim().replaceFirst(RegExp(r'^/+'), '');
  if (clean.isEmpty || clean == 'null') return ('', '');
  if (clean.startsWith('http://') || clean.startsWith('https://')) {
    return (clean, '');
  }
  final rel = clean.startsWith('dare_images/')
      ? clean
      : (clean.startsWith('shows/') ? 'dare_images/$clean' : 'dare_images/shows/$clean');
  return (
    'https://jiotvimages.cdn.jio.com/$rel',
    'https://jiotv.catchup.cdn.jio.com/$rel',
  );
}

List<Map<String, dynamic>> _parseEpgBatchIsolate(Map<String, dynamic> args) {
  final body = args['body'] as String;
  final nowMs = args['nowMs'] as int;
  final cutoffMs = args['cutoffMs'] as int;
  final channelName = args['channelName'] as String;

  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  String fmtTime(DateTime dt) {
    final hour24 = dt.hour;
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final min = dt.minute.toString().padLeft(2, '0');
    final period = hour24 >= 12 ? 'PM' : 'AM';
    return '$hour12:$min $period';
  }

  final seenStart = <int>{};
  final rawEntries = <Map<String, dynamic>>[];

  if (body.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(body);
      final List rows = decoded is Map && decoded['epg'] is List ? decoded['epg'] as List : [];
      for (final row in rows) {
        if (row is! Map) continue;
        final s = _parseEpochMsStatic(row['startEpoch']);
        final e = _parseEpochMsStatic(row['endEpoch']);
        if (s <= 0 || e <= s) continue;
        if (e <= nowMs || s > cutoffMs) continue;
        if (!seenStart.add(s)) continue;
        rawEntries.add({
          '_startMs': s,
          '_endMs': e,
          'showname': row['showname'],
          'description': row['description'],
          'episodePoster': row['episodePoster'],
          'showpic': row['showpic'],
        });
      }
    } catch (_) {}
  }

  rawEntries.sort((a, b) => (a['_startMs'] as int).compareTo(b['_startMs'] as int));

  final out = <Map<String, dynamic>>[];
  for (final raw in rawEntries) {
    final sMs = raw['_startMs'] as int;
    final eMs = raw['_endMs'] as int;
    final sDt = DateTime.fromMillisecondsSinceEpoch(sMs);
    final eDt = DateTime.fromMillisecondsSinceEpoch(eMs);
    final isLive = nowMs >= sMs && nowMs < eMs;
    final prog = isLive && eMs > sMs
        ? ((nowMs - sMs) / (eMs - sMs)).clamp(0.05, 0.98)
        : 0.0;
    final rawPoster = (raw['episodePoster'] ?? raw['showpic'] ?? '').toString();
    final posters = _posterCandidatesStatic(rawPoster);
    final rawTitle = (raw['showname'] ?? '$channelName Show').toString().trim();
    final rawDesc = (raw['description'] ?? '$channelName television broadcast.').toString().trim();
    final day = days[(sDt.weekday - 1).clamp(0, 6)];
    out.add({
      'startMs': sMs,
      'title': rawTitle.isEmpty ? '$channelName Show' : rawTitle,
      'timeLabel': '$day : ${fmtTime(sDt)} - ${fmtTime(eDt)}',
      'description': rawDesc.isEmpty ? '$channelName television broadcast.' : rawDesc,
      'posterUrl': posters.$1,
      'fallbackPosterUrl': posters.$2,
      'progress': prog,
      'isLiveNow': isLive,
    });
  }
  return out;
}

class _EpgService {
  static final Map<int, List<_StbProgram>> _cache = {};
  static final Map<int, Set<int>> _loadedOffsets = {};
  static final Map<int, Set<int>> _emptyOffsets = {};
  static final Map<int, int> _epgDonorIdFor = {};
  static final Map<String, List<TvChannel>> _byExact = {};
  static final Map<String, List<TvChannel>> _bySdEquiv = {};
  static final Map<String, List<TvChannel>> _byLangSd = {};
  static final Map<String, List<TvChannel>> _byBase = {};
  static final Map<String, List<TvChannel>> _byLangBase = {};

  static void registerChannels(List<TvChannel> channels) {
    _epgDonorIdFor.clear();
    _byExact.clear();
    _bySdEquiv.clear();
    _byLangSd.clear();
    _byBase.clear();
    _byLangBase.clear();
    for (final ch in channels) {
      if (ch.epgChannelId != null && ch.epgChannelId! < 1000000) {
        _epgDonorIdFor[ch.id] = ch.epgChannelId!;
      }
      if (ch.id >= 1000000) continue;
      final ek = _ChannelMatcher.exactKey(ch.name);
      final sk = _ChannelMatcher.sdEquivKey(ch.name);
      final lk = _ChannelMatcher.langNeutralSdKey(ch.name);
      final bk = _ChannelMatcher.baseKey(ch.name);
      final lbk = _ChannelMatcher.langNeutralBaseKey(ch.name);
      if (ek.isNotEmpty) _byExact.putIfAbsent(ek, () => []).add(ch);
      if (sk.isNotEmpty) _bySdEquiv.putIfAbsent(sk, () => []).add(ch);
      if (lk.isNotEmpty) _byLangSd.putIfAbsent(lk, () => []).add(ch);
      if (bk.isNotEmpty) _byBase.putIfAbsent(bk, () => []).add(ch);
      if (lbk.isNotEmpty) _byLangBase.putIfAbsent(lbk, () => []).add(ch);
    }
  }

  static List<int> _candidateIdsFor(TvChannel ch) {
    final ids = <int>[];
    void addId(int? id) {
      if (id != null && id > 0 && id < 1000000 && !ids.contains(id)) {
        ids.add(id);
      }
    }

    addId(ch.id);
    addId(ch.epgChannelId);
    addId(_epgDonorIdFor[ch.id]);

    final ek = _ChannelMatcher.exactKey(ch.name);
    final sk = _ChannelMatcher.sdEquivKey(ch.name);
    final lk = _ChannelMatcher.langNeutralSdKey(ch.name);
    final bk = _ChannelMatcher.baseKey(ch.name);
    final lbk = _ChannelMatcher.langNeutralBaseKey(ch.name);
    for (final list in [
      _byExact[ek],
      _bySdEquiv[sk],
      _byLangSd[lk],
      _byBase[bk],
      _byLangBase[lbk],
    ]) {
      if (list == null) continue;
      for (final donor in list) {
        addId(donor.id);
      }
    }
    return ids;
  }

  static List<_StbProgram>? cachedFor(int channelId) {
    final direct = _cache[channelId];
    if (direct != null && direct.isNotEmpty) return direct;
    final donorId = _epgDonorIdFor[channelId];
    if (donorId != null) return _cache[donorId];
    return direct;
  }

  static bool hasOffset(int channelId, int offset) =>
      _loadedOffsets[channelId]?.contains(offset) ?? false;

  static String _fmtTime(DateTime dt) {
    final hour24 = dt.hour;
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final min = dt.minute.toString().padLeft(2, '0');
    final period = hour24 >= 12 ? 'PM' : 'AM';
    return '$hour12:$min $period';
  }

  static String _weekdayShort(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[(weekday - 1).clamp(0, 6)];
  }

  static List<_StbProgram> fallback48h(TvChannel ch) {
    final now = DateTime.now();
    final slotStartMin = now.minute < 30 ? 0 : 30;
    final firstStart = DateTime(now.year, now.month, now.day, now.hour, slotStartMin);
    final cat = ch.category.toLowerCase();

    List<(String, String)> templates;
    if (cat.contains('sport')) {
      templates = [
        ('${ch.name} Live Match & Analysis', 'Live stadium action, pitch insights, Hindi commentary aur real-time score updates.'),
        ('Post Match & Highlights Special', 'Match ke best moments, top wickets, boundaries aur expert panel analysis.'),
        ('Sports Countdown & Top Plays', 'Din ke sabse behtareen sporting moments aur player stats.'),
        ('Live Studio Pre-Game Show', 'Aane wale mukable ki team news, playing XI aur expert preview.'),
      ];
    } else if (cat.contains('movie')) {
      templates = [
        ('${ch.name} Blockbuster Feature Film', 'Superhit feature movie HD picture quality aur surround audio ke saath.'),
        ('Prime Cinema Showcase', 'Family entertainer blockbuster movie non-stop broadcasting ke saath.'),
        ('Action & Drama Movie Special', 'Viewer choice hit cinema presentation poori family ke liye.'),
        ('Late Night Classic Cinema', 'Sadaabahar superhit Hindi aur regional cinema presentation.'),
      ];
    } else if (cat.contains('news')) {
      templates = [
        ('Breaking News & Live Bulletin', 'Desh aur duniya ki sabse badi khabrein aur live ground reports.'),
        ('Prime Debate & Top Headlines', 'Din bhar ki badi khabron par vishesh charcha aur tezi se updates.'),
        ('24x7 Express News Desk', 'Har rajya aur shahar ki taaza khabrein aur live reporters se update.'),
        ('Special Report & Analysis', 'Khas muddon par ground zero reporting aur panel discussion.'),
      ];
    } else if (cat.contains('kid')) {
      templates = [
        ('${ch.name} Cartoon Adventure', 'Bachchon ka pasandida animated show masti aur comedy ke saath.'),
        ('Super Hero Kids Hour', 'Naya episode action aur fun-filled adventures se bhara hua.'),
        ('Junior Fun Time Special', 'Animated characters ke saath hasi aur learning ka zabardast tadka.'),
        ('Mega Toon Marathon', 'Non-stop back-to-back popular kids episodes.'),
      ];
    } else if (cat.contains('music')) {
      templates = [
        ('Top Trending Hindi Hits', 'Non-stop Bollywood chartbusters aur latest trending music videos.'),
        ('Retro & Romantic Special', 'Sadaabahar superhit gaane aur viewers choice playlist.'),
        ('Party & Dance Beats', 'High energy music tracks aur superhit club remixes.'),
        ('Fresh Hits Countdown', 'Is hafte ke sabse zyada pasand kiye gaye top 20 songs.'),
      ];
    } else {
      templates = [
        ('${ch.name} Prime Show', '${ch.name} par dekhein popular family show aur live entertainment broadcast.'),
        ('${ch.name} Special Episode', 'Naya drama, twists aur family entertainment ka special episode.'),
        ('Viewer Choice Mega Serial', 'Darshakon ka pasandida daily soap aur emotional drama moments.'),
        ('Weekend Entertainment Hour', 'Comedy, dance aur star performances se bhara special showcase.'),
      ];
    }

    final list = <_StbProgram>[];
    for (var i = 0; i < 16; i++) {
      final start = firstStart.add(Duration(minutes: i * 60 - (i > 0 ? 30 : 0)));
      final end = i == 0 ? firstStart.add(const Duration(minutes: 30)) : start.add(const Duration(minutes: 60));
      final tpl = templates[i % templates.length];
      final prog = i == 0
          ? (now.difference(start).inSeconds / 1800.0).clamp(0.05, 0.96)
          : 0.0;
      list.add(_StbProgram(
        startMs: start.millisecondsSinceEpoch,
        title: tpl.$1,
        timeLabel: '${_weekdayShort(start.weekday)} : ${_fmtTime(start)} - ${_fmtTime(end)}',
        description: tpl.$2,
        posterUrl: '',
        fallbackPosterUrl: '',
        progress: prog,
        isLiveNow: i == 0,
      ));
    }
    return list;
  }

  static Future<List<_StbProgram>> fetchOffset(TvChannel ch, {int offset = 0}) async {
    final loaded = _loadedOffsets.putIfAbsent(ch.id, () => <int>{});
    final existing = _cache[ch.id];
    if (loaded.contains(offset) && existing != null && existing.isNotEmpty) {
      return existing;
    }

    final candidates = _candidateIdsFor(ch);
    if (candidates.isEmpty) {
      return existing ?? fallback48h(ch);
    }

    for (final cid in candidates) {
      final cidLoaded = _loadedOffsets.putIfAbsent(cid, () => <int>{});
      final cidEmpty = _emptyOffsets.putIfAbsent(cid, () => <int>{});
      final cidCache = _cache[cid];

      if (cidLoaded.contains(offset) && cidCache != null && cidCache.isNotEmpty) {
        _cache[ch.id] = cidCache;
        loaded.add(offset);
        return cidCache;
      }
      if (cidEmpty.contains(offset)) {
        continue;
      }

      try {
        final url = 'https://jiotv.data.cdn.jio.com/apis/v1.3/getepg/get?channel_id=$cid&offset=$offset';
        final res = await http
            .get(Uri.parse(url), headers: _AnasTvHomePageState.headers)
            .timeout(const Duration(seconds: 6));

        if (res.statusCode != 200 || res.body.trim().isEmpty) {
          cidEmpty.add(offset);
          continue;
        }

        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final cutoffMs = nowMs + const Duration(hours: 48).inMilliseconds;
        final parsedMaps = await compute(_parseEpgBatchIsolate, {
          'body': res.body,
          'nowMs': nowMs,
          'cutoffMs': cutoffMs,
          'channelName': ch.name,
        });

        if (parsedMaps.isEmpty) {
          cidEmpty.add(offset);
          continue;
        }

        final byStart = <int, _StbProgram>{};
        if (cidCache != null) {
          for (final item in cidCache) {
            byStart[item.startMs] = item;
          }
        }
        if (existing != null) {
          for (final item in existing) {
            byStart[item.startMs] = item;
          }
        }
        for (final m in parsedMaps) {
          final sMs = (m['startMs'] as num?)?.toInt() ?? 0;
          if (sMs <= 0) continue;
          byStart[sMs] = _StbProgram(
            startMs: sMs,
            title: (m['title'] ?? '').toString(),
            timeLabel: (m['timeLabel'] ?? '').toString(),
            description: (m['description'] ?? '').toString(),
            posterUrl: (m['posterUrl'] ?? '').toString(),
            fallbackPosterUrl: (m['fallbackPosterUrl'] ?? '').toString(),
            progress: (m['progress'] as num?)?.toDouble() ?? 0.0,
            isLiveNow: m['isLiveNow'] == true,
          );
        }

        final merged = byStart.values.toList()..sort((a, b) => a.startMs.compareTo(b.startMs));
        if (merged.isEmpty) {
          cidEmpty.add(offset);
          continue;
        }
        _cache[cid] = merged;
        cidLoaded.add(offset);
        _cache[ch.id] = merged;
        loaded.add(offset);
        return merged;
      } catch (_) {
        continue;
      }
    }

    return existing ?? fallback48h(ch);
  }
}

class AnasTvPlayerScreen extends StatefulWidget {
  final List<TvChannel> channels;
  final List<TvChannel>? allChannels;
  final int initialIndex;
  final bool isTv;

  const AnasTvPlayerScreen({
    super.key,
    required this.channels,
    this.allChannels,
    required this.initialIndex,
    required this.isTv,
  });

  @override
  State<AnasTvPlayerScreen> createState() => _AnasTvPlayerScreenState();
}

enum _StbPickerKind { audio, quality, stretch }

class _AnasTvPlayerScreenState extends State<AnasTvPlayerScreen> {
  static const List<Shadow> _textShadows = [
    Shadow(color: Color(0xCC000000), blurRadius: 2, offset: Offset(0, 1)),
  ];
  static const MethodChannel _texChannel = MethodChannel('anas_tv/texture_player');
  static const MethodChannel _deviceChannel = MethodChannel('anas_tv/device');

  final FocusNode _playerFocus = FocusNode();

  late List<TvChannel> _channels;
  late int _playingIndex;
  late int _previewIndex;
  late List<_StbProgram> _previewPrograms;
  int _programIndex = 0;
  int _programAnimDir = 1;

  ResolvedPlayback? _resolved;
  String? _error;
  bool _loading = true;
  bool _isPaused = false;
  bool _isExiting = false;
  bool _bannerVisible = false;
  bool _optionsMode = false;
  int _selectedOptionIdx = 0;

  bool _useSecurePlatformView = false;
  int? _textureId;
  double _videoWidth = 16;
  double _videoHeight = 9;

  _StbPickerKind? _openPicker;
  List<Map<String, dynamic>> _pickerItems = [];
  int _pickerFocusedIdx = 0;
  bool _pickerLoading = false;

  String _resizeMode = 'fill';

  MethodChannel? _platformChannel;
  Timer? _watchdog;
  Timer? _bannerAutoHideTimer;
  Timer? _clockTimer;
  Timer? _epgDebounceTimer;
  Timer? _digitCommitTimer;
  String _typedDigits = '';
  String? _digitOsdError;
  DateTime _now = DateTime.now();
  int _playRequestSeq = 0;
  int _lookaheadSeq = 0;
  double _panDeltaX = 0;
  double _panDeltaY = 0;

  TvChannel get _playingChannel => _channels[_playingIndex];
  TvChannel get _previewChannel => _channels[_previewIndex];
  MethodChannel? get _activePlayerChannel =>
      _useSecurePlatformView ? _platformChannel : _texChannel;

  _StbProgram get _activeProgram {
    if (_previewPrograms.isEmpty) {
      return _EpgService.fallback48h(_previewChannel).first;
    }
    final idx = _programIndex.clamp(0, _previewPrograms.length - 1);
    return _previewPrograms[idx];
  }

  @override
  void initState() {
    super.initState();
    _channels = widget.channels;
    _playingIndex = widget.initialIndex.clamp(0, _channels.length - 1);
    _previewIndex = _playingIndex;
    _previewPrograms = _EpgService.cachedFor(_previewChannel.id) ??
        _EpgService.fallback48h(_previewChannel);

    _clockTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });

    _initTextureChannel();
    _loadPreviewAndNeighbors(_previewIndex, immediateFetch: true);
    _startChannelStream(_playingIndex);
    _scheduleBannerAutoHide();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!widget.isTv) {
        await _deviceChannel.invokeMethod('setDisplayCutoutMode', true).catchError((_) {});
      }
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (!mounted) return;
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      if (widget.isTv && mounted) {
        _playerFocus.requestFocus();
      }
    });
  }

  Future<void> _initTextureChannel() async {
    _texChannel.setMethodCallHandler(_onNativePlayerCall);
    try {
      final id = await _texChannel.invokeMethod<num>('create');
      if (!mounted || id == null) return;
      setState(() => _textureId = id.toInt());
      _sendPlayIfReady();
    } catch (_) {}
  }

  Future<dynamic> _onNativePlayerCall(MethodCall call) async {
    if (!mounted) return;
    if (call.method == 'onStateChanged') {
      final state = (call.arguments ?? 'unknown').toString();
      final isBuffering = state == 'idle' || state == 'buffering';
      if (_loading != isBuffering) {
        setState(() => _loading = isBuffering);
      }
      if (state == 'ready' || state == 'ended') {
        _watchdog?.cancel();
        if (_useSecurePlatformView) {
          _platformChannel?.invokeMethod('setResizeMode', _resizeMode);
        }
      }
    } else if (call.method == 'onVideoSizeChanged') {
      final args = call.arguments;
      if (args is Map) {
        final w = (args['width'] as num?)?.toDouble() ?? 0;
        final h = (args['height'] as num?)?.toDouble() ?? 0;
        if (w > 0 && h > 0 && (w != _videoWidth || h != _videoHeight)) {
          setState(() {
            _videoWidth = w;
            _videoHeight = h;
          });
        }
      }
    } else if (call.method == 'onError') {
      _watchdog?.cancel();
      setState(() {
        _loading = false;
        _error = (call.arguments ?? 'Native player reported an error').toString();
      });
    }
  }

  @override
  void dispose() {
    _lookaheadSeq++;
    _watchdog?.cancel();
    _bannerAutoHideTimer?.cancel();
    _clockTimer?.cancel();
    _epgDebounceTimer?.cancel();
    _digitCommitTimer?.cancel();
    _platformChannel?.setMethodCallHandler(null);
    _texChannel.setMethodCallHandler(null);
    _texChannel.invokeMethod('stop').catchError((_) {});
    _playerFocus.dispose();
    if (!widget.isTv) {
      _deviceChannel.invokeMethod('setDisplayCutoutMode', false).catchError((_) {});
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    }
    super.dispose();
  }

  void _scheduleBannerAutoHide() {
    _bannerAutoHideTimer?.cancel();
    if (_openPicker != null || _error != null) return;
    _bannerAutoHideTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted || _openPicker != null || _error != null) return;
      setState(() {
        _bannerVisible = false;
        _optionsMode = false;
        _programIndex = 0;
        _previewIndex = _playingIndex;
      });
      _loadPreviewAndNeighbors(_playingIndex, immediateFetch: true);
    });
  }

  void _showBanner({bool resetToPlaying = false, bool openOptions = false}) {
    setState(() {
      if (resetToPlaying) {
        _previewIndex = _playingIndex;
        _programIndex = 0;
      }
      _bannerVisible = true;
      _optionsMode = openOptions;
      if (openOptions) _selectedOptionIdx = _selectedOptionIdx.clamp(0, 2);
    });
    if (resetToPlaying) {
      _loadPreviewAndNeighbors(_playingIndex, immediateFetch: true);
    }
    _scheduleBannerAutoHide();
  }

  Future<void> _precachePoster(String url) async {
    if (!mounted || url.trim().isEmpty) return;
    await precacheImage(
      CachedNetworkImageProvider(
        url,
        headers: _imageHeadersFor(url),
        maxWidth: 640,
        maxHeight: 360,
      ),
      context,
    ).catchError((_) {});
  }

  // Exact 1-step sliding lookahead:
  // 1) Current channel -> load Live (progIdx) first, then automatically Up Next (progIdx + 1) only.
  // 2) Left (-1) & Right (+1) channels -> load ONLY their Live (index 0) data & poster.
  void _loadPreviewAndNeighbors(int targetIdx, {bool immediateFetch = false}) {
    _epgDebounceTimer?.cancel();
    final seq = ++_lookaheadSeq;
    final target = _channels[targetIdx];

    final cached = _EpgService.cachedFor(target.id);
    setState(() {
      _previewPrograms =
          (cached != null && cached.isNotEmpty) ? cached : _EpgService.fallback48h(target);
      _programIndex = 0;
    });

    Future<void> syncCurrentAndAdjacent() async {
      if (!mounted || seq != _lookaheadSeq || _previewIndex != targetIdx) return;

      // Step 1: Current channel offset=0 -> Live (0) poster -> Next (1) poster
      var programs = (cached != null && cached.isNotEmpty)
          ? cached
          : await _EpgService.fetchOffset(target, offset: 0);
      if (!mounted || seq != _lookaheadSeq || _previewIndex != targetIdx) return;

      if (programs.length < 2 && !_EpgService.hasOffset(target.id, 1)) {
        programs = await _EpgService.fetchOffset(target, offset: 1);
        if (!mounted || seq != _lookaheadSeq || _previewIndex != targetIdx) return;
      }

      if (programs.isNotEmpty) {
        setState(() {
          _previewPrograms = programs;
          if (_programIndex >= programs.length) _programIndex = 0;
        });
        await _precachePoster(programs[0].posterUrl);
        if (!mounted || seq != _lookaheadSeq || _previewIndex != targetIdx) return;
        if (programs.length > 1) {
          await _precachePoster(programs[1].posterUrl);
        }
      }

      if (!mounted || seq != _lookaheadSeq || _previewIndex != targetIdx) return;

      // Step 2: Adjacent channels (-1 and +1) -> ONLY Live (index 0) data & poster
      if (_channels.length > 1) {
        final total = _channels.length;
        for (final delta in [-1, 1]) {
          final adjIdx = (targetIdx + delta + total) % total;
          if (adjIdx == targetIdx) continue;
          final adjCh = _channels[adjIdx];
          final adjList = await _EpgService.fetchOffset(adjCh, offset: 0);
          if (!mounted || seq != _lookaheadSeq || _previewIndex != targetIdx) return;
          if (adjList.isNotEmpty) {
            await _precachePoster(adjList[0].posterUrl);
          }
        }
      }
    }

    if (immediateFetch || (cached != null && cached.isNotEmpty)) {
      syncCurrentAndAdjacent();
    } else {
      _epgDebounceTimer = Timer(const Duration(milliseconds: 140), syncCurrentAndAdjacent);
    }
  }

  Future<void> _precacheNextProgramOnly(int progIdx) async {
    final nextIdx = progIdx + 1;
    final ch = _previewChannel;

    // Lazily fetch next EPG day only if user scrolls near the end of currently loaded items.
    if (_previewPrograms.length - nextIdx <= 2) {
      if (!_EpgService.hasOffset(ch.id, 1)) {
        final more = await _EpgService.fetchOffset(ch, offset: 1);
        if (mounted && _previewChannel.id == ch.id) {
          setState(() => _previewPrograms = more);
        }
      } else if (!_EpgService.hasOffset(ch.id, 2)) {
        final more = await _EpgService.fetchOffset(ch, offset: 2);
        if (mounted && _previewChannel.id == ch.id) {
          setState(() => _previewPrograms = more);
        }
      }
    }

    if (!mounted || _previewChannel.id != ch.id) return;
    if (nextIdx >= 0 && nextIdx < _previewPrograms.length) {
      await _precachePoster(_previewPrograms[nextIdx].posterUrl);
    }
  }

  Future<void> _startChannelStream(int targetIndex, {bool showBanner = false}) async {
    final reqId = ++_playRequestSeq;
    final target = _channels[targetIndex];

    _watchdog?.cancel();
    setState(() {
      _playingIndex = targetIndex;
      _previewIndex = targetIndex;
      _programIndex = 0;
      _loading = true;
      _error = null;
      _isPaused = false;
      _bannerVisible = showBanner;
      _optionsMode = false;
      _openPicker = null;
    });
    _loadPreviewAndNeighbors(targetIndex, immediateFetch: true);
    if (showBanner) {
      _scheduleBannerAutoHide();
    }

    _watchdog = Timer(const Duration(seconds: 25), () {
      if (!mounted || reqId != _playRequestSeq || !_loading) return;
      setState(() {
        _loading = false;
        _error = 'Playback timeout (25s). Stream respond nahi kar rahi.';
      });
    });

    try {
      final resolved = await StreamResolver.resolve(target);
      if (!mounted || reqId != _playRequestSeq) return;
      _resolved = resolved;
      final needsSecureSurface = resolved.drmLicenseUrl.isNotEmpty;
      if (_useSecurePlatformView != needsSecureSurface) {
        if (needsSecureSurface) {
          await _texChannel.invokeMethod('stop').catchError((_) {});
        }
        if (!mounted || reqId != _playRequestSeq) return;
        setState(() => _useSecurePlatformView = needsSecureSurface);
      }
      _sendPlayIfReady();
    } catch (e) {
      if (!mounted || reqId != _playRequestSeq) return;
      _watchdog?.cancel();
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _created(int id) {
    if (_platformChannel != null) return;
    final ch = MethodChannel('anas_tv/media3_player_$id');
    _platformChannel = ch;
    ch.setMethodCallHandler(_onNativePlayerCall);
    ch.invokeMethod('setResizeMode', _resizeMode);
    _sendPlayIfReady();
  }

  void _sendPlayIfReady() {
    final pb = _resolved;
    if (pb == null) return;
    final ch = _useSecurePlatformView ? _platformChannel : (_textureId != null ? _texChannel : null);
    if (ch == null) return;

    ch.invokeMethod('play', {
      'streamUrl': pb.streamUrl,
      'headers': pb.headers,
      'drmLicenseUrl': pb.drmLicenseUrl,
      'clearKeys': pb.clearKeys,
    }).catchError((Object e) {
      if (!mounted) return;
      _watchdog?.cancel();
      setState(() {
        _loading = false;
        _error = 'Native player start failed: $e';
      });
    });
  }

  void _stepPreviewChannel(int delta) {
    if (_channels.isEmpty) return;
    final nextIdx = (_previewIndex + delta + _channels.length) % _channels.length;
    setState(() {
      _bannerVisible = true;
      _optionsMode = false;
      _previewIndex = nextIdx;
      _programIndex = 0;
      _programAnimDir = 1;
    });
    _loadPreviewAndNeighbors(nextIdx);
    _scheduleBannerAutoHide();
  }

  void _stepProgram(int delta) {
    if (_previewPrograms.isEmpty) return;
    final next = (_programIndex + delta).clamp(0, _previewPrograms.length - 1);
    if (next != _programIndex) {
      setState(() {
        _programAnimDir = delta >= 0 ? 1 : -1;
        _programIndex = next;
      });
      if (delta >= 0) {
        _precacheNextProgramOnly(next);
      }
    }
    _scheduleBannerAutoHide();
  }

  void _switchChannelDirectly(int targetIndex) {
    if (_channels.isEmpty) return;
    final safeIdx = (targetIndex % _channels.length + _channels.length) % _channels.length;
    _startChannelStream(safeIdx, showBanner: true);
  }

  void _clearTypedDigits() {
    _digitCommitTimer?.cancel();
    if (_typedDigits.isNotEmpty || _digitOsdError != null) {
      setState(() {
        _typedDigits = '';
        _digitOsdError = null;
      });
    }
  }

  void _appendTypedDigit(String digit) {
    _digitCommitTimer?.cancel();
    setState(() {
      _digitOsdError = null;
      _typedDigits = _typedDigits.length >= 4 ? digit : '$_typedDigits$digit';
    });
    _digitCommitTimer = Timer(const Duration(milliseconds: 1400), _commitTypedChannel);
  }

  void _commitTypedChannel() {
    _digitCommitTimer?.cancel();
    final raw = _typedDigits;
    if (raw.isEmpty || _channels.isEmpty) {
      _clearTypedDigits();
      return;
    }
    final num = int.tryParse(raw);
    final idx = num == null ? null : _resolveChannelIndexByNumber(_channels, num);
    if (idx != null) {
      setState(() {
        _typedDigits = '';
        _digitOsdError = null;
      });
      _switchChannelDirectly(idx);
      return;
    }
    final globalList = widget.allChannels;
    final globalIdx =
        (num != null && globalList != null) ? _resolveChannelIndexByNumber(globalList, num) : null;
    if (globalIdx != null && globalList != null) {
      setState(() {
        _channels = globalList;
        _typedDigits = '';
        _digitOsdError = null;
      });
      _switchChannelDirectly(globalIdx);
      return;
    }
    setState(() {
      _typedDigits = '';
      _digitOsdError = 'Ch $raw not found';
    });
    _digitCommitTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _digitOsdError = null);
    });
  }

  String? get _typedPreviewChannelName {
    final num = int.tryParse(_typedDigits);
    if (num == null) return null;
    final idx = _resolveChannelIndexByNumber(_channels, num);
    if (idx != null) return _channels[idx].name;
    final globalList = widget.allChannels;
    if (globalList != null) {
      final globalIdx = _resolveChannelIndexByNumber(globalList, num);
      if (globalIdx != null) return globalList[globalIdx].name;
    }
    return null;
  }

  void _triggerLeft() {
    if (!_bannerVisible) {
      _showBanner(resetToPlaying: true);
      return;
    }
    if (_optionsMode) {
      setState(() => _selectedOptionIdx = (_selectedOptionIdx - 1 + 3) % 3);
      _scheduleBannerAutoHide();
      return;
    }
    _stepPreviewChannel(-1);
  }

  void _triggerRight() {
    if (!_bannerVisible) {
      _showBanner(resetToPlaying: true);
      return;
    }
    if (_optionsMode) {
      setState(() => _selectedOptionIdx = (_selectedOptionIdx + 1) % 3);
      _scheduleBannerAutoHide();
      return;
    }
    _stepPreviewChannel(1);
  }

  void _triggerUp() {
    if (!_bannerVisible) {
      _showBanner(resetToPlaying: true);
      return;
    }
    if (_optionsMode) {
      setState(() => _optionsMode = false);
      _scheduleBannerAutoHide();
      return;
    }
    _stepProgram(-1);
  }

  void _triggerDown() {
    if (!_bannerVisible) {
      _showBanner(resetToPlaying: true);
      return;
    }
    if (_optionsMode) return;
    _stepProgram(1);
  }

  void _triggerOk() {
    if (_typedDigits.isNotEmpty) {
      _commitTypedChannel();
      return;
    }
    if (_error != null) {
      _startChannelStream(_previewIndex);
      return;
    }
    if (_openPicker != null) {
      _applyPickerSelection(_pickerFocusedIdx);
      return;
    }
    if (!_bannerVisible) {
      _showBanner(resetToPlaying: true);
      return;
    }
    if (_optionsMode) {
      _triggerOption(_selectedOptionIdx);
      return;
    }
    if (_previewIndex != _playingIndex) {
      _startChannelStream(_previewIndex, showBanner: true);
    } else {
      _showBanner(openOptions: true);
    }
  }

  Future<void> _openTrackPicker(_StbPickerKind kind) async {
    _bannerAutoHideTimer?.cancel();
    setState(() {
      _bannerVisible = true;
      _optionsMode = true;
      _openPicker = kind;
      _pickerLoading = true;
      _pickerItems = [];
      _pickerFocusedIdx = 0;
    });

    List<Map<String, dynamic>> items = [];
    if (kind == _StbPickerKind.stretch) {
      items = [
        {'id': 'fill', 'label': 'Stretched (Full Screen)', 'selected': _resizeMode == 'fill'},
        {'id': 'fit', 'label': 'Fit (Original Aspect)', 'selected': _resizeMode == 'fit'},
        {'id': 'zoom', 'label': 'Zoom (Fill & Crop)', 'selected': _resizeMode == 'zoom'},
      ];
    } else if (kind == _StbPickerKind.audio) {
      try {
        final raw = await _activePlayerChannel?.invokeMethod<List<dynamic>>('getAudioTracks') ?? [];
        items = raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
      if (items.isEmpty) {
        items = [
          {'groupIndex': -1, 'trackIndex': -1, 'label': 'Default Stream Audio', 'selected': true},
        ];
      }
    } else if (kind == _StbPickerKind.quality) {
      try {
        final raw = await _activePlayerChannel?.invokeMethod<List<dynamic>>('getVideoQualities') ?? [];
        items = raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
      if (items.isEmpty) {
        items = [
          {'groupIndex': -1, 'trackIndex': -1, 'label': 'Highest (Default)', 'selected': true},
        ];
      }
    }

    if (!mounted || _openPicker != kind) return;
    final selectedIdx = items.indexWhere((e) => e['selected'] == true);
    setState(() {
      _pickerItems = items;
      _pickerFocusedIdx = selectedIdx >= 0 ? selectedIdx : 0;
      _pickerLoading = false;
    });
  }

  Future<void> _applyPickerSelection(int idx) async {
    if (idx < 0 || idx >= _pickerItems.length || _openPicker == null) return;
    final kind = _openPicker!;
    final item = _pickerItems[idx];

    if (kind == _StbPickerKind.stretch) {
      final mode = (item['id'] ?? 'fill').toString();
      if (_useSecurePlatformView) {
        await _platformChannel?.invokeMethod('setResizeMode', mode);
      }
      if (!mounted) return;
      setState(() {
        _resizeMode = mode;
        _openPicker = null;
      });
    } else if (kind == _StbPickerKind.audio) {
      final g = (item['groupIndex'] as num?)?.toInt() ?? -1;
      final t = (item['trackIndex'] as num?)?.toInt() ?? -1;
      await _activePlayerChannel?.invokeMethod('setAudioTrack', {'groupIndex': g, 'trackIndex': t});
      if (!mounted) return;
      setState(() => _openPicker = null);
    } else if (kind == _StbPickerKind.quality) {
      final g = (item['groupIndex'] as num?)?.toInt() ?? -1;
      final t = (item['trackIndex'] as num?)?.toInt() ?? -1;
      await _activePlayerChannel?.invokeMethod('setVideoQuality', {'groupIndex': g, 'trackIndex': t});
      if (!mounted) return;
      setState(() => _openPicker = null);
    }
    _scheduleBannerAutoHide();
  }

  Future<void> _togglePlayPause() async {
    final nextPaused = !_isPaused;
    await _activePlayerChannel?.invokeMethod(nextPaused ? 'pause' : 'resume');
    if (!mounted) return;
    setState(() => _isPaused = nextPaused);
    _scheduleBannerAutoHide();
  }

  void _triggerOption(int optionIdx) {
    setState(() => _selectedOptionIdx = optionIdx);
    switch (optionIdx) {
      case 0:
        _openTrackPicker(_StbPickerKind.audio);
        break;
      case 1:
        _openTrackPicker(_StbPickerKind.quality);
        break;
      case 2:
        _openTrackPicker(_StbPickerKind.stretch);
        break;
    }
  }

  Future<void> _exitPlayer() async {
    if (_isExiting) return;
    _isExiting = true;
    _watchdog?.cancel();
    _bannerAutoHideTimer?.cancel();
    _digitCommitTimer?.cancel();
    _texChannel.invokeMethod('stop').catchError((_) {});
    if (!widget.isTv) {
      await _deviceChannel.invokeMethod('setDisplayCutoutMode', false).catchError((_) {});
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    }
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleBack() async {
    if (_typedDigits.isNotEmpty) {
      _clearTypedDigits();
      return;
    }
    if (_openPicker != null) {
      setState(() => _openPicker = null);
      _scheduleBannerAutoHide();
      return;
    }
    if (_optionsMode) {
      setState(() => _optionsMode = false);
      _scheduleBannerAutoHide();
      return;
    }
    if (_bannerVisible && _error == null) {
      setState(() {
        _bannerVisible = false;
        _programIndex = 0;
        _previewIndex = _playingIndex;
      });
      _loadPreviewAndNeighbors(_playingIndex, immediateFetch: true);
      _bannerAutoHideTimer?.cancel();
      return;
    }
    await _exitPlayer();
  }

  bool _isMenuKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.contextMenu ||
      key == LogicalKeyboardKey.info ||
      key == LogicalKeyboardKey.guide ||
      key == LogicalKeyboardKey.f1 ||
      key == LogicalKeyboardKey.keyM ||
      key == LogicalKeyboardKey.appSwitch;

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;

    if (event is KeyRepeatEvent &&
        (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter)) {
      _showBanner(resetToPlaying: true, openOptions: true);
      return KeyEventResult.handled;
    }

    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.escape) {
      if (event is KeyDownEvent) _handleBack();
      return KeyEventResult.handled;
    }

    final digit = _digitFromKeyEvent(event);
    if (digit != null && _openPicker == null) {
      if (event is KeyDownEvent) {
        _appendTypedDigit(digit);
      }
      return KeyEventResult.handled;
    }

    if (_openPicker != null) {
      if (key == LogicalKeyboardKey.arrowUp && _pickerItems.isNotEmpty) {
        setState(() {
          _pickerFocusedIdx = (_pickerFocusedIdx - 1 + _pickerItems.length) % _pickerItems.length;
        });
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown && _pickerItems.isNotEmpty) {
        setState(() {
          _pickerFocusedIdx = (_pickerFocusedIdx + 1) % _pickerItems.length;
        });
        return KeyEventResult.handled;
      }
      if ((key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.numpadEnter) &&
          event is KeyDownEvent) {
        _applyPickerSelection(_pickerFocusedIdx);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (_isMenuKey(key) && event is KeyDownEvent) {
      if (_bannerVisible && _optionsMode && _previewIndex == _playingIndex) {
        setState(() => _optionsMode = false);
        _scheduleBannerAutoHide();
      } else {
        _showBanner(resetToPlaying: true, openOptions: true);
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.mediaPlayPause || key == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent) {
        _togglePlayPause();
        _showBanner();
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.channelUp) {
      if (event is KeyDownEvent) _switchChannelDirectly(_playingIndex + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.channelDown) {
      if (event is KeyDownEvent) _switchChannelDirectly(_playingIndex - 1);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      _triggerLeft();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _triggerRight();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _triggerUp();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _triggerDown();
      return KeyEventResult.handled;
    }

    if ((key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter) &&
        event is KeyDownEvent) {
      _triggerOk();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  String _clockHeaderText() {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dayName = days[(_now.weekday - 1).clamp(0, 6)];
    final h24 = _now.hour;
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    final min = _now.minute.toString().padLeft(2, '0');
    final ampm = h24 >= 12 ? 'pm' : 'am';
    return '$dayName, ${months[_now.month - 1]} ${_now.day}  |  $h12:$min $ampm';
  }

  BoxFit get _videoBoxFit {
    switch (_resizeMode) {
      case 'fit':
        return BoxFit.contain;
      case 'zoom':
        return BoxFit.cover;
      default:
        return BoxFit.fill;
    }
  }

  @override
  Widget build(BuildContext context) {
    final previewCh = _previewChannel;
    final activeProgram = _activeProgram;
    final size = MediaQuery.sizeOf(context);
    final compactLayout = !widget.isTv || size.width < 720 || size.height < 500;
    final narrowCompact = size.width < 540;
    final posterWidth = narrowCompact ? 148.0 : (compactLayout ? 250.0 : 340.0);
    final posterHeight = narrowCompact ? 104.0 : (compactLayout ? 150.0 : 192.0);
    final titleRowHeight = narrowCompact ? 30.0 : (compactLayout ? 32.0 : 36.0);
    final middleSlotHeight = narrowCompact ? 76.0 : (compactLayout ? 80.0 : 92.0);
    final topPadInsideStrip = narrowCompact ? 4.0 : (compactLayout ? 5.0 : 6.0);
    final rowGap = narrowCompact ? 4.0 : (compactLayout ? 6.0 : 8.0);
    final rightContentHeight =
        topPadInsideStrip + titleRowHeight + rowGap + middleSlotHeight + rowGap + 3.0;
    final stripTopOffset = math.max(0.0, posterHeight - rightContentHeight);
    final progKey = ValueKey('${previewCh.id}_$_programIndex');
    final posterKey = ValueKey('poster_${previewCh.id}_$_programIndex');
    final displayChannelNumber =
        previewCh.channelNumber > 0 ? previewCh.channelNumber : (_previewIndex + 101);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _handleBack();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _playerFocus,
          autofocus: true,
          onKeyEvent: _onKeyEvent,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_openPicker != null) {
                setState(() => _openPicker = null);
                _scheduleBannerAutoHide();
              } else if (_bannerVisible) {
                setState(() {
                  _bannerVisible = false;
                  _optionsMode = false;
                });
                _bannerAutoHideTimer?.cancel();
              } else {
                _showBanner(resetToPlaying: true);
              }
            },
            onDoubleTap: (!widget.isTv && _openPicker == null) ? _triggerOk : null,
            onLongPress: !widget.isTv
                ? () => _showBanner(resetToPlaying: true, openOptions: true)
                : null,
            onPanStart: (!widget.isTv && _openPicker == null)
                ? (_) {
                    _panDeltaX = 0;
                    _panDeltaY = 0;
                  }
                : null,
            onPanUpdate: (!widget.isTv && _openPicker == null)
                ? (d) {
                    _panDeltaX += d.delta.dx;
                    _panDeltaY += d.delta.dy;
                  }
                : null,
            onPanEnd: (!widget.isTv && _openPicker == null)
                ? (d) {
                    final vx = d.velocity.pixelsPerSecond.dx;
                    final vy = d.velocity.pixelsPerSecond.dy;
                    if (_panDeltaX.abs() >= _panDeltaY.abs()) {
                      if (_panDeltaX < -32 || vx < -220) {
                        _triggerRight();
                      } else if (_panDeltaX > 32 || vx > 220) {
                        _triggerLeft();
                      }
                    } else {
                      if (_panDeltaY < -28 || vy < -200) {
                        _triggerDown();
                      } else if (_panDeltaY > 28 || vy > 200) {
                        _triggerUp();
                      }
                    }
                  }
                : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                IgnorePointer(
                  child: _useSecurePlatformView
                      ? RepaintBoundary(
                          child: PlatformViewLink(
                            viewType: 'anas_tv/media3_player',
                            surfaceFactory: (context, controller) => AndroidViewSurface(
                              controller: controller as AndroidViewController,
                              gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
                              hitTestBehavior: PlatformViewHitTestBehavior.transparent,
                            ),
                            onCreatePlatformView: (params) {
                              return PlatformViewsService.initExpensiveAndroidView(
                                id: params.id,
                                viewType: 'anas_tv/media3_player',
                                layoutDirection: TextDirection.ltr,
                                creationParams: const <String, dynamic>{},
                                creationParamsCodec: const StandardMessageCodec(),
                                onFocus: () => params.onFocusChanged(true),
                              )
                                ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
                                ..addOnPlatformViewCreatedListener(_created)
                                ..create();
                            },
                          ),
                        )
                      : (_textureId != null
                          ? SizedBox.expand(
                              child: ClipRect(
                                child: FittedBox(
                                  fit: _videoBoxFit,
                                  child: SizedBox(
                                    width: _videoWidth,
                                    height: _videoHeight,
                                    child: Texture(textureId: _textureId!),
                                  ),
                                ),
                              ),
                            )
                          : const ColoredBox(color: Colors.black)),
                ),
                if (_loading) const Center(child: _BrandCircularLoader(size: 84)),
                if (_error != null)
                  Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xE6101218),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0x40FFFFFF)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, color: Color(0xFFE65312), size: 38),
                          const SizedBox(height: 10),
                          SelectableText(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE65312)),
                                onPressed: () => _startChannelStream(_previewIndex),
                                child: const Text('Retry'),
                              ),
                              const SizedBox(width: 12),
                              TextButton(
                                onPressed: _exitPlayer,
                                child: const Text('Back to channels'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_bannerVisible)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: EdgeInsets.fromLTRB(
                        compactLayout ? 14 : 26,
                        compactLayout ? 10 : 14,
                        compactLayout ? 14 : 26,
                        12,
                      ),
                      color: Colors.transparent,
                      child: SafeArea(
                        bottom: false,
                        child: Row(
                          children: [
                            Text(
                              _clockHeaderText(),
                              style: TextStyle(
                                fontFamily: 'Anton',
                                color: Colors.white,
                                fontSize: compactLayout ? 21 : 26,
                                fontWeight: FontWeight.w400,
                                letterSpacing: 0.55,
                                shadows: _textShadows,
                              ),
                            ),
                            const Spacer(),
                            if (_isPaused)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE65312),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'PAUSED',
                                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_bannerVisible)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.bottomLeft,
                      children: [
                        Positioned(
                          left: 0,
                          right: 0,
                          top: stripTopOffset,
                          bottom: 0,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.10),
                                  Colors.black.withValues(alpha: 0.20),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SafeArea(
                          top: false,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              compactLayout ? 14 : 28,
                              0,
                              compactLayout ? 14 : 28,
                              compactLayout ? 10 : 16,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                RepaintBoundary(
                                  child: SizedBox(
                                    width: posterWidth,
                                    height: posterHeight,
                                    child: ClipRect(
                                      child: AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 180),
                                        switchInCurve: Curves.easeOutCubic,
                                        switchOutCurve: Curves.easeInCubic,
                                        layoutBuilder: (currentChild, previousChildren) => Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            ...previousChildren,
                                            if (currentChild != null) currentChild,
                                          ],
                                        ),
                                        transitionBuilder: (child, animation) {
                                          final isIncoming = child.key == posterKey;
                                          final beginOffset = isIncoming
                                              ? Offset(0, _programAnimDir >= 0 ? 0.30 : -0.30)
                                              : Offset(0, _programAnimDir >= 0 ? -0.25 : 0.25);
                                          return FadeTransition(
                                            opacity: animation,
                                            child: SlideTransition(
                                              position: Tween<Offset>(
                                                begin: beginOffset,
                                                end: Offset.zero,
                                              ).animate(animation),
                                              child: child,
                                            ),
                                          );
                                        },
                                        child: KeyedSubtree(
                                          key: posterKey,
                                          child: _ProgramPoster(
                                            primaryUrl: activeProgram.posterUrl,
                                            fallbackUrl: activeProgram.fallbackPosterUrl,
                                            title: activeProgram.title,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: compactLayout ? 14 : 22),
                                Expanded(
                                  child: RepaintBoundary(
                                    child: SizedBox(
                                      height: rightContentHeight,
                                      child: Padding(
                                        padding: EdgeInsets.only(top: topPadInsideStrip),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            SizedBox(
                                              height: titleRowHeight,
                                              child: Row(
                                                crossAxisAlignment: CrossAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    '$displayChannelNumber',
                                                    style: TextStyle(
                                                      fontFamily: 'Anton',
                                                      color: Colors.white,
                                                      fontSize: compactLayout ? 22 : 27,
                                                      height: 1.08,
                                                      fontWeight: FontWeight.w400,
                                                      letterSpacing: 0.8,
                                                      shadows: _textShadows,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Text(
                                                      previewCh.name,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontFamily: 'Anton',
                                                        color: Colors.white,
                                                        fontSize: compactLayout ? 21 : 26,
                                                        height: 1.08,
                                                        fontWeight: FontWeight.w400,
                                                        letterSpacing: 0.55,
                                                        shadows: _textShadows,
                                                      ),
                                                    ),
                                                  ),
                                                  if (_previewIndex == _playingIndex) ...[
                                                    const SizedBox(width: 8),
                                                    InkWell(
                                                      onTap: () => _showBanner(openOptions: !_optionsMode),
                                                      borderRadius: BorderRadius.circular(6),
                                                      hoverColor: Colors.white.withValues(alpha: 0.16),
                                                      focusColor: Colors.white.withValues(alpha: 0.22),
                                                      highlightColor: Colors.white.withValues(alpha: 0.12),
                                                      child: Container(
                                                        width: compactLayout ? 30 : 34,
                                                        height: compactLayout ? 30 : 34,
                                                        alignment: Alignment.center,
                                                        decoration: BoxDecoration(
                                                          color: _optionsMode
                                                              ? Colors.white.withValues(alpha: 0.22)
                                                              : Colors.transparent,
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: Icon(
                                                          Icons.tune_rounded,
                                                          size: compactLayout ? 19 : 21,
                                                          color: Colors.white,
                                                          shadows: _textShadows,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            SizedBox(height: rowGap),
                                            SizedBox(
                                              height: middleSlotHeight,
                                              width: double.infinity,
                                              child: _optionsMode
                                                  ? Align(
                                                      alignment: Alignment.centerLeft,
                                                      child: _buildStbOptionsBar(),
                                                    )
                                                  : Align(
                                                      alignment: Alignment.topLeft,
                                                      child: ClipRect(
                                                        child: AnimatedSwitcher(
                                                          duration: const Duration(milliseconds: 180),
                                                          switchInCurve: Curves.easeOutCubic,
                                                          switchOutCurve: Curves.easeInCubic,
                                                          layoutBuilder: (currentChild, previousChildren) => Stack(
                                                            alignment: Alignment.topLeft,
                                                            children: [
                                                              ...previousChildren,
                                                              if (currentChild != null) currentChild,
                                                            ],
                                                          ),
                                                          transitionBuilder: (child, animation) {
                                                            final isIncoming = child.key == progKey;
                                                            final beginOffset = isIncoming
                                                                ? Offset(0, _programAnimDir >= 0 ? 0.35 : -0.35)
                                                                : Offset(0, _programAnimDir >= 0 ? -0.30 : 0.30);
                                                            return FadeTransition(
                                                              opacity: animation,
                                                              child: SlideTransition(
                                                                position: Tween<Offset>(
                                                                  begin: beginOffset,
                                                                  end: Offset.zero,
                                                                ).animate(animation),
                                                                child: child,
                                                              ),
                                                            );
                                                          },
                                                          child: KeyedSubtree(
                                                            key: progKey,
                                                            child: _buildStbProgramDetails(
                                                              activeProgram,
                                                              compactLayout: compactLayout,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                            ),
                                            const Spacer(),
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(2),
                                              child: LinearProgressIndicator(
                                                minHeight: 3,
                                                value: activeProgram.isLiveNow ? activeProgram.progress : 0.0,
                                                backgroundColor: Colors.white.withValues(alpha: 0.25),
                                                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE53935)),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_openPicker != null) _buildStbTrackPickerOverlay(),
                if (_typedDigits.isNotEmpty || _digitOsdError != null)
                  Positioned(
                    top: 16,
                    right: 24,
                    child: SafeArea(
                      child: _StbChannelNumberOsd(
                        digits: _typedDigits,
                        previewChannelName: _typedPreviewChannelName,
                        errorMessage: _digitOsdError,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStbProgramDetails(_StbProgram program, {required bool compactLayout}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          program.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Anton',
            color: Colors.white,
            fontSize: compactLayout ? 16 : 19,
            height: 1.15,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.45,
            shadows: _textShadows,
          ),
        ),
        SizedBox(height: compactLayout ? 4 : 5),
        Text(
          program.timeLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Anton',
            color: const Color(0xFFF0F4FA),
            fontSize: compactLayout ? 13 : 14.5,
            height: 1.15,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.45,
            shadows: _textShadows,
          ),
        ),
        SizedBox(height: compactLayout ? 4 : 5),
        Text(
          program.description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: const Color(0xFFD6DCE8),
            fontSize: compactLayout ? 11 : 12.5,
            height: 1.30,
            shadows: _textShadows,
          ),
        ),
      ],
    );
  }

  Widget _buildStbOptionsBar() {
    const options = [
      Icons.audiotrack_rounded,
      Icons.hd_rounded,
      Icons.aspect_ratio_rounded,
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(options.length, (i) {
          final selected = _selectedOptionIdx == i;
          final iconData = options[i];
          return Padding(
            padding: const EdgeInsets.only(right: 16),
            child: InkWell(
              onTap: () => _triggerOption(i),
              borderRadius: BorderRadius.circular(6),
              hoverColor: Colors.white.withValues(alpha: 0.16),
              focusColor: Colors.white.withValues(alpha: 0.22),
              highlightColor: Colors.white.withValues(alpha: 0.12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 110),
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? Colors.white.withValues(alpha: 0.22) : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  iconData,
                  color: selected ? Colors.white : Colors.white.withValues(alpha: 0.85),
                  size: 23,
                  shadows: _textShadows,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStbTrackPickerOverlay() {
    final kind = _openPicker!;
    final title = kind == _StbPickerKind.audio
        ? 'Audio Track'
        : kind == _StbPickerKind.quality
            ? 'Video Quality'
            : 'Screen Stretch Mode';

    return Container(
      color: Colors.black.withValues(alpha: 0.24),
      alignment: Alignment.center,
      child: GestureDetector(
        onTap: () {},
        child: Container(
          width: 340,
          constraints: const BoxConstraints(maxHeight: 320),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      shadows: _textShadows,
                    ),
                  ),
                  const Spacer(),
                  if (!widget.isTv)
                    InkWell(
                      onTap: () {
                        setState(() => _openPicker = null);
                        _scheduleBannerAutoHide();
                      },
                      borderRadius: BorderRadius.circular(4),
                      hoverColor: Colors.white.withValues(alpha: 0.16),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (_pickerLoading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2.5),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _pickerItems.length,
                    itemBuilder: (context, idx) {
                      final item = _pickerItems[idx];
                      final focused = idx == _pickerFocusedIdx;
                      final active = item['selected'] == true;
                      return InkWell(
                        onTap: () => _applyPickerSelection(idx),
                        borderRadius: BorderRadius.circular(4),
                        hoverColor: Colors.white.withValues(alpha: 0.16),
                        focusColor: Colors.white.withValues(alpha: 0.22),
                        highlightColor: Colors.white.withValues(alpha: 0.12),
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: focused
                                ? Colors.white.withValues(alpha: 0.22)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  (item['label'] ?? '').toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: focused || active ? Colors.white : Colors.white.withValues(alpha: 0.86),
                                    fontSize: 13.5,
                                    fontWeight: focused || active ? FontWeight.w700 : FontWeight.w500,
                                    shadows: _textShadows,
                                  ),
                                ),
                              ),
                              if (active)
                                const Icon(
                                  Icons.check_rounded,
                                  size: 18,
                                  color: Colors.white,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgramPoster extends StatefulWidget {
  final String primaryUrl;
  final String fallbackUrl;
  final String title;

  const _ProgramPoster({
    required this.primaryUrl,
    required this.fallbackUrl,
    required this.title,
  });

  @override
  State<_ProgramPoster> createState() => _ProgramPosterState();
}

class _ProgramPosterState extends State<_ProgramPoster> {
  int _attempt = 0;

  @override
  void didUpdateWidget(covariant _ProgramPoster oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.primaryUrl != widget.primaryUrl ||
        oldWidget.fallbackUrl != widget.fallbackUrl) {
      _attempt = 0;
    }
  }

  List<String> get _candidates => [
        widget.primaryUrl,
        widget.fallbackUrl,
      ].where((u) => u.trim().isNotEmpty).toSet().toList();

  Widget _placeholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1D2230), Color(0xFF0D1017)],
        ),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.live_tv_rounded, size: 38, color: Color(0xFFE65312)),
          if (widget.title.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              widget.title,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final urls = _candidates;
    if (_attempt >= urls.length) {
      return _placeholder();
    }
    final url = urls[_attempt];

    return ColoredBox(
      color: Colors.white,
      child: CachedNetworkImage(
        imageUrl: url,
        httpHeaders: _imageHeadersFor(url),
        fit: BoxFit.fill,
        width: double.infinity,
        height: double.infinity,
        memCacheWidth: 640,
        memCacheHeight: 360,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        useOldImageOnUrlChange: true,
        placeholder: (_, __) => _placeholder(),
        errorWidget: (_, __, ___) {
          if (_attempt + 1 < urls.length) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _attempt++);
            });
          }
          return _placeholder();
        },
      ),
    );
  }
}

class _ChannelCard extends StatefulWidget {
  final TvChannel channel;
  final bool isTv;
  final bool autofocus;
  final FocusNode? focusNode;
  final FocusOnKeyEventCallback? onKeyEvent;
  final VoidCallback onTap;

  const _ChannelCard({
    required this.channel,
    required this.isTv,
    required this.onTap,
    this.autofocus = false,
    this.focusNode,
    this.onKeyEvent,
  });

  @override
  State<_ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends State<_ChannelCard> {
  bool focused = false;
  bool hovered = false;

  void _ensureVisible() {
    final ro = context.findRenderObject();
    if (ro == null || !ro.attached) return;
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) return;
    final viewport = RenderAbstractViewport.maybeOf(ro);
    if (viewport == null) return;
    final pos = scrollable.position;
    final topOffset = viewport.getOffsetToReveal(ro, 0.0).offset - 14.0;
    final bottomOffset = viewport.getOffsetToReveal(ro, 1.0).offset + 14.0;
    if (pos.pixels < bottomOffset) {
      pos.animateTo(
        bottomOffset.clamp(pos.minScrollExtent, pos.maxScrollExtent),
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
      );
    } else if (pos.pixels > topOffset) {
      pos.animateTo(
        topOffset.clamp(pos.minScrollExtent, pos.maxScrollExtent),
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final showTvFocus = widget.isTv && (focused || hovered);
    final cardColor = showTvFocus ? const Color(0xFFE65312) : const Color(0xFF080808);
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final h = box.maxHeight;
      final logoSize = math.min(w * 0.68, h * 0.65);
      final nameSize = (w * 0.13).clamp(9.0, 16.0).toDouble();
      return Material(
        color: Colors.transparent,
        elevation: showTvFocus ? 24 : 0,
        child: AnimatedScale(
        scale: showTvFocus ? 1.16 : 1.0,
        duration: const Duration(milliseconds: 85),
        curve: Curves.easeOut,
        child: Focus(
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          canRequestFocus: widget.isTv,
          onKeyEvent: widget.onKeyEvent,
          onFocusChange: (value) {
            if (widget.isTv) {
              setState(() => focused = value);
              if (value) _ensureVisible();
            }
          },
          child: MouseRegion(
            onEnter: (_) {
              if (widget.isTv) setState(() => hovered = true);
            },
            onExit: (_) {
              if (widget.isTv) setState(() => hovered = false);
            },
            child: GestureDetector(
              onTap: widget.onTap,
              child: Container(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 5),
                decoration: BoxDecoration(
                  color: cardColor,
                  border: showTvFocus
                      ? null
                      : Border.all(color: const Color(0xFFD94B0A), width: 1.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SizedBox(
                      width: logoSize,
                      height: logoSize,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF5CCFE0),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: showTvFocus ? Colors.white : const Color(0xFFD94B0A),
                            width: 1.1,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        padding: EdgeInsets.all(logoSize * 0.08),
                        child: _ChannelLogo(
                          primaryUrl: widget.channel.logo,
                          fallbackUrl: widget.channel.fallbackLogo,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: nameSize * 1.38,
                      width: double.infinity,
                      child: Center(
                        child: _ChannelMarquee(
                          text: widget.channel.name,
                          animate: !widget.isTv || showTvFocus,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: nameSize,
                            height: 1.05,
                            fontWeight: showTvFocus ? FontWeight.w700 : FontWeight.w500,
                            fontFamily: 'Roboto',
                            letterSpacing: -.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        ),
      );
    });
  }
}

class _ChannelMarquee extends StatefulWidget {
  final String text;
  final TextStyle style;
  final bool animate;

  const _ChannelMarquee({
    required this.text,
    required this.style,
    this.animate = true,
  });

  @override
  State<_ChannelMarquee> createState() => _ChannelMarqueeState();
}

class _ChannelMarqueeState extends State<_ChannelMarquee> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _running = false;
  double _lastDistance = 0;
  static const double _gap = 34;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(covariant _ChannelMarquee oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || (!widget.animate && _running)) {
      _running = false;
      _lastDistance = 0;
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) {
      return Text(
        widget.text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: widget.style,
      );
    }

    return LayoutBuilder(builder: (context, constraints) {
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: widget.style),
        maxLines: 1,
        textDirection: Directionality.of(context),
      )..layout();
      final textWidth = painter.width;
      if (textWidth <= constraints.maxWidth || constraints.maxWidth <= 0) {
        _running = false;
        _controller.stop();
        return ClipRect(
          child: Text(
            widget.text,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: widget.style,
          ),
        );
      }
      final distance = textWidth + _gap;
      if (!_running || (_lastDistance - distance).abs() > 1) {
        _running = true;
        _lastDistance = distance;
        _controller.duration = Duration(milliseconds: ((distance / 38) * 1000).round().clamp(1800, 18000).toInt());
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _running) _controller.repeat();
        });
      }
      return ClipRect(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => Transform.translate(
            offset: Offset(-distance * _controller.value, 0),
            child: child,
          ),
          child: SizedBox(
            width: distance + textWidth,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: textWidth, child: Text(widget.text, maxLines: 1, softWrap: false, style: widget.style)),
                const SizedBox(width: _gap),
                SizedBox(width: textWidth, child: Text(widget.text, maxLines: 1, softWrap: false, style: widget.style)),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _ChannelLogo extends StatefulWidget {
  final String primaryUrl, fallbackUrl;
  const _ChannelLogo({
    required this.primaryUrl,
    required this.fallbackUrl,
  });
  @override
  State<_ChannelLogo> createState() => _ChannelLogoState();
}

class _ChannelLogoState extends State<_ChannelLogo> {
  int _attempt = 0;

  @override
  void didUpdateWidget(covariant _ChannelLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.primaryUrl != widget.primaryUrl ||
        oldWidget.fallbackUrl != widget.fallbackUrl) {
      _attempt = 0;
    }
  }

  List<String> get _candidates {
    final out = <String>[];
    void addUrl(String raw) {
      final clean = raw.trim();
      if (clean.isNotEmpty && !out.contains(clean)) {
        out.add(clean);
      }
    }

    addUrl(widget.primaryUrl);
    if (widget.primaryUrl.contains('://www.sonypicturesnetworks.com/')) {
      addUrl(widget.primaryUrl.replaceFirst(
        '://www.sonypicturesnetworks.com/',
        '://sonypicturesnetworks.com/',
      ));
    }
    addUrl(widget.fallbackUrl);
    if (widget.fallbackUrl.contains('jiotvimages.cdn.jio.com/')) {
      addUrl(widget.fallbackUrl.replaceFirst(
        'jiotvimages.cdn.jio.com/',
        'jiotv.catchup.cdn.jio.com/',
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final urls = _candidates;
    if (_attempt >= urls.length) {
      return const Center(child: Icon(Icons.tv_rounded, size: 28, color: Color(0xFF163842)));
    }
    final url = urls[_attempt];
    return CachedNetworkImage(
      imageUrl: url,
      httpHeaders: _imageHeadersFor(url),
      fit: BoxFit.contain,
      memCacheWidth: 140,
      memCacheHeight: 140,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      useOldImageOnUrlChange: true,
      errorWidget: (_, __, ___) {
        if (_attempt + 1 < urls.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _attempt++);
          });
        }
        return const Center(child: Icon(Icons.tv_rounded, size: 28, color: Color(0xFF163842)));
      },
    );
  }
}
