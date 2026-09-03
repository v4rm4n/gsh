-module(ffi).

-export([
    system_version/0,
    app_version/1
]).

system_version() ->
    unicode:characters_to_binary(erlang:system_info(system_version)).

app_version(AppAtom) ->
    case application:get_key(AppAtom, vsn) of
        {ok, VersionStr} -> unicode:characters_to_binary(VersionStr);
        undefined -> <<"0.0.0">>
    end.