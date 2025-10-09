// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'study_set_entity.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetStudySetEntityCollection on Isar {
  IsarCollection<StudySetEntity> get studySetEntitys => this.collection();
}

const StudySetEntitySchema = CollectionSchema(
  name: r'StudySetEntity',
  id: -1861588269261112808,
  properties: {
    r'borderColor': PropertySchema(
      id: 0,
      name: r'borderColor',
      type: IsarType.long,
    ),
    r'description': PropertySchema(
      id: 1,
      name: r'description',
      type: IsarType.string,
    ),
    r'exercises': PropertySchema(
      id: 2,
      name: r'exercises',
      type: IsarType.long,
    ),
    r'explanations': PropertySchema(
      id: 3,
      name: r'explanations',
      type: IsarType.long,
    ),
    r'flashcards': PropertySchema(
      id: 4,
      name: r'flashcards',
      type: IsarType.long,
    ),
    r'studySetId': PropertySchema(
      id: 5,
      name: r'studySetId',
      type: IsarType.string,
    ),
    r'tagIndex': PropertySchema(
      id: 6,
      name: r'tagIndex',
      type: IsarType.long,
    ),
    r'title': PropertySchema(
      id: 7,
      name: r'title',
      type: IsarType.string,
    ),
    r'views': PropertySchema(
      id: 8,
      name: r'views',
      type: IsarType.string,
    )
  },
  estimateSize: _studySetEntityEstimateSize,
  serialize: _studySetEntitySerialize,
  deserialize: _studySetEntityDeserialize,
  deserializeProp: _studySetEntityDeserializeProp,
  idName: r'id',
  indexes: {
    r'studySetId': IndexSchema(
      id: 3367433084871930268,
      name: r'studySetId',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'studySetId',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _studySetEntityGetId,
  getLinks: _studySetEntityGetLinks,
  attach: _studySetEntityAttach,
  version: '3.1.0+1',
);

int _studySetEntityEstimateSize(
  StudySetEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.description.length * 3;
  bytesCount += 3 + object.studySetId.length * 3;
  bytesCount += 3 + object.title.length * 3;
  bytesCount += 3 + object.views.length * 3;
  return bytesCount;
}

void _studySetEntitySerialize(
  StudySetEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeLong(offsets[0], object.borderColor);
  writer.writeString(offsets[1], object.description);
  writer.writeLong(offsets[2], object.exercises);
  writer.writeLong(offsets[3], object.explanations);
  writer.writeLong(offsets[4], object.flashcards);
  writer.writeString(offsets[5], object.studySetId);
  writer.writeLong(offsets[6], object.tagIndex);
  writer.writeString(offsets[7], object.title);
  writer.writeString(offsets[8], object.views);
}

StudySetEntity _studySetEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = StudySetEntity();
  object.borderColor = reader.readLong(offsets[0]);
  object.description = reader.readString(offsets[1]);
  object.exercises = reader.readLong(offsets[2]);
  object.explanations = reader.readLong(offsets[3]);
  object.flashcards = reader.readLong(offsets[4]);
  object.id = id;
  object.studySetId = reader.readString(offsets[5]);
  object.tagIndex = reader.readLong(offsets[6]);
  object.title = reader.readString(offsets[7]);
  object.views = reader.readString(offsets[8]);
  return object;
}

P _studySetEntityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readLong(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readLong(offset)) as P;
    case 3:
      return (reader.readLong(offset)) as P;
    case 4:
      return (reader.readLong(offset)) as P;
    case 5:
      return (reader.readString(offset)) as P;
    case 6:
      return (reader.readLong(offset)) as P;
    case 7:
      return (reader.readString(offset)) as P;
    case 8:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _studySetEntityGetId(StudySetEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _studySetEntityGetLinks(StudySetEntity object) {
  return [];
}

void _studySetEntityAttach(
    IsarCollection<dynamic> col, Id id, StudySetEntity object) {
  object.id = id;
}

extension StudySetEntityByIndex on IsarCollection<StudySetEntity> {
  Future<StudySetEntity?> getByStudySetId(String studySetId) {
    return getByIndex(r'studySetId', [studySetId]);
  }

  StudySetEntity? getByStudySetIdSync(String studySetId) {
    return getByIndexSync(r'studySetId', [studySetId]);
  }

  Future<bool> deleteByStudySetId(String studySetId) {
    return deleteByIndex(r'studySetId', [studySetId]);
  }

  bool deleteByStudySetIdSync(String studySetId) {
    return deleteByIndexSync(r'studySetId', [studySetId]);
  }

  Future<List<StudySetEntity?>> getAllByStudySetId(
      List<String> studySetIdValues) {
    final values = studySetIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'studySetId', values);
  }

  List<StudySetEntity?> getAllByStudySetIdSync(List<String> studySetIdValues) {
    final values = studySetIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'studySetId', values);
  }

  Future<int> deleteAllByStudySetId(List<String> studySetIdValues) {
    final values = studySetIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'studySetId', values);
  }

  int deleteAllByStudySetIdSync(List<String> studySetIdValues) {
    final values = studySetIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'studySetId', values);
  }

  Future<Id> putByStudySetId(StudySetEntity object) {
    return putByIndex(r'studySetId', object);
  }

  Id putByStudySetIdSync(StudySetEntity object, {bool saveLinks = true}) {
    return putByIndexSync(r'studySetId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByStudySetId(List<StudySetEntity> objects) {
    return putAllByIndex(r'studySetId', objects);
  }

  List<Id> putAllByStudySetIdSync(List<StudySetEntity> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'studySetId', objects, saveLinks: saveLinks);
  }
}

