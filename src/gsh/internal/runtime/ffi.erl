-module(ffi).

-export([
    system_time/0,
    system_version/0,
    app_version/1,
    get_exports/1,
    load_and_run/2,
    store_put/2,
    store_lookup/1,
    get_args/0,
    boot_app/1,
    pid_from_string/1,
    setup_logger/0,
    get_logs/0,
    log/2,
    start_observer/0,
    compile_and_load/2,
    run_entry/2,
    ensure_code_paths/0,
    start_network/2,
    set_cookie/1,
    rpc_compile_and_run/4,
    ping_node/1,
    reload_modified/0,
    trap_exits/0,
    drain_exits/0,
    start_output_proxy/0,
    use_output_proxy/1
]).

%% Returns the current system time in microseconds to guarantee 
%% unique file names for the REPL evaluator.
system_time() ->
    erlang:system_time(microsecond).

system_version() ->
    unicode:characters_to_binary(erlang:system_info(system_version)).

app_version(AppAtom) ->
    case application:get_key(AppAtom, vsn) of
        {ok, VersionStr} -> unicode:characters_to_binary(VersionStr);
        undefined -> <<"0.0.0">>
    end.

%% Takes an Erlang module name as a binary (e.g., <<"gleam@int">>) 
%% and returns a list of its public functions as binaries.
get_exports(ModuleNameBin) ->
    try
        ModuleName = binary_to_atom(ModuleNameBin, utf8),
        case code:ensure_loaded(ModuleName) of
            {module, ModuleName} ->
                Exports = ModuleName:module_info(exports),
                [unicode:characters_to_binary(atom_to_list(F)) || {F, _Arity} <- Exports, F =/= module_info];
            _ -> 
                []
        end
    catch
        _:_ -> []
    end.

load_and_run(ModuleNameBin, FunctionNameBin) ->
    Module = binary_to_atom(ModuleNameBin, utf8),
    Function = binary_to_atom(FunctionNameBin, utf8),
    code:purge(Module),
    code:delete(Module),
    case filelib:wildcard("build/dev/erlang/*/ebin") of
        [] -> ok;
        Paths -> lists:foreach(fun(P) -> code:add_patha(P) end, Paths)
    end,
    case code:load_file(Module) of
        {module, Module} ->
            try
                Result = apply(Module, Function, []),
                {ok, Result}
            catch
                Class:Reason:Stack ->
                    {error, {Class, Reason, Stack}}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% Side-effect cache used by generated evaluation modules (see store.gleam).
%% Keys are namespaced so they can't collide with anything evaluated code keeps
%% in the process dictionary, and values are wrapped so a cached `undefined`
%% atom (e.g. a Gleam `Undefined` constructor) isn't mistaken for a missing entry.
store_put(Key, Value) ->
    put({gsh_store, Key}, {cached, Value}),
    Value.

store_lookup(Key) ->
    case get({gsh_store, Key}) of
        {cached, Value} -> {ok, Value};
        undefined -> {error, nil}
    end.

%% Reads arguments passed after `--` in the CLI
get_args() ->
    [unicode:characters_to_binary(A) || A <- init:get_plain_arguments()].

%% Dynamically loads a Gleam module and runs its main() in a background process
boot_app(ModuleNameBin) ->
    NormalizedBin = binary:replace(ModuleNameBin, <<"/">>, <<"@">>, [global]),
    Module = binary_to_atom(NormalizedBin, utf8),
    case code:ensure_loaded(Module) of
        {module, Module} ->
            Pid = spawn(fun() -> apply(Module, main, []) end),
            {ok, Pid};
        {error, Reason} -> 
            ReasonStr = list_to_binary(io_lib:format("~p", [Reason])),
            {error, <<"Could not load '", NormalizedBin/binary, "': ", ReasonStr/binary>>}
    end.

%% Converts a string like "<0.83.0>" into an actual Erlang PID
pid_from_string(Bin) ->
    Str = string:trim(binary_to_list(Bin)),
    Full = case Str of
        "<" ++ _ -> Str;
        _ -> "<" ++ Str ++ ">"
    end,
    list_to_pid(Full).

