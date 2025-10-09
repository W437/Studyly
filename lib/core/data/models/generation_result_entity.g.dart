// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'generation_result_entity.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetGenerationResultEntityCollection on Isar {
  IsarCollection<GenerationResultEntity> get generationResultEntitys =>
      this.collection();
}

const GenerationResultEntitySchema = CollectionSchema(
  name: r'GenerationResultEntity',
  id: 7381117909648140688,
  properties: {
    r'completedAt': PropertySchema(
      id: 0,
      name: r'completedAt',
      type: IsarType.dateTime,
    ),
    r'createdAt': PropertySchema(
      id: 1,
      name: r'createdAt',
      type: IsarType.dateTime,
    ),
    r'errorMessage': PropertySchema(
      id: 2,
      name: r'errorMessage',
      type: IsarType.string,
    ),
    r'imageUrl': PropertySchema(
      id: 3,
      name: r'imageUrl',
      type: IsarType.string,
    ),
    r'inputText': PropertySchema(
      id: 4,
      name: r'inputText',
      type: IsarType.string,
    ),
    r'resultId': PropertySchema(
      id: 5,
      name: r'resultId',
      type: IsarType.string,
    ),
    r'resultJson': PropertySchema(
      id: 6,
      name: r'resultJson',
      type: IsarType.string,
    ),
    r'scannedItemId': PropertySchema(
      id: 7,
      name: r'scannedItemId',
      type: IsarType.string,
    ),
    r'statusIndex': PropertySchema(
      id: 8,
      name: r'statusIndex',
      type: IsarType.long,
    ),
    r'typeIndex': PropertySchema(
      id: 9,
      name: r'typeIndex',
      type: IsarType.long,
    ),
    r'userId': PropertySchema(
      id: 10,
      name: r'userId',
      type: IsarType.string,
    )
  },
  estimateSize: _generationResultEntityEstimateSize,
  serialize: _generationResultEntitySerialize,
  deserialize: _generationResultEntityDeserialize,
  deserializeProp: _generationResultEntityDeserializeProp,
  idName: r'id',
  indexes: {
    r'resultId': IndexSchema(
      id: 1875462584315805120,
      name: r'resultId',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'resultId',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _generationResultEntityGetId,
  getLinks: _generationResultEntityGetLinks,
  attach: _generationResultEntityAttach,
  version: '3.1.0+1',
);

int _generationResultEntityEstimateSize(
  GenerationResultEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.errorMessage;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.imageUrl;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.inputText;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.resultId.length * 3;
  {
    final value = object.resultJson;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.scannedItemId.length * 3;
  bytesCount += 3 + object.userId.length * 3;
  return bytesCount;
}

void _generationResultEntitySerialize(
  GenerationResultEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeDateTime(offsets[0], object.completedAt);
  writer.writeDateTime(offsets[1], object.createdAt);
  writer.writeString(offsets[2], object.errorMessage);
  writer.writeString(offsets[3], object.imageUrl);
  writer.writeString(offsets[4], object.inputText);
  writer.writeString(offsets[5], object.resultId);
  writer.writeString(offsets[6], object.resultJson);
  writer.writeString(offsets[7], object.scannedItemId);
  writer.writeLong(offsets[8], object.statusIndex);
  writer.writeLong(offsets[9], object.typeIndex);
  writer.writeString(offsets[10], object.userId);
}

GenerationResultEntity _generationResultEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = GenerationResultEntity();
  object.completedAt = reader.readDateTimeOrNull(offsets[0]);
  object.createdAt = reader.readDateTime(offsets[1]);
  object.errorMessage = reader.readStringOrNull(offsets[2]);
  object.id = id;
  object.imageUrl = reader.readStringOrNull(offsets[3]);
  object.inputText = reader.readStringOrNull(offsets[4]);
  object.resultId = reader.readString(offsets[5]);
  object.resultJson = reader.readStringOrNull(offsets[6]);
  object.scannedItemId = reader.readString(offsets[7]);
  object.statusIndex = reader.readLong(offsets[8]);
  object.typeIndex = reader.readLong(offsets[9]);
  object.userId = reader.readString(offsets[10]);
  return object;
}

P _generationResultEntityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 1:
      return (reader.readDateTime(offset)) as P;
    case 2:
      return (reader.readStringOrNull(offset)) as P;
    case 3:
      return (reader.readStringOrNull(offset)) as P;
    case 4:
      return (reader.readStringOrNull(offset)) as P;
    case 5:
      return (reader.readString(offset)) as P;
    case 6:
      return (reader.readStringOrNull(offset)) as P;
    case 7:
      return (reader.readString(offset)) as P;
    case 8:
      return (reader.readLong(offset)) as P;
    case 9:
      return (reader.readLong(offset)) as P;
    case 10:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _generationResultEntityGetId(GenerationResultEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _generationResultEntityGetLinks(
    GenerationResultEntity object) {
  return [];
}

void _generationResultEntityAttach(
    IsarCollection<dynamic> col, Id id, GenerationResultEntity object) {
  object.id = id;
}

extension GenerationResultEntityByIndex
    on IsarCollection<GenerationResultEntity> {
  Future<GenerationResultEntity?> getByResultId(String resultId) {
    return getByIndex(r'resultId', [resultId]);
  }

  GenerationResultEntity? getByResultIdSync(String resultId) {
    return getByIndexSync(r'resultId', [resultId]);
  }

  Future<bool> deleteByResultId(String resultId) {
    return deleteByIndex(r'resultId', [resultId]);
  }

  bool deleteByResultIdSync(String resultId) {
    return deleteByIndexSync(r'resultId', [resultId]);
  }

  Future<List<GenerationResultEntity?>> getAllByResultId(
      List<String> resultIdValues) {
    final values = resultIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'resultId', values);
  }

  List<GenerationResultEntity?> getAllByResultIdSync(
      List<String> resultIdValues) {
    final values = resultIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'resultId', values);
  }

  Future<int> deleteAllByResultId(List<String> resultIdValues) {
    final values = resultIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'resultId', values);
  }

  int deleteAllByResultIdSync(List<String> resultIdValues) {
    final values = resultIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'resultId', values);
  }

  Future<Id> putByResultId(GenerationResultEntity object) {
    return putByIndex(r'resultId', object);
  }

  Id putByResultIdSync(GenerationResultEntity object, {bool saveLinks = true}) {
    return putByIndexSync(r'resultId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByResultId(List<GenerationResultEntity> objects) {
    return putAllByIndex(r'resultId', objects);
  }

  List<Id> putAllByResultIdSync(List<GenerationResultEntity> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'resultId', objects, saveLinks: saveLinks);
  }
}

