import 'package:field_ops/app/session_cubit.dart';
import 'package:field_ops/data/api/fake_field_ops_api.dart';
import 'package:field_ops/data/api/field_ops_api.dart';
import 'package:field_ops/domain/auth.dart';
import 'package:field_ops/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  String _tenantId = FakeFieldOpsApi.tenants.first.id;
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _useDemo(Role role) {
    final user = FakeFieldOpsApi.demoUsers.firstWhere((u) => u.tenant.id == _tenantId && u.role == role);
    _email.text = user.email;
    _password.text = FakeFieldOpsApi.demoPassword;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final state = context.watch<SessionCubit>().state;
    final busy = state is SignedOut && state.busy;
    final error = switch (state) {
      SignedOut(error: Offline()) => l10n.offlineError,
      SignedOut(error: ApiError()) => l10n.invalidCredentials,
      _ => null,
    };

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.warehouse_outlined, size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(l10n.signInTitle, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                  const SizedBox(height: 4),
                  Text(l10n.signInSubtitle, textAlign: TextAlign.center),
                  const SizedBox(height: 32),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _tenantId,
                    decoration: InputDecoration(labelText: l10n.company, prefixIcon: const Icon(Icons.business)),
                    items: [
                      for (final t in FakeFieldOpsApi.tenants) DropdownMenuItem(value: t.id, child: Text(t.name)),
                    ],
                    onChanged: (v) => setState(() => _tenantId = v!),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('email'),
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(labelText: l10n.email),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: InputDecoration(labelText: l10n.password),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error,
                      style: TextStyle(color: theme.colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () => context.read<SessionCubit>().signIn(
                            tenantId: _tenantId,
                            email: _email.text,
                            password: _password.text,
                          ),
                    child: busy
                        ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : Text(l10n.signIn),
                  ),
                  const SizedBox(height: 24),
                  Text(l10n.demoAccounts, style: theme.textTheme.labelLarge, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    children: [
                      for (final role in Role.values)
                        ActionChip(label: Text(l10n.role(role)), onPressed: () => _useDemo(role)),
                    ],
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
