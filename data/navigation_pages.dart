import 'package:after_sales/enums/user_role.dart';
import 'package:flutter/material.dart';
import 'package:after_sales/screens/chat_screen.dart';

// Admin
import 'package:after_sales/screens/admin/admin_notification.dart';
import 'package:after_sales/screens/admin/home_admin.dart';

// Customer
import 'package:after_sales/screens/customer/customer_notification.dart';
import 'package:after_sales/screens/customer/history_customer.dart';
import 'package:after_sales/screens/customer/home_customer.dart';
import 'package:after_sales/screens/customer/profile_customer.dart';

// Technician
import 'package:after_sales/screens/technician/home_technician.dart';

final Map<UserRole, List<Widget>> navigationPages = {
  UserRole.customer: const [
    HomeCustomer(),
    HistoryCustomer(),
    ChatScreen(role: UserRole.customer),
    CustomerNotificationPage(),
    ProfileCustomer(),
  ],
  UserRole.technician: const [
    HomeTechnician(),
    //TechnicianJobPage(),
    ChatScreen(role: UserRole.technician),
    //TechnicianNotificationPage(),
    //TechnicianProfilePage(),
  ],
  UserRole.admin: const [
    HomeAdmin(),
    //AdminJobPage(),
    ChatScreen(role: UserRole.admin),
    AdminNotificationPage(),
    //AdminProfilePage(),
  ],
};
