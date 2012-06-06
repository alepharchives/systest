%% -*- tab-width: 4;erlang-indent-level: 4;indent-tabs-mode: nil -*-
%% ex: ts=4 sw=4 et
%% ----------------------------------------------------------------------------
%%
%% Copyright (c) 2005 - 2012 Nebularis.
%% Copyright (c) 2010 Dave Smith (dizzyd@dizzyd.com).
%%
%% Some portions of the code taken from sh (c) 2005 - 2012 Nebularis
%% Some portions of the code taken from rebar (c) 2010 Dave Smith
%% Some portions of the code taken from retest (c) 2010 Dave Smith
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
-module(systest_supervision_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include("../include/systest.hrl").
-compile(export_all).

suite() -> [{timetrap, {seconds, 200}}].

all() ->
    [suite_nodes_should_be_up_and_running,
     end_per_tc_can_manage_shutdown,
     {group, inter_testcase_cleanup}].

groups() ->
    [{inter_testcase_cleanup, [sequence],
      [end_per_tc_automation,
       after_end_per_tc_automation]}].

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

init_per_testcase(_TC, Config) ->
    Config.

end_per_testcase(TC=init_per_tc_manages_shutdown, Config) ->
    ct:pal("explicitly killing cluster ~p~n", [TC]),
    Pid = ?CONFIG(active, Config),
    systest:stop(Pid),
    ct:pal("explicit stop of ~p has returned (live=~p)~n",
           [Pid, erlang:is_process_alive(Pid)]),
    ok;
end_per_testcase(_TC, _Config) ->
    ok.

suite_nodes_should_be_up_and_running(_Config) ->
    ?assertEqual(pong, net_adm:ping(systest_utils:make_node(red))),
    ?assertEqual(pong, net_adm:ping(systest_utils:make_node(blue))),
    ok.

end_per_tc_can_manage_shutdown(Config) ->
    systest_cluster:print_status(?CONFIG(active, Config)),
    ok.

end_per_tc_automation(Config) ->
    %% this is a *deliberately* oversimplified test case, which
    %% exists simply to verify that the 'end_per_tc_automation'
    %% test cluster *was* up here, and will *not* be later on
    Pid = ?CONFIG(active, Config),
    Status = systest_cluster:status(Pid),
    ?assertMatch([{_, 'nodeup'},
                  {_, 'nodeup'},
                  {_, 'nodeup'}], Status),
    %% common test makes us declare inter-test dependencies
    %% specifically, accepting that their impossible to remove
    %% in some cases - this test (of how two test cases in a
    %% managed test framework will interact) being a perfect example
    {save_config, [{previous_active, Pid}]}.

after_end_per_tc_automation() ->
    [{userdata,[{doc, "Runs after end_per_tc_automation, ensuring that the"
                      " cluster set up during that test has been"
                      " automatically torn down by our ct_hooks."}]}].

after_end_per_tc_automation(Config) ->
    {end_per_tc_automation, SavedConfig} = ?config(saved_config, Config),
    ClusterPid = ?CONFIG(previous_active, SavedConfig),
    ct:pal("is end_per_tc_automation still alive!?...~n"),
    ?assertEqual(false, erlang:is_process_alive(ClusterPid)).

