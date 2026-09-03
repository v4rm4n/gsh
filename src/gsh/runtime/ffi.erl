-module(ffi).

-export([
    system_version/0,
    app_version/1,
    get_char/0,
    get_char_timeout/1,
    pushback/1
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

%% Ensures a single background process is continuously reading stdin
%% and forwarding each character to the calling (owner) process's mailbox.
%% This lets us use `receive ... after` for timeouts, since a plain
%% io:get_chars call can never be cancelled once it's blocked.
ensure_reader() ->
    case whereis(gsh_reader) of
        undefined ->
            Owner = self(),
            Pid = spawn(fun() -> reader_loop(Owner) end),
            register(gsh_reader, Pid);
        _ ->
            ok
    end.

reader_loop(Owner) ->
    Ch = io:get_chars("", 1),
    Owner ! {gsh_char, Ch},
    reader_loop(Owner).

%% Blocking read (used for normal typing) - checks the pushback queue first.
get_char() ->
    case pop_pushback() of
        {ok, Ch} -> Ch;
        empty ->
            ensure_reader(),
            receive
                {gsh_char, Ch} -> Ch
            end
    end.


%% Non-blocking-with-timeout read (used for escape-sequence continuation
%% bytes). Returns {ok, Char} or {error, timeout}.
get_char_timeout(TimeoutMs) ->
    case pop_pushback() of
        {ok, Ch} -> {ok, Ch};
        empty ->
            ensure_reader(),
            receive
                {gsh_char, Ch} -> {ok, Ch}
            after TimeoutMs ->
                {error, timeout}
            end
    end.

pushback(Ch) ->
    put(gsh_pushback, Ch),
    nil.

pop_pushback() ->
    case get(gsh_pushback_queue) of
        undefined -> empty;
        [] -> empty;
        [H | T] ->
            put(gsh_pushback_queue, T),
            {ok, H}
    end.