%% Creates an in-memory table and reroutes logs into it
setup_logger() ->
    ets:new(gsh_logs, [named_table, public, ordered_set]),
    logger:remove_handler(default),
    logger:add_handler(gsh_ui, ?MODULE, #{
        formatter => {logger_formatter, #{
            single_line => true,
            template => [time, " ", pid, " [", level, "] ", msg]
        }}
    }).

%% The callback Erlang triggers every time a background app logs something
log(LogEvent, Config) ->
    {Formatter, FormatterConfig} = maps:get(formatter, Config),
    Formatted = Formatter:format(LogEvent, FormatterConfig),
    Bin = unicode:characters_to_binary(Formatted, utf8),
    Clean = binary:replace(Bin, <<"\n">>, <<>>, [global]),
    Time = erlang:system_time(microsecond),
    ets:insert(gsh_logs, {Time, Clean}),
    case ets:info(gsh_logs, size) > 50 of
        true -> ets:delete(gsh_logs, ets:first(gsh_logs));
        false -> ok
    end.

%% Called by the Gleam UI to fetch the logs to draw in the box
get_logs() ->
    Logs = ets:tab2list(gsh_logs),
    [Text || {_Time, Text} <- Logs].

%% Launches the native BEAM diagnostic GUI in the background
start_observer() ->
    try
        observer:start(),
        {ok, nil}
    catch
        _:_ -> 
            {error, <<"Erlang VM was compiled without wxWidgets support.">>}
    end.

%% Compiles an .erl file directly into RAM and hot-loads it into the VM
compile_and_load(ErlFilePath, ModuleNameStr) ->
    ErlFile = binary_to_list(ErlFilePath),
    ModuleName = binary_to_atom(ModuleNameStr, utf8),
    case compile:file(ErlFile, [binary, report_errors]) of
        {ok, ModuleName, Binary} ->
            case code:load_binary(ModuleName, ErlFile, Binary) of
                {module, ModuleName} -> {ok, nil};
                {error, What} -> {error, atom_to_binary(What, utf8)}
            end;
        error ->
            {error, <<"Erlang compilation failed">>};
        {error, Errors, _Warnings} ->
            {error, unicode:characters_to_binary(io_lib:format("~p", [Errors]))}
    end.

%% Executes Module:Function() in memory and traps VM runtime errors
run_entry(ModuleBin, FunctionBin) ->
    Module = binary_to_atom(ModuleBin, utf8),
    Function = binary_to_atom(FunctionBin, utf8),
    try
        Result = Module:Function(),
        {ok, Result}
    catch
        Class:Reason:Stacktrace ->
            FormattedError = unicode:characters_to_binary(
                io_lib:format("~p:~p~n~p", [Class, Reason, Stacktrace])
            ),
            {error, FormattedError}
    end.

ensure_code_paths() ->
    case filelib:wildcard("build/dev/erlang/*/ebin") of
        [] -> ok;
        Paths -> lists:foreach(fun(P) -> code:add_patha(P) end, Paths)
    end,
    ok.

start_network(NameBin, NameTypeBin) ->
    NodeName = binary_to_atom(NameBin, utf8),
    Type = binary_to_atom(NameTypeBin, utf8),
    net_kernel:stop(),
    case net_kernel:start([NodeName, Type]) of
        {ok, _Pid} -> {ok, nil};
        {error, {already_started, _}} -> {ok, nil};
        {error, Reason} -> {error, list_to_binary(io_lib:format("~p", [Reason]))}
    end.

set_cookie(CookieBin) ->
    CookieAtom = binary_to_atom(CookieBin, utf8),
    erlang:set_cookie(CookieAtom),
    nil.

