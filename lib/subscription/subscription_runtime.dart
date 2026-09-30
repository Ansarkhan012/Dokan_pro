import 'entitlement_policy.dart';
import 'entitlement_store.dart';
import 'entitlement_verifier.dart';

/// Builds the production authorizer from the pinned public verification key
/// and secure local entitlement store. No network access is performed here.
EntitlementPolicyService productionEntitlementPolicy() =>
    EntitlementPolicyService(
      verifier: EntitlementVerifier(rsaPublicKeyFromEnvironment()),
      store: SecureEntitlementStore(),
    );

FinancialMutationAuthorizer productionFinancialMutationAuthorizer() =>
    EntitlementMutationAuthorizer(productionEntitlementPolicy());
