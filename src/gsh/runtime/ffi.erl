-module(ffi).

-export([
    system_version/0,
    app_version/1,
    get_exports/1
]).

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