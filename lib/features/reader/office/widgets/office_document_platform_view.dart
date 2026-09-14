import 'dart:async';
import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../data/office_document_gateway.dart';
import '../logic/office_document_renderer_base.dart';

class OfficeDocumentPlatformView extends StatefulWidget {
  const OfficeDocumentPlatformView({
    required this.renderer,
    required this.onContentTap,
    required this.onReadingGesture,
    super.key,
  });

  final OfficeDocumentRendererBase renderer;
  final VoidCallback onContentTap;
  final ValueChanged<double> onReadingGesture;

  @override
  State<OfficeDocumentPlatformView> createState() =>
      _OfficeDocumentPlatformViewState();
}

class _OfficeDocumentPlatformViewState
    extends State<OfficeDocumentPlatformView> {
  _MethodChannelOfficeView? _controller;

  @override
  void didUpdateWidget(OfficeDocumentPlatformView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.renderer, widget.renderer)) {
      _detach();
    }
  }

  void _platformViewCreated(int viewId) {
    _detach();
    final session = widget.renderer.session;
    if (session == null) {
      return;
    }
    final controller = _MethodChannelOfficeView(
      viewId: viewId,
      onEvent: _handleEvent,
    );
    _controller = controller;
    widget.renderer.attachView(controller, session.id);
    unawaited(controller.start());
  }

  void _handleEvent(Map<Object?, Object?> event) {
    if (!mounted) {
      return;
    }
    widget.renderer.handleViewEvent(event);
    switch (event['type']) {
      case 'tap':
        widget.onContentTap();
      case 'scroll':
        final delta = (event['delta'] as num?)?.toDouble() ?? 0;
        if (delta != 0) {
          widget.onReadingGesture(delta);
        }
    }
  }

  void _detach() {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      widget.renderer.detachView(controller);
      controller.dispose();
    }
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.renderer.session;
    if (!Platform.isAndroid || session == null) {
      return const SizedBox.shrink();
    }
    return RepaintBoundary(
      key: ValueKey<String>('office_document_view_${session.id}'),
      child: AndroidView(
        viewType: 'folio/office_view',
        layoutDirection: TextDirection.ltr,
        creationParams: <String, Object?>{'sessionId': session.id},
        creationParamsCodec: const StandardMessageCodec(),
        hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        onPlatformViewCreated: _platformViewCreated,
      ),
    );
  }
}

class _MethodChannelOfficeView implements OfficeViewCommands {
  _MethodChannelOfficeView({required int viewId, required this.onEvent})
    : _channel = MethodChannel('folio/office_view/$viewId') {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  final MethodChannel _channel;
  final ValueChanged<Map<Object?, Object?>> onEvent;
  bool _disposed = false;

  Future<void> start() => _invoke('start');

  @override
  Future<void> search(String query) =>
      _invoke('search', <String, Object?>{'query': query});

  @override
  Future<void> showNextHit() => _invoke('nextHit');

  @override
  Future<void> showPreviousHit() => _invoke('previousHit');

  @override
  Future<void> goToPosition(int zeroBasedIndex) =>
      _invoke('goToPosition', <String, Object?>{'index': zeroBasedIndex});

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    if (_disposed) {
      return;
    }
    await _channel.invokeMethod<void>(method, arguments);
  }

  Future<Object?> _handleMethodCall(MethodCall call) async {
    if (!_disposed && call.method == 'event' && call.arguments is Map) {
      onEvent((call.arguments as Map).cast<Object?, Object?>());
    }
    return null;
  }

  void dispose() {
    _disposed = true;
    _channel.setMethodCallHandler(null);
  }
}
