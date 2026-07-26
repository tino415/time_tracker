import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../theme/tokens.dart';

/// App-wide theme mode, toggled from the scaffold home. (Phase 1 replaces this
/// home with the real Now / Timeline / Reports / Activities screens.)
final themeModeProvider = StateProvider<ThemeMode>((_) => ThemeMode.system);

class PhoneApp extends ConsumerWidget {
  const PhoneApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Track',
      debugShowCheckedModeBanner: false,
      theme: neoTheme(NeoTokens.light, Brightness.light),
      darkTheme: neoTheme(NeoTokens.dark, Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      home: const _ScaffoldHome(),
    );
  }
}

/// Placeholder home — a smoke screen proving Drift + Riverpod + the neobrutalist
/// tokens are wired. NOT the real UI; the phase-1 "Now" screen replaces it.
class _ScaffoldHome extends ConsumerWidget {
  const _ScaffoldHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).extension<NeoTokens>()!;
    final activities = ref.watch(activitiesStreamProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '[track]',
                    style: TextStyle(
                      fontFamily: kMonoFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: t.brand,
                    ),
                  ),
                  _ThemeButton(),
                ],
              ),
              const SizedBox(height: 14),
              _Chip(text: 'scaffold ok · phase 0'),
              const SizedBox(height: 14),
              Expanded(
                child: activities.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('DB error: $e'),
                  data: (list) => list.isEmpty
                      ? _EmptyState(t: t)
                      : ListView.separated(
                          itemCount: list.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final a = list[i];
                            final fill = _parseColor(a.color);
                            return Container(
                              decoration: t.card(shadowOffset: 4),
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 18,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      color: fill,
                                      border: Border.all(color: t.line, width: 2),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      a.name,
                                      style: TextStyle(
                                        fontFamily: kMonoFont,
                                        fontWeight: FontWeight.w700,
                                        color: t.ink,
                                      ),
                                    ),
                                  ),
                                  if (a.bookmarked)
                                    Text('★', style: TextStyle(color: t.brand)),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ),
              const SizedBox(height: 12),
              _SeedButton(),
            ],
          ),
        ),
      ),
    );
  }

  static Color _parseColor(String hex) {
    final v = hex.replaceFirst('#', '');
    return Color(int.parse('FF$v', radix: 16));
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.t});
  final NeoTokens t;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'no activities yet —\ntap "seed sample activities"',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: kMonoFont,
          color: t.muted,
          height: 1.5,
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<NeoTokens>()!;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        color: t.line,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontFamily: kMonoFont,
            fontWeight: FontWeight.w800,
            fontSize: 11,
            letterSpacing: 1.2,
            color: t.surface,
          ),
        ),
      ),
    );
  }
}

class _ThemeButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).extension<NeoTokens>()!;
    return GestureDetector(
      onTap: () {
        final cur = Theme.of(context).brightness;
        ref.read(themeModeProvider.notifier).state =
            cur == Brightness.dark ? ThemeMode.light : ThemeMode.dark;
      },
      child: Container(
        decoration: BoxDecoration(color: t.line, boxShadow: t.hardShadow(3)),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          '◑ THEME',
          style: TextStyle(
            fontFamily: kMonoFont,
            fontWeight: FontWeight.w700,
            fontSize: 11,
            color: t.surface,
          ),
        ),
      ),
    );
  }
}

class _SeedButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).extension<NeoTokens>()!;
    return GestureDetector(
      onTap: () async {
        final repo = ref.read(activityRepositoryProvider);
        const names = ['Work', 'Email', 'Break', 'Reading'];
        for (var i = 0; i < names.length; i++) {
          final c = ActivityPalette.all[i % ActivityPalette.all.length];
          await repo.createActivity(
            name: names[i],
            color: '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
            bookmarked: true,
          );
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: t.brand,
          border: Border.all(color: t.line, width: 3),
          boxShadow: t.hardShadow(5),
        ),
        padding: const EdgeInsets.all(13),
        alignment: Alignment.center,
        child: Text(
          '+ SEED SAMPLE ACTIVITIES',
          style: TextStyle(
            fontFamily: kMonoFont,
            fontWeight: FontWeight.w800,
            letterSpacing: .6,
            color: t.brandInk,
          ),
        ),
      ),
    );
  }
}
