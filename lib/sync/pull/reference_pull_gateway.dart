import 'pull_models.dart';

abstract interface class ReferencePullGateway {
  Future<List<RemoteChange>> fetch({
    required PullEntity entity,
    required String shopId,
    PullCursor? after,
    int limit = 100,
  });
}
