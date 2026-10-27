import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../common/di/di_container.dart';
import '../../../../common/extensions/context_extension.dart';
import '../../../../common/widgets/container_input_field.dart';
import '../../../../common/widgets/custom_app_bar.dart';
import '../../../../common/widgets/primary_button.dart';
import '../../../calendar/ui/widgets/label.dart';
import '../../data/client.dart';
import '../../domain/bloc/clients_bloc.dart';

class AddEditClientScreenArgs {
  const AddEditClientScreenArgs({
    this.client,
    this.isClientAddedFromAppointment = false,
  });

  final Client? client;
  final bool isClientAddedFromAppointment;
}

class AddEditClientScreen extends StatefulWidget {
  const AddEditClientScreen({required this.args, super.key});

  final AddEditClientScreenArgs args;

  @override
  State<AddEditClientScreen> createState() => _AddEditClientScreenState();
}

class _AddEditClientScreenState extends State<AddEditClientScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneNumberController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();

  final clientBloc = getIt<ClientsBloc>();

  final _errorNameMessage = 'Ime i prezime klijenta ne smije biti prazano';

  String? _nameError;

  bool _isEditing = false;

  bool _isFormValid = false;

  @override
  void initState() {
    super.initState();
    nameController.text = widget.args.client?.name ?? '';
    phoneNumberController.text = widget.args.client?.phoneNumber ?? '';
    descriptionController.text = widget.args.client?.description ?? '';
    _isEditing = widget.args.client?.id != null;
    _isFormValid = nameController.text.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ClientsBloc, ClientsState>(
      bloc: clientBloc,
      listenWhen:
          (previous, current) =>
              previous is ClientsAdding && current is ClientsFetchingSuccess,
      listener: (context, state) {
        if (state is ClientsFetchingSuccess) {
          final message =
              _isEditing
                  ? 'Klijent je izmijenjen!'
                  : 'Klijent je uspješno dodat!';
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
          context.pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: const CustomAppBar(title: Text('Dodajte klijenta')),
        body: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  const Label(title: 'Ime i prezime'),
                  const SizedBox(height: 8),
                  ContainerInputField(
                    controller: nameController,
                    hintText: 'Unesite ime i prezime',
                    keyboardType: TextInputType.text,
                    inputFormatters: const [],
                    maxLines: 1,
                    errorText: _nameError,
                    onChanged: (value) {
                      setState(() {
                        _nameError =
                            value.isNotEmpty ? null : _errorNameMessage;
                        _isFormValid = value.isNotEmpty;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  const Label(title: 'Broj telefona'),
                  const SizedBox(height: 8),
                  ContainerInputField(
                    controller: phoneNumberController,
                    hintText: 'Unesite broj telefona',
                    onChanged: (_) {},
                    maxLines: 1,
                    keyboardType: TextInputType.phone,
                    inputFormatters: const [],
                  ),
                  const SizedBox(height: 16),
                  const Label(title: 'Napomena'),
                  const SizedBox(height: 8),
                  ContainerInputField(
                    controller: descriptionController,
                    hintText: 'Unesite napomenu',
                    keyboardType: TextInputType.text,
                    inputFormatters: const [],
                    maxLines: 3,
                    onChanged: (_) {},
                  ),
                  const SizedBox(height: 30),
                  BlocBuilder<ClientsBloc, ClientsState>(
                    bloc: clientBloc,
                    buildWhen:
                        (previous, current) =>
                            current is ClientsAdding ||
                            current is ClientsFetchingSuccess,
                    builder: (context, state) {
                      return PrimaryButton(
                        onTap:
                            !_isFormValid || state is ClientsAdding
                                ? null
                                : _onSubmit,
                        width: MediaQuery.of(context).size.width,
                        title: 'Potvrdi',
                        borderRadius: BorderRadius.circular(12),
                        padding: const EdgeInsets.all(10),
                        backgroundColor:
                            !_isFormValid
                                ? Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.12)
                                : null,
                        textColor:
                            !_isFormValid
                                ? Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.38)
                                : null,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onSubmit() {
    final name = nameController.text.trim();
    final phoneNumber = phoneNumberController.text.trim();
    final description = descriptionController.text.trim();

    if (name.isEmpty) {
      setState(() {
        _nameError = _errorNameMessage;
      });
      return;
    }

    if (_isEditing) {
      clientBloc.add(
        ClientUpdated(
          client: Client(
            id: widget.args.client?.id,
            name: name,
            phoneNumber: phoneNumber,
            description: description,
            createdAt: widget.args.client?.createdAt,
            isActive: true,
          ),
        ),
      );
    } else {
      clientBloc.add(
        ClientAdded(
          client: Client(
            name: name,
            phoneNumber: phoneNumber,
            description: description,
            isActive: true,
          ),
          isClientAddedFromAppointment:
              widget.args.isClientAddedFromAppointment,
        ),
      );
    }
  }
}
