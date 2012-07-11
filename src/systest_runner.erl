%% -*- tab-width: 4;erlang-indent-level: 4;indent-tabs-mode: nil -*-
%% ex: ts=4 sw=4 et
%% ----------------------------------------------------------------------------
%%
%% Copyright (c) 2005 - 2012 Nebularis.
%%
%% Permission is hereby granted, free of charge, to any person obtaining a copy
%% of this software and associated documentation files (the "Software"), deal
%% in the Software without restriction, including without limitation the rights
%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the Software is
%% furnished to do so, subject to the following conditions:
%%
%% The above copyright notice and this permission notice shall be included in
%% all copies or substantial portions of the Software.
%%
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
%% FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
%% IN THE SOFTWARE.
%% ----------------------------------------------------------------------------
-module(systest_runner).

-include("systest.hrl").

%-export([execute/1]).
-compile(export_all).

-type execution() :: #execution{}.
-export_type([execution/0]).

-define(WORKDIR(A, B, C),
        systest_env:work_directory(A, B, C)).

-exprecs_prefix([operation]).
-exprecs_fname(["record_", prefix]).
-exprecs_vfname([fname, "__", version]).

-compile({parse_transform, exprecs}).
-export_records([execution]).

behaviour_info(callbacks) ->
    [{run, 1}, {dryrun, 1}];
behaviour_info(_) ->
    undefined.

execute(Config) ->
    maybe_start_net_kernel(Config),
    {ok, BaseDir} = file:get_cwd(),
    Exec = build_exec([{base_dir, BaseDir}|Config]),
    BaseDir = Exec#execution.base_dir,
    Prof = Exec#execution.profile,
    DefaultSettings = systest_profile:get(settings_base, Prof),
    Resources = verify_resources(Prof, BaseDir),

    %% because sometimes, code that is accessed from an escript archive doesn't
    %% get handled in a particularly useful way by the code server.... :/
    % code:ensure_loaded(systest_utils)
    systest:start(),
    print_banner(),
    set_defaults(Prof),
    start_logging(Config),

    preload_resources(Resources),
    ensure_test_directories(Prof),
    systest_config:set_env(base_dir, BaseDir),
    
    Targets = load_test_targets(Prof, Config),
    Settings = systest_settings:load(DefaultSettings),
    Exec2 = set([{targets, Targets}, {settings, Settings}], Exec),
    verify(Exec2).

set_defaults(Profile) ->
    ScratchDir = systest_profile:get(output_dir, Profile),
    systest_config:set_env("SCRATCH_DIR", ScratchDir).

print_banner() ->
    %% Urgh - could there be an uglier way!?
    %% TODO: refactor this...
    AppVsn = element(3, lists:keyfind(systest, 1,
                                      application:loaded_applications())),
    {ok, Banner} = application:get_env(systest, banner),
    io:format("~s~n"
              "Version ~s~n", [Banner, AppVsn]).

start_logging(Config) ->
    Active = ?CONFIG(logging, Config, []),
    [begin
        io:format(user, "activating logging sub-system ~p~n", [SubSystem]),
        ok = systest_log:start(SubSystem, systest_log, user)
     end || SubSystem <- Active],
    ok.

verify(Exec2=#execution{profile     = Prof,
                        base_dir    = BaseDir,
                        targets     = Targets,
                        base_config = Config}) ->
    Mod = systest_profile:get(framework, Prof),
    io:format(user, "~s~n",
              [systest_utils:border("SysTest Task Descriptor", "-")]),
    io:format(user, "~s~n",
              [systest_utils:proplist_format([
                {"Base Directory", BaseDir},
                {"Test Directories", lists:concat([D || {dir, D} <- Targets])},
                {"Test Suites", lists:concat([S || {suite, S} <- Targets])}])]),

    Prop = systest_utils:record_to_proplist(Prof, systest_profile),
    Print = systest_utils:proplist_format(Prop),
    io:format(user, "~s~n",
              [systest_utils:border("SysTest Profile", "-")]),
    io:format(user, "~s~n", [Print]),

    TestFun = case ?CONFIG(dryrun, Config, false) of
                  true  -> dryrun;
                  false -> run
              end,

    case catch( erlang:apply(Mod, TestFun, [Exec2]) ) of
        ok ->
            ok;
        {error,{failures, N}} ->
            handle_failures(Prof, N, Config);
        {'EXIT', Reason} ->
            handle_errors(Exec2, Reason, Config);
        Errors ->
            handle_errors(Exec2, Errors, Config)
    end.

