import 'package:flutter/widgets.dart';

/// Подписи новых экранов (v2.1) на двух языках: русский и узбекский (латиница). Выбор по языку интерфейса.
extension TrX on BuildContext {
  bool get isUz => Localizations.localeOf(this).languageCode == 'uz';
  String tr(String ru, String uz) => isUz ? uz : ru;
}