extension GenerationResultEntityQueryWhereSort
    on QueryBuilder<GenerationResultEntity, GenerationResultEntity, QWhere> {
  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterWhere>
      anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension GenerationResultEntityQueryWhere on QueryBuilder<
    GenerationResultEntity, GenerationResultEntity, QWhereClause> {
  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterWhereClause> idNotEqualTo(Id id) {
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

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterWhereClause> idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterWhereClause> idLessThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterWhereClause> idBetween(
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

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterWhereClause> resultIdEqualTo(String resultId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'resultId',
        value: [resultId],
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterWhereClause> resultIdNotEqualTo(String resultId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'resultId',
              lower: [],
              upper: [resultId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'resultId',
              lower: [resultId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'resultId',
              lower: [resultId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'resultId',
              lower: [],
              upper: [resultId],
              includeUpper: false,
            ));
      }
    });
  }
}

extension GenerationResultEntityQueryFilter on QueryBuilder<
    GenerationResultEntity, GenerationResultEntity, QFilterCondition> {
  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> completedAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'completedAt',
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> completedAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'completedAt',
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> completedAtEqualTo(DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'completedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> completedAtGreaterThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'completedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> completedAtLessThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'completedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> completedAtBetween(
    DateTime? lower,
    DateTime? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'completedAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> createdAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> createdAtGreaterThan(
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

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> createdAtLessThan(
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

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> createdAtBetween(
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

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> errorMessageIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'errorMessage',
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> errorMessageIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'errorMessage',
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> errorMessageEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'errorMessage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> errorMessageGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'errorMessage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> errorMessageLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'errorMessage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> errorMessageBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'errorMessage',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> errorMessageStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'errorMessage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> errorMessageEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'errorMessage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
          QAfterFilterCondition>
      errorMessageContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'errorMessage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
          QAfterFilterCondition>
      errorMessageMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'errorMessage',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> errorMessageIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'errorMessage',
        value: '',
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> errorMessageIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'errorMessage',
        value: '',
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> idGreaterThan(
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

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> idLessThan(
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

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> idBetween(
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

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> imageUrlIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'imageUrl',
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> imageUrlIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'imageUrl',
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> imageUrlEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'imageUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> imageUrlGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'imageUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> imageUrlLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'imageUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> imageUrlBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'imageUrl',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> imageUrlStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'imageUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> imageUrlEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'imageUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
          QAfterFilterCondition>
      imageUrlContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'imageUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
          QAfterFilterCondition>
      imageUrlMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'imageUrl',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> imageUrlIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'imageUrl',
        value: '',
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> imageUrlIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'imageUrl',
        value: '',
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> inputTextIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'inputText',
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> inputTextIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'inputText',
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> inputTextEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'inputText',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> inputTextGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'inputText',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> inputTextLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'inputText',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> inputTextBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'inputText',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> inputTextStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'inputText',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> inputTextEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'inputText',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
          QAfterFilterCondition>
      inputTextContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'inputText',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
          QAfterFilterCondition>
      inputTextMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'inputText',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> inputTextIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'inputText',
        value: '',
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> inputTextIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'inputText',
        value: '',
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> resultIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'resultId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> resultIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'resultId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> resultIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'resultId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> resultIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'resultId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> resultIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'resultId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> resultIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'resultId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
          QAfterFilterCondition>
      resultIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'resultId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
          QAfterFilterCondition>
      resultIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'resultId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> resultIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'resultId',
        value: '',
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> resultIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'resultId',
        value: '',
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> resultJsonIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'resultJson',
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> resultJsonIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'resultJson',
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> resultJsonEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'resultJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> resultJsonGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'resultJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> resultJsonLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'resultJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> resultJsonBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'resultJson',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> resultJsonStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'resultJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> resultJsonEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'resultJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
          QAfterFilterCondition>
      resultJsonContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'resultJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
          QAfterFilterCondition>
      resultJsonMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'resultJson',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> resultJsonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'resultJson',
        value: '',
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> resultJsonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'resultJson',
        value: '',
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> scannedItemIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'scannedItemId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> scannedItemIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'scannedItemId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> scannedItemIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'scannedItemId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> scannedItemIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'scannedItemId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> scannedItemIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'scannedItemId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> scannedItemIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'scannedItemId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
          QAfterFilterCondition>
      scannedItemIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'scannedItemId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
          QAfterFilterCondition>
      scannedItemIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'scannedItemId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> scannedItemIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'scannedItemId',
        value: '',
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> scannedItemIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'scannedItemId',
        value: '',
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> statusIndexEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'statusIndex',
        value: value,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> statusIndexGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'statusIndex',
        value: value,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> statusIndexLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'statusIndex',
        value: value,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> statusIndexBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'statusIndex',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> typeIndexEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'typeIndex',
        value: value,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> typeIndexGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'typeIndex',
        value: value,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> typeIndexLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'typeIndex',
        value: value,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> typeIndexBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'typeIndex',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> userIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'userId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> userIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'userId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> userIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'userId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> userIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'userId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> userIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'userId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> userIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'userId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
          QAfterFilterCondition>
      userIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'userId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
          QAfterFilterCondition>
      userIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'userId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> userIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'userId',
        value: '',
      ));
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity,
      QAfterFilterCondition> userIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'userId',
        value: '',
      ));
    });
  }
}

extension GenerationResultEntityQueryObject on QueryBuilder<
    GenerationResultEntity, GenerationResultEntity, QFilterCondition> {}

extension GenerationResultEntityQueryLinks on QueryBuilder<
    GenerationResultEntity, GenerationResultEntity, QFilterCondition> {}

extension GenerationResultEntityQuerySortBy
    on QueryBuilder<GenerationResultEntity, GenerationResultEntity, QSortBy> {
  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      sortByCompletedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'completedAt', Sort.asc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      sortByCompletedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'completedAt', Sort.desc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      sortByErrorMessage() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'errorMessage', Sort.asc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      sortByErrorMessageDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'errorMessage', Sort.desc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      sortByImageUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'imageUrl', Sort.asc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      sortByImageUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'imageUrl', Sort.desc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      sortByInputText() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'inputText', Sort.asc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      sortByInputTextDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'inputText', Sort.desc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      sortByResultId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'resultId', Sort.asc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      sortByResultIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'resultId', Sort.desc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      sortByResultJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'resultJson', Sort.asc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      sortByResultJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'resultJson', Sort.desc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      sortByScannedItemId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'scannedItemId', Sort.asc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      sortByScannedItemIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'scannedItemId', Sort.desc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      sortByStatusIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'statusIndex', Sort.asc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      sortByStatusIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'statusIndex', Sort.desc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      sortByTypeIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'typeIndex', Sort.asc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      sortByTypeIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'typeIndex', Sort.desc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      sortByUserId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'userId', Sort.asc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      sortByUserIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'userId', Sort.desc);
    });
  }
}

