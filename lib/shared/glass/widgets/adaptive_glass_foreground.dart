import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../settings/folio_settings_scope.dart';

/// Fraction down from the top of a glass rect used as the shared backdrop
/// sample. One point per control keeps black/white stable; per-pixel sampling
/// would shimmer on gradients. Single helper so fixed/morph/search never drift.
const kAdaptiveSampleHeightFraction = 0.2;

/// Shared sample point near the top of [rect] (same 0.2 rule everywhere).
Offset adaptiveGlassSamplePoint(Rect rect) => Offset(
  rect.center.dx,
  rect.top + rect.height * kAdaptiveSampleHeightFraction,
);

/// Outline keeping white fallbacks readable on light backdrops. Shared by
/// [_OutlinedIcon] and [_OutlinedText] so the safe path never drifts.
const kAdaptiveOutlineShadows = <Shadow>[
  Shadow(color: Color(0xFF000000), blurRadius: 3),
  Shadow(color: Color(0xFF000000), blurRadius: 1),
];

/// Defines one shared backdrop sample point for every adaptive glyph in a
/// liquid-glass control. The default is the center of this render box.
class AdaptiveGlassForegroundGroup extends SingleChildRenderObjectWidget {
  const AdaptiveGlassForegroundGroup({
    required super.child,
    this.samplePoint,
    super.key,
  });

  final Offset? samplePoint;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAdaptiveGlassGroup(samplePoint);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    final group = renderObject as _RenderAdaptiveGlassGroup;
    group
      ..samplePoint = samplePoint
      // A Stack can move a glyph by changing parent data without repainting
      // the glyph render object itself. Its filter uses screen-space bounds,
      // so invalidate those retained bounds whenever the owning control is
      // rebuilt by its motion controller.
      ..invalidateAdaptiveDescendantGeometry();
  }
}

class _RenderAdaptiveGlassGroup extends RenderProxyBox {
  _RenderAdaptiveGlassGroup(this._samplePoint);

  Offset? _samplePoint;

  set samplePoint(Offset? value) {
    if (value == _samplePoint) {
      return;
    }
    _samplePoint = value;
    markNeedsPaint();
  }

  Offset get globalSamplePoint =>
      localToGlobal(_samplePoint ?? (Offset.zero & size).center);

  void invalidateAdaptiveDescendantGeometry() {
    void invalidate(RenderObject child) {
      if (child is _RenderAdaptiveBackdrop) {
        child.invalidateAncestorGeometry();
      }
      child.visitChildren(invalidate);
    }

    visitChildren(invalidate);
  }
}

/// An icon whose black/white foreground is computed by the GPU from the
/// shared sample point of its nearest [AdaptiveGlassForegroundGroup].
///
/// The widget never reads pixels back to the CPU and never schedules tone
/// updates. Each painted frame therefore reflects the current backdrop.
///
/// `style` color/shadows are ignored: the shader outputs pure black or white
/// (fallback: white with [kAdaptiveOutlineShadows]).
class AdaptiveGlassIcon extends StatelessWidget {
  const AdaptiveGlassIcon(
    this.icon, {
    this.size = 24,
    this.semanticLabel,
    super.key,
  });

  final IconData icon;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    if (!FolioSettingsScope.blurEnabledOf(context)) {
      return Icon(
        icon,
        size: size,
        semanticLabel: semanticLabel,
        color: const Color(0xFFFFFFFF),
      );
    }
    final shaderSupported =
        AdaptiveGlassDebug.shaderFilterSupportedOverride ??
        ui.ImageFilter.isShaderFilterSupported;
    if (!shaderSupported) {
      return _OutlinedIcon(
        icon: icon,
        size: size,
        semanticLabel: semanticLabel,
      );
    }
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    Widget glyph = AdaptiveGlassText(
      String.fromCharCode(icon.codePoint),
      textDirection: direction,
      semanticsLabel: semanticLabel ?? '',
      style: TextStyle(
        inherit: false,
        color: const Color(0xFFFFFFFF),
        fontSize: size,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        fontFamilyFallback: icon.fontFamilyFallback,
        height: 1,
        leadingDistribution: TextLeadingDistribution.even,
      ),
    );
    if (icon.matchTextDirection && direction == TextDirection.rtl) {
      glyph = Transform.flip(flipX: true, child: glyph);
    }
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: SizedBox.square(dimension: size, child: glyph),
    );
  }
}

