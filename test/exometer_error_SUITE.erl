-module(exometer_error_SUITE).

%% -------------------------------------------------------------------
%%
%% Copyright (c) 2014 Basho Technologies, Inc.  All Rights Reserved.
%%
%%   This Source Code Form is subject to the terms of the Mozilla Public
%%   License, v. 2.0. If a copy of the MPL was not distributed with this
%%   file, You can obtain one at http://mozilla.org/MPL/2.0/.
%%
%% -------------------------------------------------------------------
%% common_test exports
-export(
   [
    all/0, groups/0, suite/0,
    init_per_suite/1, end_per_suite/1,
    init_per_testcase/2, end_per_testcase/2
   ]).

%% test case exports
-export(
   [
    test_failing_probe/1,
    test_escalation_1/1,
    test_escalation_2/1
   ]).

-include_lib("common_test/include/ct.hrl").

%%%===================================================================
%%% common_test API
%%%===================================================================

all() ->
    [
     {group, test_probes}
    ].

groups() ->
    [
     {test_probes, [shuffle],
      [
       test_failing_probe,
       test_escalation_1,
       test_escalation_2
      ]}
    ].

suite() ->
    [].

init_per_suite(Config) ->
    _ = application:stop(exometer_core),
    Config.

end_per_suite(_Config) ->
    ok.

init_per_testcase(Case, Config) ->
    {ok, Started} = exometer_test_util:ensure_all_started(exometer_core),
    ct:log("Started: ~p~n", [[{T, catch ets:tab2list(T)}
                              || T <- exometer_util:tables()]]),
    [{started_apps, Started}|Config].

end_per_testcase(_Case, Config) ->
    ct:log("end_per_testcase(Config = ~p)~n", [Config]),
    stop_started_apps(Config),
    ok.

stop_started_apps(Config) ->
    [application:stop(A) || A <- lists:reverse(?config(started_apps, Config))],
    ok.

%%%===================================================================
%%% Test Cases
%%%===================================================================
test_failing_probe(_Config) ->
    M = [?MODULE, ?LINE],
    ok = exometer:new(M, histogram, []),
    true = killed_probe_restarts(M),
    ok.

test_escalation_1(_Config) ->
    M = [?MODULE, ?LINE],
    Levels = [{{3,5000}, restart},
              {'_', disable}],
    ok = exometer:new(M, histogram, [{restart, Levels}]),
    true = killed_probe_restarts(M),
    true = killed_probe_restarts(M),
    true = killed_probe_restarts(M),
    true = killed_probe_disabled(M),
    ok.

test_escalation_2(_Config) ->
    M = [?MODULE, ?LINE],
    Levels = [{{3,5000}, restart},
              {'_', delete}],
    ok = exometer:new(M, histogram, [{restart, Levels}]),
    true = killed_probe_restarts(M),
    true = killed_probe_restarts(M),
    true = killed_probe_restarts(M),
    true = killed_probe_deleted(M),
    ok.

killed_probe_restarts(M) ->
    Pid = exometer:info(M, ref),
    ct:log("Pid = ~p~n", [Pid]),
    exit(Pid, kill),
    ok = await_death(Pid),
    NewPid = exometer:info(M, ref),
    ct:log("NewPid = ~p~n", [NewPid]),
    enabled = exometer:info(M, status),
    true = Pid =/= NewPid.

killed_probe_disabled(M) ->
    Pid = exometer:info(M, ref),
    ct:log("Pid = ~p~n", [Pid]),
    exit(Pid, kill),
    ok = await_death(Pid),
    undefined = exometer:info(M, ref),
    ct:log("Ref = undefined~n", []),
    disabled = exometer:info(M, status),
    true.

killed_probe_deleted(M) ->
    Pid = exometer:info(M, ref),
    ct:log("Pid = ~p~n", [Pid]),
    exit(Pid, kill),
    ok = await_death(Pid),
    ct:log("Ets = ~p~n", [[{T,ets:tab2list(T)} ||
                              T <- exometer_util:tables()]]),
    {error, not_found} = exometer:get_value(M),
    ct:log("~p deleted~n", [M]),
    true.

await_death(Pid) ->
    Ref = erlang:send_after(1000, self(), zombie),
    await_death(Pid, Ref).

await_death(Pid, Ref) ->
    case erlang:read_timer(Ref) of
        false ->
            error({process_not_dead, Pid});
        _ ->
            case erlang:is_process_alive(Pid) of
                true ->
                    erlang:bump_reductions(500),
                    await_death(Pid, Ref);
                false ->
                    erlang:cancel_timer(Ref),
                    _ = sys:get_status(exometer_admin),
                    _ = sys:get_status(exometer_admin),
                    ok
            end
    end.
