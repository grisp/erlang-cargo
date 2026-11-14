-module(cargo_opts).

-export_type([
    params/0,
    t/0
]).

-export([
    new/1,
    toolchain/1,
    path/1,
    target/1,
    release/1,
    release/2,
    target_dir/1,
    target_dir/2,
    path/2,
    features/1,
    default_features/1,
    library_types/1,
    env/1,
    rustflags/1
]).

-record(opts, {
    path :: file:name_all(),
    release :: boolean(),
    toolchain :: binary() | undefined,
    target :: binary() | undefined,
    target_dir :: binary() | undefined,
    features :: [binary()],
    default_features :: boolean(),
    library_types :: [binary()],
    env :: [{string(), string() | false}],
    rustflags :: [binary()] | undefined
}).

-type params() :: #{
    path := file:name_all(),
    release => boolean(),
    toolchain => binary() | undefined,
    target => binary() | undefined,
    target_dir => binary() | undefined,
    features => [binary()],
    default_features => boolean(),
    library_types => [binary()],
    env => [{string(), string() | false}],
    rustflags => [binary()] | undefined
}.

-opaque t() :: #opts{}.

%% @private
-spec new(params()) -> t().
new(Opts) ->
    Path = maps:get(path, Opts),
    Release = maps:get(release, Opts, false),
    Toolchain = maps:get(toolchain, Opts, undefined),
    Target = maps:get(target, Opts, undefined),
    TargetDir = maps:get(target_dir, Opts, undefined),

    #opts{
        path = Path,
        release = Release,
        toolchain = Toolchain,
        target = Target,
        target_dir = TargetDir,
        features = maps:get(features, Opts, []),
        default_features = maps:get(default_features, Opts, true),
        library_types = maps:get(library_types, Opts, [
            <<"lib">>, <<"rlib">>, <<"cdylib">>, <<"staticlib">>, <<"dylib">>
        ]),
        env = maps:get(env, Opts, []),
        rustflags = maps:get(rustflags, Opts, undefined)
    }.

-spec toolchain(t()) -> binary() | undefined.
toolchain(#opts{toolchain = Toolchain}) ->
    Toolchain.

-spec release(t()) -> boolean().
release(#opts{release = Release}) ->
    Release.

-spec release(t(), boolean()) -> t().
release(O, Release) ->
    O#opts{release = Release}.

-spec path(t()) -> file:filename_all().
path(#opts{path = Path}) ->
    Path.

-spec target(t()) -> binary() | undefined.
target(#opts{target = Target}) ->
    Target.

-spec target_dir(t()) -> binary() | undefined.
target_dir(#opts{target_dir = TargetDir}) ->
    TargetDir.

-spec target_dir(t(), binary() | undefined) -> t().
target_dir(O, TargetDir) ->
    O#opts{target_dir = TargetDir}.

-spec path(t(), file:name_all()) -> t().
path(O, Path) ->
    O#opts{path = Path}.

-spec features(t()) -> [binary()].
features(#opts{features = Value}) ->
    Value.

-spec default_features(t()) -> boolean().
default_features(#opts{default_features = Value}) ->
    Value.

-spec library_types(t()) -> [binary()].
library_types(#opts{library_types = Value}) ->
    Value.

-spec env(t()) -> [{string(), string() | false}].
env(#opts{env = Value}) ->
    Value.

-spec rustflags(t()) -> [binary()] | undefined.
rustflags(#opts{rustflags = Value}) ->
    Value.