/// Text whose whole black/white foreground is computed by the GPU from the
/// shared sample point of its nearest [AdaptiveGlassForegroundGroup].
///
/// [style.color] and [style.shadows] are ignored: the glyph mask is always
/// built white and the shader (or the outlined fallback) decides the visible
/// tone, so callers must not rely on a custom color.
class AdaptiveGlassText extends StatelessWidget {
  const AdaptiveGlassText(
    this.data, {
    required this.style,
    this.maxLines = 1,
    this.overflow,
    this.softWrap = true,
    this.textAlign,
    this.textDirection,
    this.textScaler,
    this.semanticsLabel,
    super.key,
  });

  final String data;
  final TextStyle style;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool softWrap;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final TextScaler? textScaler;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    if (!FolioSettingsScope.blurEnabledOf(context)) {
      return Text(
        data,
        style: style.copyWith(
          color: const Color(0xFFFFFFFF),
          shadows: const <Shadow>[],
        ),
        maxLines: maxLines,
        overflow: overflow,
        softWrap: softWrap,
        textAlign: textAlign,
        textDirection: textDirection,
        textScaler: textScaler,
        semanticsLabel: semanticsLabel,
      );
    }
    final effectiveStyle = DefaultTextStyle.of(context).style.merge(style);
    final direction = textDirection ?? Directionality.of(context);
    final scaler = textScaler ?? MediaQuery.textScalerOf(context);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final layoutWidth = softWrap && constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : double.infinity;
        final painter = _textPainter(
          data: data,
          style: effectiveStyle,
          direction: direction,
          scaler: scaler,
          maxLines: maxLines,
          overflow: overflow,
          textAlign: textAlign,
        )..layout(maxWidth: layoutWidth);
        final size = constraints.constrain(painter.size);
        painter.dispose();
        final key = _TextMaskKey(
          data,
          effectiveStyle,
          direction,
          scaler,
          maxLines,
          overflow,
          textAlign,
          size,
          pixelRatio,
        );
        final fallback = _OutlinedText(
          data: data,
          style: effectiveStyle,
          maxLines: maxLines,
          overflow: overflow,
          softWrap: softWrap,
          textAlign: textAlign,
          textDirection: direction,
          textScaler: scaler,
          semanticsLabel: semanticsLabel,
        );
        return Semantics(
          label: semanticsLabel ?? data,
          excludeSemantics: true,
          child: SizedBox.fromSize(
            size: size,
            child: _AdaptiveMaskSurface(
              maskKey: key,
              createMask: () => _createTextMask(key),
              fallback: fallback,
            ),
          ),
        );
      },
    );
  }
}

TextPainter _textPainter({
  required String data,
  required TextStyle style,
  required TextDirection direction,
  required TextScaler scaler,
  required int? maxLines,
  required TextOverflow? overflow,
  required TextAlign? textAlign,
}) {
  return TextPainter(
    text: TextSpan(
      text: data,
      style: style.copyWith(
        color: const Color(0xFFFFFFFF),
        backgroundColor: const Color(0x00000000),
        shadows: const <Shadow>[],
      ),
    ),
    textDirection: direction,
    textScaler: scaler,
    maxLines: maxLines,
    ellipsis: overflow == TextOverflow.ellipsis ? '\u2026' : null,
    textAlign: textAlign ?? TextAlign.start,
    textWidthBasis: TextWidthBasis.parent,
  );
}

class _AdaptiveMaskSurface extends StatefulWidget {
  const _AdaptiveMaskSurface({
    required this.maskKey,
    required this.createMask,
    required this.fallback,
  });

  final _MaskKey maskKey;
  final ui.Image Function() createMask;
  final Widget fallback;

  @override
  State<_AdaptiveMaskSurface> createState() => _AdaptiveMaskSurfaceState();
}

class _AdaptiveMaskSurfaceState extends State<_AdaptiveMaskSurface> {
  ui.Image? _mask;
  int _programRequest = 0;

  bool get _shaderSupported =>
      AdaptiveGlassDebug.shaderFilterSupportedOverride ??
      ui.ImageFilter.isShaderFilterSupported;

  @override
  void initState() {
    super.initState();
    if (_shaderSupported) {
      _acquireMask();
    }
    _loadProgram();
  }

