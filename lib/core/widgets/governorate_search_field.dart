// lib/core/widgets/governorate_search_field.dart
// ─────────────────────────────────────────────
// Searchable governorate selector using Autocomplete.
// Types name or code to filter, then picks from list.
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../theme.dart';
import '../../data/models/governorate_model.dart';

class GovernorateSearchField extends StatelessWidget {
  final List<GovernorateModel> governorates;
  final GovernorateModel? selected;
  final ValueChanged<GovernorateModel?> onChanged;
  final String? Function(GovernorateModel?)? validator;

  const GovernorateSearchField({
    super.key,
    required this.governorates,
    this.selected,
    required this.onChanged,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Autocomplete<GovernorateModel>(
      initialValue: TextEditingValue(
        text: selected != null
            ? (selected!.code != null && selected!.code!.isNotEmpty
                ? '${selected!.code} - ${selected!.name}'
                : selected!.name)
            : '',
      ),
      optionsBuilder: (textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return const Iterable<GovernorateModel>.empty();
        }
        final q = textEditingValue.text.toLowerCase();
        return governorates.where((g) =>
            g.name.toLowerCase().contains(q) ||
            (g.code != null && g.code!.contains(q)));
      },
      displayStringForOption: (g) =>
          g.code != null && g.code!.isNotEmpty
              ? '${g.code} - ${g.name}'
              : g.name,
      onSelected: (g) => onChanged(g),
      fieldViewBuilder:
          (context, textController, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: textController,
          focusNode: focusNode,
          onFieldSubmitted: (_) => onFieldSubmitted(),
          onChanged: (value) {
            if (selected != null) {
              final expectedText = selected!.code != null && selected!.code!.isNotEmpty
                  ? '${selected!.code} - ${selected!.name}'
                  : selected!.name;
              if (value != expectedText) {
                onChanged(null);
              }
            }
          },
          validator: (_) {
            if (validator != null) return validator!(selected);
            return null;
          },
          decoration: InputDecoration(
            hintText: 'ابحث بالاسم أو الكود...',
            prefixIcon:
                const Icon(Icons.location_on_outlined, size: 18),
            suffixIcon: selected != null
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      onChanged(null);
                      textController.clear();
                    },
                  )
                : null,
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return _GovernorateOptions(
          options: options.toList(),
          selectedId: selected?.id,
          onSelected: onSelected,
        );
      },
    );
  }
}

// ── Autocomplete options overlay ──────────────
class _GovernorateOptions extends StatelessWidget {
  final List<GovernorateModel> options;
  final int? selectedId;
  final AutocompleteOnSelected<GovernorateModel> onSelected;

  const _GovernorateOptions({
    required this.options,
    this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 200, maxWidth: 460),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE0E0E0)),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: options.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final g = options[i];
              final isSelected = g.id == selectedId;
              final highlightedIndex = AutocompleteHighlightedOption.of(context);
              final isHighlighted = highlightedIndex == i;
              return Material(
                color: isHighlighted ? AppTheme.primary.withValues(alpha: 0.1) : Colors.transparent,
                child: ListTile(
                  dense: true,
                  leading: SizedBox(
                    width: 36,
                    child: Text(
                      g.code ?? '',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? AppTheme.primary
                            : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  title: Text(
                    g.name,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isSelected
                          ? AppTheme.primary
                          : AppTheme.textPrimary,
                    ),
                  ),
                trailing: isSelected
                    ? const Icon(Icons.check_circle,
                        color: AppTheme.primary, size: 18)
                    : null,
                onTap: () => onSelected(g),
              ));
            },
          ),
        ),
      ),
    );
  }
}
