import 'package:field_ops/domain/auth.dart';
import 'package:field_ops/domain/inventory.dart';
import 'package:field_ops/l10n/gen/app_localizations.dart';
import 'package:flutter/widgets.dart';

export 'package:field_ops/l10n/gen/app_localizations.dart';

extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

extension L10nDomain on AppLocalizations {
  String role(Role role) => switch (role) {
    Role.manager => roleManager,
    Role.clerk => roleClerk,
    Role.viewer => roleViewer,
  };

  String movementType(MovementType type) => switch (type) {
    MovementType.receive => receive,
    MovementType.issue => issue,
    MovementType.transfer => transfer,
    MovementType.adjustment => adjustment,
  };

  String movementStatus(MovementStatus status) => switch (status) {
    MovementStatus.pending => statusPending,
    MovementStatus.synced => statusSynced,
    MovementStatus.rejected => statusRejected,
  };

  String rejectReason(String? reason) {
    if (reason != null && reason.startsWith('insufficient_stock:')) {
      return rejectedInsufficient(int.parse(reason.split(':').last));
    }
    return rejectedOther;
  }
}
