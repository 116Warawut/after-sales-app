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

/// ตัวนับ "ค่าที่อยู่เปลี่ยน" ใช้ให้ช่องอำเภอ/ตำบลคำนวณรายการใหม่ทุกครั้งที่ช่องอื่น
/// เลือก/ล้าง/คืนค่า โดยไม่ต้องพึ่งให้หน้าแม่ setState (ใช้ร่วมกันทุกช่องในแอป)
final ValueNotifier<int> _thaiAddressRevision = ValueNotifier<int>(0);

/// ความสูงของแต่ละรายการใน dropdown (ใช้คำนวณความสูงสูงสุด = 6 รายการ)
const double _kOptionHeight = 44;

/// ช่องกรอกที่อยู่แบบค้นหาอัตโนมัติ (จังหวัด → อำเภอ/เขต → ตำบล/แขวง)
///
/// 🐛 [แก้บัค] พฤติกรรมของช่องนี้ (ใช้ร่วมกันทุกหน้า):
/// - พิมพ์ค้นหา/ลบตัวอักษรได้ต่อเนื่อง โฟกัสและคีย์บอร์ดไม่หลุด — `onSelected`
///   จะถูกเรียกเฉพาะตอนที่ "เลือกรายการ", กด Enter, กดปุ่ม ✕ หรือออกจากช่องแล้ว
///   ข้อความตรงกับรายการพอดี ไม่ถูกเรียกระหว่างพิมพ์ทีละตัวอักษร
/// - เลือกรายการ (แตะตัวเลือก หรือกด Enter/ตกลงบนคีย์บอร์ด) แล้วโฟกัสจะเลื่อนไป
///   ช่องถัดไปให้เอง (ช่องสุดท้ายให้ส่ง `moveToNextField: false` แล้วจะหุบคีย์บอร์ด)
/// - ช่องที่ขึ้นกับช่องก่อนหน้า (อำเภอ/ตำบล) จะโหลดรายการใหม่ให้ทุกครั้งที่ช่องเปิดใช้
///   งานหรือรายการเปลี่ยน จึงแตะแล้วเห็นรายการทันที ไม่ต้องพิมพ์แล้วลบก่อน
/// - ถ้าพิมพ์ค้างไว้แล้วแตะที่ว่างออกจากช่อง: ตรงกับรายการพอดี → ใช้ค่านั้น,
///   ไม่ตรง → คืนเป็นค่าที่เลือกไว้เดิม (ไม่ปล่อยให้เหลือข้อความครึ่ง ๆ กลาง ๆ)
///
/// ⚠️ อย่าใส่ `key: ValueKey(...)` ที่ผูกกับข้อความในช่องเองตอนเรียกใช้ เพราะจะทำให้
/// ช่องถูกสร้างใหม่และเสียโฟกัสทุกครั้งที่ข้อความเปลี่ยน
class ThaiAddressAutocompleteField extends StatefulWidget {
  final String labelText;
  final TextEditingController controller;
  final List<String> Function() optionsBuilder;
  final ValueChanged<String>? onSelected;
  final bool enabled;
  final String? Function(String?)? validator;

  /// เลือกแล้วให้ย้ายโฟกัสไปช่องถัดไป (ค่าเริ่มต้น true) — ช่องสุดท้ายของชุด
  /// (ตำบล/แขวง) ให้ส่ง false
  final bool moveToNextField;

  /// ใช้กับช่อง "จังหวัด": พิมพ์ชื่อจังหวัดที่ถูกต้องแล้ว "แตะที่ว่างบนหน้าจอ" ให้ไป
  /// ช่องอำเภอต่อเลย (เหมือนกด Enter) — ช่องอำเภอ/ตำบลไม่ต้องส่ง แตะที่ว่างแล้วจะแค่ออกจากช่อง
  final bool advanceOnOutsideTap;

  const ThaiAddressAutocompleteField({
    super.key,
    required this.labelText,
    required this.controller,
    required this.optionsBuilder,
    this.onSelected,
    this.enabled = true,
    this.validator,
    this.moveToNextField = true,
    this.advanceOnOutsideTap = false,
  });

  @override
  State<ThaiAddressAutocompleteField> createState() =>
      _ThaiAddressAutocompleteFieldState();
}

