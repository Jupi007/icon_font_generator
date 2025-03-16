import 'package:icon_font_generator/src/utils/logger.dart';
import 'package:recase/recase.dart';

import '../common/constant.dart';
import '../common/generic_glyph.dart';
import '../common/naming_strategy.dart';
import '../otf/defaults.dart';

const _kUnnamedIconName = 'unnamed';
const _kDefaultIndent = 2;
const _kDefaultClassName = 'UiIcons';
const _kDefaultFontFileName = 'icon_font_generator_icons.otf';
const _kDefaultNamingStrategy = NamingStrategy.camel;

/// Removes any characters that are not valid for variable name.
///
/// Returns a new string.
String _getVarName(String string) {
  final replaced = string.replaceAll(RegExp(r'[^a-zA-Z0-9_\-$]'), '');
  return RegExp(r'^[a-zA-Z$].*').firstMatch(replaced)?.group(0) ?? '';
}

String _fixNamingStrategy(String string, NamingStrategy namingStrategy) {
  switch (namingStrategy) {
    case NamingStrategy.camel:
      return string.camelCase;
    case NamingStrategy.snake:
      return string.snakeCase;
  }
}

/// A helper for generating Flutter-compatible class with IconData objects for each icon.
class FlutterClassGenerator {
  /// * [glyphList] is a list of non-default glyphs.
  /// * [className] is generated class' name (preferably, in PascalCase).
  /// * [familyName] is font's family name to use in IconData.
  /// * [package] is the name of a font package. Used to provide a font through package dependency.
  /// * [fontFileName] is font file's name. Used in generated docs for class.
  /// * [indent] is a number of spaces in leading indentation for class' members. Defaults to 2.
  FlutterClassGenerator(
    this.glyphList, {
    String? className,
    String? familyName,
    String? fontFileName,
    int? indent,
    NamingStrategy? namingStrategy,
    Map<String, String>? symlinkMap,
    String? package,
  })  : _className = _getVarName(className ?? _kDefaultClassName),
        _familyName = familyName ?? kDefaultFontFamily,
        _fontFileName = fontFileName ?? _kDefaultFontFileName,
        _indent = ' ' * (indent ?? _kDefaultIndent),
        _namingStrategy = namingStrategy ?? _kDefaultNamingStrategy,
        _symlinkMap = symlinkMap,
        _package = package?.isEmpty ?? true ? null : package;

  final List<GenericGlyph> glyphList;
  final String _className;
  final String _familyName;
  final String _fontFileName;
  final String _indent;
  final NamingStrategy _namingStrategy;
  final Map<String, String>? _symlinkMap;
  final String? _package;

  Map<String, GenericGlyph> _generateIconMap() {
    final iconMap = <String, GenericGlyph>{};

    for (final glyph in glyphList) {
      final baseName = _fixNamingStrategy(
        _getVarName(glyph.metadata.name!),
        _namingStrategy,
      );
      final usingDefaultName = baseName.isEmpty;

      var variableName = usingDefaultName ? _kUnnamedIconName : baseName;

      // Handling same names by adding numeration to them
      if (iconMap.keys.contains(variableName)) {
        // If name already contains numeration, then splitting it
        final countMatch = RegExp(r'^(.*)_([0-9]+)$').firstMatch(variableName);

        var variableNameCount = 1;
        var variableWithoutCount = variableName;

        if (countMatch != null) {
          variableNameCount = int.parse(countMatch.group(2)!);
          variableWithoutCount = countMatch.group(1)!;
        }

        String variableNameWithCount;

        do {
          variableNameWithCount =
              '${variableWithoutCount}_${++variableNameCount}';
        } while (iconMap.keys.contains(variableNameWithCount));

        variableName = variableNameWithCount;
      }

      iconMap.addAll({variableName: glyph});
    }

    return iconMap;
  }

