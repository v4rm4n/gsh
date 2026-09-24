%% REPL-driven debugging for GSH.
%%
%% Application code pauses itself with a pry call. The process then waits
%% for the GSH shell on the same node, runs whatever code the shell sends it,
%% and carries on when the shell sends `:continue`.
%%
%% Application code declares the call through an external, because gsh is a
%% dev dependency and `src/` modules can't import dev dependencies:
%%
%%   @external(erlang, "gsh_pry", "pry")
%%   fn pry(value: a, label: String) -> a
%%
%% A pry call is dev-only: in a build without gsh (e.g. an Erlang shipment)
%% this module doesn't exist and the call fails with `undef`.

-module(gsh_pry).

-export([
    pry/2,
    value/1,
    start_server/1,
    take/0,
    take_id/1,
    list/0,
    waiting/0,
    set_enabled/1,
    resume/2,
    run/5,
    pid_text/1
]).

-define(SERVER, gsh_pry_server).
-define(CALL_TIMEOUT, 5000).

%% ===========================================================================
%% Application side
%% ===========================================================================

%% Pauses the calling process until the shell resumes it, then returns Value.
%% Returns Value immediately when no gsh session runs on this node, when pry
%% points are switched off, or when called from the shell process itself
%% (which would otherwise wait on itself forever).
pry(Value, Label) ->
    case whereis(?SERVER) of
        undefined ->
            Value;
        Server ->
            Ref = erlang:monitor(process, Server),
            Server ! {pry_request, self(), Ref, Label, location()},
            receive
                {Ref, skip} ->
                    erlang:demonitor(Ref, [flush]),
                    Value;
                {Ref, paused, Id} ->
                    put({gsh_pry_value, Id}, Value),
                    serve(Id, Ref),
                    erase({gsh_pry_value, Id}),
                    erase_store(),
                    Value;
                {'DOWN', Ref, process, _, _} ->
                    Value
            end
    end.

%% Called by evaluation modules (running inside the paused process) to read
%% the value that was passed to pry.
value(Id) ->
    get({gsh_pry_value, Id}).

%% While paused, run evaluations sent by the shell, until it resumes us or
%% the session ends. Only messages tagged for this pry are received, so the
%% process's own mailbox is left untouched.
serve(Id, ServerRef) ->
    receive
        {gsh_pry_run, Id, From, Ref, Module, Binary, Function} ->
            From ! {Ref, run_here(Module, Binary, Function)},
            serve(Id, ServerRef);
        {gsh_pry_resume, Id} ->
            erlang:demonitor(ServerRef, [flush]),
            ok;
        {'DOWN', ServerRef, process, _, _} ->
            ok
    end.

run_here(Module, Binary, Function) ->
    code:purge(Module),
    case code:load_binary(Module, "", Binary) of
        {module, Module} ->
            try
                {ok, Module:Function()}
            catch
                Class:Reason:Stack ->
                    {error, unicode:characters_to_binary(
                        io_lib:format("~p:~p~n~p", [Class, Reason, Stack]))}
            end;
        Error ->
            {error, unicode:characters_to_binary(
                io_lib:format("could not load ~p: ~p", [Module, Error]))}
    end.

%% Removes the binding cache that pry-session evaluations left in this
%% process, so nothing gsh-related stays behind in the application.
erase_store() ->
    [erase(Key) || {{gsh_store, _} = Key, _} <- get()],
    ok.

%% The file of the code that called pry, e.g. <<"src/hello.gleam">>.
%%
%% Only the file is reported. Gleam marks where each function starts, not each
%% line, and the Erlang compiler inlines small functions into their callers, so
%% line numbers and function names in stack traces can point at the wrong spot.
%% The label passed to pry is what identifies the exact pry point. If pry is the
%% last expression of a function, that function's frame is gone (tail call) and
%% this is the caller's file.
location() ->
    {current_stacktrace, Frames} = process_info(self(), current_stacktrace),
    Callers = [F || {M, _, _, _} = F <- Frames,
                    not lists:member(M, [?MODULE, erlang, proc_lib])],
    case Callers of
        [{_M, _F, _A, Info} | _] ->
            unicode:characters_to_binary(proplists:get_value(file, Info, "an unknown file"));
        [] ->
            <<"an unknown file">>
    end.

%% ===========================================================================
%% Pry server: one per gsh session, registered on the node
%% ===========================================================================