  @override
  void didUpdateWidget(_AdaptiveMaskSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.maskKey != widget.maskKey) {
      if (_mask != null) {
        _releaseMask(oldWidget.maskKey);
      }
      if (_shaderSupported) {
        _acquireMask();
      }
    }
    // Fallback is consumed directly by build; no resource update needed.
  }

  void _acquireMask() {
    _mask = _GlassMaskCache.acquire(widget.maskKey, widget.createMask);
  }

  void _releaseMask(_MaskKey key) {
    _GlassMaskCache.release(key);
    _mask = null;
  }

  Future<void> _loadProgram() async {
    if (!_shaderSupported) {
      return;
    }
    final request = ++_programRequest;
    final program = await _AdaptiveGlassProgram.load();
    if (!mounted || request != _programRequest || program == null) {
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _programRequest++;
    if (_mask != null) {
      _releaseMask(widget.maskKey);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final program = _AdaptiveGlassProgram.program;
    if (program == null || _mask == null) {
      return widget.fallback;
    }
    // Keep a normal Flutter glyph below the runtime-effect layer. Some older
    // Android GPU drivers report shader-filter support but temporarily drop a
    // BackdropFilter when it is nested in an opacity/image-filter/transform
    // animation. The underlay makes that failure mode visible and harmless;
    // the adaptive result remains on top whenever the driver renders it.
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        widget.fallback,
        _AdaptiveBackdrop(
          program: program,
          mask: _mask!,
          devicePixelRatio: widget.maskKey.pixelRatio,
        ),
      ],
    );
  }
}

class _AdaptiveBackdrop extends LeafRenderObjectWidget {
  const _AdaptiveBackdrop({
    required this.program,
    required this.mask,
    required this.devicePixelRatio,
  });

  final ui.FragmentProgram program;
  final ui.Image mask;
  final double devicePixelRatio;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAdaptiveBackdrop(program, mask, devicePixelRatio);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderAdaptiveBackdrop renderObject,
  ) {
    renderObject
      ..program = program
      ..mask = mask
      ..devicePixelRatio = devicePixelRatio;
  }
}

class _RenderAdaptiveBackdrop extends RenderBox {
  _RenderAdaptiveBackdrop(this._program, this._mask, this._devicePixelRatio);

  ui.FragmentProgram _program;
  ui.Image _mask;
  double _devicePixelRatio;
  Rect? _physicalBounds;
  Offset? _physicalSamplePoint;
  ui.FragmentShader? _shader;
  ui.ImageFilter? _filter;
  bool _filterCreationFailed = false;

  static final Paint _coveragePaint = Paint()
    ..color = const Color.fromARGB(1, 0, 0, 0);

  set program(ui.FragmentProgram value) {
    if (identical(value, _program)) {
      return;
    }
    _program = value;
    _invalidateFilter();
  }

