// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $ActivitiesTable extends Activities
    with TableInfo<$ActivitiesTable, Activity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActivitiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _syncIdMeta = const VerificationMeta('syncId');
  @override
  late final GeneratedColumn<String> syncId = GeneratedColumn<String>(
    'sync_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES activities (sync_id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bookmarkedMeta = const VerificationMeta(
    'bookmarked',
  );
  @override
  late final GeneratedColumn<bool> bookmarked = GeneratedColumn<bool>(
    'bookmarked',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("bookmarked" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _lastUsedAtMeta = const VerificationMeta(
    'lastUsedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastUsedAt = GeneratedColumn<DateTime>(
    'last_used_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _externalIdMeta = const VerificationMeta(
    'externalId',
  );
  @override
  late final GeneratedColumn<String> externalId = GeneratedColumn<String>(
    'external_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<List<String>, String> aliases =
      GeneratedColumn<String>(
        'aliases',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      ).withConverter<List<String>>($ActivitiesTable.$converteraliases);
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    syncId,
    parentId,
    name,
    color,
    bookmarked,
    lastUsedAt,
    externalId,
    aliases,
    version,
    deletedAt,
    dirty,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'activities';
  @override
  VerificationContext validateIntegrity(
    Insertable<Activity> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('sync_id')) {
      context.handle(
        _syncIdMeta,
        syncId.isAcceptableOrUnknown(data['sync_id']!, _syncIdMeta),
      );
    } else if (isInserting) {
      context.missing(_syncIdMeta);
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    } else if (isInserting) {
      context.missing(_colorMeta);
    }
    if (data.containsKey('bookmarked')) {
      context.handle(
        _bookmarkedMeta,
        bookmarked.isAcceptableOrUnknown(data['bookmarked']!, _bookmarkedMeta),
      );
    }
    if (data.containsKey('last_used_at')) {
      context.handle(
        _lastUsedAtMeta,
        lastUsedAt.isAcceptableOrUnknown(
          data['last_used_at']!,
          _lastUsedAtMeta,
        ),
      );
    }
    if (data.containsKey('external_id')) {
      context.handle(
        _externalIdMeta,
        externalId.isAcceptableOrUnknown(data['external_id']!, _externalIdMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {syncId};
  @override
  Activity map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Activity(
      syncId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_id'],
      )!,
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color'],
      )!,
      bookmarked: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}bookmarked'],
      )!,
      lastUsedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_used_at'],
      ),
      externalId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}external_id'],
      ),
      aliases: $ActivitiesTable.$converteraliases.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}aliases'],
        )!,
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
    );
  }

  @override
  $ActivitiesTable createAlias(String alias) {
    return $ActivitiesTable(attachedDatabase, alias);
  }

  static TypeConverter<List<String>, String> $converteraliases =
      const AliasListConverter();
}

class Activity extends DataClass implements Insertable<Activity> {
  final String syncId;

  /// Parent in the hierarchy, or null for a top-level activity. Self-FK.
  /// Soft-delete (see [deletedAt]) is the norm, so this cascade only bites on
  /// a genuine hard delete.
  final String? parentId;
  final String name;

  /// Concrete hex colour (e.g. `#4F8FEE`) on every node — pre-filled from the
  /// parent on creation but editable.
  final String color;
  final bool bookmarked;

  /// Recency, for last-used-first autocomplete when picking/pasting a task.
  final DateTime? lastUsedAt;

  /// Optional pasted work-tracker id (e.g. `CU-1042`) for a leaf task.
  final String? externalId;

  /// Other words the activity is searched by.
  final List<String> aliases;
  final int version;

  /// Non-null marks a tombstone: archived/deleted at this instant, row kept
  /// (with bumped [version]) so the deletion participates in version-LWW sync.
  final DateTime? deletedAt;

  /// Set by every local write, cleared once the server has accepted the row.
  ///
  /// This is what "needs pushing" means — an `updatedAt > lastSync` comparison
  /// would be at the mercy of clock skew between devices, and a row edited while
  /// a sync was in flight would be missed.
  final bool dirty;
  const Activity({
    required this.syncId,
    this.parentId,
    required this.name,
    required this.color,
    required this.bookmarked,
    this.lastUsedAt,
    this.externalId,
    required this.aliases,
    required this.version,
    this.deletedAt,
    required this.dirty,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['sync_id'] = Variable<String>(syncId);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    map['name'] = Variable<String>(name);
    map['color'] = Variable<String>(color);
    map['bookmarked'] = Variable<bool>(bookmarked);
    if (!nullToAbsent || lastUsedAt != null) {
      map['last_used_at'] = Variable<DateTime>(lastUsedAt);
    }
    if (!nullToAbsent || externalId != null) {
      map['external_id'] = Variable<String>(externalId);
    }
    {
      map['aliases'] = Variable<String>(
        $ActivitiesTable.$converteraliases.toSql(aliases),
      );
    }
    map['version'] = Variable<int>(version);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['dirty'] = Variable<bool>(dirty);
    return map;
  }

  ActivitiesCompanion toCompanion(bool nullToAbsent) {
    return ActivitiesCompanion(
      syncId: Value(syncId),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      name: Value(name),
      color: Value(color),
      bookmarked: Value(bookmarked),
      lastUsedAt: lastUsedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastUsedAt),
      externalId: externalId == null && nullToAbsent
          ? const Value.absent()
          : Value(externalId),
      aliases: Value(aliases),
      version: Value(version),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      dirty: Value(dirty),
    );
  }

