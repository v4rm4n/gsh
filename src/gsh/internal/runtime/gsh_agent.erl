-module(gsh_agent).
-export([start/1]).

%% A long-lived process on the remote node that runs every REPL evaluation
%% for one gsh session, so the process-dictionary binding cache survives
%% between prompts. It exits when its gsh session goes away.
start(Owner) ->
    spawn(fun() -> init(Owner) end).

init(Owner) ->
    OwnerRef = erlang:monitor(process, Owner),
    loop(OwnerRef).

loop(OwnerRef) ->
    receive
        {run, From, Ref, Module, Binary, Function} ->
            code:purge(Module),
            Reply =
                case code:load_binary(Module, "", Binary) of
                    {module, Module} ->
                        try {ok, Module:Function()}
                        catch Class:Reason:Stack -> {error, {Class, Reason, Stack}}
                        end;
                    Error -> {error, {load_failed, Error}}
                end,
            From ! {Ref, Reply},
            loop(OwnerRef);
        {'DOWN', OwnerRef, process, _, _} ->
            %% gsh quit or the connection dropped: exit and free the cached bindings
            ok
    end.