extension StudySetEntityQueryWhereSort
    on QueryBuilder<StudySetEntity, StudySetEntity, QWhere> {
  QueryBuilder<StudySetEntity, StudySetEntity, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension StudySetEntityQueryWhere
    on QueryBuilder<StudySetEntity, StudySetEntity, QWhereClause> {
  QueryBuilder<StudySetEntity, StudySetEntity, QAfterWhereClause> idEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterWhereClause> idNotEqualTo(
      Id id) {
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

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterWhereClause> idGreaterThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterWhereClause> idLessThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterWhereClause> idBetween(
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

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterWhereClause>
      studySetIdEqualTo(String studySetId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'studySetId',
        value: [studySetId],
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterWhereClause>
      studySetIdNotEqualTo(String studySetId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'studySetId',
              lower: [],
              upper: [studySetId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'studySetId',
              lower: [studySetId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'studySetId',
              lower: [studySetId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'studySetId',
              lower: [],
              upper: [studySetId],
              includeUpper: false,
            ));
      }
    });
  }
}

extension StudySetEntityQueryFilter
    on QueryBuilder<StudySetEntity, StudySetEntity, QFilterCondition> {
  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      borderColorEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'borderColor',
        value: value,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      borderColorGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'borderColor',
        value: value,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      borderColorLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'borderColor',
        value: value,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      borderColorBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'borderColor',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      descriptionEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'description',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      descriptionGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'description',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      descriptionLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'description',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      descriptionBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'description',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      descriptionStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'description',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      descriptionEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'description',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      descriptionContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'description',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      descriptionMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'description',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      descriptionIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'description',
        value: '',
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      descriptionIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'description',
        value: '',
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      exercisesEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'exercises',
        value: value,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      exercisesGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'exercises',
        value: value,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      exercisesLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'exercises',
        value: value,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      exercisesBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'exercises',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      explanationsEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'explanations',
        value: value,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      explanationsGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'explanations',
        value: value,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      explanationsLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'explanations',
        value: value,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      explanationsBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'explanations',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      flashcardsEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'flashcards',
        value: value,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      flashcardsGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'flashcards',
        value: value,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      flashcardsLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'flashcards',
        value: value,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      flashcardsBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'flashcards',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
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

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
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

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition> idBetween(
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

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
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

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
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

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
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

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
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

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
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

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
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

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      studySetIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'studySetId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      studySetIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'studySetId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      studySetIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'studySetId',
        value: '',
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      studySetIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'studySetId',
        value: '',
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      tagIndexEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'tagIndex',
        value: value,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      tagIndexGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'tagIndex',
        value: value,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      tagIndexLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'tagIndex',
        value: value,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      tagIndexBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'tagIndex',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      titleEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      titleGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      titleLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      titleBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'title',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      titleStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      titleEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      titleContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      titleMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'title',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      titleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'title',
        value: '',
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      titleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'title',
        value: '',
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      viewsEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'views',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      viewsGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'views',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      viewsLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'views',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      viewsBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'views',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      viewsStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'views',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      viewsEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'views',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      viewsContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'views',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      viewsMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'views',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      viewsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'views',
        value: '',
      ));
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterFilterCondition>
      viewsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'views',
        value: '',
      ));
    });
  }
}

extension StudySetEntityQueryObject
    on QueryBuilder<StudySetEntity, StudySetEntity, QFilterCondition> {}

