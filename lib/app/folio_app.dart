import 'package:flutter/widgets.dart';

import '../features/library/data/file_library_repository.dart';
import '../features/library/data/library_repository.dart';
import '../features/library/logic/library_controller.dart';
import '../features/library/widgets/library_screen.dart';
import '../shared/platform/android_storage_gateway.dart';
import '../shared/theme/folio_theme.dart';

class FolioApp extends StatefulWidget {
  const FolioApp({this.libraryRepository, super.key});

  final LibraryRepository? libraryRepository;

  @override
  State<FolioApp> createState() => _FolioAppState();
}

class _FolioAppState extends State<FolioApp> {
  late final LibraryController _libraryController;

  @override
  void initState() {
    super.initState();
    _libraryController = LibraryController(
      repository:
          widget.libraryRepository ??
          FileLibraryRepository(storageGateway: AndroidStorageGateway()),
    );
  }

  @override
  void dispose() {
    _libraryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      color: FolioColors.background,
      debugShowCheckedModeBanner: false,
      title: 'Folio',
      textStyle: FolioText.body,
      pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) {
        return PageRouteBuilder<T>(
          settings: settings,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (context, primaryAnimation, secondaryAnimation) =>
              builder(context),
        );
      },
      builder: (context, child) {
        return ScrollConfiguration(
          behavior: const FolioScrollBehavior(),
          child: DefaultTextStyle(
            style: FolioText.body,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: LibraryScreen(controller: _libraryController),
    );
  }
}

class FolioScrollBehavior extends ScrollBehavior {
  const FolioScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(
      decelerationRate: ScrollDecelerationRate.fast,
    );
  }
}
