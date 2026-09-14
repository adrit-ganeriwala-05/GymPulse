import 'dart:developer' as developer;

import 'package:flutter_bloc/flutter_bloc.dart';

/// Minimal observability hook. Every bloc's unhandled error — and anything a
/// handler forwards via `addError` — lands here instead of vanishing.
class AppBlocObserver extends BlocObserver {
  const AppBlocObserver();

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    developer.log(
      'Error in ${bloc.runtimeType}',
      name: 'gympulse.bloc',
      error: error,
      stackTrace: stackTrace,
    );
    super.onError(bloc, error, stackTrace);
  }
}
