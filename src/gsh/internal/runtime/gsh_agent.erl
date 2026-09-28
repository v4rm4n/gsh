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
        {'DOWN', OwnerRef, process, _, _} ->
            ok;

        {run, From, Ref, Module, Binary, Function} ->
            code:purge(Module),
            Reply =
                case code:load_binary(Module, "", Binary) of
                    {module, Module} ->
                        try {ok, Module:Function()}
                        catch 
                            error:undef:Stacktrace ->
                                case Stacktrace of
                                    [{MissingMod, MissingFunc, _, _} | _] ->
                                        RawMod = atom_to_binary(MissingMod, utf8),
                                        ModStr = binary:replace(RawMod, <<"@">>, <<"/">>, [global]),
                                        FuncStr = atom_to_binary(MissingFunc, utf8),
                                        {error, <<"\e[31merror:\e[0m Undefined module or function '", 
                                                ModStr/binary, ".", FuncStr/binary, "()'\n",
                                                "\e[33mHint:\e[0m Did you forget to compile your project with :cc?">>};
                                    _ ->
                                        {error, <<"\e[31merror:\e[0m Undefined module or function call.\n",
                                                "\e[33mHint:\e[0m Did you forget to compile your project with :cc?">>}
                                end;
                            Class:Reason:Stack -> 
                                {error, {Class, Reason, Stack}}
                        end;
                    Error -> {error, {load_failed, Error}}
                end,
            From ! {Ref, Reply},
            loop(OwnerRef);

        stop -> ok
    end.