extension StudySetEntityQueryLinks
    on QueryBuilder<StudySetEntity, StudySetEntity, QFilterCondition> {}

extension StudySetEntityQuerySortBy
    on QueryBuilder<StudySetEntity, StudySetEntity, QSortBy> {
  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy>
      sortByBorderColor() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'borderColor', Sort.asc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy>
      sortByBorderColorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'borderColor', Sort.desc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy>
      sortByDescription() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'description', Sort.asc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy>
      sortByDescriptionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'description', Sort.desc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy> sortByExercises() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'exercises', Sort.asc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy>
      sortByExercisesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'exercises', Sort.desc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy>
      sortByExplanations() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'explanations', Sort.asc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy>
      sortByExplanationsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'explanations', Sort.desc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy>
      sortByFlashcards() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'flashcards', Sort.asc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy>
      sortByFlashcardsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'flashcards', Sort.desc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy>
      sortByStudySetId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'studySetId', Sort.asc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy>
      sortByStudySetIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'studySetId', Sort.desc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy> sortByTagIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tagIndex', Sort.asc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy>
      sortByTagIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tagIndex', Sort.desc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy> sortByTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.asc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy> sortByTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.desc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy> sortByViews() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'views', Sort.asc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy> sortByViewsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'views', Sort.desc);
    });
  }
}

extension StudySetEntityQuerySortThenBy
    on QueryBuilder<StudySetEntity, StudySetEntity, QSortThenBy> {
  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy>
      thenByBorderColor() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'borderColor', Sort.asc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy>
      thenByBorderColorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'borderColor', Sort.desc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy>
      thenByDescription() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'description', Sort.asc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy>
      thenByDescriptionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'description', Sort.desc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy> thenByExercises() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'exercises', Sort.asc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy>
      thenByExercisesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'exercises', Sort.desc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy>
      thenByExplanations() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'explanations', Sort.asc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy>
      thenByExplanationsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'explanations', Sort.desc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy>
      thenByFlashcards() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'flashcards', Sort.asc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy>
      thenByFlashcardsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'flashcards', Sort.desc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy>
      thenByStudySetId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'studySetId', Sort.asc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy>
      thenByStudySetIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'studySetId', Sort.desc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy> thenByTagIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tagIndex', Sort.asc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy>
      thenByTagIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tagIndex', Sort.desc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy> thenByTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.asc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy> thenByTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.desc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy> thenByViews() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'views', Sort.asc);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QAfterSortBy> thenByViewsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'views', Sort.desc);
    });
  }
}

extension StudySetEntityQueryWhereDistinct
    on QueryBuilder<StudySetEntity, StudySetEntity, QDistinct> {
  QueryBuilder<StudySetEntity, StudySetEntity, QDistinct>
      distinctByBorderColor() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'borderColor');
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QDistinct> distinctByDescription(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'description', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QDistinct>
      distinctByExercises() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'exercises');
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QDistinct>
      distinctByExplanations() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'explanations');
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QDistinct>
      distinctByFlashcards() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'flashcards');
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QDistinct> distinctByStudySetId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'studySetId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QDistinct> distinctByTagIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'tagIndex');
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QDistinct> distinctByTitle(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'title', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StudySetEntity, StudySetEntity, QDistinct> distinctByViews(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'views', caseSensitive: caseSensitive);
    });
  }
}

extension StudySetEntityQueryProperty
    on QueryBuilder<StudySetEntity, StudySetEntity, QQueryProperty> {
  QueryBuilder<StudySetEntity, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<StudySetEntity, int, QQueryOperations> borderColorProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'borderColor');
    });
  }

  QueryBuilder<StudySetEntity, String, QQueryOperations> descriptionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'description');
    });
  }

  QueryBuilder<StudySetEntity, int, QQueryOperations> exercisesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'exercises');
    });
  }

  QueryBuilder<StudySetEntity, int, QQueryOperations> explanationsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'explanations');
    });
  }

  QueryBuilder<StudySetEntity, int, QQueryOperations> flashcardsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'flashcards');
    });
  }

  QueryBuilder<StudySetEntity, String, QQueryOperations> studySetIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'studySetId');
    });
  }

  QueryBuilder<StudySetEntity, int, QQueryOperations> tagIndexProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'tagIndex');
    });
  }

  QueryBuilder<StudySetEntity, String, QQueryOperations> titleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'title');
    });
  }

  QueryBuilder<StudySetEntity, String, QQueryOperations> viewsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'views');
    });
  }
}
