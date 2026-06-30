import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_common/core/presentation/buttons/app_primary_button.dart';
import 'package:flutter_common/core/presentation/buttons/app_text_button.dart';
import 'package:flutter_common/core/presentation/responsive_dialog/app_responsive_dialog.dart';
import 'package:ionicons/ionicons.dart';
import 'package:flutter_common/core/extensions/extensions.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EmergencyContact {
  final String name;
  final String phone;

  EmergencyContact({required this.name, required this.phone});

  Map<String, dynamic> toJson() => {'name': name, 'phone': phone};
  factory EmergencyContact.fromJson(Map<String, dynamic> json) =>
      EmergencyContact(name: json['name'], phone: json['phone']);
}

class EmergencyContactsDialog extends StatefulWidget {
  const EmergencyContactsDialog({super.key});

  @override
  State<EmergencyContactsDialog> createState() =>
      _EmergencyContactsDialogState();
}

class _EmergencyContactsDialogState extends State<EmergencyContactsDialog> {
  List<EmergencyContact> contacts = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final String? contactsJson = prefs.getString('emergency_contacts');
    if (contactsJson != null) {
      final List<dynamic> decoded = jsonDecode(contactsJson);
      setState(() {
        contacts = decoded.map((e) => EmergencyContact.fromJson(e)).toList();
      });
    }
    setState(() {
      isLoading = false;
    });
  }

  Future<void> _saveContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(contacts.map((e) => e.toJson()).toList());
    await prefs.setString('emergency_contacts', encoded);
  }

  void _addContact(String name, String phone) {
    setState(() {
      contacts.add(EmergencyContact(name: name, phone: phone));
    });
    _saveContacts();
  }

  void _removeContact(int index) {
    setState(() {
      contacts.removeAt(index);
    });
    _saveContacts();
  }

  @override
  Widget build(BuildContext context) {
    return AppResponsiveDialog(
      type: context.responsive(DialogType.bottomSheet, xl: DialogType.dialog),
      header: (
        Ionicons.people,
        'Contatos de Emergência',
        'Avisar pessoas de confiança em caso de SOS',
      ),
      primaryButton: AppPrimaryButton(
        onPressed: contacts.length >= 3
            ? null
            : () {
                _showAddContactModal(context);
              },
        child: const Text('Adicionar Contato'),
      ),
      secondaryButton: AppTextButton(
        onPressed: () => Navigator.of(context).pop(),
        text: 'Voltar',
      ),
      child: isLoading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: CircularProgressIndicator(),
              ),
            )
          : contacts.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Text(
                'Você ainda não adicionou nenhum contato de emergência. Adicione até 3 contatos.',
                textAlign: TextAlign.center,
                style: context.bodyMedium?.copyWith(
                  color: context.theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: contacts.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final contact = contacts[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: context.colorScheme.primaryContainer,
                    child: Icon(
                      Ionicons.person,
                      color: context.colorScheme.primary,
                    ),
                  ),
                  title: Text(contact.name, style: context.titleSmall),
                  subtitle: Text(contact.phone, style: context.bodySmall),
                  trailing: IconButton(
                    icon: const Icon(Ionicons.trash_outline, color: Colors.red),
                    onPressed: () => _removeContact(index),
                  ),
                );
              },
            ),
    );
  }

  void _showAddContactModal(BuildContext parentContext) {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: parentContext,
      builder: (context) => AlertDialog(
        title: const Text('Novo Contato'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Nome (Ex: Mãe)'),
                validator: (v) => v!.isEmpty ? 'Informe o nome' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Telefone com DDD',
                ),
                validator: (v) => v!.length < 10 ? 'Telefone inválido' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                _addContact(nameController.text, phoneController.text);
                Navigator.of(context).pop();
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}
