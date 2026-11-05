// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'engine.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BackgroundSettings {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BackgroundSettings);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BackgroundSettings()';
}


}

/// @nodoc
class $BackgroundSettingsCopyWith<$Res>  {
$BackgroundSettingsCopyWith(BackgroundSettings _, $Res Function(BackgroundSettings) __);
}


/// Adds pattern-matching-related methods to [BackgroundSettings].
extension BackgroundSettingsPatterns on BackgroundSettings {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BackgroundSettings_Transparent value)?  transparent,TResult Function( BackgroundSettings_BaseImage value)?  baseImage,TResult Function( BackgroundSettings_Translucent value)?  translucent,TResult Function( BackgroundSettings_Lucent value)?  lucent,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BackgroundSettings_Transparent() when transparent != null:
return transparent(_that);case BackgroundSettings_BaseImage() when baseImage != null:
return baseImage(_that);case BackgroundSettings_Translucent() when translucent != null:
return translucent(_that);case BackgroundSettings_Lucent() when lucent != null:
return lucent(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BackgroundSettings_Transparent value)  transparent,required TResult Function( BackgroundSettings_BaseImage value)  baseImage,required TResult Function( BackgroundSettings_Translucent value)  translucent,required TResult Function( BackgroundSettings_Lucent value)  lucent,}){
final _that = this;
switch (_that) {
case BackgroundSettings_Transparent():
return transparent(_that);case BackgroundSettings_BaseImage():
return baseImage(_that);case BackgroundSettings_Translucent():
return translucent(_that);case BackgroundSettings_Lucent():
return lucent(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BackgroundSettings_Transparent value)?  transparent,TResult? Function( BackgroundSettings_BaseImage value)?  baseImage,TResult? Function( BackgroundSettings_Translucent value)?  translucent,TResult? Function( BackgroundSettings_Lucent value)?  lucent,}){
final _that = this;
switch (_that) {
case BackgroundSettings_Transparent() when transparent != null:
return transparent(_that);case BackgroundSettings_BaseImage() when baseImage != null:
return baseImage(_that);case BackgroundSettings_Translucent() when translucent != null:
return translucent(_that);case BackgroundSettings_Lucent() when lucent != null:
return lucent(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  transparent,TResult Function( String path)?  baseImage,TResult Function( TranslucentSettings params)?  translucent,TResult Function( LucentSettings params)?  lucent,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BackgroundSettings_Transparent() when transparent != null:
return transparent();case BackgroundSettings_BaseImage() when baseImage != null:
return baseImage(_that.path);case BackgroundSettings_Translucent() when translucent != null:
return translucent(_that.params);case BackgroundSettings_Lucent() when lucent != null:
return lucent(_that.params);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  transparent,required TResult Function( String path)  baseImage,required TResult Function( TranslucentSettings params)  translucent,required TResult Function( LucentSettings params)  lucent,}) {final _that = this;
switch (_that) {
case BackgroundSettings_Transparent():
return transparent();case BackgroundSettings_BaseImage():
return baseImage(_that.path);case BackgroundSettings_Translucent():
return translucent(_that.params);case BackgroundSettings_Lucent():
return lucent(_that.params);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  transparent,TResult? Function( String path)?  baseImage,TResult? Function( TranslucentSettings params)?  translucent,TResult? Function( LucentSettings params)?  lucent,}) {final _that = this;
switch (_that) {
case BackgroundSettings_Transparent() when transparent != null:
return transparent();case BackgroundSettings_BaseImage() when baseImage != null:
return baseImage(_that.path);case BackgroundSettings_Translucent() when translucent != null:
return translucent(_that.params);case BackgroundSettings_Lucent() when lucent != null:
return lucent(_that.params);case _:
  return null;

}
}

}

/// @nodoc


class BackgroundSettings_Transparent extends BackgroundSettings {
  const BackgroundSettings_Transparent(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BackgroundSettings_Transparent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BackgroundSettings.transparent()';
}


}




/// @nodoc


class BackgroundSettings_BaseImage extends BackgroundSettings {
  const BackgroundSettings_BaseImage({required this.path}): super._();
  

 final  String path;

/// Create a copy of BackgroundSettings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BackgroundSettings_BaseImageCopyWith<BackgroundSettings_BaseImage> get copyWith => _$BackgroundSettings_BaseImageCopyWithImpl<BackgroundSettings_BaseImage>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BackgroundSettings_BaseImage&&(identical(other.path, path) || other.path == path));
}


@override
int get hashCode => Object.hash(runtimeType,path);