  factory Activity.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Activity(
      syncId: serializer.fromJson<String>(json['syncId']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      name: serializer.fromJson<String>(json['name']),
      color: serializer.fromJson<String>(json['color']),
      bookmarked: serializer.fromJson<bool>(json['bookmarked']),
      lastUsedAt: serializer.fromJson<DateTime?>(json['lastUsedAt']),
      externalId: serializer.fromJson<String?>(json['externalId']),
      aliases: serializer.fromJson<List<String>>(json['aliases']),
      version: serializer.fromJson<int>(json['version']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'syncId': serializer.toJson<String>(syncId),
      'parentId': serializer.toJson<String?>(parentId),
      'name': serializer.toJson<String>(name),
      'color': serializer.toJson<String>(color),
      'bookmarked': serializer.toJson<bool>(bookmarked),
      'lastUsedAt': serializer.toJson<DateTime?>(lastUsedAt),
      'externalId': serializer.toJson<String?>(externalId),
      'aliases': serializer.toJson<List<String>>(aliases),
      'version': serializer.toJson<int>(version),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'dirty': serializer.toJson<bool>(dirty),
    };
  }

  Activity copyWith({
    String? syncId,
    Value<String?> parentId = const Value.absent(),
    String? name,
    String? color,
    bool? bookmarked,
    Value<DateTime?> lastUsedAt = const Value.absent(),
    Value<String?> externalId = const Value.absent(),
    List<String>? aliases,
    int? version,
    Value<DateTime?> deletedAt = const Value.absent(),
    bool? dirty,
  }) => Activity(
    syncId: syncId ?? this.syncId,
    parentId: parentId.present ? parentId.value : this.parentId,
    name: name ?? this.name,
    color: color ?? this.color,
    bookmarked: bookmarked ?? this.bookmarked,
    lastUsedAt: lastUsedAt.present ? lastUsedAt.value : this.lastUsedAt,
    externalId: externalId.present ? externalId.value : this.externalId,
    aliases: aliases ?? this.aliases,
    version: version ?? this.version,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    dirty: dirty ?? this.dirty,
  );
  Activity copyWithCompanion(ActivitiesCompanion data) {
    return Activity(
      syncId: data.syncId.present ? data.syncId.value : this.syncId,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      name: data.name.present ? data.name.value : this.name,
      color: data.color.present ? data.color.value : this.color,
      bookmarked: data.bookmarked.present
          ? data.bookmarked.value
          : this.bookmarked,
      lastUsedAt: data.lastUsedAt.present
          ? data.lastUsedAt.value
          : this.lastUsedAt,
      externalId: data.externalId.present
          ? data.externalId.value
          : this.externalId,
      aliases: data.aliases.present ? data.aliases.value : this.aliases,
      version: data.version.present ? data.version.value : this.version,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Activity(')
          ..write('syncId: $syncId, ')
          ..write('parentId: $parentId, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('bookmarked: $bookmarked, ')
          ..write('lastUsedAt: $lastUsedAt, ')
          ..write('externalId: $externalId, ')
          ..write('aliases: $aliases, ')
          ..write('version: $version, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('dirty: $dirty')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    syncId,
    parentId,
    name,
    color,
    bookmarked,
    lastUsedAt,
    externalId,
    aliases,
    version,
    deletedAt,
    dirty,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Activity &&
          other.syncId == this.syncId &&
          other.parentId == this.parentId &&
          other.name == this.name &&
          other.color == this.color &&
          other.bookmarked == this.bookmarked &&
          other.lastUsedAt == this.lastUsedAt &&
          other.externalId == this.externalId &&
          other.aliases == this.aliases &&
          other.version == this.version &&
          other.deletedAt == this.deletedAt &&
          other.dirty == this.dirty);
}

class ActivitiesCompanion extends UpdateCompanion<Activity> {
  final Value<String> syncId;
  final Value<String?> parentId;
  final Value<String> name;
  final Value<String> color;
  final Value<bool> bookmarked;
  final Value<DateTime?> lastUsedAt;
  final Value<String?> externalId;
  final Value<List<String>> aliases;
  final Value<int> version;
  final Value<DateTime?> deletedAt;
  final Value<bool> dirty;
  final Value<int> rowid;
  const ActivitiesCompanion({
    this.syncId = const Value.absent(),
    this.parentId = const Value.absent(),
    this.name = const Value.absent(),
    this.color = const Value.absent(),
    this.bookmarked = const Value.absent(),
    this.lastUsedAt = const Value.absent(),
    this.externalId = const Value.absent(),
    this.aliases = const Value.absent(),
    this.version = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ActivitiesCompanion.insert({
    required String syncId,
    this.parentId = const Value.absent(),
    required String name,
    required String color,
    this.bookmarked = const Value.absent(),
    this.lastUsedAt = const Value.absent(),
    this.externalId = const Value.absent(),
    this.aliases = const Value.absent(),
    this.version = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : syncId = Value(syncId),
       name = Value(name),
       color = Value(color);
  static Insertable<Activity> custom({
    Expression<String>? syncId,
    Expression<String>? parentId,
    Expression<String>? name,
    Expression<String>? color,
    Expression<bool>? bookmarked,
    Expression<DateTime>? lastUsedAt,
    Expression<String>? externalId,
    Expression<String>? aliases,
    Expression<int>? version,
    Expression<DateTime>? deletedAt,
    Expression<bool>? dirty,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (syncId != null) 'sync_id': syncId,
      if (parentId != null) 'parent_id': parentId,
      if (name != null) 'name': name,
      if (color != null) 'color': color,
      if (bookmarked != null) 'bookmarked': bookmarked,
      if (lastUsedAt != null) 'last_used_at': lastUsedAt,
      if (externalId != null) 'external_id': externalId,
      if (aliases != null) 'aliases': aliases,
      if (version != null) 'version': version,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (dirty != null) 'dirty': dirty,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ActivitiesCompanion copyWith({
    Value<String>? syncId,
    Value<String?>? parentId,
    Value<String>? name,
    Value<String>? color,
    Value<bool>? bookmarked,
    Value<DateTime?>? lastUsedAt,
    Value<String?>? externalId,
    Value<List<String>>? aliases,
    Value<int>? version,
    Value<DateTime?>? deletedAt,
    Value<bool>? dirty,
    Value<int>? rowid,
  }) {
    return ActivitiesCompanion(
      syncId: syncId ?? this.syncId,
      parentId: parentId ?? this.parentId,
      name: name ?? this.name,
      color: color ?? this.color,
      bookmarked: bookmarked ?? this.bookmarked,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      externalId: externalId ?? this.externalId,
      aliases: aliases ?? this.aliases,
      version: version ?? this.version,
      deletedAt: deletedAt ?? this.deletedAt,
      dirty: dirty ?? this.dirty,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (syncId.present) {
      map['sync_id'] = Variable<String>(syncId.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (bookmarked.present) {
      map['bookmarked'] = Variable<bool>(bookmarked.value);
    }
    if (lastUsedAt.present) {
      map['last_used_at'] = Variable<DateTime>(lastUsedAt.value);
    }
    if (externalId.present) {
      map['external_id'] = Variable<String>(externalId.value);
    }
    if (aliases.present) {
      map['aliases'] = Variable<String>(
        $ActivitiesTable.$converteraliases.toSql(aliases.value),
      );
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActivitiesCompanion(')
          ..write('syncId: $syncId, ')
          ..write('parentId: $parentId, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('bookmarked: $bookmarked, ')
          ..write('lastUsedAt: $lastUsedAt, ')
          ..write('externalId: $externalId, ')
          ..write('aliases: $aliases, ')
          ..write('version: $version, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('dirty: $dirty, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ActivityChangesTable extends ActivityChanges
    with TableInfo<$ActivityChangesTable, ActivityChange> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActivityChangesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _syncIdMeta = const VerificationMeta('syncId');
  @override
  late final GeneratedColumn<String> syncId = GeneratedColumn<String>(
    'sync_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> changedAt =
      GeneratedColumn<int>(
        'changed_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($ActivityChangesTable.$converterchangedAt);
  static const VerificationMeta _commentMeta = const VerificationMeta(
    'comment',
  );
  @override
  late final GeneratedColumn<String> comment = GeneratedColumn<String>(
    'comment',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    syncId,
    changedAt,
    comment,
    version,
    deletedAt,
    dirty,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'activity_changes';
  @override
  VerificationContext validateIntegrity(
    Insertable<ActivityChange> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('sync_id')) {
      context.handle(
        _syncIdMeta,
        syncId.isAcceptableOrUnknown(data['sync_id']!, _syncIdMeta),
      );
    } else if (isInserting) {
      context.missing(_syncIdMeta);
    }
    if (data.containsKey('comment')) {
      context.handle(
        _commentMeta,
        comment.isAcceptableOrUnknown(data['comment']!, _commentMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {syncId};
  @override
  ActivityChange map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ActivityChange(
      syncId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_id'],
      )!,
      changedAt: $ActivityChangesTable.$converterchangedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}changed_at'],
        )!,
      ),
      comment: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}comment'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
    );
  }

  @override
  $ActivityChangesTable createAlias(String alias) {
    return $ActivityChangesTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterchangedAt =
      const EpochMillisConverter();
}

class ActivityChange extends DataClass implements Insertable<ActivityChange> {
  final String syncId;

  /// The boundary instant, epoch millis (see [EpochMillisConverter]).
  final DateTime changedAt;
  final String? comment;
  final int version;
  final DateTime? deletedAt;

  /// See [Activities.dirty].
  final bool dirty;
  const ActivityChange({
    required this.syncId,
    required this.changedAt,
    this.comment,
    required this.version,
    this.deletedAt,
    required this.dirty,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['sync_id'] = Variable<String>(syncId);
    {
      map['changed_at'] = Variable<int>(
        $ActivityChangesTable.$converterchangedAt.toSql(changedAt),
      );
    }
    if (!nullToAbsent || comment != null) {
      map['comment'] = Variable<String>(comment);
    }
    map['version'] = Variable<int>(version);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['dirty'] = Variable<bool>(dirty);
    return map;
  }

  ActivityChangesCompanion toCompanion(bool nullToAbsent) {
    return ActivityChangesCompanion(
      syncId: Value(syncId),
      changedAt: Value(changedAt),
      comment: comment == null && nullToAbsent
          ? const Value.absent()
          : Value(comment),
      version: Value(version),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      dirty: Value(dirty),
    );
  }

  factory ActivityChange.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ActivityChange(
      syncId: serializer.fromJson<String>(json['syncId']),
      changedAt: serializer.fromJson<DateTime>(json['changedAt']),
      comment: serializer.fromJson<String?>(json['comment']),
      version: serializer.fromJson<int>(json['version']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'syncId': serializer.toJson<String>(syncId),
      'changedAt': serializer.toJson<DateTime>(changedAt),
      'comment': serializer.toJson<String?>(comment),
      'version': serializer.toJson<int>(version),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'dirty': serializer.toJson<bool>(dirty),
    };
  }

  ActivityChange copyWith({
    String? syncId,
    DateTime? changedAt,
    Value<String?> comment = const Value.absent(),
    int? version,
    Value<DateTime?> deletedAt = const Value.absent(),
    bool? dirty,
  }) => ActivityChange(
    syncId: syncId ?? this.syncId,
    changedAt: changedAt ?? this.changedAt,
    comment: comment.present ? comment.value : this.comment,
    version: version ?? this.version,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    dirty: dirty ?? this.dirty,
  );
  ActivityChange copyWithCompanion(ActivityChangesCompanion data) {
    return ActivityChange(
      syncId: data.syncId.present ? data.syncId.value : this.syncId,
      changedAt: data.changedAt.present ? data.changedAt.value : this.changedAt,
      comment: data.comment.present ? data.comment.value : this.comment,
      version: data.version.present ? data.version.value : this.version,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ActivityChange(')
          ..write('syncId: $syncId, ')
          ..write('changedAt: $changedAt, ')
          ..write('comment: $comment, ')
          ..write('version: $version, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('dirty: $dirty')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(syncId, changedAt, comment, version, deletedAt, dirty);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ActivityChange &&
          other.syncId == this.syncId &&
          other.changedAt == this.changedAt &&
          other.comment == this.comment &&
          other.version == this.version &&
          other.deletedAt == this.deletedAt &&
          other.dirty == this.dirty);
}

class ActivityChangesCompanion extends UpdateCompanion<ActivityChange> {
  final Value<String> syncId;
  final Value<DateTime> changedAt;
  final Value<String?> comment;
  final Value<int> version;
  final Value<DateTime?> deletedAt;
  final Value<bool> dirty;
  final Value<int> rowid;
  const ActivityChangesCompanion({
    this.syncId = const Value.absent(),
    this.changedAt = const Value.absent(),
    this.comment = const Value.absent(),
    this.version = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ActivityChangesCompanion.insert({
    required String syncId,
    required DateTime changedAt,
    this.comment = const Value.absent(),
    this.version = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : syncId = Value(syncId),
       changedAt = Value(changedAt);
  static Insertable<ActivityChange> custom({
    Expression<String>? syncId,
    Expression<int>? changedAt,
    Expression<String>? comment,
    Expression<int>? version,
    Expression<DateTime>? deletedAt,
    Expression<bool>? dirty,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (syncId != null) 'sync_id': syncId,
      if (changedAt != null) 'changed_at': changedAt,
      if (comment != null) 'comment': comment,
      if (version != null) 'version': version,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (dirty != null) 'dirty': dirty,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ActivityChangesCompanion copyWith({
    Value<String>? syncId,
    Value<DateTime>? changedAt,
    Value<String?>? comment,
    Value<int>? version,
    Value<DateTime?>? deletedAt,
    Value<bool>? dirty,
    Value<int>? rowid,
  }) {
    return ActivityChangesCompanion(
      syncId: syncId ?? this.syncId,
      changedAt: changedAt ?? this.changedAt,
      comment: comment ?? this.comment,
      version: version ?? this.version,
      deletedAt: deletedAt ?? this.deletedAt,
      dirty: dirty ?? this.dirty,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (syncId.present) {
      map['sync_id'] = Variable<String>(syncId.value);
    }
    if (changedAt.present) {
      map['changed_at'] = Variable<int>(
        $ActivityChangesTable.$converterchangedAt.toSql(changedAt.value),
      );
    }
    if (comment.present) {
      map['comment'] = Variable<String>(comment.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActivityChangesCompanion(')
          ..write('syncId: $syncId, ')
          ..write('changedAt: $changedAt, ')
          ..write('comment: $comment, ')
          ..write('version: $version, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('dirty: $dirty, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ActivityChangeActivitiesTable extends ActivityChangeActivities
    with TableInfo<$ActivityChangeActivitiesTable, ActivityChangeActivity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActivityChangeActivitiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _activityChangeIdMeta = const VerificationMeta(
    'activityChangeId',
  );
  @override
  late final GeneratedColumn<String> activityChangeId = GeneratedColumn<String>(
    'activity_change_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES activity_changes (sync_id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _activityIdMeta = const VerificationMeta(
    'activityId',
  );
  @override
  late final GeneratedColumn<String> activityId = GeneratedColumn<String>(
    'activity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES activities (sync_id) ON DELETE CASCADE',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [activityChangeId, activityId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'activity_change_activities';
  @override
  VerificationContext validateIntegrity(
    Insertable<ActivityChangeActivity> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('activity_change_id')) {
      context.handle(
        _activityChangeIdMeta,
        activityChangeId.isAcceptableOrUnknown(
          data['activity_change_id']!,
          _activityChangeIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_activityChangeIdMeta);
    }
    if (data.containsKey('activity_id')) {
      context.handle(
        _activityIdMeta,
        activityId.isAcceptableOrUnknown(data['activity_id']!, _activityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_activityIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {activityChangeId, activityId};
  @override
  ActivityChangeActivity map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ActivityChangeActivity(
      activityChangeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}activity_change_id'],
      )!,
      activityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}activity_id'],
      )!,
    );
  }

  @override
  $ActivityChangeActivitiesTable createAlias(String alias) {
    return $ActivityChangeActivitiesTable(attachedDatabase, alias);
  }
}

class ActivityChangeActivity extends DataClass
    implements Insertable<ActivityChangeActivity> {
  final String activityChangeId;
  final String activityId;
  const ActivityChangeActivity({
    required this.activityChangeId,
    required this.activityId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['activity_change_id'] = Variable<String>(activityChangeId);
    map['activity_id'] = Variable<String>(activityId);
    return map;
  }

  ActivityChangeActivitiesCompanion toCompanion(bool nullToAbsent) {
    return ActivityChangeActivitiesCompanion(
      activityChangeId: Value(activityChangeId),
      activityId: Value(activityId),
    );
  }

  factory ActivityChangeActivity.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ActivityChangeActivity(
      activityChangeId: serializer.fromJson<String>(json['activityChangeId']),
      activityId: serializer.fromJson<String>(json['activityId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'activityChangeId': serializer.toJson<String>(activityChangeId),
      'activityId': serializer.toJson<String>(activityId),
    };
  }

  ActivityChangeActivity copyWith({
    String? activityChangeId,
    String? activityId,
  }) => ActivityChangeActivity(
    activityChangeId: activityChangeId ?? this.activityChangeId,
    activityId: activityId ?? this.activityId,
  );
  ActivityChangeActivity copyWithCompanion(
    ActivityChangeActivitiesCompanion data,
  ) {
    return ActivityChangeActivity(
      activityChangeId: data.activityChangeId.present
          ? data.activityChangeId.value
          : this.activityChangeId,
      activityId: data.activityId.present
          ? data.activityId.value
          : this.activityId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ActivityChangeActivity(')
          ..write('activityChangeId: $activityChangeId, ')
          ..write('activityId: $activityId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(activityChangeId, activityId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ActivityChangeActivity &&
          other.activityChangeId == this.activityChangeId &&
          other.activityId == this.activityId);
}

class ActivityChangeActivitiesCompanion
    extends UpdateCompanion<ActivityChangeActivity> {
  final Value<String> activityChangeId;
  final Value<String> activityId;
  final Value<int> rowid;
  const ActivityChangeActivitiesCompanion({
    this.activityChangeId = const Value.absent(),
    this.activityId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ActivityChangeActivitiesCompanion.insert({
    required String activityChangeId,
    required String activityId,
    this.rowid = const Value.absent(),
  }) : activityChangeId = Value(activityChangeId),
       activityId = Value(activityId);
  static Insertable<ActivityChangeActivity> custom({
    Expression<String>? activityChangeId,
    Expression<String>? activityId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (activityChangeId != null) 'activity_change_id': activityChangeId,
      if (activityId != null) 'activity_id': activityId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ActivityChangeActivitiesCompanion copyWith({
    Value<String>? activityChangeId,
    Value<String>? activityId,
    Value<int>? rowid,
  }) {
    return ActivityChangeActivitiesCompanion(
      activityChangeId: activityChangeId ?? this.activityChangeId,
      activityId: activityId ?? this.activityId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (activityChangeId.present) {
      map['activity_change_id'] = Variable<String>(activityChangeId.value);
    }
    if (activityId.present) {
      map['activity_id'] = Variable<String>(activityId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActivityChangeActivitiesCompanion(')
          ..write('activityChangeId: $activityChangeId, ')
          ..write('activityId: $activityId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncMetaTable extends SyncMeta
    with TableInfo<$SyncMetaTable, SyncMetaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncMetaData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SyncMetaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncMetaData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SyncMetaTable createAlias(String alias) {
    return $SyncMetaTable(attachedDatabase, alias);
  }
}

class SyncMetaData extends DataClass implements Insertable<SyncMetaData> {
  final String key;
  final String value;
  const SyncMetaData({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SyncMetaCompanion toCompanion(bool nullToAbsent) {
    return SyncMetaCompanion(key: Value(key), value: Value(value));
  }

  factory SyncMetaData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncMetaData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SyncMetaData copyWith({String? key, String? value}) =>
      SyncMetaData(key: key ?? this.key, value: value ?? this.value);
  SyncMetaData copyWithCompanion(SyncMetaCompanion data) {
    return SyncMetaData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetaData(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncMetaData &&
          other.key == this.key &&
          other.value == this.value);
}

class SyncMetaCompanion extends UpdateCompanion<SyncMetaData> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SyncMetaCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncMetaCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SyncMetaData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncMetaCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SyncMetaCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetaCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WearOutboxTable extends WearOutbox
    with TableInfo<$WearOutboxTable, WearOutboxData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WearOutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _collapseKeyMeta = const VerificationMeta(
    'collapseKey',
  );
  @override
  late final GeneratedColumn<String> collapseKey = GeneratedColumn<String>(
    'collapse_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [id, type, payload, collapseKey];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'wear_outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<WearOutboxData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('collapse_key')) {
      context.handle(
        _collapseKeyMeta,
        collapseKey.isAcceptableOrUnknown(
          data['collapse_key']!,
          _collapseKeyMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WearOutboxData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WearOutboxData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      collapseKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}collapse_key'],
      ),
    );
  }

  @override
  $WearOutboxTable createAlias(String alias) {
    return $WearOutboxTable(attachedDatabase, alias);
  }
}

class WearOutboxData extends DataClass implements Insertable<WearOutboxData> {
  final int id;

  /// [WearMessage.type], and [payload] is its `toPayload()` as JSON.
  final String type;
  final String payload;

  /// Null keeps every entry; otherwise a new entry replaces the one it matches.
  final String? collapseKey;
  const WearOutboxData({
    required this.id,
    required this.type,
    required this.payload,
    this.collapseKey,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['type'] = Variable<String>(type);
    map['payload'] = Variable<String>(payload);
    if (!nullToAbsent || collapseKey != null) {
      map['collapse_key'] = Variable<String>(collapseKey);
    }
    return map;
  }

  WearOutboxCompanion toCompanion(bool nullToAbsent) {
    return WearOutboxCompanion(
      id: Value(id),
      type: Value(type),
      payload: Value(payload),
      collapseKey: collapseKey == null && nullToAbsent
          ? const Value.absent()
          : Value(collapseKey),
    );
  }

  factory WearOutboxData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WearOutboxData(
      id: serializer.fromJson<int>(json['id']),
      type: serializer.fromJson<String>(json['type']),
      payload: serializer.fromJson<String>(json['payload']),
      collapseKey: serializer.fromJson<String?>(json['collapseKey']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'type': serializer.toJson<String>(type),
      'payload': serializer.toJson<String>(payload),
      'collapseKey': serializer.toJson<String?>(collapseKey),
    };
  }

  WearOutboxData copyWith({
    int? id,
    String? type,
    String? payload,
    Value<String?> collapseKey = const Value.absent(),
  }) => WearOutboxData(
    id: id ?? this.id,
    type: type ?? this.type,
    payload: payload ?? this.payload,
    collapseKey: collapseKey.present ? collapseKey.value : this.collapseKey,
  );
  WearOutboxData copyWithCompanion(WearOutboxCompanion data) {
    return WearOutboxData(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      payload: data.payload.present ? data.payload.value : this.payload,
      collapseKey: data.collapseKey.present
          ? data.collapseKey.value
          : this.collapseKey,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WearOutboxData(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('payload: $payload, ')
          ..write('collapseKey: $collapseKey')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, type, payload, collapseKey);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WearOutboxData &&
          other.id == this.id &&
          other.type == this.type &&
          other.payload == this.payload &&
          other.collapseKey == this.collapseKey);
}

class WearOutboxCompanion extends UpdateCompanion<WearOutboxData> {
  final Value<int> id;
  final Value<String> type;
  final Value<String> payload;
  final Value<String?> collapseKey;
  const WearOutboxCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.payload = const Value.absent(),
    this.collapseKey = const Value.absent(),
  });
  WearOutboxCompanion.insert({
    this.id = const Value.absent(),
    required String type,
    required String payload,
    this.collapseKey = const Value.absent(),
  }) : type = Value(type),
       payload = Value(payload);
  static Insertable<WearOutboxData> custom({
    Expression<int>? id,
    Expression<String>? type,
    Expression<String>? payload,
    Expression<String>? collapseKey,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (payload != null) 'payload': payload,
      if (collapseKey != null) 'collapse_key': collapseKey,
    });
  }

  WearOutboxCompanion copyWith({
    Value<int>? id,
    Value<String>? type,
    Value<String>? payload,
    Value<String?>? collapseKey,
  }) {
    return WearOutboxCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      payload: payload ?? this.payload,
      collapseKey: collapseKey ?? this.collapseKey,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (collapseKey.present) {
      map['collapse_key'] = Variable<String>(collapseKey.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WearOutboxCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('payload: $payload, ')
          ..write('collapseKey: $collapseKey')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ActivitiesTable activities = $ActivitiesTable(this);
  late final $ActivityChangesTable activityChanges = $ActivityChangesTable(
    this,
  );
  late final $ActivityChangeActivitiesTable activityChangeActivities =
      $ActivityChangeActivitiesTable(this);
  late final $SyncMetaTable syncMeta = $SyncMetaTable(this);
  late final $WearOutboxTable wearOutbox = $WearOutboxTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    activities,
    activityChanges,
    activityChangeActivities,
    syncMeta,
    wearOutbox,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'activities',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('activities', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'activity_changes',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [
        TableUpdate('activity_change_activities', kind: UpdateKind.delete),
      ],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'activities',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [
        TableUpdate('activity_change_activities', kind: UpdateKind.delete),
      ],
    ),
  ]);
}

typedef $$ActivitiesTableCreateCompanionBuilder =
    ActivitiesCompanion Function({
      required String syncId,
      Value<String?> parentId,
      required String name,
      required String color,
      Value<bool> bookmarked,
      Value<DateTime?> lastUsedAt,
      Value<String?> externalId,
      Value<List<String>> aliases,
      Value<int> version,
      Value<DateTime?> deletedAt,
      Value<bool> dirty,
      Value<int> rowid,
    });
typedef $$ActivitiesTableUpdateCompanionBuilder =
    ActivitiesCompanion Function({
      Value<String> syncId,
      Value<String?> parentId,
      Value<String> name,
      Value<String> color,
      Value<bool> bookmarked,
      Value<DateTime?> lastUsedAt,
      Value<String?> externalId,
      Value<List<String>> aliases,
      Value<int> version,
      Value<DateTime?> deletedAt,
      Value<bool> dirty,
      Value<int> rowid,
    });

final class $$ActivitiesTableReferences
    extends BaseReferences<_$AppDatabase, $ActivitiesTable, Activity> {
  $$ActivitiesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ActivitiesTable _parentIdTable(_$AppDatabase db) =>
      db.activities.createAlias('activities__parent_id__activities__sync_id');

  $$ActivitiesTableProcessedTableManager? get parentId {
    final $_column = $_itemColumn<String>('parent_id');
    if ($_column == null) return null;
    final manager = $$ActivitiesTableTableManager(
      $_db,
      $_db.activities,
    ).filter((f) => f.syncId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_parentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<
    $ActivityChangeActivitiesTable,
    List<ActivityChangeActivity>
  >
  _activityChangeActivitiesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.activityChangeActivities,
        aliasName:
            'activities__sync_id__activity_change_activities__activity_id',
      );

  $$ActivityChangeActivitiesTableProcessedTableManager
  get activityChangeActivitiesRefs {
    final manager =
        $$ActivityChangeActivitiesTableTableManager(
          $_db,
          $_db.activityChangeActivities,
        ).filter(
          (f) =>
              f.activityId.syncId.sqlEquals($_itemColumn<String>('sync_id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _activityChangeActivitiesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ActivitiesTableFilterComposer
    extends Composer<_$AppDatabase, $ActivitiesTable> {
  $$ActivitiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get syncId => $composableBuilder(
    column: $table.syncId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get bookmarked => $composableBuilder(
    column: $table.bookmarked,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get externalId => $composableBuilder(
    column: $table.externalId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<List<String>, List<String>, String>
  get aliases => $composableBuilder(
    column: $table.aliases,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  $$ActivitiesTableFilterComposer get parentId {
    final $$ActivitiesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentId,
      referencedTable: $db.activities,
      getReferencedColumn: (t) => t.syncId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivitiesTableFilterComposer(
            $db: $db,
            $table: $db.activities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> activityChangeActivitiesRefs(
    Expression<bool> Function($$ActivityChangeActivitiesTableFilterComposer f)
    f,
  ) {
    final $$ActivityChangeActivitiesTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.syncId,
          referencedTable: $db.activityChangeActivities,
          getReferencedColumn: (t) => t.activityId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ActivityChangeActivitiesTableFilterComposer(
                $db: $db,
                $table: $db.activityChangeActivities,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$ActivitiesTableOrderingComposer
    extends Composer<_$AppDatabase, $ActivitiesTable> {
  $$ActivitiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get syncId => $composableBuilder(
    column: $table.syncId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get bookmarked => $composableBuilder(
    column: $table.bookmarked,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get externalId => $composableBuilder(
    column: $table.externalId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aliases => $composableBuilder(
    column: $table.aliases,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  $$ActivitiesTableOrderingComposer get parentId {
    final $$ActivitiesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentId,
      referencedTable: $db.activities,
      getReferencedColumn: (t) => t.syncId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivitiesTableOrderingComposer(
            $db: $db,
            $table: $db.activities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActivitiesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ActivitiesTable> {
  $$ActivitiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get syncId =>
      $composableBuilder(column: $table.syncId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<bool> get bookmarked => $composableBuilder(
    column: $table.bookmarked,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get externalId => $composableBuilder(
    column: $table.externalId,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<List<String>, String> get aliases =>
      $composableBuilder(column: $table.aliases, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  $$ActivitiesTableAnnotationComposer get parentId {
    final $$ActivitiesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentId,
      referencedTable: $db.activities,
      getReferencedColumn: (t) => t.syncId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivitiesTableAnnotationComposer(
            $db: $db,
            $table: $db.activities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> activityChangeActivitiesRefs<T extends Object>(
    Expression<T> Function($$ActivityChangeActivitiesTableAnnotationComposer a)
    f,
  ) {
    final $$ActivityChangeActivitiesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.syncId,
          referencedTable: $db.activityChangeActivities,
          getReferencedColumn: (t) => t.activityId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ActivityChangeActivitiesTableAnnotationComposer(
                $db: $db,
                $table: $db.activityChangeActivities,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$ActivitiesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ActivitiesTable,
          Activity,
          $$ActivitiesTableFilterComposer,
          $$ActivitiesTableOrderingComposer,
          $$ActivitiesTableAnnotationComposer,
          $$ActivitiesTableCreateCompanionBuilder,
          $$ActivitiesTableUpdateCompanionBuilder,
          (Activity, $$ActivitiesTableReferences),
          Activity,
          PrefetchHooks Function({
            bool parentId,
            bool activityChangeActivitiesRefs,
          })
        > {
  $$ActivitiesTableTableManager(_$AppDatabase db, $ActivitiesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ActivitiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ActivitiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ActivitiesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> syncId = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> color = const Value.absent(),
                Value<bool> bookmarked = const Value.absent(),
                Value<DateTime?> lastUsedAt = const Value.absent(),
                Value<String?> externalId = const Value.absent(),
                Value<List<String>> aliases = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActivitiesCompanion(
                syncId: syncId,
                parentId: parentId,
                name: name,
                color: color,
                bookmarked: bookmarked,
                lastUsedAt: lastUsedAt,
                externalId: externalId,
                aliases: aliases,
                version: version,
                deletedAt: deletedAt,
                dirty: dirty,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String syncId,
                Value<String?> parentId = const Value.absent(),
                required String name,
                required String color,
                Value<bool> bookmarked = const Value.absent(),
                Value<DateTime?> lastUsedAt = const Value.absent(),
                Value<String?> externalId = const Value.absent(),
                Value<List<String>> aliases = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActivitiesCompanion.insert(
                syncId: syncId,
                parentId: parentId,
                name: name,
                color: color,
                bookmarked: bookmarked,
                lastUsedAt: lastUsedAt,
                externalId: externalId,
                aliases: aliases,
                version: version,
                deletedAt: deletedAt,
                dirty: dirty,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ActivitiesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({parentId = false, activityChangeActivitiesRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (activityChangeActivitiesRefs)
                      db.activityChangeActivities,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (parentId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.parentId,
                                    referencedTable: $$ActivitiesTableReferences
                                        ._parentIdTable(db),
                                    referencedColumn:
                                        $$ActivitiesTableReferences
                                            ._parentIdTable(db)
                                            .syncId,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (activityChangeActivitiesRefs)
                        await $_getPrefetchedData<
                          Activity,
                          $ActivitiesTable,
                          ActivityChangeActivity
                        >(
                          currentTable: table,
                          referencedTable: $$ActivitiesTableReferences
                              ._activityChangeActivitiesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ActivitiesTableReferences(
                                db,
                                table,
                                p0,
                              ).activityChangeActivitiesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.activityId == item.syncId,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ActivitiesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ActivitiesTable,
      Activity,
      $$ActivitiesTableFilterComposer,
      $$ActivitiesTableOrderingComposer,
      $$ActivitiesTableAnnotationComposer,
      $$ActivitiesTableCreateCompanionBuilder,
      $$ActivitiesTableUpdateCompanionBuilder,
      (Activity, $$ActivitiesTableReferences),
      Activity,
      PrefetchHooks Function({bool parentId, bool activityChangeActivitiesRefs})
    >;
typedef $$ActivityChangesTableCreateCompanionBuilder =
    ActivityChangesCompanion Function({
      required String syncId,
      required DateTime changedAt,
      Value<String?> comment,
      Value<int> version,
      Value<DateTime?> deletedAt,
      Value<bool> dirty,
      Value<int> rowid,
    });
typedef $$ActivityChangesTableUpdateCompanionBuilder =
    ActivityChangesCompanion Function({
      Value<String> syncId,
      Value<DateTime> changedAt,
      Value<String?> comment,
      Value<int> version,
      Value<DateTime?> deletedAt,
      Value<bool> dirty,
      Value<int> rowid,
    });

final class $$ActivityChangesTableReferences
    extends
        BaseReferences<_$AppDatabase, $ActivityChangesTable, ActivityChange> {
  $$ActivityChangesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<
    $ActivityChangeActivitiesTable,
    List<ActivityChangeActivity>
  >
  _activityChangeActivitiesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.activityChangeActivities,
    aliasName:
        'activity_changes__sync_id__activity_change_activities__activity_change_id',
  );

  $$ActivityChangeActivitiesTableProcessedTableManager
  get activityChangeActivitiesRefs {
    final manager =
        $$ActivityChangeActivitiesTableTableManager(
          $_db,
          $_db.activityChangeActivities,
        ).filter(
          (f) => f.activityChangeId.syncId.sqlEquals(
            $_itemColumn<String>('sync_id')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(
      _activityChangeActivitiesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ActivityChangesTableFilterComposer
    extends Composer<_$AppDatabase, $ActivityChangesTable> {
  $$ActivityChangesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get syncId => $composableBuilder(
    column: $table.syncId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get changedAt =>
      $composableBuilder(
        column: $table.changedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get comment => $composableBuilder(
    column: $table.comment,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> activityChangeActivitiesRefs(
    Expression<bool> Function($$ActivityChangeActivitiesTableFilterComposer f)
    f,
  ) {
    final $$ActivityChangeActivitiesTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.syncId,
          referencedTable: $db.activityChangeActivities,
          getReferencedColumn: (t) => t.activityChangeId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ActivityChangeActivitiesTableFilterComposer(
                $db: $db,
                $table: $db.activityChangeActivities,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$ActivityChangesTableOrderingComposer
    extends Composer<_$AppDatabase, $ActivityChangesTable> {
  $$ActivityChangesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get syncId => $composableBuilder(
    column: $table.syncId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get changedAt => $composableBuilder(
    column: $table.changedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get comment => $composableBuilder(
    column: $table.comment,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ActivityChangesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ActivityChangesTable> {
  $$ActivityChangesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get syncId =>
      $composableBuilder(column: $table.syncId, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get changedAt =>
      $composableBuilder(column: $table.changedAt, builder: (column) => column);

  GeneratedColumn<String> get comment =>
      $composableBuilder(column: $table.comment, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  Expression<T> activityChangeActivitiesRefs<T extends Object>(
    Expression<T> Function($$ActivityChangeActivitiesTableAnnotationComposer a)
    f,
  ) {
    final $$ActivityChangeActivitiesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.syncId,
          referencedTable: $db.activityChangeActivities,
          getReferencedColumn: (t) => t.activityChangeId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ActivityChangeActivitiesTableAnnotationComposer(
                $db: $db,
                $table: $db.activityChangeActivities,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$ActivityChangesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ActivityChangesTable,
          ActivityChange,
          $$ActivityChangesTableFilterComposer,
          $$ActivityChangesTableOrderingComposer,
          $$ActivityChangesTableAnnotationComposer,
          $$ActivityChangesTableCreateCompanionBuilder,
          $$ActivityChangesTableUpdateCompanionBuilder,
          (ActivityChange, $$ActivityChangesTableReferences),
          ActivityChange,
          PrefetchHooks Function({bool activityChangeActivitiesRefs})
        > {
  $$ActivityChangesTableTableManager(
    _$AppDatabase db,
    $ActivityChangesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ActivityChangesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ActivityChangesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ActivityChangesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> syncId = const Value.absent(),
                Value<DateTime> changedAt = const Value.absent(),
                Value<String?> comment = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActivityChangesCompanion(
                syncId: syncId,
                changedAt: changedAt,
                comment: comment,
                version: version,
                deletedAt: deletedAt,
                dirty: dirty,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String syncId,
                required DateTime changedAt,
                Value<String?> comment = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActivityChangesCompanion.insert(
                syncId: syncId,
                changedAt: changedAt,
                comment: comment,
                version: version,
                deletedAt: deletedAt,
                dirty: dirty,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ActivityChangesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({activityChangeActivitiesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (activityChangeActivitiesRefs) db.activityChangeActivities,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (activityChangeActivitiesRefs)
                    await $_getPrefetchedData<
                      ActivityChange,
                      $ActivityChangesTable,
                      ActivityChangeActivity
                    >(
                      currentTable: table,
                      referencedTable: $$ActivityChangesTableReferences
                          ._activityChangeActivitiesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$ActivityChangesTableReferences(
                            db,
                            table,
                            p0,
                          ).activityChangeActivitiesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.activityChangeId == item.syncId,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ActivityChangesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ActivityChangesTable,
      ActivityChange,
      $$ActivityChangesTableFilterComposer,
      $$ActivityChangesTableOrderingComposer,
      $$ActivityChangesTableAnnotationComposer,
      $$ActivityChangesTableCreateCompanionBuilder,
      $$ActivityChangesTableUpdateCompanionBuilder,
      (ActivityChange, $$ActivityChangesTableReferences),
      ActivityChange,
      PrefetchHooks Function({bool activityChangeActivitiesRefs})
    >;
typedef $$ActivityChangeActivitiesTableCreateCompanionBuilder =
    ActivityChangeActivitiesCompanion Function({
      required String activityChangeId,
      required String activityId,
      Value<int> rowid,
    });
typedef $$ActivityChangeActivitiesTableUpdateCompanionBuilder =
    ActivityChangeActivitiesCompanion Function({
      Value<String> activityChangeId,
      Value<String> activityId,
      Value<int> rowid,
    });

final class $$ActivityChangeActivitiesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ActivityChangeActivitiesTable,
          ActivityChangeActivity
        > {
  $$ActivityChangeActivitiesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ActivityChangesTable _activityChangeIdTable(
    _$AppDatabase db,
  ) => db.activityChanges.createAlias(
    'activity_change_activities__activity_change_id__activity_changes__sync_id',
  );

  $$ActivityChangesTableProcessedTableManager get activityChangeId {
    final $_column = $_itemColumn<String>('activity_change_id')!;

    final manager = $$ActivityChangesTableTableManager(
      $_db,
      $_db.activityChanges,
    ).filter((f) => f.syncId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_activityChangeIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ActivitiesTable _activityIdTable(_$AppDatabase db) =>
      db.activities.createAlias(
        'activity_change_activities__activity_id__activities__sync_id',
      );

  $$ActivitiesTableProcessedTableManager get activityId {
    final $_column = $_itemColumn<String>('activity_id')!;

    final manager = $$ActivitiesTableTableManager(
      $_db,
      $_db.activities,
    ).filter((f) => f.syncId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_activityIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ActivityChangeActivitiesTableFilterComposer
    extends Composer<_$AppDatabase, $ActivityChangeActivitiesTable> {
  $$ActivityChangeActivitiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$ActivityChangesTableFilterComposer get activityChangeId {
    final $$ActivityChangesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.activityChangeId,
      referencedTable: $db.activityChanges,
      getReferencedColumn: (t) => t.syncId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivityChangesTableFilterComposer(
            $db: $db,
            $table: $db.activityChanges,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ActivitiesTableFilterComposer get activityId {
    final $$ActivitiesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.activityId,
      referencedTable: $db.activities,
      getReferencedColumn: (t) => t.syncId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivitiesTableFilterComposer(
            $db: $db,
            $table: $db.activities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActivityChangeActivitiesTableOrderingComposer
    extends Composer<_$AppDatabase, $ActivityChangeActivitiesTable> {
  $$ActivityChangeActivitiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$ActivityChangesTableOrderingComposer get activityChangeId {
    final $$ActivityChangesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.activityChangeId,
      referencedTable: $db.activityChanges,
      getReferencedColumn: (t) => t.syncId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivityChangesTableOrderingComposer(
            $db: $db,
            $table: $db.activityChanges,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ActivitiesTableOrderingComposer get activityId {
    final $$ActivitiesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.activityId,
      referencedTable: $db.activities,
      getReferencedColumn: (t) => t.syncId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivitiesTableOrderingComposer(
            $db: $db,
            $table: $db.activities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActivityChangeActivitiesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ActivityChangeActivitiesTable> {
  $$ActivityChangeActivitiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$ActivityChangesTableAnnotationComposer get activityChangeId {
    final $$ActivityChangesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.activityChangeId,
      referencedTable: $db.activityChanges,
      getReferencedColumn: (t) => t.syncId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivityChangesTableAnnotationComposer(
            $db: $db,
            $table: $db.activityChanges,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ActivitiesTableAnnotationComposer get activityId {
    final $$ActivitiesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.activityId,
      referencedTable: $db.activities,
      getReferencedColumn: (t) => t.syncId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivitiesTableAnnotationComposer(
            $db: $db,
            $table: $db.activities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActivityChangeActivitiesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ActivityChangeActivitiesTable,
          ActivityChangeActivity,
          $$ActivityChangeActivitiesTableFilterComposer,
          $$ActivityChangeActivitiesTableOrderingComposer,
          $$ActivityChangeActivitiesTableAnnotationComposer,
          $$ActivityChangeActivitiesTableCreateCompanionBuilder,
          $$ActivityChangeActivitiesTableUpdateCompanionBuilder,
          (ActivityChangeActivity, $$ActivityChangeActivitiesTableReferences),
          ActivityChangeActivity,
          PrefetchHooks Function({bool activityChangeId, bool activityId})
        > {
  $$ActivityChangeActivitiesTableTableManager(
    _$AppDatabase db,
    $ActivityChangeActivitiesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ActivityChangeActivitiesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ActivityChangeActivitiesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ActivityChangeActivitiesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> activityChangeId = const Value.absent(),
                Value<String> activityId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActivityChangeActivitiesCompanion(
                activityChangeId: activityChangeId,
                activityId: activityId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String activityChangeId,
                required String activityId,
                Value<int> rowid = const Value.absent(),
              }) => ActivityChangeActivitiesCompanion.insert(
                activityChangeId: activityChangeId,
                activityId: activityId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ActivityChangeActivitiesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({activityChangeId = false, activityId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (activityChangeId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.activityChangeId,
                                referencedTable:
                                    $$ActivityChangeActivitiesTableReferences
                                        ._activityChangeIdTable(db),
                                referencedColumn:
                                    $$ActivityChangeActivitiesTableReferences
                                        ._activityChangeIdTable(db)
                                        .syncId,
                              )
                              as T;
                    }
                    if (activityId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.activityId,
                                referencedTable:
                                    $$ActivityChangeActivitiesTableReferences
                                        ._activityIdTable(db),
                                referencedColumn:
                                    $$ActivityChangeActivitiesTableReferences
                                        ._activityIdTable(db)
                                        .syncId,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ActivityChangeActivitiesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ActivityChangeActivitiesTable,
      ActivityChangeActivity,
      $$ActivityChangeActivitiesTableFilterComposer,
      $$ActivityChangeActivitiesTableOrderingComposer,
      $$ActivityChangeActivitiesTableAnnotationComposer,
      $$ActivityChangeActivitiesTableCreateCompanionBuilder,
      $$ActivityChangeActivitiesTableUpdateCompanionBuilder,
      (ActivityChangeActivity, $$ActivityChangeActivitiesTableReferences),
      ActivityChangeActivity,
      PrefetchHooks Function({bool activityChangeId, bool activityId})
    >;
typedef $$SyncMetaTableCreateCompanionBuilder =
    SyncMetaCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$SyncMetaTableUpdateCompanionBuilder =
    SyncMetaCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$SyncMetaTableFilterComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncMetaTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncMetaTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SyncMetaTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncMetaTable,
          SyncMetaData,
          $$SyncMetaTableFilterComposer,
          $$SyncMetaTableOrderingComposer,
          $$SyncMetaTableAnnotationComposer,
          $$SyncMetaTableCreateCompanionBuilder,
          $$SyncMetaTableUpdateCompanionBuilder,
          (
            SyncMetaData,
            BaseReferences<_$AppDatabase, $SyncMetaTable, SyncMetaData>,
          ),
          SyncMetaData,
          PrefetchHooks Function()
        > {
  $$SyncMetaTableTableManager(_$AppDatabase db, $SyncMetaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncMetaCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SyncMetaCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncMetaTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncMetaTable,
      SyncMetaData,
      $$SyncMetaTableFilterComposer,
      $$SyncMetaTableOrderingComposer,
      $$SyncMetaTableAnnotationComposer,
      $$SyncMetaTableCreateCompanionBuilder,
      $$SyncMetaTableUpdateCompanionBuilder,
      (
        SyncMetaData,
        BaseReferences<_$AppDatabase, $SyncMetaTable, SyncMetaData>,
      ),
      SyncMetaData,
      PrefetchHooks Function()
    >;
typedef $$WearOutboxTableCreateCompanionBuilder =
    WearOutboxCompanion Function({
      Value<int> id,
      required String type,
      required String payload,
      Value<String?> collapseKey,
    });
typedef $$WearOutboxTableUpdateCompanionBuilder =
    WearOutboxCompanion Function({
      Value<int> id,
      Value<String> type,
      Value<String> payload,
      Value<String?> collapseKey,
    });

class $$WearOutboxTableFilterComposer
    extends Composer<_$AppDatabase, $WearOutboxTable> {
  $$WearOutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get collapseKey => $composableBuilder(
    column: $table.collapseKey,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WearOutboxTableOrderingComposer
    extends Composer<_$AppDatabase, $WearOutboxTable> {
  $$WearOutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get collapseKey => $composableBuilder(
    column: $table.collapseKey,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WearOutboxTableAnnotationComposer
    extends Composer<_$AppDatabase, $WearOutboxTable> {
  $$WearOutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get collapseKey => $composableBuilder(
    column: $table.collapseKey,
    builder: (column) => column,
  );
}

class $$WearOutboxTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WearOutboxTable,
          WearOutboxData,
          $$WearOutboxTableFilterComposer,
          $$WearOutboxTableOrderingComposer,
          $$WearOutboxTableAnnotationComposer,
          $$WearOutboxTableCreateCompanionBuilder,
          $$WearOutboxTableUpdateCompanionBuilder,
          (
            WearOutboxData,
            BaseReferences<_$AppDatabase, $WearOutboxTable, WearOutboxData>,
          ),
          WearOutboxData,
          PrefetchHooks Function()
        > {
  $$WearOutboxTableTableManager(_$AppDatabase db, $WearOutboxTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WearOutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WearOutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WearOutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<String?> collapseKey = const Value.absent(),
              }) => WearOutboxCompanion(
                id: id,
                type: type,
                payload: payload,
                collapseKey: collapseKey,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String type,
                required String payload,
                Value<String?> collapseKey = const Value.absent(),
              }) => WearOutboxCompanion.insert(
                id: id,
                type: type,
                payload: payload,
                collapseKey: collapseKey,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WearOutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WearOutboxTable,
      WearOutboxData,
      $$WearOutboxTableFilterComposer,
      $$WearOutboxTableOrderingComposer,
      $$WearOutboxTableAnnotationComposer,
      $$WearOutboxTableCreateCompanionBuilder,
      $$WearOutboxTableUpdateCompanionBuilder,
      (
        WearOutboxData,
        BaseReferences<_$AppDatabase, $WearOutboxTable, WearOutboxData>,
      ),
      WearOutboxData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ActivitiesTableTableManager get activities =>
      $$ActivitiesTableTableManager(_db, _db.activities);
  $$ActivityChangesTableTableManager get activityChanges =>
      $$ActivityChangesTableTableManager(_db, _db.activityChanges);
  $$ActivityChangeActivitiesTableTableManager get activityChangeActivities =>
      $$ActivityChangeActivitiesTableTableManager(
        _db,
        _db.activityChangeActivities,
      );
  $$SyncMetaTableTableManager get syncMeta =>
      $$SyncMetaTableTableManager(_db, _db.syncMeta);
  $$WearOutboxTableTableManager get wearOutbox =>
      $$WearOutboxTableTableManager(_db, _db.wearOutbox);
}