%% Compiles the eval module locally, then runs it inside a persistent
%% gsh_agent process on the remote node. A plain rpc:call would run each
%% evaluation in a brand-new process, losing the process-dictionary
%% binding cache and re-running every historical side effect on the remote.
rpc_compile_and_run(NodeBin, ErlPathBin, ModuleBin, FunctionBin) ->
    Node = binary_to_atom(NodeBin, utf8),
    Module = binary_to_atom(ModuleBin, utf8),
    Function = binary_to_atom(FunctionBin, utf8),
    case compile:file(binary_to_list(ErlPathBin), [binary]) of
        {ok, Module, Binary} ->
            case remote_agent(Node) of
                {ok, Agent} ->
                    Ref = erlang:monitor(process, Agent),
                    Agent ! {run, self(), Ref, Module, Binary, Function},
                    receive
                        {Ref, Reply} ->
                            erlang:demonitor(Ref, [flush]),
                            Reply;
                        {'DOWN', Ref, process, _, Reason} ->
                            erase({gsh_agent, Node}),
                            {error, {remote_agent_down, Reason}}
                    end;
                {error, _} = Err ->
                    Err
            end;
        error ->
            {error, compile_failed};
        {error, Errors, _Warnings} ->
            {error, {compile_failed, Errors}}
    end.

%% Starts this session's evaluation agent on the remote node (once per session)
%% and remembers its pid in the REPL process's dictionary. The agent monitors
%% this process, so it exits when the session ends or the connection drops.
remote_agent(Node) ->
    case get({gsh_agent, Node}) of
        Pid when is_pid(Pid) ->
            {ok, Pid};
        undefined ->
            case ensure_agent_code(Node) of
                ok ->
                    case rpc:call(Node, gsh_agent, start, [self()]) of
                        Pid when is_pid(Pid) ->
                            put({gsh_agent, Node}, Pid),
                            {ok, Pid};
                        Other ->
                            {error, {agent_start_failed, Other}}
                    end;
                {error, _} = Err ->
                    Err
            end
    end.

%% Loads gsh_agent on the remote node only if it's missing or different.
%% Re-loading identical code would still age the version other sessions'
%% agents are running, and a second re-load would kill them.
ensure_agent_code(Node) ->
    case code:get_object_code(gsh_agent) of
        {gsh_agent, Bin, File} ->
            {ok, {gsh_agent, Md5}} = beam_lib:md5(Bin),
            case rpc:call(Node, erlang, get_module_info, [gsh_agent, md5]) of
                Md5 ->
                    ok;
                _ ->
                    case rpc:call(Node, code, load_binary, [gsh_agent, File, Bin]) of
                        {module, gsh_agent} -> ok;
                        Other -> {error, {agent_load_failed, Other}}
                    end
            end;
        error ->
            {error, <<"gsh_agent.beam not found: add gsh_agent.erl next to ffi.erl in gsh's src/">>}
    end.

%% Handshakes with a remote node. On failure, reports the local node name
%% and a fingerprint of the cookie actually used, so a mismatch can be
%% checked without printing the cookie itself.
ping_node(NodeBin) ->
    Node = binary_to_atom(NodeBin, utf8),
    case net_adm:ping(Node) of
        pong ->
            {ok, nil};
        pang ->
            Fingerprint = case is_alive() of
                true -> erlang:phash2(erlang:get_cookie(Node));
                false -> none
            end,
            {error, unicode:characters_to_binary(io_lib:format(
                "local node ~p, cookie fingerprint ~p. "
                "On the remote, erlang:phash2(erlang:get_cookie()). must print the same number.",
                [node(), Fingerprint]))}
    end.

%% Reloads every module whose .beam on disk differs from the loaded version,
%% like IEx's recompile. Returns the names of the modules it reloaded.
reload_modified() ->
    Modified = [M || M <- code:modified_modules(), not is_eval_module(M)],
    lists:filtermap(fun(M) ->
        code:purge(M),
        case code:load_file(M) of
            {module, M} -> {true, atom_to_binary(M, utf8)};
            {error, _} -> false
        end
    end, Modified).

%% gsh's own REPL evaluation modules. The package-interface export can leave
%% compiled copies of them in the build, so :cc would otherwise report them.
is_eval_module(Module) ->
    lists:prefix("gsh_eval_", atom_to_list(Module)).


