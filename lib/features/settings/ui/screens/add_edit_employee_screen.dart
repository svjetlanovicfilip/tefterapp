import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../common/di/di_container.dart';
import '../../../../common/widgets/container_input_field.dart';
import '../../../../common/widgets/custom_app_bar.dart';
import '../../../../common/widgets/primary_button.dart';
import '../../../calendar/ui/widgets/label.dart';
import '../../../login/data/models/user_model.dart';
import '../../../users/domain/bloc/users_bloc.dart';

class AddEditEmployeeScreen extends StatefulWidget {
  const AddEditEmployeeScreen({super.key});

  @override
  State<AddEditEmployeeScreen> createState() => _AddEditEmployeeViewState();
}

class _AddEditEmployeeViewState extends State<AddEditEmployeeScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController lastNameController = TextEditingController();
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();

  final usersBloc = getIt<UsersBloc>();

  final _errorNameMessage = 'Ime ne smije biti prazno';
  final _errorLastNameMessage = 'Prezime ne smije biti prazno';
  final _errorUsernameMessage = 'Korisničko ime ne smije biti prazno';
  final _errorEmailMessage = 'Email ne smije biti prazan';

  String? _nameError;
  String? _lastNameError;
  String? _usernameError;
  String? _emailError;

  bool _checkIsFormValid() =>
      nameController.text.trim().isNotEmpty &&
      lastNameController.text.trim().isNotEmpty &&
      usernameController.text.trim().isNotEmpty &&
      _isEmailValid;

  bool _isFormValid = false;

  // (opciono) basic email check
  bool get _isEmailValid {
    final e = emailController.text.trim();
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return emailRegex.hasMatch(e);
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<UsersBloc, UsersState>(
      bloc: usersBloc,
      listener: (context, state) {
        if (state is UsersAddingFailure) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(state.message)));
          return;
        }
        if (state is UsersFetchingSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Zaposleni je uspješno dodat. Poslat je email za reset lozinke.',
              ),
            ),
          );
          Navigator.of(context).pop(nameController.text.trim());
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: const CustomAppBar(title: Text('Dodajte novog zaposlenog')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                const Label(title: 'Ime'),
                const SizedBox(height: 8),
                ContainerInputField(
                  controller: nameController,
                  hintText: 'Unesite ime',
                  keyboardType: TextInputType.text,
                  inputFormatters: const [],
                  maxLines: 1,
                  errorText: _nameError,
                  onChanged: (value) {
                    setState(() {
                      _nameError = value.isNotEmpty ? null : _errorNameMessage;
                      _isFormValid = _checkIsFormValid();
                    });
                  },
                ),
                const SizedBox(height: 16),
                const Label(title: 'Prezime'),
                const SizedBox(height: 8),
                ContainerInputField(
                  controller: lastNameController,
                  hintText: 'Unesite prezime',
                  keyboardType: TextInputType.text,
                  inputFormatters: const [],
                  maxLines: 1,
                  errorText: _lastNameError,
                  onChanged: (value) {
                    setState(() {
                      _lastNameError =
                          value.isNotEmpty ? null : _errorLastNameMessage;
                      _isFormValid = _checkIsFormValid();
                    });
                  },
                ),
                const SizedBox(height: 16),
                const Label(title: 'Korisničko ime'),
                const SizedBox(height: 8),
                ContainerInputField(
                  controller: usernameController,
                  hintText: 'Unesite korisničko ime',
                  keyboardType: TextInputType.text,
                  inputFormatters: const [],
                  maxLines: 1,
                  errorText: _usernameError,
                  onChanged: (value) {
                    setState(() {
                      _usernameError =
                          value.isNotEmpty ? null : _errorUsernameMessage;
                      _isFormValid = _checkIsFormValid();
                    });
                  },
                ),
                const SizedBox(height: 16),
                const Label(title: 'Email'),
                const SizedBox(height: 8),
                ContainerInputField(
                  controller: emailController,
                  hintText: 'Unesite email',
                  keyboardType: TextInputType.text,
                  inputFormatters: const [],
                  maxLines: 1,
                  errorText: _emailError,
                  onChanged: (value) {
                    setState(() {
                      _emailError = _isEmailValid ? null : _errorEmailMessage;
                      _isFormValid = _checkIsFormValid();
                    });
                  },
                ),
                const SizedBox(height: 32),
                BlocBuilder<UsersBloc, UsersState>(
                  bloc: usersBloc,
                  builder: (context, state) {
                    return PrimaryButton(
                      onTap:
                          !_isFormValid || state is UsersAdding
                              ? null
                              : () => _onSubmit(context),
                      width: MediaQuery.of(context).size.width,
                      title: 'Potvrdi',
                      borderRadius: BorderRadius.circular(12),
                      padding: const EdgeInsets.all(10),
                      isLoading: state is UsersAdding,
                      backgroundColor:
                          !_isFormValid
                              ? Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.12)
                              : null,
                    );
                  },
                ),

                if (!_isFormValid) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Popunite sva polja da biste mogli potvrditi.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onSubmit(BuildContext context) {
    // dodatna validacija (čak i ako je dugme disabled dok nije validno)

    final name = nameController.text.trim();
    final lastName = lastNameController.text.trim();
    final username = usernameController.text.trim();
    final email = emailController.text.trim();

    if (name.isEmpty) {
      setState(() {
        _nameError = _errorNameMessage;
      });
      return;
    }

    if (lastName.isEmpty) {
      setState(() {
        _lastNameError = _errorLastNameMessage;
      });
      return;
    }

    if (username.isEmpty) {
      setState(() {
        _usernameError = _errorUsernameMessage;
      });
      return;
    }

    if (email.isEmpty) {
      setState(() {
        _emailError = _errorEmailMessage;
        if (!_isEmailValid) {
          _emailError = 'Email nije validan!';
        } else {
          _emailError = null;
        }
      });
    }

    usersBloc.add(
      UserAdded(
        user: UserModel(
          name: name,
          surname: lastName,
          username: username,
          email: email,
        ),
      ),
    );
  }
}