handle_failures(Prof, N, Config) ->
    ProfileName = systest_profile:get(name, Prof),
    ErrorHandler = ?CONFIG(error_handler, Config, fun systest_utils:abort/2),
    ErrorHandler("[failed] Execution Profile ~p: ~p failed test cases~n",
                 [ProfileName, N]).

handle_errors(_Exec, Reason, Config) ->
    ErrorHandler = ?CONFIG(error_handler, Config, fun systest_utils:abort/2),
    ErrorHandler("[error] Framework Encountered Unhandled Errors: ~p~n",
                 [Reason]).

load_test_targets(Prof, Config) ->
    case proplists:get_all_values(testsuite, Config) of
        [] ->
            case ?CONFIG(testcase, Config, undefined) of
                undefined   -> load_test_targets(Prof);
                {Suite, TC} -> [{suite, Suite}, {testcase, TC}]
            end;
        Suites ->
            [{suite, Suites}]
    end.

load_test_targets(Prof) ->
    {Dirs, Suites} = load_targets_from_profile(Prof),
    Suites2 = case Suites of
                  [] ->
                      [begin
                          list_to_atom(hd(string:tokens(
                                filename:basename(F), ".")))
                       end || Dir <- Dirs,
                                F <- filelib:wildcard(
                                            filename:join(Dir, "*_SUITE.*"))];
                  _ ->
                      Suites
              end,
    [{suite, systest_utils:uniq(Suites2)},
     {dir, systest_utils:uniq(Dirs)}].

load_targets_from_profile(Prof) ->
    lists:foldl(
        fun(Path, {Dirs, _}=Acc) when is_list(Path) ->
                setelement(1, Acc, [filename:absname(Path)|Dirs]);
           (Mod, {Dirs, Suites}) when is_atom(Mod) ->
                Path = test_dir(Mod),
                {[Path|Dirs], [Mod|Suites]}
        end, {[], []}, systest_profile:get(targets, Prof)).

test_dir(Thing) when is_atom(Thing) ->
    case code:ensure_loaded(Thing) of
        {error, Reason} ->
            throw({invalid_target, {Thing, Reason}});
        _ ->
            filename:absname(filename:dirname(code:which(Thing)))
    end.

preload_resources(Resources) ->
    [begin
        case file:consult(Resource) of
            {ok, Terms} ->
                systest_config:load_config_terms(Terms);
            Error ->
                throw(Error)
        end
     end || Resource <- Resources].

verify_resources(Profile, BaseDir) ->
    Resources = lists:foldl(fun(P, Acc) ->
                                Glob = filename:join(BaseDir, P),
                                filelib:wildcard(Glob) ++ Acc
                            end, [], systest_profile:get(resources, Profile)),
    [begin
        case filelib:is_regular(Path) of
            false -> throw({invalid_resource, Path});
            true  -> Path
        end
     end || Path <- Resources].

ensure_test_directories(Prof) ->
    filelib:ensure_dir(filename:join(
                       systest_profile:get(output_dir, Prof), "foo")),
    filelib:ensure_dir(filename:join(
                       systest_profile:get(log_dir, Prof), "foo")).

build_exec(Config) ->
    %% TODO: consider adding a time stamp to the scratch
    %%       dir like common test does
    ScratchDir = ?CONFIG(scratch_dir, Config,
                         ?WORKDIR(systest_env:temp_dir(),
                                  systest, "SYSTEST_SCRATCH_DIR")),
    Config2 = ?REPLACE(scratch_dir, ScratchDir, Config),
    Profile = systest_profile:load(Config2),
    BaseDir = ?REQUIRE(base_dir, Config),
    #execution{profile      = Profile,
               base_dir     = BaseDir,
               base_config  = Config2}.

maybe_start_net_kernel(Config) ->
    UseLongNames = ?CONFIG(longnames, Config, false),
    case net_kernel:longnames() of
        ignored ->
            if
                UseLongNames =:= true ->
                    net_kernel:start([?MODULE, longnames]);
                UseLongNames =:= false ->
                    net_kernel:start([?MODULE, shortnames])
            end;
        LongNames ->
            systest_utils:throw_unless(
                LongNames == UseLongNames, runner,
                "The supplied configuration indicates that "
                "longnames should be ~p, "
                "but the current node is running with ~p.~n",
                [use_longnames(UseLongNames),
                long_or_short_names(LongNames)])
    end.

use_longnames(true)  -> enabled;
use_longnames(false) -> disabled.

long_or_short_names(true)  -> longnames;
long_or_short_names(false) -> shortnames.