extension GenerationResultEntityQuerySortThenBy on QueryBuilder<
    GenerationResultEntity, GenerationResultEntity, QSortThenBy> {
  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      thenByCompletedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'completedAt', Sort.asc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      thenByCompletedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'completedAt', Sort.desc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      thenByErrorMessage() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'errorMessage', Sort.asc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      thenByErrorMessageDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'errorMessage', Sort.desc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      thenByImageUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'imageUrl', Sort.asc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      thenByImageUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'imageUrl', Sort.desc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      thenByInputText() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'inputText', Sort.asc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      thenByInputTextDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'inputText', Sort.desc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      thenByResultId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'resultId', Sort.asc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      thenByResultIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'resultId', Sort.desc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      thenByResultJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'resultJson', Sort.asc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      thenByResultJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'resultJson', Sort.desc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      thenByScannedItemId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'scannedItemId', Sort.asc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      thenByScannedItemIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'scannedItemId', Sort.desc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      thenByStatusIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'statusIndex', Sort.asc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      thenByStatusIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'statusIndex', Sort.desc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      thenByTypeIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'typeIndex', Sort.asc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      thenByTypeIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'typeIndex', Sort.desc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      thenByUserId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'userId', Sort.asc);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QAfterSortBy>
      thenByUserIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'userId', Sort.desc);
    });
  }
}

