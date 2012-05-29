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
-module(systest_rebar).

-export([systest/2, write_log/2]).

-include("log.hrl").

%%
%% Systest Logging API
%%

write_log(systest_log, {Str, Args}) ->
    %% TODO: do we REALLY want to do this!?
    write_log(systest_log, {info, Str, Args});
write_log(systest_log, {Level, Str, Args}) ->
    %% NB: we're here because rebar does *NOT* log to 'user' which
    %% causes log messages to get lost in the ct group_leader take over
    {ok, LogLevel} = application:get_env(rebar, log_level),
    case should_log(LogLevel, Level) of
        true ->
            io:format(user, log_prefix(Level) ++ Str, Args);
        false ->
            ok
    end.

%%
%% Public (Callable) Rebar API
%%

systest(Config, _) ->
    systest:start(),
    systest_log:start(?MODULE),
    
    %% TODO: consider adding a time stamp to the scratch
    %%       dir like common test does
    ScratchDir = case os:getenv("SYSTEST_SCRATCH_DIR") of
                     false -> filename:join(systest_utils:temp_dir(),
                                            "systest");
                     Dir   -> Dir
                 end,
    rebar_file_utils:rm_rf(ScratchDir),
    filelib:ensure_dir(filename:join(ScratchDir, "foo")),
    rebar_config:set_global(scratch_dir, ScratchDir),

    Profile = case os:getenv("SYSTEST_PROFILE") of
                  false -> os:getenv("USER");
                  Name -> Name
              end,
    Spec = case rebar_utils:find_files("profiles", Profile ++ "\\.spec") of
               [SpecFile] -> SpecFile;
               _          -> filename:join("profiles", "default.spec")
           end,

    case filelib:is_regular(Spec) of
        false ->
            rebar_core:process_commands([ct], Config);
        true ->
            Env = clean_config_dirs(Config) ++ rebar_env() ++ os_env(Config),

            {ok, SpecOutput} = transform_file(Spec,
                                              systest_utils:temp_dir(), Env),

            {ok, FinalSpec} = process_config_files(ScratchDir,
                                                   SpecOutput, Env),

            %FinalConfig = rebar_config:set(Config, ct_extra_params,
            %                               "-spec " ++ FinalSpec ++
            %                              " -s systest start"),
            % rebar_core:process_commands([ct], FinalConfig)
            Opts = ct_options(ScratchDir, Profile, FinalSpec, Config),
            ct:install(Opts),
            case ct:run_test(Opts) of
                {error, Reason} ->
                    rebar_utils:abort("Test run failed: ~p~n", [Reason]);
                TestResults ->
                    ?DEBUG("Results: ~p~n", [TestResults]),
                    ok
            end
    end.

%%
%% Private API
%%

ct_options(ScratchDir, Profile, FinalSpec, Config) ->
    UserConfig = rebar_config:get_local(Config, systest, []),
    LogDir = filename:join(ScratchDir, "logs"),
    filelib:ensure_dir(filename:join(LogDir, "systest")),
    io:format(user,
           "----------------------------------------------------------------~n"
           "SysTest Parameters~n"
           "Profile Name:               ~s~n"
           "Scratch Directory:          ~s~n"
           "Log Directory:              ~s~n"
           "Common Test Spec:           ~s~n"
           "----------------------------------------------------------------",
           [ScratchDir, LogDir, Profile, FinalSpec]),
    [{spec, [FinalSpec]},
     {logdir, LogDir}] ++ UserConfig.

process_config_files(ScratchDir, TempSpec, Env) ->
    {ok, Terms} = file:consult(TempSpec),
    {[Configs], Rest} = proplists:split(Terms, [config]),
    rebar_log:log(debug, "Processing config sections: ~p~n", [Configs]),
    Replacements = [begin
                        {ok, Path} = transform_file(F, ScratchDir, Env),
                        {config, Path}
                    end || {_, F} <- lists:flatten(Configs)],
    Spec = filename:join(ScratchDir, filename:basename(TempSpec)),
    {ok, Fd} = file:open(Spec, [append]),
    Content = Replacements ++ Rest,
    rebar_log:log(debug, "Write to ~s: ~p~n", [Spec, Content]),
    write_terms(Content, Fd),
    {ok, Spec}.

transform_file(File, ScratchDir, Env) ->
    case filelib:is_regular(File) of
        false -> rebar_utils:abort("File ~s not found.~n", [File]);
        true  -> ok
    end,
    Output = filename:join(ScratchDir, filename:basename(File)),
    Target = filename:absname(Output),
    Origin = filename:absname(File),
    rebar_log:log(info, "transform ~s into ~s~n", [Origin, Target]),
    rebar_log:log(debug, "template environment: ~p~n", [Env]),

    Context = rebar_templater:resolve_variables(Env, dict:new()),
    {ok, Bin} = file:read_file(File),
    Rendered = rebar_templater:render(Bin, Context),

    file:write_file(Output, Rendered),
    {ok, Target}.

write_terms(Terms, Fd) ->
    try
        [begin
            Element = lists:flatten(erl_pp:expr(erl_parse:abstract(Item))),
            Term = Element ++ ".\n",
            ok = file:write(Fd, Term)
         end || Item <- Terms]
    after
        file:close(Fd)
    end.

clean_config_dirs(Config) ->
    [{plugin_dir, rebar_config:get_local(Config, plugin_dir, "")}] ++
    lower_case_key_names(rebar_config:get_env(Config, rebar_deps)).

lower_case_key_names(Items) ->
    [{string:to_lower(K), V} || {K, V} <- Items].

rebar_env() ->
    [{base_dir, rebar_config:get_global(base_dir, rebar_utils:get_cwd())}] ++
    clean_env(application:get_all_env(rebar_global)).

os_env(_Config) ->
    systest_config:get_env().

clean_env(Env) ->
   [ E || {_, [H|_]}=E <- Env, is_integer(H) ].

should_log(debug, _)     -> true;
should_log(info, debug)  -> false;
should_log(info, _)      -> true;
should_log(warn, debug)  -> false;
should_log(warn, info)   -> false;
should_log(warn, _)      -> true;
should_log(error, error) -> true;
should_log(error, _)     -> false;
should_log(_, _)         -> false.

log_prefix(debug) -> "DEBUG: ";
log_prefix(info)  -> "INFO:  ";
log_prefix(warn)  -> "WARN:  ";
log_prefix(error) -> "ERROR: ".