class _ThaiAddressAutocompleteFieldState
    extends State<ThaiAddressAutocompleteField> {
  final FocusNode _focusNode = FocusNode();

  /// ผู้ใช้พิมพ์/ลบเองแต่ยังไม่ได้ยืนยัน (เลือกรายการ/กด Enter/ออกจากช่อง)
  bool _dirty = false;
  bool _hadFocus = false;

  /// ข้อความในช่องตอนที่เพิ่งได้โฟกัส — ใช้คืนค่าถ้าพิมพ์แล้วไม่ตรงรายการ
  String _textAtFocus = '';

  int? _lastSignature;

  /// กำลังย้ายโฟกัสไปช่องถัดไปหลังแตะที่ว่าง — กันไม่ให้ช่องนี้เปิด dropdown วูบขึ้นมาตอนขอโฟกัสกลับ
  bool _advancing = false;

  /// 🐛 [แก้บัค] RawAutocomplete ของ Flutter คำนวณรายการตัวเลือก "เฉพาะตอนที่ข้อความ
  /// ในช่องเปลี่ยน" เท่านั้น การแตะ/ย้ายโฟกัสมาที่ช่องเฉย ๆ จึงไม่มี dropdown ขึ้น
  /// (ต้องพิมพ์แล้วลบก่อนถึงจะขึ้น) — จึงสะกิดให้คำนวณใหม่ด้วยการเติมช่องว่างท้าย
  /// ข้อความแล้วคืนค่าเดิมทันที (ทั้งสองอย่างเกิดใน frame เดียวกัน ผู้ใช้ไม่เห็น
  /// และ optionsBuilder ตัดช่องว่างท้ายทิ้งอยู่แล้ว) ทำให้ dropdown ขึ้นทันทีที่ได้โฟกัส
  void _refreshOptions() {
    if (!mounted || !widget.enabled || !_focusNode.hasFocus) return;
    final original = widget.controller.value;
    widget.controller.value = TextEditingValue(
      text: '${original.text} ',
      selection: TextSelection.collapsed(offset: original.text.length + 1),
    );
    widget.controller.value = original;
  }

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  List<String> _filter(List<String> options, String rawQuery) {
    final query = rawQuery.trim();
    if (query.isEmpty) return options;
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
  }

  String? _exactMatch(List<String> options, String text) {
    final clean = cleanThaiAddressPrefix(text).toLowerCase();
    if (clean.isEmpty) return null;
    for (final o in options) {
      if (o.trim() == text.trim() ||
          cleanThaiAddressPrefix(o).toLowerCase() == clean) {
        return o;
      }
    }
    return null;
  }

  /// เลือกค่า → อัปเดตช่อง → แจ้งหน้าแม่ → ไปช่องถัดไป (หรือหุบคีย์บอร์ดถ้าเป็นช่องสุดท้าย)
  void _select(String option) {
    _dirty = false;
    widget.controller.value = TextEditingValue(
      text: option,
      selection: TextSelection.collapsed(offset: option.length),
    );
    widget.onSelected?.call(option);
    _thaiAddressRevision.value++;

    if (widget.moveToNextField) {
      // รอให้หน้าแม่ rebuild ก่อน (ช่องถัดไปเพิ่งถูกเปิดใช้งานจากการเลือกนี้)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        FocusScope.of(context).nextFocus();
      });
    } else {
      _focusNode.unfocus();
    }
  }

  /// กด Enter/ตกลงบนคีย์บอร์ด: ใช้รายการที่ตรงพอดี ถ้าไม่มีให้ใช้รายการแรกที่ค้นเจอ
  void _onSubmitted(String value) {
    if (!widget.enabled) return;
    final options = widget.optionsBuilder();
    if (options.isEmpty || value.trim().isEmpty) return;

    String? pick = _exactMatch(options, value);
    if (pick == null) {
      final filtered = _filter(options, value);
      if (filtered.isNotEmpty) pick = filtered.first;
    }
    if (pick != null) _select(pick);
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      _hadFocus = true;
      _textAtFocus = widget.controller.text;
      if (!_advancing) _refreshOptions();
      return;
    }
    if (!_hadFocus) return;
    _hadFocus = false;
    // หน่วงเล็กน้อย เผื่อกำลังแตะเลือกรายการ (ซึ่งจะเคลียร์ _dirty เอง)
    Future.delayed(const Duration(milliseconds: 150), _commitTypedText);
  }

  /// ย้ายโฟกัสไปช่องถัดไปหลัง "แตะที่ว่าง" — ขอโฟกัสกลับมาที่ช่องนี้ก่อน (ให้ระบบนับ
  /// ตำแหน่งจากช่องนี้) แล้วค่อยเลื่อนไปช่องถัดไปหลัง frame ที่หน้าแม่ rebuild เสร็จ
  void _advanceAfterTapOutside() {
    _advancing = true;
    _focusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _advancing = false;
      if (!mounted) return;
      FocusScope.of(context).nextFocus();
    });
  }

  /// ออกจากช่องโดยไม่ได้เลือกรายการ (แตะที่ว่าง ฯลฯ)
  ///
  /// ช่องที่ตั้ง `advanceOnOutsideTap` (จังหวัด): แตะที่ว่างต้องได้ผลเหมือนกด Enter
  /// คือถ้าในช่องมีชื่อที่ถูกต้องอยู่แล้ว (เลือกไว้ / พิมพ์ครบ / พิมพ์ไม่ครบแต่ตรงกับ
  /// รายการเดียว) ให้ใช้ค่านั้นแล้วไปช่องถัดไปเลย ไม่ใช่แค่หุบ dropdown ทิ้ง
  void _commitTypedText() {
    if (!mounted || _focusNode.hasFocus) return;

    // โฟกัสหลุดเพราะ "แตะที่ว่าง" (ไม่ได้ไปโฟกัสช่องอื่น)
    final primary = FocusManager.instance.primaryFocus;
    final tappedEmptySpace = primary == null || primary is FocusScopeNode;
    final canAdvance =
        widget.advanceOnOutsideTap && widget.moveToNextField && tappedEmptySpace;

    final text = widget.controller.text.trim();

    if (!_dirty) {
      // ไม่ได้พิมพ์แก้อะไร แต่ในช่องมีชื่อที่ถูกต้องอยู่ → แตะที่ว่างแล้วไปช่องถัดไป
      if (canAdvance &&
          text.isNotEmpty &&
          _exactMatch(widget.optionsBuilder(), text) != null) {
        _advanceAfterTapOutside();
      }
      return;
    }
    _dirty = false;

    if (text.isEmpty) {
      // ผู้ใช้ลบจนว่างเอง → ถือว่าล้างค่า (ล้างช่องที่ขึ้นกับช่องนี้ด้วย)
      if (_textAtFocus.trim().isNotEmpty) widget.onSelected?.call('');
      _thaiAddressRevision.value++;
      return;
    }

    final options = widget.optionsBuilder();
    var match = _exactMatch(options, text);
    if (match == null && widget.advanceOnOutsideTap) {
      // พิมพ์ไม่ครบแต่ตรงกับรายการเดียว (เช่น "สมุทรปรา") → ใช้รายการนั้นเลย
      final filtered = _filter(options, text);
      if (filtered.length == 1) match = filtered.first;
    }

    if (match != null) {
      widget.controller.text = match;
      if (match.trim() != _textAtFocus.trim()) widget.onSelected?.call(match);
      _thaiAddressRevision.value++;
      if (canAdvance) _advanceAfterTapOutside();
    } else {
      // พิมพ์ไม่ครบ/ไม่ตรงรายการ → คืนค่าเดิม
      widget.controller.text = _textAtFocus;
      _thaiAddressRevision.value++;
    }
  }

  @override
  Widget build(BuildContext context) {
    // ฟังตัวนับ _thaiAddressRevision เพื่อคำนวณรายการใหม่เมื่อช่องอื่นในชุดเดียวกันเปลี่ยนค่า
    return ValueListenableBuilder<int>(
      valueListenable: _thaiAddressRevision,
      builder: (context, _, __) => _buildField(context),
    );
  }

  Widget _buildField(BuildContext context) {
    // 🐛 ผูก key ของ RawAutocomplete กับ "เปิดใช้งานอยู่ไหม + รายการตอนนี้คืออะไร"
    // (ไม่ใช่ข้อความในช่อง) เพื่อให้ช่องอำเภอ/ตำบลคำนวณรายการใหม่ทันทีที่จังหวัด/อำเภอ
    // เปลี่ยน ไม่ค้างรายการเก่าที่ว่างเปล่าจากตอนที่ยังถูกล็อก ส่วน FocusNode และ
    // controller เป็นของ widget นี้ จึงไม่หายไปตอนสร้างใหม่
    final currentOptions =
        widget.enabled ? widget.optionsBuilder() : const <String>[];
    final signature =
        Object.hash(widget.enabled, Object.hashAll(currentOptions));

    // ถ้ารายการเปลี่ยนตอนที่ช่องนี้กำลังมีโฟกัสอยู่ (RawAutocomplete ถูกสร้างใหม่)
    // ให้คำนวณรายการใหม่หลัง frame นี้ เพื่อให้ dropdown ยังขึ้นอยู่
    if (_lastSignature != null && _lastSignature != signature && _focusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshOptions());
    }
    _lastSignature = signature;

    return RawAutocomplete<String>(
      key: ValueKey<int>(signature),
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (!widget.enabled) return const Iterable<String>.empty();
        final options = widget.optionsBuilder();
        if (options.isEmpty) return const Iterable<String>.empty();
        return _filter(options, textEditingValue.text);
      },
      onSelected: _select,
      fieldViewBuilder:
          (context, textEditingController, focusNode, onFieldSubmitted) {
        return ValueListenableBuilder<TextEditingValue>(
          valueListenable: textEditingController,
          builder: (context, value, _) {
            final hasText = value.text.isNotEmpty;
            return TextFormField(
              controller: textEditingController,
              focusNode: focusNode,
              enabled: widget.enabled,
              validator: widget.validator,
              textInputAction: widget.moveToNextField
                  ? TextInputAction.next
                  : TextInputAction.done,
              style: const TextStyle(fontFamily: AppStyles.fontFamily),
              decoration: AppStyles.inputDecoration(
                hintText: widget.enabled
                    ? widget.labelText
                    : '${widget.labelText} (เลือกข้อมูลก่อนหน้าก่อน)',
                // ExcludeFocus: ไม่ให้ปุ่มท้ายช่องถูกนับเป็น "ช่องถัดไป" ตอนย้ายโฟกัส
                suffixIcon: widget.enabled
                    ? ExcludeFocus(
                        child: hasText
                            ? IconButton(
                                icon: const Icon(Icons.clear,
                                    size: 18, color: AppColors.textHint),
                                onPressed: () {
                                  _dirty = false;
                                  widget.controller.clear();
                                  widget.onSelected?.call('');
                                  _thaiAddressRevision.value++;
                                  focusNode.requestFocus();
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
                              ),
                      )
                    : const Icon(Icons.arrow_drop_down,
                        color: AppColors.textHint),
              ),
              onChanged: (_) => _dirty = true,
              // ปิดพฤติกรรมเริ่มต้นของ TextInputAction.next (ย้ายโฟกัสทันที ซึ่งตอนนั้น
              // ช่องถัดไปยังถูกล็อกอยู่) — ให้ _onSubmitted จัดการย้ายโฟกัสเองหลังเลือกค่าแล้ว
              onEditingComplete: () {},
              onFieldSubmitted: _onSubmitted,
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
                // ExcludeFocus: รายการตัวเลือกต้องไม่ถูกนับเป็น "ช่องถัดไป" ตอนย้ายโฟกัส
                child: ExcludeFocus(
                  child: Material(
                    elevation: 4,
                    color: Colors.white,
                    shadowColor: Colors.black26,
                    borderRadius: BorderRadius.circular(10),
                    clipBehavior: Clip.antiAlias,
                    child: Container(
                      width: boxWidth,
                      // แสดงสูงสุด 6 รายการ (สูงรายการละ 44 + เส้นคั่น 1 + ขอบ 2) ที่เหลือเลื่อนดู
                      constraints: const BoxConstraints(
                          maxHeight: _kOptionHeight * 6 + 5 + 2),
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
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: AppColors.border),
                        itemBuilder: (context, index) {
                          final option = options.elementAt(index);
                          return InkWell(
                            onTap: () => onSelectedOption(option),
                            child: Container(
                              height: _kOptionHeight,
                              alignment: Alignment.centerLeft,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                option,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
              ),
            );
          },
        );
      },
    );
  }
}