// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'flashcard_entity.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetFlashcardEntityCollection on Isar {
  IsarCollection<FlashcardEntity> get flashcardEntitys => this.collection();
}

const FlashcardEntitySchema = CollectionSchema(
  name: r'FlashcardEntity',
  id: 8104981407035358586,
  properties: {
    r'back': PropertySchema(
      id: 0,
      name: r'back',
      type: IsarType.string,
    ),
    r'createdAt': PropertySchema(
      id: 1,
      name: r'createdAt',
      type: IsarType.dateTime,
    ),
    r'difficulty': PropertySchema(
      id: 2,
      name: r'difficulty',
      type: IsarType.long,
    ),
    r'flashcardId': PropertySchema(
      id: 3,
      name: r'flashcardId',
      type: IsarType.string,
    ),
    r'front': PropertySchema(
      id: 4,
      name: r'front',
      type: IsarType.string,
    ),
    r'hint': PropertySchema(
      id: 5,
      name: r'hint',
      type: IsarType.string,
    ),
    r'srsEaseFactor': PropertySchema(
      id: 6,
      name: r'srsEaseFactor',
      type: IsarType.double,
    ),
    r'srsInterval': PropertySchema(
      id: 7,
      name: r'srsInterval',
      type: IsarType.long,
    ),
    r'srsLastReviewDate': PropertySchema(
      id: 8,
      name: r'srsLastReviewDate',
      type: IsarType.dateTime,
    ),
    r'srsNextReviewDate': PropertySchema(
      id: 9,
      name: r'srsNextReviewDate',
      type: IsarType.dateTime,
    ),
    r'srsRepetitions': PropertySchema(
      id: 10,
      name: r'srsRepetitions',
      type: IsarType.long,
    ),
    r'studySetId': PropertySchema(
      id: 11,
      name: r'studySetId',
      type: IsarType.string,
    )
  },
  estimateSize: _flashcardEntityEstimateSize,
  serialize: _flashcardEntitySerialize,
  deserialize: _flashcardEntityDeserialize,
  deserializeProp: _flashcardEntityDeserializeProp,
  idName: r'id',
  indexes: {
    r'flashcardId': IndexSchema(
      id: -8337910829515384627,
      name: r'flashcardId',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'flashcardId',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _flashcardEntityGetId,
  getLinks: _flashcardEntityGetLinks,
  attach: _flashcardEntityAttach,
  version: '3.1.0+1',
);

int _flashcardEntityEstimateSize(
  FlashcardEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.back.length * 3;
  bytesCount += 3 + object.flashcardId.length * 3;
  bytesCount += 3 + object.front.length * 3;
  {
    final value = object.hint;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.studySetId.length * 3;
  return bytesCount;
}

void _flashcardEntitySerialize(
  FlashcardEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.back);
  writer.writeDateTime(offsets[1], object.createdAt);
  writer.writeLong(offsets[2], object.difficulty);
  writer.writeString(offsets[3], object.flashcardId);
  writer.writeString(offsets[4], object.front);
  writer.writeString(offsets[5], object.hint);
  writer.writeDouble(offsets[6], object.srsEaseFactor);
  writer.writeLong(offsets[7], object.srsInterval);
  writer.writeDateTime(offsets[8], object.srsLastReviewDate);
  writer.writeDateTime(offsets[9], object.srsNextReviewDate);
  writer.writeLong(offsets[10], object.srsRepetitions);
  writer.writeString(offsets[11], object.studySetId);
}

FlashcardEntity _flashcardEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = FlashcardEntity();
  object.back = reader.readString(offsets[0]);
  object.createdAt = reader.readDateTime(offsets[1]);
  object.difficulty = reader.readLong(offsets[2]);
  object.flashcardId = reader.readString(offsets[3]);
  object.front = reader.readString(offsets[4]);
  object.hint = reader.readStringOrNull(offsets[5]);
  object.id = id;
  object.srsEaseFactor = reader.readDoubleOrNull(offsets[6]);
  object.srsInterval = reader.readLongOrNull(offsets[7]);
  object.srsLastReviewDate = reader.readDateTimeOrNull(offsets[8]);
  object.srsNextReviewDate = reader.readDateTimeOrNull(offsets[9]);
  object.srsRepetitions = reader.readLongOrNull(offsets[10]);
  object.studySetId = reader.readString(offsets[11]);
  return object;
}

P _flashcardEntityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readDateTime(offset)) as P;
    case 2:
      return (reader.readLong(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    case 5:
      return (reader.readStringOrNull(offset)) as P;
    case 6:
      return (reader.readDoubleOrNull(offset)) as P;
    case 7:
      return (reader.readLongOrNull(offset)) as P;
    case 8:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 9:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 10:
      return (reader.readLongOrNull(offset)) as P;
    case 11:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _flashcardEntityGetId(FlashcardEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _flashcardEntityGetLinks(FlashcardEntity object) {
  return [];
}

void _flashcardEntityAttach(
    IsarCollection<dynamic> col, Id id, FlashcardEntity object) {
  object.id = id;
}

extension FlashcardEntityByIndex on IsarCollection<FlashcardEntity> {
  Future<FlashcardEntity?> getByFlashcardId(String flashcardId) {
    return getByIndex(r'flashcardId', [flashcardId]);
  }

  FlashcardEntity? getByFlashcardIdSync(String flashcardId) {
    return getByIndexSync(r'flashcardId', [flashcardId]);
  }

  Future<bool> deleteByFlashcardId(String flashcardId) {
    return deleteByIndex(r'flashcardId', [flashcardId]);
  }

  bool deleteByFlashcardIdSync(String flashcardId) {
    return deleteByIndexSync(r'flashcardId', [flashcardId]);
  }

  Future<List<FlashcardEntity?>> getAllByFlashcardId(
      List<String> flashcardIdValues) {
    final values = flashcardIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'flashcardId', values);
  }

  List<FlashcardEntity?> getAllByFlashcardIdSync(
      List<String> flashcardIdValues) {
    final values = flashcardIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'flashcardId', values);
  }

  Future<int> deleteAllByFlashcardId(List<String> flashcardIdValues) {
    final values = flashcardIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'flashcardId', values);
  }

  int deleteAllByFlashcardIdSync(List<String> flashcardIdValues) {
    final values = flashcardIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'flashcardId', values);
  }

  Future<Id> putByFlashcardId(FlashcardEntity object) {
    return putByIndex(r'flashcardId', object);
  }

  Id putByFlashcardIdSync(FlashcardEntity object, {bool saveLinks = true}) {
    return putByIndexSync(r'flashcardId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByFlashcardId(List<FlashcardEntity> objects) {
    return putAllByIndex(r'flashcardId', objects);
  }

  List<Id> putAllByFlashcardIdSync(List<FlashcardEntity> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'flashcardId', objects, saveLinks: saveLinks);
  }
}

