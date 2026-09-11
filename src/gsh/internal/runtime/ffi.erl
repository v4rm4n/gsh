-module(ffi).

-export([
    system_time/0,
    system_version/0,
    app_version/1,
    get_exports/1,
    load_and_run/2,
    store_put/2,
    store_get/1,
    store_has/1,
    get_args/0,
    boot_app/1,
    pid_from_string/1,
    setup_logger/0,
    get_logs/0,
    log/2,
    start_observer/0,
    compile_and_load/2,
    run_entry/2,
    ensure_code_paths/0
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
        %% Convert binary to an atom
        ModuleName = binary_to_atom(ModuleNameBin, utf8),
        
        %% Ensure the module is loaded into the VM memory
        case code:ensure_loaded(ModuleName) of
            {module, ModuleName} ->
                %% module_info(exports) returns a list like [{to_string, 1}, {parse, 1}]
                Exports = ModuleName:module_info(exports),
                
                %% Extract just the function names, ignoring internal module_info functions
                [unicode:characters_to_binary(atom_to_list(F)) || {F, _Arity} <- Exports, F =/= module_info];
            _ -> 
                [] %% Module not found
        end
    catch
        _:_ -> [] %% Failsafe if anything crashes
    end.

load_and_run(ModuleNameBin, FunctionNameBin) ->
    Module = binary_to_atom(ModuleNameBin, utf8),
    Function = binary_to_atom(FunctionNameBin, utf8),

    %% Purge old version from memory
    code:purge(Module),
    code:delete(Module),

    %% Dynamically locate ebin directories under build/
    case filelib:wildcard("build/dev/erlang/*/ebin") of
        [] -> ok;
        Paths -> lists:foreach(fun(P) -> code:add_patha(P) end, Paths)
    end,

    %% Hot-load the freshly compiled bytecode
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

store_put(KeyBin, Value) ->
    put(KeyBin, Value),
    Value.

store_get(KeyBin) ->
    get(KeyBin).

store_has(KeyBin) ->
    get(KeyBin) =/= undefined.

%% Reads arguments passed after `--` in the CLI
get_args() ->
    [unicode:characters_to_binary(A) || A <- init:get_plain_arguments()].

%% Dynamically loads a Gleam module and runs its main() in a background process
boot_app(ModuleNameBin) ->
    %% Convert Gleam path syntax (my_app/server) to Erlang module syntax (my_app@server)
    NormalizedBin = binary:replace(ModuleNameBin, <<"/">>, <<"@">>, [global]),
    Module = binary_to_atom(NormalizedBin, utf8),
    
    case code:ensure_loaded(Module) of
        {module, Module} ->
            Pid = spawn(fun() -> apply(Module, main, []) end),
            {ok, Pid};
        {error, Reason} -> 
            %% Capture the exact Erlang error (e.g. 'nofile')
            ReasonStr = list_to_binary(io_lib:format("~p", [Reason])),
            {error, <<"Could not load '", NormalizedBin/binary, "': ", ReasonStr/binary>>}
    end.

%% Converts a string like "<0.83.0>" into an actual Erlang PID
pid_from_string(Bin) ->
    list_to_pid(binary_to_list(Bin)).

%% Creates an in-memory table and reroutes logs into it
setup_logger() ->
    %% Create a public, named ring-buffer in memory
    ets:new(gsh_logs, [named_table, public, ordered_set]),
    
    %% Kill the default handler that floods the screen
    logger:remove_handler(default),
    
    %% Add our custom handler that traps logs in ETS
    logger:add_handler(gsh_ui, ?MODULE, #{
        formatter => {logger_formatter, #{
            single_line => true,
            %% Explicitly inject the PID into the log string
            template => [time, " ", pid, " [", level, "] ", msg]
        }}
    }).

%% The callback Erlang triggers every time a background app logs something
log(LogEvent, Config) ->
    %% Format the log using standard Erlang tools
    {Formatter, FormatterConfig} = maps:get(formatter, Config),
    Formatted = Formatter:format(LogEvent, FormatterConfig),
    
    Bin = unicode:characters_to_binary(Formatted, utf8),
    Clean = binary:replace(Bin, <<"\n">>, <<>>, [global]),
    
    %% Store it in ETS with a timestamp as the key so it sorts chronologically
    Time = erlang:system_time(microsecond),
    ets:insert(gsh_logs, {Time, Clean}),
    
    %% Keep only the last 50 logs to prevent memory leaks
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
    
    %% FIX: Change '->' to 'of' on this line!
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