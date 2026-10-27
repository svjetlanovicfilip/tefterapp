import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../common/di/di_container.dart';
import '../../../../common/widgets/custom_app_bar.dart';
import '../../../../common/widgets/primary_button.dart';
import '../../../../config/style/colors.dart';
import '../../domain/bloc/employee_report_bloc.dart';
import '../widgets/employee_report_body.dart';
import '../widgets/employee_report_filter.dart';

class EmployeeReportScreen extends StatefulWidget {
  const EmployeeReportScreen({super.key});

  @override
  State<EmployeeReportScreen> createState() => _EmployeeReportScreenState();
}

class _EmployeeReportScreenState extends State<EmployeeReportScreen> {
  final EmployeeReportBloc employeeReportBloc = getIt<EmployeeReportBloc>();

  @override
  void dispose() {
    employeeReportBloc.resetState();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: Text('Mjesečni izvještaj')),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: EmployeeReportFilter()),
            BlocBuilder<EmployeeReportBloc, EmployeeReportState>(
              buildWhen:
                  (previous, current) =>
                      current is EmployeeReportFetched ||
                      current is EmployeeReportFetching ||
                      current is EmployeeReportFailure ||
                      current is EmployeeSelected ||
                      current is EmployeeReportInitial,
              bloc: getIt<EmployeeReportBloc>(),
              builder: (context, state) {
                if (state is EmployeeReportFetched) {
                  return SliverToBoxAdapter(
                    child: EmployeeReportBody(report: state.report),
                  );
                } else if (state is EmployeeReportFailure) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 16,
                        children: [
                          Text(
                            state.message,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          PrimaryButton(
                            onTap:
                                () => employeeReportBloc.add(
                                  EmployeeReportFetchRequested(),
                                ),
                            title: 'Pokušaj ponovo',
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ],
                      ),
                    ),
                  );
                } else if (state is EmployeeReportFetching) {
                  return const SliverFillRemaining(
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppColors.amber500,
                      ),
                    ),
                  );
                } else {
                  return BlocBuilder<EmployeeReportBloc, EmployeeReportState>(
                    bloc: employeeReportBloc,
                    buildWhen:
                        (previous, current) =>
                            current is EmployeeSelected ||
                            current is EmployeeReportInitial,
                    builder: (context, state) {
                      final isEmployeeSelected = state is EmployeeSelected;

                      return SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: PrimaryButton(
                            onTap:
                                isEmployeeSelected
                                    ? () {
                                      getIt<EmployeeReportBloc>().add(
                                        EmployeeReportFetchRequested(),
                                      );
                                    }
                                    : null,
                            title: 'Učitaj izvještaj',
                            borderRadius: BorderRadius.circular(12),
                            backgroundColor:
                                isEmployeeSelected
                                    ? null
                                    : Theme.of(context).colorScheme.onSurface
                                        .withValues(alpha: 0.12),
                            textColor:
                                isEmployeeSelected
                                    ? null
                                    : Theme.of(context).colorScheme.onSurface
                                        .withValues(alpha: 0.38),
                          ),
                        ),
                      );
                    },
                  );
                }
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}