%% Starts the server for the shell process Owner. The server exits with the
%% shell, and every paused process monitors it, so they all resume then.
start_server(Owner) ->
    case whereis(?SERVER) of
        undefined -> ok;
        Old ->
            catch unregister(?SERVER),
            exit(Old, kill)
    end,
    Pid = spawn(fun() ->
        erlang:monitor(process, Owner),
        server(#{owner => Owner, enabled => true, queue => [], next_id => 1})
    end),
    register(?SERVER, Pid),
    nil.

server(#{owner := Owner, enabled := Enabled, queue := Queue, next_id := NextId} = S) ->
    receive
        {pry_request, From, Ref, _Label, _Location} when From =:= Owner; not Enabled ->
            From ! {Ref, skip},
            server(S);

        {pry_request, From, Ref, Label, Location} ->
            erlang:monitor(process, From),
            From ! {Ref, paused, NextId},
            notify(NextId, From, Label, Location, length(Queue) + 1),
            server(S#{queue := Queue ++ [{NextId, From, Label, Location}],
                      next_id := NextId + 1});

        {take, Which, From, Ref} ->
            Found = case Which of
                oldest -> Queue;
                Id -> [E || {EId, _, _, _} = E <- Queue, EId =:= Id]
            end,
            case Found of
                [] ->
                    From ! {Ref, {error, nil}},
                    server(S);
                [{Id2, Pid, Label, Location} = Taken | _] ->
                    Rest = lists:delete(Taken, Queue),
                    From ! {Ref, {ok, {paused, Pid, Id2, Label, Location, length(Rest)}}},
                    server(S#{queue := Rest})
            end;

        {list, From, Ref} ->
            From ! {Ref, [{paused, Pid, Id, Label, Location, 0}
                          || {Id, Pid, Label, Location} <- Queue]},
            server(S);

        {waiting, From, Ref} ->
            From ! {Ref, length(Queue)},
            server(S);

        {set_enabled, true, From, Ref} ->
            From ! {Ref, 0},
            server(S#{enabled := true});

        {set_enabled, false, From, Ref} ->
            [Pid ! {gsh_pry_resume, Id} || {Id, Pid, _, _} <- Queue],
            From ! {Ref, length(Queue)},
            server(S#{enabled := false, queue := []});

        {'DOWN', _, process, Owner, _} ->
            %% The shell exited. Stopping resumes every paused process.
            ok;

        {'DOWN', _, process, Pid, _} ->
            server(S#{queue := [E || {_, P, _, _} = E <- Queue, P =/= Pid]})
    end.

notify(Id, Pid, Label, Location, Waiting) ->
    Hint = case Waiting of
        1 -> "Type :pry to attach.";
        N -> io_lib:format("~p waiting, :pry list to see them.", [N])
    end,
    io:put_chars(unicode:characters_to_binary(io_lib:format(
        "\r\n\e[36m[pry]\e[0m #~p ~p paused at \"~ts\" (~ts). ~s\r\n",
        [Id, Pid, Label, Location, Hint]))).

%% ===========================================================================
%% Shell side
%% ===========================================================================

take() -> call(fun(Ref) -> {take, oldest, self(), Ref} end, {error, nil}).

take_id(Id) -> call(fun(Ref) -> {take, Id, self(), Ref} end, {error, nil}).

list() -> call(fun(Ref) -> {list, self(), Ref} end, []).

waiting() -> call(fun(Ref) -> {waiting, self(), Ref} end, 0).

set_enabled(On) -> call(fun(Ref) -> {set_enabled, On, self(), Ref} end, 0).

resume(Pid, Id) ->
    Pid ! {gsh_pry_resume, Id},
    nil.

%% Compiles an evaluation module here and runs it inside the paused process.
run(Pid, Id, ErlPathBin, ModuleBin, FunctionBin) ->
    Module = binary_to_atom(ModuleBin, utf8),
    Function = binary_to_atom(FunctionBin, utf8),
    case compile:file(binary_to_list(ErlPathBin), [binary]) of
        {ok, Module, Binary} ->
            Ref = erlang:monitor(process, Pid),
            Pid ! {gsh_pry_run, Id, self(), Ref, Module, Binary, Function},
            receive
                {Ref, Reply} ->
                    erlang:demonitor(Ref, [flush]),
                    Reply;
                {'DOWN', Ref, process, _, Reason} ->
                    {error, unicode:characters_to_binary(
                        io_lib:format("the paused process exited: ~p", [Reason]))}
            end;
        error ->
            {error, <<"Erlang compilation failed">>};
        {error, Errors, _Warnings} ->
            {error, unicode:characters_to_binary(io_lib:format("~p", [Errors]))}
    end.

%% "<0.231.0>", for messages.
pid_text(Pid) ->
    list_to_binary(pid_to_list(Pid)).

call(Build, Default) ->
    case whereis(?SERVER) of
        undefined ->
            Default;
        Server ->
            Ref = erlang:monitor(process, Server),
            Server ! Build(Ref),
            receive
                {Ref, Reply} ->
                    erlang:demonitor(Ref, [flush]),
                    Reply;
                {'DOWN', Ref, process, _, _} ->
                    Default
            after ?CALL_TIMEOUT ->
                erlang:demonitor(Ref, [flush]),
                Default
            end
    end.