extension FlashcardEntityQueryWhereSort
    on QueryBuilder<FlashcardEntity, FlashcardEntity, QWhere> {
  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension FlashcardEntityQueryWhere
    on QueryBuilder<FlashcardEntity, FlashcardEntity, QWhereClause> {
  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterWhereClause> idEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterWhereClause>
      idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterWhereClause>
      idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterWhereClause> idLessThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterWhereClause>
      flashcardIdEqualTo(String flashcardId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'flashcardId',
        value: [flashcardId],
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterWhereClause>
      flashcardIdNotEqualTo(String flashcardId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'flashcardId',
              lower: [],
              upper: [flashcardId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'flashcardId',
              lower: [flashcardId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'flashcardId',
              lower: [flashcardId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'flashcardId',
              lower: [],
              upper: [flashcardId],
              includeUpper: false,
            ));
      }
    });
  }
}

extension FlashcardEntityQueryFilter
    on QueryBuilder<FlashcardEntity, FlashcardEntity, QFilterCondition> {
  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      backEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'back',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      backGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'back',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      backLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'back',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      backBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'back',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      backStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'back',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      backEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'back',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      backContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'back',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      backMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'back',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      backIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'back',
        value: '',
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      backIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'back',
        value: '',
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      createdAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      createdAtGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      createdAtLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      createdAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'createdAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      difficultyEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'difficulty',
        value: value,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      difficultyGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'difficulty',
        value: value,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      difficultyLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'difficulty',
        value: value,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      difficultyBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'difficulty',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      flashcardIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'flashcardId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      flashcardIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'flashcardId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      flashcardIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'flashcardId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      flashcardIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'flashcardId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      flashcardIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'flashcardId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      flashcardIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'flashcardId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      flashcardIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'flashcardId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      flashcardIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'flashcardId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      flashcardIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'flashcardId',
        value: '',
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      flashcardIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'flashcardId',
        value: '',
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      frontEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'front',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      frontGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'front',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      frontLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'front',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      frontBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'front',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      frontStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'front',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      frontEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'front',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      frontContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'front',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      frontMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'front',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      frontIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'front',
        value: '',
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      frontIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'front',
        value: '',
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      hintIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'hint',
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      hintIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'hint',
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      hintEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'hint',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      hintGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'hint',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      hintLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'hint',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      hintBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'hint',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      hintStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'hint',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      hintEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'hint',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      hintContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'hint',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      hintMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'hint',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      hintIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'hint',
        value: '',
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      hintIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'hint',
        value: '',
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      srsEaseFactorIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'srsEaseFactor',
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      srsEaseFactorIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'srsEaseFactor',
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      srsEaseFactorEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'srsEaseFactor',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      srsEaseFactorGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'srsEaseFactor',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      srsEaseFactorLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'srsEaseFactor',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      srsEaseFactorBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'srsEaseFactor',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      srsIntervalIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'srsInterval',
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      srsIntervalIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'srsInterval',
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      srsIntervalEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'srsInterval',
        value: value,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      srsIntervalGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'srsInterval',
        value: value,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      srsIntervalLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'srsInterval',
        value: value,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      srsIntervalBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'srsInterval',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      srsLastReviewDateIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'srsLastReviewDate',
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      srsLastReviewDateIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'srsLastReviewDate',
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      srsLastReviewDateEqualTo(DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'srsLastReviewDate',
        value: value,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      srsLastReviewDateGreaterThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'srsLastReviewDate',
        value: value,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      srsLastReviewDateLessThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'srsLastReviewDate',
        value: value,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      srsLastReviewDateBetween(
    DateTime? lower,
    DateTime? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'srsLastReviewDate',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      srsNextReviewDateIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'srsNextReviewDate',
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      srsNextReviewDateIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'srsNextReviewDate',
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      srsNextReviewDateEqualTo(DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'srsNextReviewDate',
        value: value,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      srsNextReviewDateGreaterThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'srsNextReviewDate',
        value: value,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      srsNextReviewDateLessThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'srsNextReviewDate',
        value: value,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      srsNextReviewDateBetween(
    DateTime? lower,
    DateTime? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'srsNextReviewDate',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      srsRepetitionsIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'srsRepetitions',
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      srsRepetitionsIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'srsRepetitions',
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      srsRepetitionsEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'srsRepetitions',
        value: value,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      srsRepetitionsGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'srsRepetitions',
        value: value,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      srsRepetitionsLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'srsRepetitions',
        value: value,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      srsRepetitionsBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'srsRepetitions',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      studySetIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'studySetId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      studySetIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'studySetId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      studySetIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'studySetId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      studySetIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'studySetId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      studySetIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'studySetId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      studySetIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'studySetId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      studySetIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'studySetId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      studySetIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'studySetId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      studySetIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'studySetId',
        value: '',
      ));
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterFilterCondition>
      studySetIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'studySetId',
        value: '',
      ));
    });
  }
}

