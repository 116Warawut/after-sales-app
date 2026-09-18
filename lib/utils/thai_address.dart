// =============================================================================
// 🆕 ยูทิลข้อมูลจังหวัด/อำเภอ/ตำบลของไทยแบบใช้ร่วมกันทั้งแอป (แก้ไขปัญหาพิมพ์แล้วเด้ง / แตะไม่ติด)
// =============================================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:after_sales/app_styles.dart';

class ThaiTambon {
  final String name;
  final String zip;
  ThaiTambon(this.name, this.zip);
}

class ThaiAmphure {
  final String name;
  final List<ThaiTambon> tambons;
  ThaiAmphure(this.name, this.tambons);
}

class ThaiProvince {
  final String name;
  final List<ThaiAmphure> amphures;
  ThaiProvince(this.name, this.amphures);
}

/// โหลดรายชื่อจังหวัด/อำเภอ/ตำบลทั้งหมดจาก assets/data/thai_address.json
Future<List<ThaiProvince>> loadThaiProvinces() async {
  final raw = await rootBundle.loadString('assets/data/thai_address.json');
  final List<dynamic> data = jsonDecode(raw);
  return data.map((p) {
    final amphures = (p['amphures'] as List).map((a) {
      final tambons = (a['tambons'] as List)
          .map((t) => ThaiTambon(t['name'] as String, t['zip'].toString()))
          .toList();
      return ThaiAmphure(a['name'] as String, tambons);
    }).toList();
    return ThaiProvince(p['name'] as String, amphures);
  }).toList();
}

/// ตัดคำนำหน้าจังหวัด/อำเภอ/ตำบล ที่อาจติดมากับข้อมูลเก่า/ข้อมูลดิบออกก่อนเสมอ
String cleanThaiAddressPrefix(String? text) {
  if (text == null) return '';
  var s = text.trim();
  if (s == '-' || s.isEmpty) return '';
  const prefixes = [
    'จังหวัด', 'จ.', 'จ ',
    'อำเภอ', 'อ.', 'อ ', 'เขต',
    'ตำบล', 'ต.', 'ต ', 'แขวง',
  ];
  for (final p in prefixes) {
    if (s.startsWith(p)) {
      s = s.substring(p.length).trim();
    }
  }
  return s;
}

bool isBangkokProvince(String? province) =>
    cleanThaiAddressPrefix(province) == 'กรุงเทพมหานคร';

/// ประกอบที่อยู่แบบเต็ม เลือกคำนำหน้า "ตำบล/อำเภอ" หรือ "แขวง/เขต" ตามจังหวัด
String formatThaiAddress({
  String? houseNo,
  String? moo,
  String? tambon,
  String? amphoe,
  String? changwat,
  String? postalCode,
  bool includeCountry = false,
  String emptyFallback = '-',
}) {
  final cleanTambon = cleanThaiAddressPrefix(tambon);
  final cleanAmphoe = cleanThaiAddressPrefix(amphoe);
  final cleanChangwat = cleanThaiAddressPrefix(changwat);
  final isBangkok = cleanChangwat == 'กรุงเทพมหานคร';
  final zip = postalCode?.trim() ?? '';

  final parts = <String>[
    if ((houseNo ?? '').trim().isNotEmpty) houseNo!.trim(),
    if ((moo ?? '').trim().isNotEmpty) 'หมู่ ${moo!.trim()}',
    if (cleanTambon.isNotEmpty) '${isBangkok ? 'แขวง' : 'ตำบล'}$cleanTambon',
    if (cleanAmphoe.isNotEmpty) '${isBangkok ? 'เขต' : 'อำเภอ'}$cleanAmphoe',
    if (cleanChangwat.isNotEmpty) 'จังหวัด$cleanChangwat',
    if (zip.isNotEmpty) zip,
    if (includeCountry) 'ประเทศไทย',
  ];
  return parts.isEmpty ? emptyFallback : parts.join(' ').trim();
}

/// ดึงตัวเลือกอำเภอ/เขต ตามจังหวัดที่เลือก
List<String> thaiAmphoeOptions(List<ThaiProvince> provinces, String province) {
  final cleanP = cleanThaiAddressPrefix(province);
  if (cleanP.isEmpty) return [];
  final match = provinces.where((p) =>
      cleanThaiAddressPrefix(p.name) == cleanP || p.name.trim() == province.trim());
  if (match.isEmpty) return [];
  return match.first.amphures.map((a) => cleanThaiAddressPrefix(a.name)).toList();
}

/// ดึงตัวเลือกตำบล/แขวง ตามจังหวัดและอำเภอที่เลือก
List<String> thaiTambonOptions(
    List<ThaiProvince> provinces, String province, String amphoe) {
  final cleanP = cleanThaiAddressPrefix(province);
  final cleanA = cleanThaiAddressPrefix(amphoe);
  if (cleanP.isEmpty || cleanA.isEmpty) return [];
  final provinceMatch = provinces.where((p) =>
      cleanThaiAddressPrefix(p.name) == cleanP || p.name.trim() == province.trim());
  if (provinceMatch.isEmpty) return [];
  final amphoeMatch = provinceMatch.first.amphures.where((a) =>
      cleanThaiAddressPrefix(a.name) == cleanA || a.name.trim() == amphoe.trim());
  if (amphoeMatch.isEmpty) return [];
  return amphoeMatch.first.tambons.map((t) => cleanThaiAddressPrefix(t.name)).toList();
}