  set mask(ui.Image value) {
    if (identical(value, _mask)) {
      return;
    }
    _mask = value;
    _invalidateFilter();
  }

  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) {
      return;
    }
    _devicePixelRatio = value;
    _invalidateFilter();
  }

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void performLayout() {
    size = constraints.biggest;
  }

  void _invalidateFilter() {
    _physicalBounds = null;
    _physicalSamplePoint = null;
    _filter = null;
    _filterCreationFailed = false;
    _shader?.dispose();
    _shader = null;
    markNeedsPaint();
  }

  void invalidateAncestorGeometry() {
    // Re-evaluate actual screen-space geometry in paint. Do not discard the
    // shader merely because an ancestor rebuilt with identical bounds.
    markNeedsPaint();
  }

  void _ensureFilter() {
    final globalBounds = MatrixUtils.transformRect(
      getTransformTo(null),
      Offset.zero & size,
    );
    final physicalBounds = Rect.fromLTWH(
      globalBounds.left * _devicePixelRatio,
      globalBounds.top * _devicePixelRatio,
      globalBounds.width * _devicePixelRatio,
      globalBounds.height * _devicePixelRatio,
    );
    final group = _findGroup();
    final samplePoint =
        (group?.globalSamplePoint ??
            physicalBounds.center / _devicePixelRatio) *
        _devicePixelRatio;
    if ((_filter != null || _filterCreationFailed) &&
        physicalBounds == _physicalBounds &&
        samplePoint == _physicalSamplePoint) {
      return;
    }

    final oldShader = _shader;
    ui.FragmentShader? shader;
    try {
      shader = _program.fragmentShader()
        ..setFloat(2, physicalBounds.left)
        ..setFloat(3, physicalBounds.top)
        ..setFloat(4, physicalBounds.width)
        ..setFloat(5, physicalBounds.height)
        ..setFloat(6, samplePoint.dx)
        ..setFloat(7, samplePoint.dy)
        ..setImageSampler(1, _mask, filterQuality: FilterQuality.low);
      _shader = shader;
      _filter = ui.ImageFilter.shader(shader);
      _physicalBounds = physicalBounds;
      _physicalSamplePoint = samplePoint;
      _filterCreationFailed = false;
      oldShader?.dispose();
    } on Object catch (error) {
      shader?.dispose();
      _shader = oldShader;
      _filter = null;
      _filterCreationFailed = true;
      _physicalBounds = physicalBounds;
      _physicalSamplePoint = samplePoint;
      debugPrint('Adaptive glass filter disabled for this glyph: $error');
    }
  }

  _RenderAdaptiveGlassGroup? _findGroup() {
    RenderObject? ancestor = parent;
    while (ancestor != null) {
      if (ancestor is _RenderAdaptiveGlassGroup) {
        return ancestor;
      }
      ancestor = ancestor.parent;
    }
    return null;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _ensureFilter();
    final filter = _filter;
    if (filter == null) {
      return;
    }
    context.pushClipRect(needsCompositing, offset, Offset.zero & size, (
      context,
      offset,
    ) {
      context.pushLayer(
        BackdropFilterLayer(filter: filter, blendMode: BlendMode.srcOver),
        (context, offset) {
          context.canvas.drawPoints(ui.PointMode.points, <Offset>[
            offset,
            offset + Offset(size.width - 1, 0),
            offset + Offset(0, size.height - 1),
            offset + Offset(size.width - 1, size.height - 1),
          ], _coveragePaint);
        },
        offset,
        childPaintBounds: offset & size,
      );
    });
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }
}

class _AdaptiveGlassProgram {
  static const asset = 'assets/shaders/adaptive_glass_foreground.frag';
  static Future<ui.FragmentProgram?>? _loading;
  static ui.FragmentProgram? program;

  static Future<ui.FragmentProgram?> load() {
    return _loading ??= ui.FragmentProgram.fromAsset(asset)
        .then<ui.FragmentProgram?>((value) {
          program = value;
          return value;
        })
        .onError((Object error, StackTrace stackTrace) {
          debugPrint('Adaptive glass shader unavailable: $error');
          return null;
        });
  }
}

/// Test hook for forcing the safe path without depending on the renderer used
/// by the test process. Production code leaves this null.
abstract final class AdaptiveGlassDebug {
  @visibleForTesting
  static bool? shaderFilterSupportedOverride;

  @visibleForTesting
  static Future<bool> textMaskHasCoverage() async {
    const key = _TextMaskKey(
      'Glass',
      TextStyle(fontSize: 16, color: Color(0xFFFFFFFF)),
      TextDirection.ltr,
      TextScaler.noScaling,
      1,
      null,
      null,
      Size(64, 24),
      1,
    );
    final image = _createTextMask(key);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (bytes == null) {
      return false;
    }
    return _hasCoverageAndTransparency(bytes);
  }

  @visibleForTesting
  static Future<bool> iconMaskHasCoverage(IconData icon) async {
    final image = _createTextMask(
      _TextMaskKey(
        String.fromCharCode(icon.codePoint),
        TextStyle(
          inherit: false,
          color: const Color(0xFFFFFFFF),
          fontSize: 24,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontFamilyFallback: icon.fontFamilyFallback,
          height: 1,
          leadingDistribution: TextLeadingDistribution.even,
        ),
        TextDirection.ltr,
        TextScaler.noScaling,
        1,
        null,
        null,
        const Size.square(24),
        1,
      ),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (bytes == null) {
      return false;
    }
    return _hasCoverageAndTransparency(bytes);
  }
}

bool _hasCoverageAndTransparency(ByteData bytes) {
  var hasCoverage = false;
  var hasTransparency = false;
  for (var index = 3; index < bytes.lengthInBytes; index += 4) {
    final alpha = bytes.getUint8(index);
    hasCoverage |= alpha != 0;
    hasTransparency |= alpha != 255;
    if (hasCoverage && hasTransparency) {
      break;
    }
  }
  return hasCoverage && hasTransparency;
}

sealed class _MaskKey {
  const _MaskKey(this.logicalSize, this.pixelRatio);