extension FlashcardEntityQueryObject
    on QueryBuilder<FlashcardEntity, FlashcardEntity, QFilterCondition> {}

extension FlashcardEntityQueryLinks
    on QueryBuilder<FlashcardEntity, FlashcardEntity, QFilterCondition> {}

extension FlashcardEntityQuerySortBy
    on QueryBuilder<FlashcardEntity, FlashcardEntity, QSortBy> {
  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy> sortByBack() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'back', Sort.asc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      sortByBackDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'back', Sort.desc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      sortByDifficulty() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'difficulty', Sort.asc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      sortByDifficultyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'difficulty', Sort.desc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      sortByFlashcardId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'flashcardId', Sort.asc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      sortByFlashcardIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'flashcardId', Sort.desc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy> sortByFront() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'front', Sort.asc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      sortByFrontDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'front', Sort.desc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy> sortByHint() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hint', Sort.asc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      sortByHintDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hint', Sort.desc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      sortBySrsEaseFactor() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'srsEaseFactor', Sort.asc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      sortBySrsEaseFactorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'srsEaseFactor', Sort.desc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      sortBySrsInterval() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'srsInterval', Sort.asc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      sortBySrsIntervalDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'srsInterval', Sort.desc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      sortBySrsLastReviewDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'srsLastReviewDate', Sort.asc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      sortBySrsLastReviewDateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'srsLastReviewDate', Sort.desc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      sortBySrsNextReviewDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'srsNextReviewDate', Sort.asc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      sortBySrsNextReviewDateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'srsNextReviewDate', Sort.desc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      sortBySrsRepetitions() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'srsRepetitions', Sort.asc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      sortBySrsRepetitionsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'srsRepetitions', Sort.desc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      sortByStudySetId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'studySetId', Sort.asc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      sortByStudySetIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'studySetId', Sort.desc);
    });
  }
}

