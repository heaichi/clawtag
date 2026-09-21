import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/database/app_database.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/confirm.dart';
import '../core/utils/error_utils.dart';
import '../core/utils/snack.dart';
import '../widgets/diary_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/inline_dropdown.dart';
import '../widgets/shimmer.dart';
import 'diary_detail_screen.dart';
import 'diary_editor_screen.dart';

class DiaryListScreen extends StatefulWidget {
  final String? petId;
  final String? petName;
  final ValueListenable<int>? refreshSignal;

  const DiaryListScreen({
    super.key,
    this.petId,
    this.petName,
    this.refreshSignal,
  });

  @override
  State<DiaryListScreen> createState() => _DiaryListScreenState();
}

class _DiaryListScreenState extends State<DiaryListScreen> {
  List<Diary> _diaries = [];
  List<Pet> _allPets = [];
  Map<String, _CardData> _cardDataMap = {};
  bool _loading = true;
  bool _navigating = false;
  String _searchQuery = '';
  String? _filterPetId;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.refreshSignal?.addListener(_handleExternalRefresh);
    _load();
  }

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(_handleExternalRefresh);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _handleExternalRefresh() {
    if (mounted) _load();
  }

  List<Diary> get _filteredDiaries {
    return _diaries.where((d) {
      if (_filterPetId != null && d.petId != _filterPetId) return false;
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      if (d.title.toLowerCase().contains(q)) return true;
      if (d.content.toLowerCase().contains(q)) return true;
      final data = _cardDataMap[d.id];
      if (data != null && data.petName.toLowerCase().contains(q)) return true;
      return false;
    }).toList();
  }

  Future<void> _load() async {
    try {
      final diaries = widget.petId != null
          ? await AppDatabase.getPetDiaries(widget.petId!)
          : await AppDatabase.getAllDiaries();

      if (diaries.isEmpty) {
        if (mounted) {
          setState(() {
            _diaries = [];
            _cardDataMap = {};
            _loading = false;
          });
        }
        return;
      }

      // Batch-load all card data in parallel (pet names, tags, images).
      final diaryIds = diaries.map((d) => d.id).toList();
      final results = await Future.wait([
        AppDatabase.getAllPets(),
        AppDatabase.getDiaryTagsBatch(diaryIds),
        AppDatabase.getDiaryMediaBatch(diaryIds),
      ]);
      final allPets = results[0] as List<Pet>;
      final tagsMap = results[1] as Map<String, List<Tag>>;
      final mediaMap = results[2] as Map<String, List<String>>;
      final petMap = {for (final p in allPets) p.id: p.name};

      final cardData = <String, _CardData>{};
      for (final d in diaries) {
        cardData[d.id] = _CardData(
          petName: petMap[d.petId] ?? '未知',
          tags: tagsMap[d.id] ?? [],
          mediaPaths: mediaMap[d.id] ?? [],
        );
      }

      if (mounted) {
        setState(() {
          _diaries = diaries;
          _allPets = allPets;
          _cardDataMap = cardData;
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
      appBar: AppBar(
        title: Text(widget.petName != null ? '${widget.petName}的爪札' : '爪札'),
      ),
      body: _loading
          ? const _ShimmerLoading()
          : _diaries.isEmpty
          ? EmptyState(
              icon: Icons.book_outlined,
              title: '还没有爪札',
              subtitle: '记录毛孩子的每一个瞬间',
              actionLabel: '写爪札',
              onAction: () => _addDiary(),
            )
          : Column(
              children: [
                // Search bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (v) => setState(() => _searchQuery = v),
                          decoration: InputDecoration(
                            hintText: '搜索爪札...',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                      if (_searchQuery.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            _searchCtrl.clear();
                            FocusManager.instance.primaryFocus?.unfocus();
                            setState(() => _searchQuery = '');
                          },
                          child: const Text('取消'),
                        ),
                    ],
                  ),
                ),
                if (_allPets.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: InlineDropdown<String?>(
                      label: '宠物',
                      value: _filterPetId,
                      options: [
                        const InlineOption<String?>(
                          value: null,
                          label: '全部宠物',
                          icon: Icons.pets,
                        ),
                        ..._allPets.map(
                          (p) => InlineOption<String?>(
                            value: p.id,
                            label: p.name,
                            icon: Icons.pets,
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _filterPetId = v),
                    ),
                  ),
                Expanded(
                  child: _filteredDiaries.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.search_off,
                                  size: 40,
                                  color: AppColors.cloud,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '没有找到匹配的爪札',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: _filteredDiaries.length,
                            itemBuilder: (_, i) =>
                                _buildCard(_filteredDiaries[i]),
                          ),
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'add_diary',
        onPressed: _addDiary,
        child: const Icon(Icons.edit),
      ),
    );
  }

  Widget _buildCard(Diary diary) {
    final data = _cardDataMap[diary.id];
    if (data == null) return const SizedBox.shrink();
    return Dismissible(
      key: Key(diary.id),
      direction: DismissDirection.endToStart,
      // 删除动作放在 confirmDismiss 里：失败时返回 false 让条目弹回原位，
      // 避免"已被 dismiss 但仍在树中"触发断言
      // （A dismissed Dismissible widget is still part of the tree）。
      // 见 docs/代码审计待办.md P1-11。
      confirmDismiss: (_) async {
        final confirmed = await showDestructiveConfirm(
          context,
          title: '删除爪札',
          message: '确定要删除「${diary.title}」吗？',
        );
        if (confirmed != true) return false;
        try {
          // 只软删除，保留物理文件（同详情页策略，供将来恢复/永久删除）。
          await AppDatabase.softDeleteDiary(diary.id);
          return true;
        } catch (e) {
          if (mounted) showError(context, e);
          return false;
        }
      },
      onDismissed: (_) async {
        if (!mounted) return;
        showAppSnackBar(
          context,
          '爪札已删除',
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () async {
              try {
                await AppDatabase.restoreDiary(diary.id);
                if (mounted) _load();
              } catch (e) {
                if (mounted) showError(context, e);
              }
            },
          ),
        );
        _load();
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: AppColors.error,
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 28),
      ),
      child: DiaryCard(
        diary: diary,
        petName: data.petName,
        tags: data.tags,
        mediaPaths: data.mediaPaths,
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DiaryDetailScreen(
                diary: diary,
                onRestored: _load,
              ),
            ),
          );
          _load();
        },
      ),
    );
  }

  Future<void> _addDiary() async {
    if (_navigating) return;
    _navigating = true;
    try {
      final pets = await AppDatabase.getAllPets();
      if (!mounted) return;
      if (pets.isEmpty) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('暂无宠物'),
            content: const Text('请先在"宠物"页面添加宠物后再写爪札。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
        return;
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              DiaryEditorScreen(petId: widget.petId, petName: widget.petName),
        ),
      );
      if (mounted) _load();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      _navigating = false;
    }
  }
}

class _CardData {
  final String petName;
  final List<Tag> tags;
  final List<String> mediaPaths;

  const _CardData({
    required this.petName,
    required this.tags,
    this.mediaPaths = const [],
  });
}

class _ShimmerLoading extends StatelessWidget {
  const _ShimmerLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: List.generate(4, (_) => const ShimmerDiaryCard()),
    );
  }
}
