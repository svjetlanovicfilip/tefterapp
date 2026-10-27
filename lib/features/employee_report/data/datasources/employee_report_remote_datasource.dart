import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../common/constants/routes.dart';
import '../../../../common/di/di_container.dart';

class EmployeeReportRemoteDatasource {
  EmployeeReportRemoteDatasource({required this.firebaseFirestore});

  final FirebaseFirestore firebaseFirestore;

  Future<QuerySnapshot<Map<String, dynamic>>> getEmployeeMonthlyReport({
    required String employeeId,
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      return await firebaseFirestore
          .collection(organizationsCollection)
          .doc(appState.organizationId)
          .collection(slotsCollection)
          .where('employeeIds', arrayContains: employeeId)
          .where('startDateTime', isLessThan: Timestamp.fromDate(to))
          .where(
            'endDateTime',
            isGreaterThanOrEqualTo: Timestamp.fromDate(from),
          )
          .orderBy('startDateTime')
          .get();
    } catch (e) {
      throw Exception(e);
    }
  }
}
