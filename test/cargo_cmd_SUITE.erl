-module(cargo_cmd_SUITE).
-compile([export_all, nowarn_export_all]).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

all() ->
    [command_arguments_and_environment, companion_executable, streamed_json,
     structured_diagnostics].

init_per_suite(Config) ->
    case os:type() of
        {win32, nt} -> {skip, "Unix process argument and escript coverage"};
        _ -> Config
    end.

end_per_suite(_Config) ->
    ok.

command_arguments_and_environment(Config) ->
    Root = filename:join(
        ?config(priv_dir, Config), "cargo cross"
    ),
    ok = filelib:ensure_dir(filename:join(Root, "dummy")),
    Tool = filename:join(Root, "cargo"),
    Capture = filename:join(Root, "arguments"),
    Script =
        <<"#!/usr/bin/env escript\n%%! +S 2:2\nmain(Args) ->\n",
            "file:write_file(os:getenv(\"CAPTURE\"), term_to_binary({Args, os:getenv(\"CROSS_ENV\"), os:getenv(\"CARGO_ENCODED_RUSTFLAGS\")})),\n",
            "io:format(standard_error, \"tool diagnostic~n\", []),\n",
            "io:format(\"{\\\"payload\\\":\\\"~s\\\"}~n\", [lists:duplicate(20000, $x)]),\n",
            "case Args of [\"fail\"] -> halt(42); _ -> ok end.\n">>,
    ok = file:write_file(Tool, Script),
    ok = file:change_mode(Tool, 8#755),
    Before = os:getenv("CROSS_ENV"),
    Opts = cargo_opts:new(#{
        path => Root,
        target => <<"some-target">>,
        target_dir => list_to_binary(filename:join(Root, "output dir")),
        release => true,
        features => [<<"one">>, <<"two">>],
        default_features => false,
        rustflags => [<<"-C">>, <<"panic=abort">>],
        env => [{"PATH", Root ++ ":" ++ os:getenv("PATH")},
                {"CAPTURE", Capture}, {"CROSS_ENV", "literal $PATH ; value"}]
    }),
    try
        [#{<<"payload">> := Payload}] = cargo_cmd:run_with_flags(Opts, ["meta", "data"], [
            "--format-version=1"
        ]),
        ?assertEqual(20000, byte_size(Payload)),
        {ok, MetaData} = file:read_file(Capture),
        {MetaArgs, Env, RustFlags} = binary_to_term(MetaData),
        ?assert(lists:member("--filter-platform", MetaArgs)),
        ?assertNot(lists:member("--target", MetaArgs)),
        ?assertNot(lists:member("--target-dir", MetaArgs)),
        ?assertEqual("literal $PATH ; value", Env),
        ?assertEqual("-C" ++ [31] ++ "panic=abort", RustFlags),
        [_] = cargo_cmd:run_with_flags(Opts, "build", ["--message-format=json"]),
        {ok, BuildData} = file:read_file(Capture),
        {BuildArgs, _, _} = binary_to_term(BuildData),
        ?assert(lists:member("--target", BuildArgs)),
        ?assert(lists:member("--release", BuildArgs)),
        ?assert(lists:member("one,two", BuildArgs)),
        ?assert(lists:member("--no-default-features", BuildArgs)),
        ?assert(lists:member(filename:join(Root, "output dir"), BuildArgs)),
        ?assertException(error, {cargo_error, {42, _}}, cargo_cmd:run(Opts, ["fail"])),
        ?assertEqual(Before, os:getenv("CROSS_ENV"))
    after
        file:delete(Tool),
        file:delete(Capture),
        file:del_dir(Root)
    end.

companion_executable(Config) ->
    % Exercise a real process with JSON spanning the short test line limit.
    Value = binary:copy(<<"a">>, 20000),
    Json = jsx:encode(#{<<"value">> => Value}),
    ?assertEqual([#{<<"value">> => Value}], emit_json(Config, Json)),
    ok.

streamed_json(Config) ->
    % Split a UTF-8 codepoint at the 32-byte test port boundary and retain
    % concatenated objects, newline-free EOF and incomplete-output checks.
    Prefix = binary:copy(<<"a">>, 22),
    Crab = <<16#f0, 16#9f, 16#a6, 16#80>>,
    Text = <<Prefix/binary, Crab/binary>>,
    Data = <<"{\"text\":\"", Text/binary, "\"}{\"next\":42}">>,
    ?assertEqual([#{<<"text">> => Text}, #{<<"next">> => 42}],
                 emit_json(Config, Data)),
    ?assertError(incomplete_json, emit_json(Config, <<"{\"text\":">>)),
    ok.

emit_json(Config, Data) ->
    emit_json(Config, Data, 0).

emit_json(Config, Data, ExitCode) ->
    Executable = filename:join([code:root_dir(), "bin", "erl"]),
    Eval = io_lib:format("io:put_chars(list_to_binary(~w)), halt(~w).",
                         [binary_to_list(Data), ExitCode]),
    cargo_cmd:run_executable(
        cargo_opts:new(#{path => ?config(priv_dir, Config)}), Executable,
        ["+S", "1:1", "+SDcpu", "1", "+SDio", "1", "-noshell", "-eval", Eval]).

structured_diagnostics(Config) ->
    Marker = <<"backend diagnostic marker">>,
    Message = #{<<"reason">> => <<"compiler-message">>, <<"message">> => #{
        <<"level">> => <<"error">>, <<"rendered">> => Marker, <<"children">> => []}},
    Json = jsx:encode(Message),
    ok = ct:capture_start(),
    Captured = try
        ?assertEqual([Message], emit_json(Config, Json)),
        ?assertError({cargo_error, {17, [Message]}}, emit_json(Config, Json, 17)),
        ct:capture_get()
    after
        ct:capture_stop()
    end,
    ?assertEqual(nomatch, binary:match(iolist_to_binary(Captured), Marker)),
    ok.