extension GenerationResultEntityQueryWhereDistinct
    on QueryBuilder<GenerationResultEntity, GenerationResultEntity, QDistinct> {
  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QDistinct>
      distinctByCompletedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'completedAt');
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QDistinct>
      distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QDistinct>
      distinctByErrorMessage({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'errorMessage', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QDistinct>
      distinctByImageUrl({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'imageUrl', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QDistinct>
      distinctByInputText({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'inputText', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QDistinct>
      distinctByResultId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'resultId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QDistinct>
      distinctByResultJson({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'resultJson', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QDistinct>
      distinctByScannedItemId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'scannedItemId',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QDistinct>
      distinctByStatusIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'statusIndex');
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QDistinct>
      distinctByTypeIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'typeIndex');
    });
  }

  QueryBuilder<GenerationResultEntity, GenerationResultEntity, QDistinct>
      distinctByUserId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'userId', caseSensitive: caseSensitive);
    });
  }
}

extension GenerationResultEntityQueryProperty on QueryBuilder<
    GenerationResultEntity, GenerationResultEntity, QQueryProperty> {
  QueryBuilder<GenerationResultEntity, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<GenerationResultEntity, DateTime?, QQueryOperations>
      completedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'completedAt');
    });
  }

  QueryBuilder<GenerationResultEntity, DateTime, QQueryOperations>
      createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<GenerationResultEntity, String?, QQueryOperations>
      errorMessageProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'errorMessage');
    });
  }

  QueryBuilder<GenerationResultEntity, String?, QQueryOperations>
      imageUrlProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'imageUrl');
    });
  }

  QueryBuilder<GenerationResultEntity, String?, QQueryOperations>
      inputTextProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'inputText');
    });
  }

  QueryBuilder<GenerationResultEntity, String, QQueryOperations>
      resultIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'resultId');
    });
  }

  QueryBuilder<GenerationResultEntity, String?, QQueryOperations>
      resultJsonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'resultJson');
    });
  }

  QueryBuilder<GenerationResultEntity, String, QQueryOperations>
      scannedItemIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'scannedItemId');
    });
  }

  QueryBuilder<GenerationResultEntity, int, QQueryOperations>
      statusIndexProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'statusIndex');
    });
  }

  QueryBuilder<GenerationResultEntity, int, QQueryOperations>
      typeIndexProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'typeIndex');
    });
  }

  QueryBuilder<GenerationResultEntity, String, QQueryOperations>
      userIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'userId');
    });
  }
}
