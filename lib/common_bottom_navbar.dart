import 'package:after_sales/app_styles.dart';
import 'package:after_sales/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:after_sales/enums/user_role.dart';

class CommonBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final UserRole role;
  final ValueChanged<int> onTap;

  /// จำนวนแจ้งเตือนที่ยังไม่อ่าน — โชว์เป็นวงกลมแดงบนไอคอนกระดิ่ง (ใส่ 0 = ไม่โชว์)
  final int notificationCount;

  /// จำนวน "ห้องแชท" ที่มีข้อความยังไม่อ่าน — โชว์เป็นวงกลมแดงบนไอคอนแชท (ใส่ 0 = ไม่โชว์)
  final int chatCount;

  const CommonBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.role,
    required this.onTap,
    this.notificationCount = 0,
    this.chatCount = 0,
  });

  /// ห่อไอคอนด้วยวงกลมแดงมุมขวาบน เมื่อมีจำนวนที่ต้องแจ้ง
  Widget _iconWithBadge(IconData icon, int count) {
    if (count <= 0) return Icon(icon);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        Positioned(
          right: -8,
          top: -4,
          child: CountBadge(count: count),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          top: BorderSide(
            color: AppColors.border,
            width: .5,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          showSelectedLabels: true,
          showUnselectedLabels: true,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: Colors.grey,
          selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 11,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 11,
          ),
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          elevation: 0,
          onTap: (index) {
            if (index == currentIndex) return;
            HapticFeedback.selectionClick();
            // ✅ แค่แจ้งดัชนีแท็บใหม่กลับไปให้ widget แม่ (RootShell) เป็นคน
            // setState เปลี่ยน IndexedStack เอง ไม่ push route ใหม่ทับ
            // เพื่อไม่ให้เกิด CNB ซ้อนกัน หรือ state ของแท็บอื่นหาย
            onTap(index);
          },
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'หน้าแรก',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.list_alt),
              activeIcon: Icon(Icons.list_alt),
              label: 'งานทั้งหมด',
            ),
            BottomNavigationBarItem(
              icon: _iconWithBadge(Icons.chat_bubble_outline, chatCount),
              activeIcon: _iconWithBadge(Icons.chat_bubble, chatCount),
              label: 'แชท',
            ),
            BottomNavigationBarItem(
              icon: _iconWithBadge(
                  Icons.notifications_none_outlined, notificationCount),
              activeIcon:
                  _iconWithBadge(Icons.notifications, notificationCount),
              label: 'แจ้งเตือน',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'โปรไฟล์',
            ),
          ],
        ),
      ),
    );
  }
}
