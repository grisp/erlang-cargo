-module(cargo_cmd).

-export([
    run/2,
    run_executable/3,
    run_with_flags/3
]).

-export_type([
    output/0
]).

-type output() :: list(#{
    binary() => jsx:json_term()
}).

-ifdef(TEST).
-define(MAX_LINE_LENGTH, 32).
-else.
-define(MAX_LINE_LENGTH, 16384).
-endif.

-spec run_with_flags(cargo_opts:t(), iodata(), [iodata()]) -> output().
run_with_flags(Opts, Cmd, Flags) ->
    Inserts = lists:flatmap(fun flag/1, command_options(Opts, Cmd)),

    Cmd1 = [Cmd] ++ Inserts ++ Flags,

    run(Opts, Cmd1).

command_options(Opts, Cmd0) ->
    Cmd = binary_to_list(cargo_util:ensure_binary(Cmd0)),
    Common = [
        {target, cargo_opts:target(Opts)},
        {target_dir, cargo_opts:target_dir(Opts)},
        {release, cargo_opts:release(Opts)}
    ],
    Features = [
        {features, cargo_opts:features(Opts)},
        {default_features, cargo_opts:default_features(Opts)}
    ],
    case Cmd of
        "metadata" ->
            [{filter_platform, cargo_opts:target(Opts)} | Features];
        "clean" ->
            Common;
        _ ->
            Common ++ Features
    end.

flag({release, true}) ->
    ["--release"];
flag({default_features, false}) ->
    ["--no-default-features"];
flag({features, [_ | _] = Features}) ->
    ["--features", lists:join(",", Features)];
flag({Name, Value}) when is_binary(Value) ->
    Flags = #{target => "--target", target_dir => "--target-dir",
              filter_platform => "--filter-platform"},
    [maps:get(Name, Flags), Value];
flag(_) ->
    [].

-spec run(cargo_opts:t(), [iodata()]) -> output().
run(Opts, Args) ->
    C0 = ["cargo"],
    C1 =
        case cargo_opts:toolchain(Opts) of
            undefined ->
                C0;
            Toolchain ->
                C0 ++ [io_lib:format("+~s", [Toolchain])]
        end,

    exec(C1 ++ Args, cargo_opts:path(Opts), command_env(Opts)).

%% Use the same streaming decoder, environment and platform execution path for
%% companion build tools emitting Cargo-compatible JSON messages.
-spec run_executable(cargo_opts:t(), file:filename_all(), [iodata()]) -> output().
run_executable(Opts, Executable, Args) ->
    exec([binary_to_list(cargo_util:ensure_binary(Executable)) | Args],
         cargo_opts:path(Opts), command_env(Opts)).

command_env(Opts) ->
    Env = cargo_opts:env(Opts),
    case cargo_opts:rustflags(Opts) of
        undefined ->
            Env;
        Flags ->
            [{"CARGO_ENCODED_RUSTFLAGS", binary_to_list(iolist_to_binary(
                lists:join([31], Flags)))} |
             lists:keydelete("CARGO_ENCODED_RUSTFLAGS", 1, Env)]
    end.

% Code derived from rebar3
-spec exec([iodata()], file:filename_all(), [{string(), string() | false}]) -> output().
exec([Cargo | Args], Path, Env) ->
    Options1 = [
        in,
        binary,
        {cd, Path},
        exit_status,
        {line, ?MAX_LINE_LENGTH},
        use_stdio,
        hide,
        eof,
        {env, Env}
    ],

    {Command, Options2} = case os:type() of
        {win32, nt} ->
            % Keep the established cmd.exe compatibility path unchanged.
            Cmd = lists:flatten(lists:join(" ", [
                binary_to_list(cargo_util:ensure_binary(A)) || A <- [Cargo | Args]
            ])),
            Command1 = lists:flatten(patch_on_windows(Cmd)),
            {{spawn, Command1}, Options1};
        _ ->
            Found = case proplists:get_value("PATH", Env) of
                SearchPath when is_list(SearchPath) ->
                    os:find_executable(Cargo, SearchPath);
                _ ->
                    os:find_executable(Cargo)
            end,
            Executable = case Found of
                false ->
                    error({cargo_not_found, Cargo});
                _ ->
                    Found
            end,
            {{spawn_executable, Executable}, [{args, [
                binary_to_list(cargo_util:ensure_binary(A)) || A <- Args
            ]} | Options1]}
    end,
    Port = open_port(Command, Options2),

    try
        case loop(Port, []) of
            {ok, Output} ->
                Output;
            {error, {_Rc, _Output} = Err} ->
                error({cargo_error, Err})
        end
    after
        port_close(Port)
    end.

-spec loop(port(), [T | {incomplete, _}]) -> {ok, [T]} | {error, _}.
loop(Port, Acc) ->
    receive
        {Port, {data, {_, Line}}} ->
            loop(Port, handle_output(Line, Acc));
        {Port, eof} ->
            Data = finalize(Acc),
            receive
                {Port, {exit_status, 0}} ->
                    {ok, Data};
                {Port, {exit_status, Rc}} ->
                    {error, {Rc, Data}}
            end
    end.

-spec patch_on_windows(string()) -> string().
patch_on_windows(Cmd) ->
    case os:type() of
        {win32, nt} ->
            "cmd /q /c " ++ Cmd;
        _ ->
            Cmd
    end.

% Ignore dialyzer warnings for finalize and handle_output as the spec
% for jsx:decode/2 is broken (does not include incomplete and with_tail)
-dialyzer([
    {nowarn_function, finalize/1},
    {nowarn_function, handle_output/2}
]).

finalize([{incomplete, _Decode} | _Acc]) ->
    error(incomplete_json);
finalize(Acc) ->
    lists:reverse(Acc).

handle_output("", Acc) ->
    Acc;
handle_output(<<"">>, Acc) ->
    Acc;
handle_output(Line, Acc0) ->
    {DecodeRes, Acc} =
        case Acc0 of
            [{incomplete, Decode} | Acc1] ->
                {Decode(Line), Acc1};
            Acc2 ->
                {jsx:decode(Line, [return_maps, stream, return_tail]), Acc2}
        end,

    case DecodeRes of
        {with_tail, Res, Tail} ->
            handle_output(Tail, [Res | Acc]);
        Else ->
            [Else | Acc]
    end.
