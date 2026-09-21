import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/database/app_database.dart';
import '../core/utils/error_utils.dart';
import '../core/utils/routes.dart';
import '../widgets/pet_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/shimmer.dart';
import 'pet_editor_screen.dart';
import 'pet_detail_screen.dart';

class PetListScreen extends StatefulWidget {
  final ValueListenable<int>? refreshSignal;

  const PetListScreen({super.key, this.refreshSignal});

  @override
  State<PetListScreen> createState() => _PetListScreenState();
}

class _PetListScreenState extends State<PetListScreen> {
  List<Pet> _pets = [];
  Map<String, int> _diaryCounts = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.refreshSignal?.addListener(_handleExternalRefresh);
    _load();
  }

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(_handleExternalRefresh);
    super.dispose();
  }

  void _handleExternalRefresh() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        AppDatabase.getAllPets(),
        AppDatabase.getDiaryCountsForAllPets(),
      ]);
      final pets = results[0] as List<Pet>;
      final counts = results[1] as Map<String, int>;
      if (mounted) {
        setState(() {
          _pets = pets;
          _diaryCounts = counts;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的宠物')),
      body: _loading
          ? const _ShimmerList()
          : _pets.isEmpty
              ? EmptyState(
                  icon: Icons.pets,
                  title: '还没有宠物',
                  subtitle: '快来添加你的毛孩子吧',
                  actionLabel: '添加宠物',
                  onAction: () => _addPet(),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _pets.length,
                    itemBuilder: (_, i) => PetCard(
                      pet: _pets[i],
                      diaryCount: _diaryCounts[_pets[i].id] ?? 0,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          AppRoutes.slideUp(
                            builder: (_) => PetDetailScreen(
                              pet: _pets[i],
                              onRestored: _load,
                            ),
                          ),
                        );
                        _load();
                      },
                    ),
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'add_pet',
        onPressed: _addPet,
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _addPet() async {
    await Navigator.push(
      context,
      AppRoutes.slideUp(builder: (_) => const PetEditorScreen()),
    );
    _load();
  }
}

class _ShimmerList extends StatelessWidget {
  const _ShimmerList();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: List.generate(4, (_) => const ShimmerCard()),
    );
  }
}
