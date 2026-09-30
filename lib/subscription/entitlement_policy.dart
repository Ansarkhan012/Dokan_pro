import 'entitlement.dart';
import 'entitlement_store.dart';
import 'entitlement_verifier.dart';

enum EntitlementState {
  trialActive,
  active,
  expiringSoon,
  offlineGrace,
  expired,
  clockVerificationRequired,
  unavailable,
}

enum MutationDecision { allow, allowWithWarning, allowWithStrongWarning, block }

final class EntitlementEvaluation {
  const EntitlementEvaluation(
    this.state,
    this.decision,
    this.message, {
    this.claims,
    this.lastVerified,
  });
  final EntitlementState state;
  final MutationDecision decision;
  final String message;
  final EntitlementClaims? claims;
  final DateTime? lastVerified;
  bool get permitsMutation => decision != MutationDecision.block;
}

final class EntitlementPolicyService {
  const EntitlementPolicyService({
    required this.verifier,
    required this.store,
    this.rollbackTolerance = const Duration(minutes: 5),
    this.expiringWindow = const Duration(days: 3),
  });
  final EntitlementVerifier verifier;
  final EntitlementStore store;
  final Duration rollbackTolerance, expiringWindow;
  Future<EntitlementEvaluation> evaluate({
    required String shopId,
    required String deviceId,
    required DateTime localNow,
  }) async {
    final token = await store.read(shopId, deviceId),
        observation = await store.readTime(shopId, deviceId);
    if (token == null || observation == null) {
      return const EntitlementEvaluation(
        EntitlementState.unavailable,
        MutationDecision.block,
        'Online subscription verification is required.',
      );
    }
    EntitlementClaims claims;
    try {
      claims = verifier.verify(token, shopId: shopId, deviceId: deviceId);
    } catch (_) {
      return const EntitlementEvaluation(
        EntitlementState.unavailable,
        MutationDecision.block,
        'Stored subscription proof is invalid. Verify online.',
      );
    }
    final now = localNow.toUtc();
    if (now.isBefore(observation.localUtc.subtract(rollbackTolerance))) {
      return EntitlementEvaluation(
        EntitlementState.clockVerificationRequired,
        MutationDecision.block,
        'Device time changed significantly. Connect online to verify.',
        claims: claims,
        lastVerified: observation.serverUtc,
      );
    }
    final elapsed = now.isAfter(observation.localUtc)
        ? now.difference(observation.localUtc)
        : Duration.zero;
    final trustedNow = observation.serverUtc.add(elapsed);
    if (trustedNow.isAfter(claims.offlineGraceUntil)) {
      return EntitlementEvaluation(
        EntitlementState.expired,
        MutationDecision.block,
        'Shop subscription needs renewal. Please contact the owner.',
        claims: claims,
        lastVerified: observation.serverUtc,
      );
    }
    if (trustedNow.isAfter(claims.validUntil)) {
      return EntitlementEvaluation(
        EntitlementState.offlineGrace,
        MutationDecision.allowWithStrongWarning,
        'Grace period active. Online verification is needed.',
        claims: claims,
        lastVerified: observation.serverUtc,
      );
    }
    if (claims.validUntil.difference(trustedNow) <= expiringWindow) {
      return EntitlementEvaluation(
        EntitlementState.expiringSoon,
        MutationDecision.allowWithWarning,
        'Subscription ending soon.',
        claims: claims,
        lastVerified: observation.serverUtc,
      );
    }
    return EntitlementEvaluation(
      claims.planId == 'trial'
          ? EntitlementState.trialActive
          : EntitlementState.active,
      MutationDecision.allow,
      'Subscription verified.',
      claims: claims,
      lastVerified: observation.serverUtc,
    );
  }

  void requireMutation(EntitlementEvaluation value) {
    if (!value.permitsMutation) {
      throw SubscriptionMutationBlocked(value.message);
    }
  }
}

/// The single application boundary used by every operation that creates
/// financial or stock state. Implementations must decide before the database
/// transaction starts so a denial cannot leave partial local state behind.
abstract interface class FinancialMutationAuthorizer {
  Future<EntitlementEvaluation> authorize({
    required String shopId,
    required String deviceId,
  });
}

final class EntitlementMutationAuthorizer
    implements FinancialMutationAuthorizer {
  EntitlementMutationAuthorizer(this.policy, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final EntitlementPolicyService policy;
  final DateTime Function() _clock;

  @override
  Future<EntitlementEvaluation> authorize({
    required String shopId,
    required String deviceId,
  }) async {
    final evaluation = await policy.evaluate(
      shopId: shopId,
      deviceId: deviceId,
      localNow: _clock(),
    );
    policy.requireMutation(evaluation);
    return evaluation;
  }
}

/// Test/migration seam only. Production composition always supplies an
/// [EntitlementMutationAuthorizer]. Keeping this default preserves callers
/// while all service methods still pass through the same boundary.
final class AllowFinancialMutations implements FinancialMutationAuthorizer {
  const AllowFinancialMutations();

  @override
  Future<EntitlementEvaluation> authorize({
    required String shopId,
    required String deviceId,
  }) async => const EntitlementEvaluation(
    EntitlementState.active,
    MutationDecision.allow,
    'Subscription verified.',
  );
}

final class SubscriptionMutationBlocked implements Exception {
  const SubscriptionMutationBlocked(this.message);
  final String message;
  @override
  String toString() => message;
}
