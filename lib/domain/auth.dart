import 'package:equatable/equatable.dart';

/// Actions that can be granted. Screens and use cases check permissions,
/// never roles, so a new role is a one-line change in [rolePermissions].
enum Permission { viewStock, recordMovement, countStock, approveAdjustment, viewApprovals }

enum Role { manager, clerk, viewer }

const Map<Role, Set<Permission>> rolePermissions = {
  Role.manager: {
    Permission.viewStock,
    Permission.recordMovement,
    Permission.countStock,
    Permission.approveAdjustment,
    Permission.viewApprovals,
  },
  Role.clerk: {Permission.viewStock, Permission.recordMovement, Permission.countStock},
  Role.viewer: {Permission.viewStock},
};

class Tenant extends Equatable {
  const Tenant({required this.id, required this.name});

  final String id;
  final String name;

  @override
  List<Object> get props => [id, name];
}

class User extends Equatable {
  const User({required this.id, required this.name, required this.email, required this.role, required this.tenant});

  final String id;
  final String name;
  final String email;
  final Role role;
  final Tenant tenant;

  bool can(Permission permission) => rolePermissions[role]!.contains(permission);

  @override
  List<Object> get props => [id, name, email, role, tenant];
}

/// Thrown by use cases when the user lacks a permission. The UI hides such
/// actions, but the domain checks again: hidden is not the same as secure.
class PermissionDenied implements Exception {
  const PermissionDenied(this.permission);
  final Permission permission;

  @override
  String toString() => 'PermissionDenied(${permission.name})';
}