%% The shell traps exits, so a crash in a process spawned (and linked) from a
%% REPL expression, e.g. `process.spawn(app.main)`, is reported instead of
%% taking the shell down with it.
trap_exits() ->
    process_flag(trap_exit, true),
    nil.

%% Exit signals from linked processes since the last prompt, as
%% [{<<"<0.113.0>">>, <<"reason">>}]. Normal exits are dropped.
drain_exits() ->
    drain_exits([]).

drain_exits(Acc) ->
    receive
        {'EXIT', _From, normal} ->
            drain_exits(Acc);
        {'EXIT', From, Reason} ->
            Entry = {unicode:characters_to_binary(io_lib:format("~p", [From])),
                     unicode:characters_to_binary(io_lib:format("~p", [Reason]))},
            drain_exits([Entry | Acc])
    after 0 ->
        lists:reverse(Acc)
    end.


%% ---------------------------------------------------------------------------
%% Output proxy
%%
%% While the shell waits at its prompt the terminal is in raw mode, where a
%% bare "\n" moves down a line without returning to column 0, so output from
%% background processes drifts to the right ("staircasing"). Processes started
%% through the shell (booted apps, anything spawned by REPL code) get this
%% proxy as their group leader. It writes line endings as "\r\n", like
%% terminal.print does for the shell's own output, and forwards everything
%% else to the real group leader unchanged.
%% ---------------------------------------------------------------------------

start_output_proxy() ->
    Real = group_leader(),
    put(gsh_real_group_leader, Real),
    put(gsh_output_proxy, spawn(fun() -> proxy_loop(Real, #{}) end)),
    nil.

%% Routes this process's output, and the group leader that processes spawned
%% from now on inherit, through the proxy (true) or straight to the terminal
%% (false). The shell switches it on only while booting apps and evaluating,
%% so its own line editor keeps talking to the terminal directly.
use_output_proxy(On) ->
    Key = case On of
        true -> gsh_output_proxy;
        false -> gsh_real_group_leader
    end,
    case get(Key) of
        undefined -> ok;
        GroupLeader -> group_leader(GroupLeader, self())
    end,
    nil.

%% Forwards requests without waiting for their replies, so a pending read
%% never holds up output from other processes.
proxy_loop(Real, Pending) ->
    receive
        {io_request, From, ReplyAs, Request} ->
            Ref = make_ref(),
            Real ! {io_request, self(), Ref, crlf_request(Request)},
            proxy_loop(Real, Pending#{Ref => {From, ReplyAs}});
        {io_reply, Ref, Reply} ->
            case maps:take(Ref, Pending) of
                {{From, ReplyAs}, Rest} ->
                    From ! {io_reply, ReplyAs, Reply},
                    proxy_loop(Real, Rest);
                error ->
                    proxy_loop(Real, Pending)
            end;
        _Other ->
            proxy_loop(Real, Pending)
    end.

crlf_request(Request) ->
    try
        case Request of
            {put_chars, Enc, Chars} -> {put_chars, Enc, crlf(Chars, Enc)};
            {put_chars, Enc, M, F, A} -> {put_chars, Enc, crlf(apply(M, F, A), Enc)};
            {put_chars, Chars} -> {put_chars, crlf(Chars, latin1)};
            {put_chars, M, F, A} -> {put_chars, crlf(apply(M, F, A), latin1)};
            {requests, Requests} -> {requests, [crlf_request(R) || R <- Requests]};
            _ -> Request
        end
    catch
        _:_ -> Request
    end.

crlf(Chars, Encoding) ->
    Bin = case Encoding of
        unicode ->
            case unicode:characters_to_binary(Chars) of
                B when is_binary(B) -> B;
                _ -> throw(invalid)
            end;
        latin1 ->
            iolist_to_binary(Chars)
    end,
    Normalised = binary:replace(Bin, <<"\r\n">>, <<"\n">>, [global]),
    binary:replace(Normalised, <<"\n">>, <<"\r\n">>, [global]).