  Map<String, GenericGlyph>? _generateGlyphSymlinks(
    Map<String, GenericGlyph> iconMap,
  ) {
    if (_symlinkMap == null || _symlinkMap!.isEmpty) {
      return null;
    }

    final glyphSymlinks = <String, GenericGlyph>{};

    for (final symlinkEntry in _symlinkMap!.entries) {
      final symlink = symlinkEntry.key;
      final target = symlinkEntry.value;

      if (iconMap.containsKey(symlink)) {
        logger.w(
          'Symlink "$symlink" icon already exists - symlink creation skipped',
        );
      } else if (_symlinkMap!.containsKey(target)) {
        logger.w(
          'Target "$target" icon is already a symlink - symlink creation skipped',
        );
      } else if (!iconMap.containsKey(target)) {
        logger.w(
          'Target "$target" icon does not exist - symlink creation skipped',
        );
      } else {
        glyphSymlinks.addAll({symlink: iconMap[target]!});
      }
    }

    return glyphSymlinks;
  }

  bool get _hasPackage => _package != null;

  String get _fontFamilyConst =>
      "static const iconFontFamily = '$_familyName';";

  String get _fontPackageConst => "static const iconFontPackage = '$_package';";

  List<String> _generateIconConst(String varName, GenericGlyph glyph) {
    final glyphMeta = glyph.metadata;

    final charCode = glyphMeta.charCode!;

    final hexCode = charCode.toRadixString(16);

    final posParamList = [
      'fontFamily: iconFontFamily',
      if (_hasPackage) 'fontPackage: iconFontPackage'
    ];

    final posParamString = posParamList.join(', ');

    return [
      '',
      '/// Font icon named "__${varName.sentenceCase.toLowerCase()}__"',
      if (glyphMeta.preview != null) ...[
        '///',
        "/// <image width='32px' src='data:image/svg+xml;base64,${glyphMeta.preview}'>",
      ],
      'static const $varName = IconData(0x$hexCode, $posParamString);'
    ];
  }

  List<String> _generateAllIconsMap(List<String> iconVarNames) {
    return [
      'static const all = {',
      for (final iconName in iconVarNames) "$_indent'$iconName': $iconName,",
      '};'
    ];
  }

  /// Generates content for a class' file.
  String generate() {
    final iconMap = _generateIconMap();
    final glyphSymlinks = _generateGlyphSymlinks(iconMap);

    final classContent = [
      'const $_className._();',
      '',
      _fontFamilyConst,
      if (_hasPackage) _fontPackageConst,
      for (final icon in iconMap.entries)
        ..._generateIconConst(
          icon.key,
          icon.value,
        ),
      if (glyphSymlinks != null)
        for (final symlink in glyphSymlinks.entries)
          ..._generateIconConst(
            symlink.key,
            symlink.value,
          ),
      '',
      ..._generateAllIconsMap([
        ...iconMap.keys.toList(),
        if (glyphSymlinks != null) ...glyphSymlinks.keys.toList(),
      ]),
    ];

    final classContentString =
        classContent.map((e) => e.isEmpty ? '' : '$_indent$e').join('\n');

    return '''// Generated code: do not hand-edit.

// Generated using $kVendorName.
// Copyright © ${DateTime.now().year} $kVendorName ($kVendorUrl).

// ignore_for_file: type=lint

import 'package:flutter/widgets.dart';

/// Identifiers for the icons.
///
/// Use with the [Icon] class to show specific icons.
///
/// Icons are identified by their name as listed below.
///
/// To use this class, make sure you declare the font in your
/// project's `pubspec.yaml` file in the `fonts` section. This ensures that
/// the "$_familyName" font is included in your application. This font is used to
/// display the icons. For example:
/// 
/// ```yaml
/// flutter:
///   fonts:
///     - family: $_familyName
///       fonts:
///         - asset: fonts/$_fontFileName
/// ```
@staticIconProvider
abstract final class $_className {
$classContentString
}
''';
  }
}