extension FlashcardEntityQuerySortThenBy
    on QueryBuilder<FlashcardEntity, FlashcardEntity, QSortThenBy> {
  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy> thenByBack() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'back', Sort.asc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      thenByBackDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'back', Sort.desc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      thenByDifficulty() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'difficulty', Sort.asc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      thenByDifficultyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'difficulty', Sort.desc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      thenByFlashcardId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'flashcardId', Sort.asc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      thenByFlashcardIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'flashcardId', Sort.desc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy> thenByFront() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'front', Sort.asc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      thenByFrontDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'front', Sort.desc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy> thenByHint() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hint', Sort.asc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      thenByHintDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hint', Sort.desc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      thenBySrsEaseFactor() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'srsEaseFactor', Sort.asc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      thenBySrsEaseFactorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'srsEaseFactor', Sort.desc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      thenBySrsInterval() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'srsInterval', Sort.asc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      thenBySrsIntervalDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'srsInterval', Sort.desc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      thenBySrsLastReviewDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'srsLastReviewDate', Sort.asc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      thenBySrsLastReviewDateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'srsLastReviewDate', Sort.desc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      thenBySrsNextReviewDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'srsNextReviewDate', Sort.asc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      thenBySrsNextReviewDateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'srsNextReviewDate', Sort.desc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      thenBySrsRepetitions() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'srsRepetitions', Sort.asc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      thenBySrsRepetitionsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'srsRepetitions', Sort.desc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      thenByStudySetId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'studySetId', Sort.asc);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QAfterSortBy>
      thenByStudySetIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'studySetId', Sort.desc);
    });
  }
}

extension FlashcardEntityQueryWhereDistinct
    on QueryBuilder<FlashcardEntity, FlashcardEntity, QDistinct> {
  QueryBuilder<FlashcardEntity, FlashcardEntity, QDistinct> distinctByBack(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'back', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QDistinct>
      distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QDistinct>
      distinctByDifficulty() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'difficulty');
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QDistinct>
      distinctByFlashcardId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'flashcardId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QDistinct> distinctByFront(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'front', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QDistinct> distinctByHint(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'hint', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QDistinct>
      distinctBySrsEaseFactor() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'srsEaseFactor');
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QDistinct>
      distinctBySrsInterval() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'srsInterval');
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QDistinct>
      distinctBySrsLastReviewDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'srsLastReviewDate');
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QDistinct>
      distinctBySrsNextReviewDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'srsNextReviewDate');
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QDistinct>
      distinctBySrsRepetitions() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'srsRepetitions');
    });
  }

  QueryBuilder<FlashcardEntity, FlashcardEntity, QDistinct>
      distinctByStudySetId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'studySetId', caseSensitive: caseSensitive);
    });
  }
}

extension FlashcardEntityQueryProperty
    on QueryBuilder<FlashcardEntity, FlashcardEntity, QQueryProperty> {
  QueryBuilder<FlashcardEntity, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<FlashcardEntity, String, QQueryOperations> backProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'back');
    });
  }

  QueryBuilder<FlashcardEntity, DateTime, QQueryOperations>
      createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<FlashcardEntity, int, QQueryOperations> difficultyProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'difficulty');
    });
  }

  QueryBuilder<FlashcardEntity, String, QQueryOperations>
      flashcardIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'flashcardId');
    });
  }

  QueryBuilder<FlashcardEntity, String, QQueryOperations> frontProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'front');
    });
  }

  QueryBuilder<FlashcardEntity, String?, QQueryOperations> hintProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'hint');
    });
  }

  QueryBuilder<FlashcardEntity, double?, QQueryOperations>
      srsEaseFactorProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'srsEaseFactor');
    });
  }

  QueryBuilder<FlashcardEntity, int?, QQueryOperations> srsIntervalProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'srsInterval');
    });
  }

  QueryBuilder<FlashcardEntity, DateTime?, QQueryOperations>
      srsLastReviewDateProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'srsLastReviewDate');
    });
  }

  QueryBuilder<FlashcardEntity, DateTime?, QQueryOperations>
      srsNextReviewDateProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'srsNextReviewDate');
    });
  }

  QueryBuilder<FlashcardEntity, int?, QQueryOperations>
      srsRepetitionsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'srsRepetitions');
    });
  }

  QueryBuilder<FlashcardEntity, String, QQueryOperations> studySetIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'studySetId');
    });
  }
}
