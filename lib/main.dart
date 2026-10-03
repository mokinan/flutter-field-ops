import 'package:field_ops/app/app.dart';
import 'package:field_ops/data/api/fake_field_ops_api.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(FieldOpsApp(api: FakeFieldOpsApi()));
}
