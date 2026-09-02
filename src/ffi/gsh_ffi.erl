-module(gsh_ffi).

-export([
    system_version/0,
    app_version/1
]).

%% GSH runtime bridge:
%% Returns the currently running Erlang/OTP system version as a Gleam String.
system_version() ->
    unicode:characters_to_binary(
        erlang:system_info(system_version)
    ).

%% GSH application metadata bridge:
%% Returns the application's version as a Gleam String.
app_version(AppAtom) ->
    case application:get_key(AppAtom, vsn) of
        {ok, VersionStr} ->
            unicode:characters_to_binary(VersionStr);
        undefined ->
            <<"0.0.0">>
    end.