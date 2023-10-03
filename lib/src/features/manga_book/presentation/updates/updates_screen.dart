// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/hooks/hook_primitives_wrapper.dart';
import '../../../../utils/hooks/paging_controller_hook.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../widgets/emoticons.dart';
import '../../data/updates/updates_repository.dart';
import '../../domain/chapter/chapter_model.dart';
import '../../domain/chapter_page/chapter_page_model.dart';
import '../../widgets/chapter_actions/multi_chapters_actions_bottom_app_bar.dart';
import '../../widgets/update_status_fab.dart';
import '../../widgets/update_status_popup_menu.dart';
import '../reader/controller/reader_controller.dart';
import 'widgets/chapter_manga_list_tile.dart';

class UpdatesScreen extends HookConsumerWidget {
  const UpdatesScreen({super.key});

  Future<void> _fetchPage(
    UpdatesRepository repository,
    PagingController<int, ChapterMangaPair> controller,
    int pageKey,
  ) async {
    AsyncValue.guard(
      () async => await repository.getRecentChaptersPage(pageNo: pageKey),
    ).then(
      (value) => value.whenOrNull(
        data: (recentChaptersPage) {
          try {
            if (recentChaptersPage != null) {
              if (recentChaptersPage.hasNextPage.ifNull()) {
                controller
                    .appendPage([...?recentChaptersPage.page], pageKey + 1);
              } else {
                controller.appendLastPage([...?recentChaptersPage.page]);
              }
            }
          } catch (e) {
            //
          }
        },
        error: (error, stackTrace) => controller.error = error,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller =
        usePagingController<int, ChapterMangaPair>(firstPageKey: 0);
    final updatesRepository = ref.watch(updatesRepositoryProvider);
    final isUpdatesChecking = ref
        .watch(updatesSocketProvider
            .select((value) => value.valueOrNull?.isUpdateChecking))
        .ifNull();
    final (selectedChapters, setSelectedChapters) =
        useStateRecord<Map<int, Chapter>>({});
    useEffect(() {
      controller.addPageRequestListener((pageKey) => _fetchPage(
            updatesRepository,
            controller,
            pageKey,
          ));
      return;
    }, []);
    useEffect(() {
      if (!isUpdatesChecking) {
        try {
          setSelectedChapters({});
          controller.refresh();
        } catch (e) {
          //
        }
      }
      return null;
    }, [isUpdatesChecking]);
    return Scaffold(
      floatingActionButton:
          selectedChapters.isEmpty ? const UpdateStatusFab() : null,
      appBar: selectedChapters.isNotEmpty
          ? AppBar(
              leading: IconButton(
                onPressed: () => setSelectedChapters({}),
                icon: const Icon(Icons.close_rounded),
              ),
              title: Text(
                context.l10n!.numSelected(selectedChapters.length),
              ),
            )
          : AppBar(
              title: Text(context.l10n!.updates),
              actions: const [UpdateStatusPopupMenu()],
            ),
      bottomSheet: selectedChapters.isNotEmpty
          ? MultiChaptersActionsBottomAppBar(
              setSelectedChapters: setSelectedChapters,
              selectedChapters: selectedChapters,
              afterOptionSelected: () async => controller.refresh(),
              hasPreviousDone: false,
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          setSelectedChapters({});
          controller.refresh();
        },
        child: PagedListView(
          pagingController: controller,
          builderDelegate: PagedChildBuilderDelegate<ChapterMangaPair>(
            firstPageErrorIndicatorBuilder: (context) => Emoticons(
              text: controller.error.toString(),
              button: TextButton(
                onPressed: () => controller.refresh(),
                child: Text(context.l10n!.retry),
              ),
            ),
            noItemsFoundIndicatorBuilder: (context) => Emoticons(
              text: context.l10n!.noUpdatesFound,
              button: TextButton(
                onPressed: () => controller.refresh(),
                child: Text(context.l10n!.refresh),
              ),
            ),
            itemBuilder: (context, item, index) {
              int? previousDate;
              try {
                previousDate =
                    controller.itemList?[index - 1].chapter?.fetchedAt;
              } catch (e) {
                previousDate = null;
              }
              final chapterTile = ChapterMangaListTile(
                pair: item,
                updatePair: () async {
                  if (item.manga?.id == null || item.chapter?.index == null) {
                    return;
                  } else {
                    final chapter = ref
                        .refresh(chapterProvider(
                          mangaId: item.manga!.id!,
                          chapterIndex: item.chapter!.index!,
                        ))
                        .valueOrToast(ref.read(toastProvider(context)));
                    try {
                      controller.itemList = [...?controller.itemList]
                        ..replaceRange(index, index + 1, [
                          item.copyWith(
                            chapter: chapter ?? item.chapter,
                          )
                        ]);
                    } catch (e) {
                      //
                    }
                  }
                },
                isSelected: selectedChapters.containsKey(item.chapter!.id!),
                canTapSelect: selectedChapters.isNotEmpty,
                toggleSelect: (Chapter val) {
                  if ((val.id).isNull) return;
                  setSelectedChapters(selectedChapters.toggleKey(val.id!, val));
                },
              );
              if ((item.chapter?.fetchedAt).isSameDayAs(previousDate)) {
                return chapterTile;
              } else {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      title: Text(
                        item.chapter!.fetchedAt.toDaysAgoFromSeconds(context),
                      ),
                    ),
                    chapterTile,
                  ],
                );
              }
            },
          ),
        ),
      ),
    );
  }
}
