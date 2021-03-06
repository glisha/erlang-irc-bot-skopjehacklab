-module(ircbot_plugin_hacklab_status).
-author("glisha").

-behaviour(gen_event).
-export([init/1, handle_event/2, terminate/2, handle_call/2, handle_info/2, code_change/3]).
-export([status_loop/1]).


-define(MAXBODY, 10000).

init(_Args) ->
    hackney:start(),
    spawn(?MODULE, status_loop, [undefined]),
    {ok, ok}.


handle_event(Msg, State) ->
    case Msg of
        {in, IrcBot, [_Nick, _Name, <<"PRIVMSG">>, Channel = <<"#lugola">>, <<"!status">>]} ->
            doit(IrcBot, Channel);
        {in, IrcBot, [_Nick, _Name, <<"PRIVMSG">>, Channel = <<"#lugola">>, <<"!статус">>]} ->
            doit(IrcBot, Channel);
        {in, IrcBot, [_Nick, _Name, <<"PRIVMSG">>, Channel = <<"#lugola">>, <<"!prisutni">>]} ->
            doit(IrcBot, Channel);
        {in, IrcBot, [_Nick, _Name, <<"PRIVMSG">>, Channel = <<"#lugola">>, <<"!присутни">>]} ->
            doit(IrcBot, Channel);
        _ -> ok
    end,
    {ok, State}.


doit(IrcBot, Channel) ->
    Collector = spawn(fun() ->
        Response = wait_for_responses([], 2),
        IrcBot:privmsg(Channel, Response)
    end),
    spawn(fun() ->
        Collector ! { prisutni, get_prisutni() }
    end),
    spawn(fun() ->
        Collector ! { status, get_status() }
    end).

wait_for_responses(Responses, 0) ->
    Responses ++ [<<" (http://status.spodeli.org)">>];

wait_for_responses(Responses, Needed) ->
    receive
        {prisutni, Text} ->
            wait_for_responses([Text, " " | Responses], Needed - 1);
        {status, Text} ->
            wait_for_responses([Text, " " | Responses], Needed - 1)
    after
        5000 ->
            wait_for_responses([<<"some timeout">> | Responses], 0)
    end.


get_prisutni() ->
    Url = <<"http://status.spodeli.org/status?limit=1">>,
    Headers = [{<<"User-Agent">>, <<"Mozilla/5.0 (erlang-irc-bot)">>}],
    Options = [{recv_timeout, 5000}, {follow_redirect, true}],
    {ok, StatusCode, _RespHeaders, Ref} = hackney:request(get, Url, Headers, <<>>, Options),
    {ok, Body} = hackney:body(Ref, ?MAXBODY),
    hackney:close(Ref),
    case StatusCode of
        200 ->
            {Json} = couchbeam_ejson:decode(Body),
            [{Counter}|_] = proplists:get_value(<<"counters">>, Json),
            Count = proplists:get_value(<<"count">>, Counter),
            CountS = list_to_binary(integer_to_list(Count)),
            People = proplists:get_value(<<"present">>, Json),

            case {Count, People} of
                {0, _} ->
                    <<"Во хаклаб нема никој :(">>;
                {_, []} ->
                    [<<"Во хаклаб има ">>, CountS, <<" уреди.">>];
                _ ->
                    Names = [ proplists:get_value(<<"name">>, Person) || {Person} <- People ],
                    [<<"Присутни: ">>, ircbot_lib:iolist_join(Names, ", "), <<". Вкупно уреди: ">>, CountS, <<".">>]
            end;
        _ ->
            N = list_to_binary(integer_to_list(StatusCode)),
            <<"{error ", N/binary, "}">>
    end.

get_status() ->
    Url = <<"https://api.xively.com/v2/feeds/86779/datastreams/hacklab_status.json">>,
    Headers = [{<<"User-Agent">>, <<"Mozilla/5.0 (erlang-irc-bot)">>},
                {<<"X-ApiKey">>,<<"vqElqXeb7Lu6ZwDElnKQ8XpGMG-SAKxxMHV3YWFoeHE4OD0g">>}],
    Options = [{recv_timeout, 5000}, {follow_redirect, true}],
    {ok, StatusCode, _RespHeaders, Ref} = hackney:request(get, Url, Headers, <<>>, Options),
    {ok, Body} = hackney:body(Ref, ?MAXBODY),
    hackney:close(Ref),
    case StatusCode of
        200 ->
            {Json} = couchbeam_ejson:decode(Body),
            Current_Value = proplists:get_value(<<"current_value">>, Json),
            case Current_Value of
                <<"0">> ->
                    <<"Хаклабот е затворен. :(">>;
                <<"1">> ->
                    <<"Хаклабот е отворен. Дојди!">>
            end;
        _ ->
            N = list_to_binary(integer_to_list(StatusCode)),
            <<"{error ", N/binary, "}">>
    end.

status_loop(LastStatus) ->
    Url = <<"http://hacklab.ie.mk/status/open">>,
    Options = [ {recv_timeout, 120000}, {follow_redirect, true} ],
    case hackney:get(Url, [], <<>>, Options) of
        {ok, 200, _, Ref} ->
            {ok, Body} = hackney:body(Ref, ?MAXBODY),
            hackney:close(Ref),
            case Body of
                LastStatus ->
                    status_loop(LastStatus) ;
                _ ->
                    IrcBot = ircbot_api:new(whereis(freenode)),
                    IrcBot:notice("#lugola", Body),
                    status_loop(Body)
            end;
        {_, _, _, Ref} ->
            hackney:close(Ref),
            status_loop(LastStatus);
        {error, _} ->
            timer:sleep(1000),
            status_loop(LastStatus)
    end.


handle_call(_Request, State) -> {ok, ok, State}.
handle_info(_Info, State) -> {ok, State}.
code_change(_OldVsn, State, _Extra) -> {ok, State}.
terminate(_Args, _State) -> ok.