@override
String toString() {
  return 'BackgroundSettings.baseImage(path: $path)';
}


}

/// @nodoc
abstract mixin class $BackgroundSettings_BaseImageCopyWith<$Res> implements $BackgroundSettingsCopyWith<$Res> {
  factory $BackgroundSettings_BaseImageCopyWith(BackgroundSettings_BaseImage value, $Res Function(BackgroundSettings_BaseImage) _then) = _$BackgroundSettings_BaseImageCopyWithImpl;
@useResult
$Res call({
 String path
});




}
/// @nodoc
class _$BackgroundSettings_BaseImageCopyWithImpl<$Res>
    implements $BackgroundSettings_BaseImageCopyWith<$Res> {
  _$BackgroundSettings_BaseImageCopyWithImpl(this._self, this._then);

  final BackgroundSettings_BaseImage _self;
  final $Res Function(BackgroundSettings_BaseImage) _then;

/// Create a copy of BackgroundSettings
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? path = null,}) {
  return _then(BackgroundSettings_BaseImage(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BackgroundSettings_Translucent extends BackgroundSettings {
  const BackgroundSettings_Translucent({required this.params}): super._();
  

 final  TranslucentSettings params;

/// Create a copy of BackgroundSettings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BackgroundSettings_TranslucentCopyWith<BackgroundSettings_Translucent> get copyWith => _$BackgroundSettings_TranslucentCopyWithImpl<BackgroundSettings_Translucent>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BackgroundSettings_Translucent&&(identical(other.params, params) || other.params == params));
}


@override
int get hashCode => Object.hash(runtimeType,params);

@override
String toString() {
  return 'BackgroundSettings.translucent(params: $params)';
}


}

/// @nodoc
abstract mixin class $BackgroundSettings_TranslucentCopyWith<$Res> implements $BackgroundSettingsCopyWith<$Res> {
  factory $BackgroundSettings_TranslucentCopyWith(BackgroundSettings_Translucent value, $Res Function(BackgroundSettings_Translucent) _then) = _$BackgroundSettings_TranslucentCopyWithImpl;
@useResult
$Res call({
 TranslucentSettings params
});




}
/// @nodoc
class _$BackgroundSettings_TranslucentCopyWithImpl<$Res>
    implements $BackgroundSettings_TranslucentCopyWith<$Res> {
  _$BackgroundSettings_TranslucentCopyWithImpl(this._self, this._then);

  final BackgroundSettings_Translucent _self;
  final $Res Function(BackgroundSettings_Translucent) _then;

/// Create a copy of BackgroundSettings
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? params = null,}) {
  return _then(BackgroundSettings_Translucent(
params: null == params ? _self.params : params // ignore: cast_nullable_to_non_nullable
as TranslucentSettings,
  ));
}


}

/// @nodoc


class BackgroundSettings_Lucent extends BackgroundSettings {
  const BackgroundSettings_Lucent({required this.params}): super._();
  

 final  LucentSettings params;

/// Create a copy of BackgroundSettings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BackgroundSettings_LucentCopyWith<BackgroundSettings_Lucent> get copyWith => _$BackgroundSettings_LucentCopyWithImpl<BackgroundSettings_Lucent>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BackgroundSettings_Lucent&&(identical(other.params, params) || other.params == params));
}


@override
int get hashCode => Object.hash(runtimeType,params);

@override
String toString() {
  return 'BackgroundSettings.lucent(params: $params)';
}


}

/// @nodoc
abstract mixin class $BackgroundSettings_LucentCopyWith<$Res> implements $BackgroundSettingsCopyWith<$Res> {
  factory $BackgroundSettings_LucentCopyWith(BackgroundSettings_Lucent value, $Res Function(BackgroundSettings_Lucent) _then) = _$BackgroundSettings_LucentCopyWithImpl;
@useResult
$Res call({
 LucentSettings params
});




}
/// @nodoc
class _$BackgroundSettings_LucentCopyWithImpl<$Res>
    implements $BackgroundSettings_LucentCopyWith<$Res> {
  _$BackgroundSettings_LucentCopyWithImpl(this._self, this._then);

  final BackgroundSettings_Lucent _self;
  final $Res Function(BackgroundSettings_Lucent) _then;

/// Create a copy of BackgroundSettings
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? params = null,}) {
  return _then(BackgroundSettings_Lucent(
params: null == params ? _self.params : params // ignore: cast_nullable_to_non_nullable
as LucentSettings,
  ));
}


}

// dart format on