/// ค้นหารหัสไปรษณีย์อัตโนมัติ
String? thaiZipFor(List<ThaiProvince> provinces, String province,
    String amphoe, String tambon) {
  final cleanP = cleanThaiAddressPrefix(province);
  final cleanA = cleanThaiAddressPrefix(amphoe);
  final cleanT = cleanThaiAddressPrefix(tambon);
  if (cleanP.isEmpty || cleanA.isEmpty || cleanT.isEmpty) return null;
  final provinceMatch = provinces.where((p) =>
      cleanThaiAddressPrefix(p.name) == cleanP || p.name.trim() == province.trim());
  if (provinceMatch.isEmpty) return null;
  final amphoeMatch = provinceMatch.first.amphures.where((a) =>
      cleanThaiAddressPrefix(a.name) == cleanA || a.name.trim() == amphoe.trim());
  if (amphoeMatch.isEmpty) return null;
  final tambonMatch = amphoeMatch.first.tambons.where((t) =>
      cleanThaiAddressPrefix(t.name) == cleanT || t.name.trim() == tambon.trim());
  if (tambonMatch.isEmpty) return null;
  return tambonMatch.first.zip;
}

/// ช่องกรอกที่อยู่แบบค้นหาอัตโนมัติ (แก้ไขปัญหาพิมพ์แล้วเด้ง และแตะตัวเลือกไม่ติด)
class ThaiAddressAutocompleteField extends StatefulWidget {
  final String labelText;
  final TextEditingController controller;
  final List<String> Function() optionsBuilder;
  final ValueChanged<String>? onSelected;
  final bool enabled;
  final String? Function(String?)? validator;

  const ThaiAddressAutocompleteField({
    super.key,
    required this.labelText,
    required this.controller,
    required this.optionsBuilder,
    this.onSelected,
    this.enabled = true,
    this.validator,
  });

  @override
  State<ThaiAddressAutocompleteField> createState() =>
      _ThaiAddressAutocompleteFieldState();
}

class _ThaiAddressAutocompleteFieldState
    extends State<ThaiAddressAutocompleteField> {
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (!widget.enabled) return const Iterable<String>.empty();
        final options = widget.optionsBuilder();
        if (options.isEmpty) return const Iterable<String>.empty();

        final query = textEditingValue.text.trim();
        if (query.isEmpty) {
          return options;
        }

        final cleanQuery = cleanThaiAddressPrefix(query).toLowerCase();
        final filtered = options.where((o) {
          final cleanO = cleanThaiAddressPrefix(o).toLowerCase();
          return cleanO.contains(cleanQuery) || o.toLowerCase().contains(cleanQuery);
        }).toList();

        // หากข้อความตรงกับรายการเดียวที่เลือกไว้อยู่แล้ว ให้แสดงตัวเลือกทั้งหมดเพื่อให้เปลี่ยนง่ายขึ้น
        if (filtered.length == 1 &&
            cleanThaiAddressPrefix(filtered.first).toLowerCase() == cleanQuery) {
          return options;
        }

        return filtered;
      },
      onSelected: (String selection) {
        _focusNode.unfocus();
        widget.onSelected?.call(selection);
      },
      fieldViewBuilder:
          (context, textEditingController, focusNode, onFieldSubmitted) {
        return ValueListenableBuilder<TextEditingValue>(
          valueListenable: widget.controller,
          builder: (context, value, _) {
            final hasText = value.text.isNotEmpty;
            return TextFormField(
              controller: textEditingController,
              focusNode: focusNode,
              enabled: widget.enabled,
              validator: widget.validator,
              style: const TextStyle(fontFamily: AppStyles.fontFamily),
              decoration: AppStyles.inputDecoration(
                hintText: widget.enabled
                    ? widget.labelText
                    : '${widget.labelText} (เลือกข้อมูลก่อนหน้าก่อน)',
                suffixIcon: widget.enabled
                    ? (hasText
                        ? IconButton(
                            icon: const Icon(Icons.clear,
                                size: 18, color: AppColors.textHint),
                            onPressed: () {
                              widget.controller.clear();
                              widget.onSelected?.call('');
                            },
                          )
                        : IconButton(
                            icon: const Icon(Icons.arrow_drop_down,
                                color: AppColors.textHint),
                            onPressed: () {
                              if (!focusNode.hasFocus) {
                                focusNode.requestFocus();
                              }
                            },
                          ))
                    : const Icon(Icons.arrow_drop_down,
                        color: AppColors.textHint),
              ),
              onFieldSubmitted: (val) {
                onFieldSubmitted();
              },
            );
          },
        );
      },
      optionsViewBuilder: (context, onSelectedOption, options) {
        if (options.isEmpty) return const SizedBox.shrink();

        return LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = MediaQuery.of(context).size.width;
            final boxWidth = (constraints.hasBoundedWidth && constraints.maxWidth > 0)
                ? constraints.maxWidth
                : screenWidth - 32;

            return Align(
              alignment: Alignment.topLeft,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {}, // ป้องกันไม่ให้อีเวนต์แตะหลุดไปถึง GestureDetector ชั้นนอกใน main.dart
                child: Material(
                  elevation: 4,
                  color: Colors.white,
                  shadowColor: Colors.black26,
                  borderRadius: BorderRadius.circular(10),
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    width: boxWidth,
                    constraints: const BoxConstraints(maxHeight: 220),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                      color: Colors.white,
                    ),
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: options.length,
                      separatorBuilder: (_, __) => const Divider(
                          height: 1, color: AppColors.border),
                      itemBuilder: (context, index) {
                        final option = options.elementAt(index);
                        return InkWell(
                          onTap: () {
                            onSelectedOption(option);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            child: Text(
                              option,
                              style: const TextStyle(
                                fontFamily: AppStyles.fontFamily,
                                fontSize: 14,
                                color: AppColors.textMain,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}