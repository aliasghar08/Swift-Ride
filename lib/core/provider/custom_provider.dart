import 'package:flutter/widgets.dart';

/// A pure Flutter, zero-dependency InheritedNotifier provider.
class CustomChangeNotifierProvider<T extends ChangeNotifier> extends InheritedNotifier<T> {
  const CustomChangeNotifierProvider({
    super.key,
    required T notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Subscribes the calling widget to rebuild when [notifier] changes.
  static T of<T extends ChangeNotifier>(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<CustomChangeNotifierProvider<T>>();
    assert(provider != null, 'No CustomChangeNotifierProvider found for type $T in context');
    return provider!.notifier!;
  }

  /// Reads [notifier] without subscribing to rebuilds.
  static T read<T extends ChangeNotifier>(BuildContext context) {
    final provider = context.getInheritedWidgetOfExactType<CustomChangeNotifierProvider<T>>();
    assert(provider != null, 'No CustomChangeNotifierProvider found for type $T in context');
    return provider!.notifier!;
  }
}

/// A pure Flutter widget that listens to a provider [T] and rebuilds via its builder.
class CustomConsumer<T extends ChangeNotifier> extends StatelessWidget {
  final Widget Function(BuildContext context, T provider, Widget? child) builder;
  final Widget? child;

  const CustomConsumer({
    super.key,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final provider = CustomChangeNotifierProvider.of<T>(context);
    return builder(context, provider, child);
  }
}

/// Helper to nest multiple custom providers cleanly at root.
class CustomMultiProvider extends StatelessWidget {
  final List<Widget Function(Widget child)> providers;
  final Widget child;

  const CustomMultiProvider({
    super.key,
    required this.providers,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    Widget current = child;
    for (final providerFn in providers.reversed) {
      current = providerFn(current);
    }
    return current;
  }
}
