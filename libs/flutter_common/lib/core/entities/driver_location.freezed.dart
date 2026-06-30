// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'driver_location.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

DriverLocation _$DriverLocationFromJson(Map<String, dynamic> json) {
  return _DriverLocation.fromJson(json);
}

/// @nodoc
mixin _$DriverLocation {
  String? get id => throw _privateConstructorUsedError;
  double get lat => throw _privateConstructorUsedError;
  double get lng => throw _privateConstructorUsedError;
  int? get rotation => throw _privateConstructorUsedError;
  String? get vehicleType => throw _privateConstructorUsedError;
  String? get markerUrl => throw _privateConstructorUsedError;

  /// Serializes this DriverLocation to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of DriverLocation
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $DriverLocationCopyWith<DriverLocation> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DriverLocationCopyWith<$Res> {
  factory $DriverLocationCopyWith(
          DriverLocation value, $Res Function(DriverLocation) then) =
      _$DriverLocationCopyWithImpl<$Res, DriverLocation>;
  @useResult
  $Res call(
      {String? id,
      double lat,
      double lng,
      int? rotation,
      String? vehicleType,
      String? markerUrl});
}

/// @nodoc
class _$DriverLocationCopyWithImpl<$Res, $Val extends DriverLocation>
    implements $DriverLocationCopyWith<$Res> {
  _$DriverLocationCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of DriverLocation
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = freezed,
    Object? lat = null,
    Object? lng = null,
    Object? rotation = freezed,
    Object? vehicleType = freezed,
    Object? markerUrl = freezed,
  }) {
    return _then(_value.copyWith(
      id: freezed == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String?,
      lat: null == lat
          ? _value.lat
          : lat // ignore: cast_nullable_to_non_nullable
              as double,
      lng: null == lng
          ? _value.lng
          : lng // ignore: cast_nullable_to_non_nullable
              as double,
      rotation: freezed == rotation
          ? _value.rotation
          : rotation // ignore: cast_nullable_to_non_nullable
              as int?,
      vehicleType: freezed == vehicleType
          ? _value.vehicleType
          : vehicleType // ignore: cast_nullable_to_non_nullable
              as String?,
      markerUrl: freezed == markerUrl
          ? _value.markerUrl
          : markerUrl // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$DriverLocationImplCopyWith<$Res>
    implements $DriverLocationCopyWith<$Res> {
  factory _$$DriverLocationImplCopyWith(_$DriverLocationImpl value,
          $Res Function(_$DriverLocationImpl) then) =
      __$$DriverLocationImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String? id,
      double lat,
      double lng,
      int? rotation,
      String? vehicleType,
      String? markerUrl});
}

/// @nodoc
class __$$DriverLocationImplCopyWithImpl<$Res>
    extends _$DriverLocationCopyWithImpl<$Res, _$DriverLocationImpl>
    implements _$$DriverLocationImplCopyWith<$Res> {
  __$$DriverLocationImplCopyWithImpl(
      _$DriverLocationImpl _value, $Res Function(_$DriverLocationImpl) _then)
      : super(_value, _then);

  /// Create a copy of DriverLocation
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = freezed,
    Object? lat = null,
    Object? lng = null,
    Object? rotation = freezed,
    Object? vehicleType = freezed,
    Object? markerUrl = freezed,
  }) {
    return _then(_$DriverLocationImpl(
      id: freezed == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String?,
      lat: null == lat
          ? _value.lat
          : lat // ignore: cast_nullable_to_non_nullable
              as double,
      lng: null == lng
          ? _value.lng
          : lng // ignore: cast_nullable_to_non_nullable
              as double,
      rotation: freezed == rotation
          ? _value.rotation
          : rotation // ignore: cast_nullable_to_non_nullable
              as int?,
      vehicleType: freezed == vehicleType
          ? _value.vehicleType
          : vehicleType // ignore: cast_nullable_to_non_nullable
              as String?,
      markerUrl: freezed == markerUrl
          ? _value.markerUrl
          : markerUrl // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$DriverLocationImpl extends _DriverLocation {
  const _$DriverLocationImpl(
      {this.id,
      required this.lat,
      required this.lng,
      required this.rotation,
      this.vehicleType,
      this.markerUrl})
      : super._();

  factory _$DriverLocationImpl.fromJson(Map<String, dynamic> json) =>
      _$$DriverLocationImplFromJson(json);

  @override
  final String? id;
  @override
  final double lat;
  @override
  final double lng;
  @override
  final int? rotation;
  @override
  final String? vehicleType;
  @override
  final String? markerUrl;

  @override
  String toString() {
    return 'DriverLocation(id: $id, lat: $lat, lng: $lng, rotation: $rotation, vehicleType: $vehicleType, markerUrl: $markerUrl)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DriverLocationImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.lat, lat) || other.lat == lat) &&
            (identical(other.lng, lng) || other.lng == lng) &&
            (identical(other.rotation, rotation) ||
                other.rotation == rotation) &&
            (identical(other.vehicleType, vehicleType) ||
                other.vehicleType == vehicleType) &&
            (identical(other.markerUrl, markerUrl) ||
                other.markerUrl == markerUrl));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, id, lat, lng, rotation, vehicleType, markerUrl);

  /// Create a copy of DriverLocation
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$DriverLocationImplCopyWith<_$DriverLocationImpl> get copyWith =>
      __$$DriverLocationImplCopyWithImpl<_$DriverLocationImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$DriverLocationImplToJson(
      this,
    );
  }
}

abstract class _DriverLocation extends DriverLocation {
  const factory _DriverLocation(
      {final String? id,
      required final double lat,
      required final double lng,
      required final int? rotation,
      final String? vehicleType,
      final String? markerUrl}) = _$DriverLocationImpl;
  const _DriverLocation._() : super._();

  factory _DriverLocation.fromJson(Map<String, dynamic> json) =
      _$DriverLocationImpl.fromJson;

  @override
  String? get id;
  @override
  double get lat;
  @override
  double get lng;
  @override
  int? get rotation;
  @override
  String? get vehicleType;
  @override
  String? get markerUrl;

  /// Create a copy of DriverLocation
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$DriverLocationImplCopyWith<_$DriverLocationImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