  final Size logicalSize;
  final double pixelRatio;
}

class _TextMaskKey extends _MaskKey {
  const _TextMaskKey(
    this.data,
    this.style,
    this.direction,
    this.scaler,
    this.maxLines,
    this.overflow,
    this.textAlign,
    Size logicalSize,
    double pixelRatio,
  ) : super(logicalSize, pixelRatio);

  final String data;
  final TextStyle style;
  final TextDirection direction;
  final TextScaler scaler;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  @override
  bool operator ==(Object other) =>
      other is _TextMaskKey &&
      other.data == data &&
      other.style == style &&
      other.direction == direction &&
      other.scaler == scaler &&
      other.maxLines == maxLines &&
      other.overflow == overflow &&
      other.textAlign == textAlign &&
      other.logicalSize == logicalSize &&
      other.pixelRatio == pixelRatio;

  @override
  int get hashCode => Object.hash(
    data,
    style,
    direction,
    scaler,
    maxLines,
    overflow,
    textAlign,
    logicalSize,
    pixelRatio,
  );
}

class _MaskEntry {
  _MaskEntry(this.image) : references = 1;

  final ui.Image image;
  int references;
}

abstract final class _GlassMaskCache {
  static const _maximumEntries = 64;
  static final LinkedHashMap<_MaskKey, _MaskEntry> _entries =
      LinkedHashMap<_MaskKey, _MaskEntry>();

  static ui.Image acquire(_MaskKey key, ui.Image Function() create) {
    final existing = _entries.remove(key);
    if (existing != null) {
      existing.references++;
      _entries[key] = existing;
      return existing.image;
    }
    final entry = _MaskEntry(create());
    _entries[key] = entry;
    _trim();
    return entry.image;
  }

  static void release(_MaskKey key) {
    final entry = _entries[key];
    if (entry == null) {
      return;
    }
    entry.references = (entry.references - 1).clamp(0, 1 << 30);
    _trim();
  }

  static void _trim() {
    if (_entries.length <= _maximumEntries) {
      return;
    }
    for (final key in _entries.keys.toList(growable: false)) {
      if (_entries.length <= _maximumEntries) {
        break;
      }
      final entry = _entries[key]!;
      if (entry.references == 0) {
        _entries.remove(key);
        entry.image.dispose();
      }
    }
  }
}

ui.Image _createTextMask(_TextMaskKey key) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(key.pixelRatio);
  final painter = _textPainter(
    data: key.data,
    style: key.style,
    direction: key.direction,
    scaler: key.scaler,
    maxLines: key.maxLines,
    overflow: key.overflow,
    textAlign: key.textAlign,
  )..layout(maxWidth: key.logicalSize.width);
  painter.paint(canvas, Offset.zero);
  painter.dispose();
  final picture = recorder.endRecording();
  final image = picture.toImageSync(
    (key.logicalSize.width * key.pixelRatio).ceil().clamp(1, 1 << 20),
    (key.logicalSize.height * key.pixelRatio).ceil().clamp(1, 1 << 20),
  );
  picture.dispose();
  return image;
}

class _OutlinedIcon extends StatelessWidget {
  const _OutlinedIcon({
    required this.icon,
    required this.size,
    this.semanticLabel,
  });

  final IconData icon;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Icon(
      icon,
      size: size,
      color: const Color(0xFFFFFFFF),
      semanticLabel: semanticLabel,
      shadows: kAdaptiveOutlineShadows,
    );
  }
}

class _OutlinedText extends StatelessWidget {
  const _OutlinedText({
    required this.data,
    required this.style,
    required this.maxLines,
    required this.overflow,
    required this.softWrap,
    required this.textAlign,
    required this.textDirection,
    required this.textScaler,
    required this.semanticsLabel,
  });

  final String data;
  final TextStyle style;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool softWrap;
  final TextAlign? textAlign;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      semanticsLabel: semanticsLabel,
      maxLines: maxLines,
      overflow: overflow,
      softWrap: softWrap,
      textAlign: textAlign,
      textDirection: textDirection,
      textScaler: textScaler,
      style: style.copyWith(
        color: const Color(0xFFFFFFFF),
        shadows: kAdaptiveOutlineShadows,
      ),
    );
  }
}
