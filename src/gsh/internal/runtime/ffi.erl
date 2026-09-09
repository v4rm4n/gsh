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
    fix_logger_staircase/0, 
    format/2,
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

%% Wraps the active logger formatter to natively inject \r\n 
%% so background logs render correctly while the terminal is in raw mode.
fix_logger_staircase() ->
    case logger:get_handler_config(default) of
        {ok, #{formatter := {Mod, Config}} = HandlerConfig} ->
            ProxyState = #{proxy_mod => Mod, proxy_config => Config},
            NewConfig = HandlerConfig#{formatter => {?MODULE, ProxyState}},
            logger:set_handler_config(default, NewConfig);
        _ -> ok
    end.

%% Fixed: The callback for our proxy formatter must be named format/2
format(LogEvent, #{proxy_mod := OriginalMod, proxy_config := OriginalConfig}) ->
    try
        %% Call the original formatter (preserves Gleam's colors and Logfmt!)
        Formatted = OriginalMod:format(LogEvent, OriginalConfig),
        
        %% Fixed: Safely handle deep unicode lists (Gleam strings)
        Bin = unicode:characters_to_binary(Formatted, utf8),
        
        case Bin of
            B when is_binary(B) ->
                %% Strip any existing \r to prevent doubling up, then replace \n with \r\n
                NoCr = binary:replace(B, <<"\r">>, <<>>, [global]),
                binary:replace(NoCr, <<"\n">>, <<"\r\n">>, [global]);
            _ -> 
                Formatted %% Fallback if conversion fails
        end
    catch
        _:_ -> 
            %% Failsafe to guarantee the logger never takes down the VM
            <<"[GSH] Formatter Proxy Error\r\n">>
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